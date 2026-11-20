"""HLS manifest proxy route: GET /m3u8?u=<upstream_url>"""

from __future__ import annotations

import logging
import re
from typing import Final

import aiohttp
from aiohttp import web

from fmp4_demux_proxy import manifest as mf
from fmp4_demux_proxy.routes.segment_route import MAP_REGISTRY_KEY
from fmp4_demux_proxy.upstream import (
    CONFIG_KEY,
    SESSION_KEY,
    fetch_upstream,
    validate_upstream_url,
)

logger = logging.getLogger(__name__)

_MANIFEST_CONTENT_TYPE: Final[str] = "application/vnd.apple.mpegurl"
_MAX_MANIFEST_BYTES: Final[int] = 2 * 1024 * 1024
_VALID_PROTOS: Final[frozenset[str]] = frozenset({"http", "https"})
_HOST_RE: Final[re.Pattern[str]] = re.compile(
    r"^([A-Za-z0-9._-]+|\[[0-9A-Fa-f:]+\])(?::[0-9]{1,5})?$"
)
BREAK_STORE_KEY: Final[web.AppKey[mf.BreakStore]] = web.AppKey("break_store", mf.BreakStore)


def _proxy_base_from_request(request: web.Request) -> str:
    raw_proto = (
        request.headers.get("X-Forwarded-Proto", request.scheme).split(",")[0].strip().lower()
    )
    scheme = raw_proto if raw_proto in _VALID_PROTOS else request.scheme
    raw_host = (request.headers.get("X-Forwarded-Host") or request.host).split(",")[0].strip()
    if not _HOST_RE.match(raw_host):
        raise web.HTTPBadRequest(text="invalid host header")
    return f"{scheme}://{raw_host}"


def _parse_hints(request: web.Request) -> mf.VariantHints | None:
    codecs = request.query.get("codecs") or None
    resolution = request.query.get("res") or None
    bandwidth_raw = request.query.get("bw")
    bandwidth: int | None = None
    if bandwidth_raw:
        try:
            parsed = int(bandwidth_raw)
        except ValueError:
            parsed = 0
        if parsed > 0:
            bandwidth = parsed
    if codecs is None and resolution is None and bandwidth is None:
        return None
    return mf.VariantHints(codecs=codecs, bandwidth=bandwidth, resolution=resolution)


async def m3u8_handler(request: web.Request) -> web.Response:
    session: aiohttp.ClientSession = request.app[SESSION_KEY]
    cfg = request.app[CONFIG_KEY]

    upstream = request.query.get("u")
    if not upstream:
        raise web.HTTPBadRequest(text="missing query param: u")

    validate_upstream_url(upstream, cfg.upstream_host_allowlist)

    try:
        status, final_url, body_bytes = await fetch_upstream(
            session,
            upstream,
            cfg.upstream_host_allowlist,
            max_bytes=_MAX_MANIFEST_BYTES,
        )
        if status != 200:
            logger.warning("upstream m3u8 returned %s for %s", status, upstream)
            raise web.HTTPBadGateway(text=f"upstream status {status}")
    except aiohttp.ClientError as exc:
        logger.error("upstream m3u8 fetch failed for %s: %s", upstream, exc)
        raise web.HTTPBadGateway(text=f"upstream fetch failed: {exc}") from exc

    try:
        body_text = body_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise web.HTTPBadGateway(text=f"upstream body not utf-8: {exc}") from exc

    proxy_base = cfg.proxy_public_url or _proxy_base_from_request(request)
    rewrite_cfg = mf.RewriteConfig(proxy_base=proxy_base)
    raw_track = request.query.get("track")
    if raw_track in (None, ""):
        track = None
    elif raw_track in {"video", "audio"}:
        track = raw_track
    else:
        raise web.HTTPBadRequest(text="invalid query param: track")

    hints = _parse_hints(request)
    map_registry = request.app.get(MAP_REGISTRY_KEY)
    break_store = request.app.get(BREAK_STORE_KEY)

    manifest_text = body_text
    if (
        track is not None
        and break_store is not None
        and "#EXT-X-ENDLIST" not in body_text
        and mf.classify(body_text) == mf.ManifestKind.VARIANT
    ):
        variant_key = f"{final_url}#{track}"
        session_key = request.query.get("k") or variant_key
        manifest_text = mf.keep_break_count(body_text, session_key, break_store, variant_key)

    rewritten = mf.rewrite(
        manifest_text,
        base_url=final_url,
        config=rewrite_cfg,
        track=track,
        hints=hints,
        map_registry=map_registry,
    )

    return web.Response(
        body=rewritten.encode("utf-8"),
        content_type=_MANIFEST_CONTENT_TYPE,
        headers={"Cache-Control": "no-store"},
    )
