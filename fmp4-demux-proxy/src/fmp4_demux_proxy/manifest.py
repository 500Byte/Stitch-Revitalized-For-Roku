"""HLS manifest (m3u8) URL rewriting."""

from __future__ import annotations

import re
from collections import OrderedDict
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any, Final
from urllib.parse import quote, urljoin

_DEFAULT_BANDWIDTH: Final[int] = 4_000_000
_DEFAULT_CODECS: Final[str] = "avc1.64001f,mp4a.40.2"
_CODEC_CHARS_RE: Final[re.Pattern[str]] = re.compile(r"^[A-Za-z0-9.,_\-]+$")

# ---------------------------------------------------------------------------
# Public types
# ---------------------------------------------------------------------------


class ManifestKind(StrEnum):
    MASTER = "master"
    VARIANT = "variant"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class RewriteConfig:
    proxy_base: str

    def __post_init__(self) -> None:
        object.__setattr__(self, "proxy_base", self.proxy_base.rstrip("/"))


@dataclass(frozen=True)
class VariantHints:
    """Optional codec/bandwidth/resolution hints for synthesized master playlists.

    Twitch Enhanced Broadcasting variants may use H.264, HEVC, or AV1. Because
    the proxy only sees the variant body (not the original master), the caller
    must supply the codec tuple parsed from the upstream master's
    #EXT-X-STREAM-INF line; otherwise the fallback H.264 codec is advertised
    and HEVC/AV1 streams will fail on the client decoder.
    """

    codecs: str | None = None
    bandwidth: int | None = None
    resolution: str | None = None


# ---------------------------------------------------------------------------
# Private constants
# ---------------------------------------------------------------------------

_PREFETCH_TAG: Final[str] = "#EXT-X-TWITCH-PREFETCH:"
_URI_ATTR_RE: Final[re.Pattern[str]] = re.compile(r'URI\s*=\s*"([^"]*)"')
_TYPE_ATTR_RE: Final[re.Pattern[str]] = re.compile(r"TYPE\s*=\s*([^,\s]+)")
_DIGITS_RE: Final[re.Pattern[str]] = re.compile(r"^[0-9]{1,9}$")

class MapRegistry:
    """Bounded LRU mapping between upstream EXT-X-MAP init URLs and short integer IDs."""

    def __init__(self, max_entries: int = 100) -> None:
        self._max = max_entries
        self._next = 0
        self.by_url: OrderedDict[str, str] = OrderedDict()
        self.by_id: dict[str, str] = {}

    def register(self, url: str) -> str:
        existing = self.by_url.get(url)
        if existing is not None:
            self.by_url.move_to_end(url)
            return existing
        self._next += 1
        map_id = str(self._next)
        self.by_url[url] = map_id
        self.by_id[map_id] = url
        if len(self.by_url) > self._max:
            _, evicted_id = self.by_url.popitem(last=False)
            self.by_id.pop(evicted_id, None)
        return map_id

    def lookup(self, map_id: str) -> str | None:
        return self.by_id.get(map_id)


@dataclass
class BreakStore:
    """Bounded LRU store tracking ad discontinuities across variants of a session."""

    max_lists: int = 8
    lists: OrderedDict[str, dict[str, Any]] = field(default_factory=OrderedDict)

    def touch(self, key: str) -> None:
        if key in self.lists:
            self.lists.move_to_end(key)
        while len(self.lists) > self.max_lists:
            self.lists.popitem(last=False)

_MASTER_INDICATORS: Final[tuple[str, ...]] = (
    "#EXT-X-STREAM-INF:",
    "#EXT-X-I-FRAME-STREAM-INF:",
)
_VARIANT_INDICATORS: Final[tuple[str, ...]] = (
    "#EXTINF:",
    "#EXT-X-MAP:",
    "#EXT-X-TARGETDURATION:",
    "#EXT-X-PART:",
    "#EXT-X-PRELOAD-HINT:",
    "#EXT-X-RENDITION-REPORT:",
    "#EXT-X-TWITCH-PREFETCH:",
)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def classify(body: str) -> ManifestKind:
    has_master_indicator = False
    has_media_tag = False
    has_variant_indicator = False

    for raw_line in body.splitlines():
        if raw_line.startswith(_MASTER_INDICATORS):
            has_master_indicator = True
            break
        if raw_line.startswith("#EXT-X-MEDIA:"):
            has_media_tag = True
        elif raw_line.startswith(_VARIANT_INDICATORS):
            has_variant_indicator = True

    if has_master_indicator or (has_media_tag and not has_variant_indicator):
        return ManifestKind.MASTER
    if has_variant_indicator:
        return ManifestKind.VARIANT
    return ManifestKind.UNKNOWN


