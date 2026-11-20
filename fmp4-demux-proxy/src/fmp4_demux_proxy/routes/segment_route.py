"""fMP4 segment proxy route: GET /s?u=<upstream_url>&k=<kind>[&track=<video|audio>]"""

from __future__ import annotations

import asyncio
import logging
import re
from collections import OrderedDict
from dataclasses import dataclass
from typing import Final
from urllib.parse import urlparse

import aiohttp
from aiohttp import web

from fmp4_demux_proxy import fmp4
from fmp4_demux_proxy import manifest as mf
from fmp4_demux_proxy.upstream import (
    CONFIG_KEY,
    SESSION_KEY,
    fetch_upstream,
    validate_upstream_url,
)

_VALID_TRACKS: Final[frozenset[str]] = frozenset({"video", "audio"})

logger = logging.getLogger(__name__)

_VALID_KINDS: Final[frozenset[str]] = frozenset({"init", "media", "part", "prefetch"})
_SEGMENT_CONTENT_TYPE: Final[str] = "video/mp4"
_MAX_CACHE: Final[int] = 50
_MAX_SEGMENT_BYTES: Final[int] = 32 * 1024 * 1024
# Cap track_maps independently — one entry per unique init / variant path.
# Bounded so long-running / multi-channel proxies don't leak memory.
_MAX_TRACK_MAPS: Final[int] = 100


@dataclass
class _LockEntry:
    lock: asyncio.Lock
    waiters: int = 0


TRACK_MAP_KEY: Final[web.AppKey[OrderedDict[str, dict[int, fmp4.TrackKind]]]] = web.AppKey(
    "track_maps", OrderedDict
)
MAP_REGISTRY_KEY: Final[web.AppKey[mf.MapRegistry]] = web.AppKey(
    "map_registry", mf.MapRegistry
)
SEGMENT_CACHE_KEY: Final[web.AppKey[OrderedDict[str, bytes]]] = web.AppKey(
    "segment_cache", OrderedDict
)
SEGMENT_LOCKS_KEY: Final[web.AppKey[dict[str, _LockEntry]]] = web.AppKey("segment_locks", dict)


def _cache_key(upstream: str) -> str:
    parsed = urlparse(upstream)
    path = parsed.path.rsplit("/", 1)[0]
    # Twitch CDN serves some media segments under /s1/v1/segment while init stays on
    # /v1/segment; strip the /sN prefix so both share one track_map entry.
    path = re.sub(r"^/s\d+(?=/)", "", path)
    return f"{parsed.scheme}://{parsed.netloc}{path}"


async def _fetch_dedup(
    session: aiohttp.ClientSession,
    upstream: str,
    app: web.Application,
) -> bytes:
    cache = app[SEGMENT_CACHE_KEY]
    locks = app[SEGMENT_LOCKS_KEY]
    cfg = app[CONFIG_KEY]

    entry = locks.get(upstream)
    if entry is None:
        entry = _LockEntry(lock=asyncio.Lock())
        locks[upstream] = entry

    entry.waiters += 1
    try:
        async with entry.lock:
            if upstream in cache:
                cache.move_to_end(upstream)
                return cache[upstream]

            try:
                status, _, data = await fetch_upstream(
                    session,
                    upstream,
                    cfg.upstream_host_allowlist,
                    max_bytes=_MAX_SEGMENT_BYTES,
                )
                if status != 200:
                    logger.warning("upstream segment returned %s for %s", status, upstream)
                    raise web.HTTPBadGateway(text=f"upstream status {status}")
            except aiohttp.ClientError as exc:
                logger.error("upstream segment fetch failed for %s: %s", upstream, exc)
                raise web.HTTPBadGateway(text=f"upstream fetch failed: {exc}") from exc

            if not data:
                logger.warning("upstream returned empty body for %s", upstream)
                raise web.HTTPBadGateway(text="upstream returned empty segment")

            cache[upstream] = data
            if len(cache) > _MAX_CACHE:
                evicted, _ = cache.popitem(last=False)
                evicted_entry = locks.get(evicted)
                if evicted_entry is not None and evicted_entry.waiters == 0:
                    locks.pop(evicted, None)
            return data
    finally:
        entry.waiters -= 1
        if entry.waiters == 0 and locks.get(upstream) is entry:
            locks.pop(upstream, None)


