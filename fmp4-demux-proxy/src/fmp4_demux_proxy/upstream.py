"""Shared outbound HTTP client for fetching upstream Twitch content."""

from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Final
from urllib.parse import urljoin, urlparse

import aiohttp
from aiohttp import web

from fmp4_demux_proxy.config import Config

SESSION_KEY: Final[web.AppKey[aiohttp.ClientSession]] = web.AppKey(
    "upstream_session", aiohttp.ClientSession
)
CONFIG_KEY: Final[web.AppKey[Config]] = web.AppKey("config", Config)

_ALLOWED_SCHEMES: Final[frozenset[str]] = frozenset({"http", "https"})
_REDIRECT_STATUSES: Final[frozenset[int]] = frozenset({301, 302, 303, 307, 308})


async def upstream_session_cleanup_ctx(app: web.Application) -> AsyncIterator[None]:
    cfg = app[CONFIG_KEY]
    timeout = aiohttp.ClientTimeout(
        connect=cfg.upstream_connect_timeout,
        total=None,
        sock_read=cfg.upstream_read_timeout,
    )
    session = aiohttp.ClientSession(timeout=timeout)
    app[SESSION_KEY] = session
    try:
        yield
    finally:
        await session.close()


def validate_upstream_url(url: str, allowlist: tuple[str, ...]) -> None:
    """Raise HTTPBadRequest if `url` fails scheme/host allowlist checks.

    Used both on the inbound ``u=`` query param and on the final URL after
    redirects, to prevent open-proxy / SSRF abuse (e.g. redirect to an
    internal service or cloud metadata endpoint).

    An empty allowlist means "no host restriction" — scheme is still enforced.
    Entries are matched as domain suffixes (``ttvnw.net`` matches
    ``foo.ttvnw.net`` and ``ttvnw.net`` but not ``evilttvnw.net``).
    """
    if not url:
        raise web.HTTPBadRequest(text="empty upstream url")

    parsed = urlparse(url)
    scheme = parsed.scheme.lower()
    if scheme not in _ALLOWED_SCHEMES:
        raise web.HTTPBadRequest(text=f"disallowed upstream scheme: {scheme or '<empty>'}")

    host = (parsed.hostname or "").lower()
    if not host:
        raise web.HTTPBadRequest(text="missing upstream host")

    if not allowlist:
        return

    for suffix in allowlist:
        if host == suffix or host.endswith("." + suffix):
            return

    raise web.HTTPBadRequest(text=f"disallowed upstream host: {host}")


async def fetch_upstream(
    session: aiohttp.ClientSession,
    url: str,
    allowlist: tuple[str, ...],
    *,
    max_redirects: int = 5,
    max_bytes: int | None = None,
) -> tuple[int, str, bytes]:
    """Fetch ``url``, validating every redirect target and bounding response size."""
    current = url
    validate_upstream_url(current, allowlist)
    for _ in range(max_redirects + 1):
        async with session.get(current, allow_redirects=False) as resp:
            if resp.status in _REDIRECT_STATUSES:
                location = resp.headers.get("Location")
                if not location:
                    return resp.status, str(resp.url), await _read_bounded(resp, max_bytes)
                next_url = urljoin(current, location)
                validate_upstream_url(next_url, allowlist)
                current = next_url
                continue
            body = await _read_bounded(resp, max_bytes)
            return resp.status, str(resp.url), body
    raise web.HTTPBadGateway(text="too many upstream redirects")


async def _read_bounded(resp: aiohttp.ClientResponse, max_bytes: int | None) -> bytes:
    if max_bytes is None:
        return await resp.read()
    cl_header = resp.headers.get("Content-Length")
    if cl_header is not None:
        try:
            if int(cl_header) > max_bytes:
                raise web.HTTPBadGateway(text="upstream response too large")
        except ValueError:
            pass
    buf = bytearray()
    async for chunk in resp.content.iter_chunked(65536):
        buf.extend(chunk)
        if len(buf) > max_bytes:
            raise web.HTTPBadGateway(text="upstream response too large")
    return bytes(buf)