def rewrite(
    body: str,
    base_url: str,
    config: RewriteConfig,
    *,
    track: str | None = None,
    hints: VariantHints | None = None,
    map_registry: MapRegistry | None = None,
) -> str:
    kind = classify(body)
    if kind == ManifestKind.UNKNOWN:
        return body

    if kind == ManifestKind.VARIANT and track is None:
        return _synthesize_master(base_url, config, hints)

    lines = body.splitlines(keepends=True)
    result: list[str] = []
    expect_uri: str | None = None
    map_param = ""

    for line in lines:
        stripped = line.rstrip("\r\n")

        if not stripped or (stripped.startswith("#") and not stripped.startswith("#EXT")):
            result.append(line)
            continue

        if expect_uri is not None and not stripped.startswith("#"):
            ending = line[len(stripped) :]
            abs_url = _resolve(stripped, base_url)
            extra = map_param if expect_uri == "media" else ""
            result.append(
                _proxy_url(config, expect_uri, abs_url, track=track, extra=extra) + ending
            )
            expect_uri = None
            continue

        if kind == ManifestKind.MASTER:
            if stripped.startswith("#EXT-X-STREAM-INF:"):
                expect_uri = "m3u8"
                result.append(line)
                continue
            if stripped.startswith(
                (
                    "#EXT-X-MEDIA:",
                    "#EXT-X-I-FRAME-STREAM-INF:",
                    "#EXT-X-SESSION-DATA:",
                )
            ):
                result.append(_rewrite_uri_attr(line, base_url, config, "m3u8"))
                continue

        elif kind == ManifestKind.VARIANT:
            if stripped.startswith("#EXTINF:"):
                expect_uri = "media"
                result.append(line)
                continue
            if stripped.startswith("#EXT-X-MAP:"):
                if map_registry is not None:
                    m = _URI_ATTR_RE.search(stripped)
                    if m is not None and m.group(1):
                        init_url = _resolve(m.group(1), base_url)
                        map_param = f"&map={map_registry.register(init_url)}"
                result.append(_rewrite_uri_attr(line, base_url, config, "init", track=track))
                continue
            if stripped.startswith("#EXT-X-PART:"):
                result.append(
                    _rewrite_uri_attr(
                        line, base_url, config, "part", track=track, extra=map_param
                    )
                )
                continue
            if stripped.startswith("#EXT-X-PRELOAD-HINT:"):
                hint_kind = _preload_hint_kind(stripped)
                extra = "" if hint_kind == "init" else map_param
                result.append(
                    _rewrite_uri_attr(
                        line, base_url, config, hint_kind, track=track, extra=extra
                    )
                )
                continue
            if stripped.startswith("#EXT-X-RENDITION-REPORT:"):
                result.append(_rewrite_uri_attr(line, base_url, config, "m3u8"))
                continue
            if stripped.startswith(_PREFETCH_TAG):
                ending = line[len(stripped) :]
                url = stripped[len(_PREFETCH_TAG) :]
                abs_url = _resolve(url, base_url)
                result.append(
                    _PREFETCH_TAG
                    + _proxy_url(config, "prefetch", abs_url, track=track, extra=map_param)
                    + ending
                )
                continue

        result.append(line)

    return "".join(result)


def _parse_live_list(lines: list[str]) -> dict[str, Any]:
    first = 0
    ok = True
    has_dsn = False
    seq_line = -1
    seg_line = -1
    uris: list[str] = []
    breaks: list[int] = []
    pending = 0
    for i, raw_line in enumerate(lines):
        line = raw_line.strip()
        if line.startswith("#EXT-X-MEDIA-SEQUENCE:"):
            v = line[22:].strip()
            if _DIGITS_RE.match(v):
                first = int(v)
            else:
                ok = False
            seq_line = i
        elif line.startswith("#EXT-X-DISCONTINUITY-SEQUENCE:"):
            has_dsn = True
        elif line == "#EXT-X-DISCONTINUITY":
            pending += 1
            if seg_line < 0:
                seg_line = i
        elif line != "" and not line.startswith("#"):
            uris.append(line)
            breaks.append(pending)
            pending = 0
            if seg_line < 0:
                seg_line = i
        elif line.startswith("#EXTINF:"):
            if seg_line < 0:
                seg_line = i
    last = first + len(uris) - 1
    marks = {first + i: b for i, b in enumerate(breaks) if b > 0}
    return {
        "ok": ok,
        "first": first,
        "last": last,
        "uris": uris,
        "marks": marks,
        "has_dsn": has_dsn,
        "seq_line": seq_line,
        "seg_line": seg_line,
    }