def _remember_track_map(
    track_maps: OrderedDict[str, dict[int, fmp4.TrackKind]],
    key: str,
    track_map: dict[int, fmp4.TrackKind],
) -> None:
    track_maps[key] = track_map
    track_maps.move_to_end(key)
    if len(track_maps) > _MAX_TRACK_MAPS:
        track_maps.popitem(last=False)


async def segment_handler(request: web.Request) -> web.Response:
    session: aiohttp.ClientSession = request.app[SESSION_KEY]
    cfg = request.app[CONFIG_KEY]

    upstream = request.query.get("u")
    kind = request.query.get("k")
    track = request.query.get("track")

    if not upstream or not kind:
        raise web.HTTPBadRequest(text="missing query params: u, k")
    if kind not in _VALID_KINDS:
        raise web.HTTPBadRequest(text=f"invalid kind: {kind}")
    if not track or track not in _VALID_TRACKS:
        raise web.HTTPBadRequest(text=f"invalid or missing track: {track}")

    validate_upstream_url(upstream, cfg.upstream_host_allowlist)

    data = await _fetch_dedup(session, upstream, request.app)

    # MPEG-TS segment (0x47 sync byte, 188-byte packets): not fMP4, pass through.
    if data[:1] == b"\x47" and (len(data) < 189 or data[188] == 0x47):
        logger.debug("MPEG-TS segment detected for %s; passing through", upstream)
        return web.Response(
            body=data,
            content_type="video/mp2t",
            headers={"Cache-Control": "no-store"},
        )

    track_maps = request.app[TRACK_MAP_KEY]
    cache_key = _cache_key(upstream)
    keep: fmp4.TrackKind = "video" if track == "video" else "audio"

    try:
        if kind == "init":
            track_map = fmp4.extract_track_map(data)
            _remember_track_map(track_maps, cache_key, track_map)
            _remember_track_map(track_maps, upstream, track_map)
            rewritten = fmp4.split_moov(data, track_map, keep)
            logger.debug("init rewritten for %s; track_map=%s", cache_key, track_map)
        else:
            map_id = request.query.get("map")
            map_registry = request.app.get(MAP_REGISTRY_KEY)
            init_url = (
                map_registry.lookup(map_id)
                if (map_id and map_registry is not None)
                else None
            )
            map_lookup_key = init_url if init_url is not None else cache_key
            track_map = track_maps.get(map_lookup_key)
            if track_map is None and init_url is not None:
                validate_upstream_url(init_url, cfg.upstream_host_allowlist)
                init_data = await _fetch_dedup(session, init_url, request.app)
                if not (
                    init_data[:1] == b"\x47"
                    and (len(init_data) < 189 or init_data[188] == 0x47)
                ):
                    track_map = fmp4.extract_track_map(init_data)
                    _remember_track_map(track_maps, _cache_key(init_url), track_map)
                    _remember_track_map(track_maps, init_url, track_map)
            if track_map is None:
                logger.warning(
                    "no track_map cached for %s (k=%s); passing through unchanged",
                    map_lookup_key,
                    kind,
                )
                rewritten = data
            else:
                track_maps.move_to_end(map_lookup_key)
                rewritten = fmp4.split_moof_mdat(data, track_map, keep)
    except fmp4.Fmp4Error as exc:
        logger.warning("fmp4 demux failed for %s (k=%s): %s", upstream, kind, exc)
        raise web.HTTPBadGateway(text=f"fmp4 demux failed: {exc}") from exc

    return web.Response(
        body=rewritten,
        content_type=_SEGMENT_CONTENT_TYPE,
        headers={"Cache-Control": "no-store"},
    )