def keep_break_count(body: str, key: str, store: BreakStore, variant: str = "") -> str:
    """Maintain cumulative #EXT-X-DISCONTINUITY-SEQUENCE across sliding live playlists."""
    if not variant:
        variant = key
    lines = body.split("\n")
    pl = _parse_live_list(lines)
    if not pl["uris"] or not pl["ok"]:
        return body

    ss = store.lists.get(key)
    if pl["has_dsn"] or (ss is not None and ss["native"]):
        if ss is None or not ss["native"]:
            store.lists[key] = {"native": True}
        store.touch(key)
        return body

    st = ss["variants"].get(variant) if ss is not None else None
    if st is not None and (pl["first"] < st["first"] or pl["last"] < st["last"]):
        seen_before = any(u in st["seen"] for u in pl["uris"])
        if pl["first"] < st["first"] and pl["first"] <= 10 and not seen_before:
            ss = None
            st = None
        else:
            store.touch(key)
            return st["out"]

    if ss is None:
        ss = {"native": False, "base": 0, "ledger": {}, "variants": {}}
        store.lists[key] = ss
    store.touch(key)
    if st is None:
        if len(ss["variants"]) >= 16:
            ss["variants"].clear()
        st = {"first": 0, "last": -1, "disc": 0, "seen": set(), "out": body}
        ss["variants"][variant] = st

    ss["ledger"].update(pl["marks"])
    if len(ss["ledger"]) > 256:
        for k in sorted(ss["ledger"])[:64]:
            ss["base"] += ss["ledger"].pop(k)

    disc = ss["base"] + sum(v for k, v in ss["ledger"].items() if k < pl["first"])
    if len(st["seen"]) > 256:
        st["seen"].clear()
    st["seen"].update(pl["uris"])
    st["first"] = pl["first"]
    st["last"] = pl["last"]

    out = body
    if disc > 0:
        at = pl["seg_line"]
        if pl["seq_line"] >= 0 and pl["seq_line"] < at:
            at = pl["seq_line"] + 1
        tag = f"#EXT-X-DISCONTINUITY-SEQUENCE:{disc}"
        if at <= 0:
            lines[0] = f"{tag}\n{lines[0]}"
        else:
            lines[at - 1] = f"{lines[at - 1]}\n{tag}"
        out = "\n".join(lines)

    st["disc"] = disc
    st["out"] = out
    return out


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------


def _resolve(url: str, base_url: str) -> str:
    if url.startswith(("http://", "https://")):
        return url
    return urljoin(base_url, url)


def _proxy_url(
    config: RewriteConfig,
    kind: str,
    upstream: str,
    *,
    track: str | None = None,
    extra: str = "",
) -> str:
    encoded = quote(upstream, safe="")
    if kind == "m3u8":
        url = f"{config.proxy_base}/m3u8?u={encoded}"
        if track:
            url += f"&track={track}"
        return url
    url = f"{config.proxy_base}/s?u={encoded}&k={kind}"
    if track:
        url += f"&track={track}"
    if extra:
        url += extra
    return url


def _rewrite_uri_attr(
    line: str,
    base_url: str,
    config: RewriteConfig,
    kind: str,
    *,
    track: str | None = None,
    extra: str = "",
) -> str:
    stripped = line.rstrip("\r\n")
    ending = line[len(stripped) :]
    m = _URI_ATTR_RE.search(stripped)
    if m is None:
        return line
    old_url = m.group(1)
    abs_url = _resolve(old_url, base_url)
    proxy_url = _proxy_url(config, kind, abs_url, track=track, extra=extra)
    return stripped[: m.start(1)] + proxy_url + stripped[m.end(1) :] + ending


def _synthesize_master(
    upstream_url: str,
    config: RewriteConfig,
    hints: VariantHints | None,
) -> str:
    encoded = quote(upstream_url, safe="")
    audio_uri = f"{config.proxy_base}/m3u8?u={encoded}&track=audio"
    video_uri = f"{config.proxy_base}/m3u8?u={encoded}&track=video"

    codecs = _safe_codecs(hints.codecs if hints else None)
    bandwidth = hints.bandwidth if hints and hints.bandwidth else _DEFAULT_BANDWIDTH
    resolution_attr = ""
    if hints and hints.resolution and _is_valid_resolution(hints.resolution):
        resolution_attr = f",RESOLUTION={hints.resolution}"

    return (
        "#EXTM3U\n"
        "#EXT-X-VERSION:6\n"
        f'#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="Audio",'
        f'DEFAULT=YES,AUTOSELECT=YES,URI="{audio_uri}"\n'
        f"#EXT-X-STREAM-INF:BANDWIDTH={bandwidth}"
        f'{resolution_attr},CODECS="{codecs}",AUDIO="aac"\n'
        f"{video_uri}\n"
    )


def _safe_codecs(codecs: str | None) -> str:
    if not codecs:
        return _DEFAULT_CODECS
    if not _CODEC_CHARS_RE.match(codecs):
        return _DEFAULT_CODECS
    return codecs


def _is_valid_resolution(value: str) -> bool:
    parts = value.split("x")
    if len(parts) != 2:
        return False
    return parts[0].isdigit() and parts[1].isdigit()


def _preload_hint_kind(stripped: str) -> str:
    m = _TYPE_ATTR_RE.search(stripped)
    if m is not None and m.group(1).upper() == "MAP":
        return "init"
    return "part"
