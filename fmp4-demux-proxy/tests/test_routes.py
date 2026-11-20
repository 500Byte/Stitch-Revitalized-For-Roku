"""Integration tests for the /m3u8 and /s routes with a fake upstream."""

from __future__ import annotations

from urllib.parse import parse_qs, quote, unquote, urlparse

import pytest
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

from fmp4_demux_proxy.app import create_app
from tests._fixtures import make_init_segment, make_media_segment
from tests.conftest import make_test_config


@pytest.fixture
async def upstream() -> TestServer:
    app = web.Application()
    app["master"] = b""
    app["variant"] = b""
    app["init"] = b""
    app["media"] = b""
    app["status"] = {"/master": 200, "/variant": 200, "/init.mp4": 200, "/seg-1.m4s": 200}

    async def master_h(request: web.Request) -> web.Response:
        status = request.app["status"]["/master"]
        if status != 200:
            return web.Response(status=status)
        return web.Response(
            body=request.app["master"], content_type="application/vnd.apple.mpegurl"
        )

    async def variant_h(request: web.Request) -> web.Response:
        status = request.app["status"]["/variant"]
        if status != 200:
            return web.Response(status=status)
        return web.Response(
            body=request.app["variant"], content_type="application/vnd.apple.mpegurl"
        )

    async def init_h(request: web.Request) -> web.Response:
        status = request.app["status"]["/init.mp4"]
        if status != 200:
            return web.Response(status=status)
        return web.Response(body=request.app["init"], content_type="video/mp4")

    async def media_h(request: web.Request) -> web.Response:
        status = request.app["status"]["/seg-1.m4s"]
        if status != 200:
            return web.Response(status=status)
        return web.Response(body=request.app["media"], content_type="video/mp4")

    app.router.add_get("/master", master_h)
    app.router.add_get("/variant", variant_h)
    app.router.add_get("/init.mp4", init_h)
    app.router.add_get("/seg-1.m4s", media_h)

    server = TestServer(app)
    await server.start_server()
    try:
        yield server
    finally:
        await server.close()


@pytest.fixture
async def proxy_client(aiohttp_client) -> TestClient:
    app = create_app(config=make_test_config())
    return await aiohttp_client(app)


@pytest.fixture
async def strict_proxy_client(aiohttp_client) -> TestClient:
    app = create_app(config=make_test_config(upstream_host_allowlist=("ttvnw.net",)))
    return await aiohttp_client(app)


class TestM3U8Route:
    async def test_missing_params_400(self, proxy_client: TestClient) -> None:
        resp = await proxy_client.get("/m3u8")
        assert resp.status == 400

    async def test_upstream_500_returns_502(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        upstream.app["status"]["/master"] = 500
        upstream.app["master"] = b"ignored"
        upstream_url = str(upstream.make_url("/master"))
        resp = await proxy_client.get(f"/m3u8?u={quote(upstream_url, safe='')}")
        assert resp.status == 502

    async def test_master_rewrites_variant_urls(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        variant_url = str(upstream.make_url("/variant"))
        master_body = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:3\n"
            '#EXT-X-STREAM-INF:BANDWIDTH=3000000,CODECS="hev1.1.6.L150.B0"\n'
            f"{variant_url}\n"
        ).encode()
        upstream.app["master"] = master_body

        upstream_url = str(upstream.make_url("/master"))
        resp = await proxy_client.get(f"/m3u8?u={quote(upstream_url, safe='')}")
        assert resp.status == 200
        body = await resp.text()
        assert "/m3u8?u=" in body
        assert variant_url not in body
        proxied_line = next(
            ln for ln in body.splitlines() if "/m3u8?u=" in ln and not ln.startswith("#")
        )
        qs = parse_qs(urlparse(proxied_line).query)
        assert unquote(qs["u"][0]) == variant_url

    async def test_variant_without_track_synthesizes_master_with_hints(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        init_url = str(upstream.make_url("/init.mp4"))
        seg_url = str(upstream.make_url("/seg-1.m4s"))
        variant_body = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:6\n"
            "#EXT-X-TARGETDURATION:2\n"
            "#EXT-X-MEDIA-SEQUENCE:1\n"
            f'#EXT-X-MAP:URI="{init_url}"\n'
            "#EXTINF:2.000,\n"
            f"{seg_url}\n"
        ).encode()
        upstream.app["variant"] = variant_body

        upstream_url = str(upstream.make_url("/variant"))
        hints_qs = "&codecs=hvc1.1.2.L120.90.0.0.0.0.0,mp4a.40.2&bw=6000000&res=1920x1080"
        resp = await proxy_client.get(f"/m3u8?u={quote(upstream_url, safe='')}{hints_qs}")
        assert resp.status == 200
        body = await resp.text()
        assert 'CODECS="hvc1.1.2.L120.90.0.0.0.0.0,mp4a.40.2"' in body
        assert "BANDWIDTH=6000000" in body
        assert "RESOLUTION=1920x1080" in body

    async def test_variant_without_hints_falls_back_to_default_codec(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        init_url = str(upstream.make_url("/init.mp4"))
        seg_url = str(upstream.make_url("/seg-1.m4s"))
        variant_body = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:6\n"
            "#EXT-X-TARGETDURATION:2\n"
            f'#EXT-X-MAP:URI="{init_url}"\n'
            "#EXTINF:2.000,\n"
            f"{seg_url}\n"
        ).encode()
        upstream.app["variant"] = variant_body

        upstream_url = str(upstream.make_url("/variant"))
        resp = await proxy_client.get(f"/m3u8?u={quote(upstream_url, safe='')}")
        assert resp.status == 200
        body = await resp.text()
        assert 'CODECS="avc1.64001f,mp4a.40.2"' in body

    async def test_variant_rewrites_segment_and_init(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        init_url = str(upstream.make_url("/init.mp4"))
        seg_url = str(upstream.make_url("/seg-1.m4s"))
        variant_body = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:6\n"
            "#EXT-X-TARGETDURATION:2\n"
            "#EXT-X-MEDIA-SEQUENCE:1\n"
            f'#EXT-X-MAP:URI="{init_url}"\n'
            "#EXTINF:2.000,\n"
            f"{seg_url}\n"
        ).encode()
        upstream.app["variant"] = variant_body

        upstream_url = str(upstream.make_url("/variant"))
        resp = await proxy_client.get(f"/m3u8?u={quote(upstream_url, safe='')}&track=video")
        assert resp.status == 200
        body = await resp.text()

        map_line = next(ln for ln in body.splitlines() if ln.startswith("#EXT-X-MAP:"))
        seg_line = next(ln for ln in body.splitlines() if not ln.startswith("#") and "/s?" in ln)
        assert "k=init" in map_line
        assert "k=media" in seg_line
        assert init_url not in body
        assert seg_url not in body


class TestSegmentRoute:
    async def test_missing_params_400(self, proxy_client: TestClient) -> None:
        assert (await proxy_client.get("/s")).status == 400

    async def test_invalid_kind_400(self, proxy_client: TestClient, upstream: TestServer) -> None:
        upstream_url = str(upstream.make_url("/init.mp4"))
        resp = await proxy_client.get(f"/s?u={quote(upstream_url, safe='')}&k=garbage")
        assert resp.status == 400

    async def test_init_segment_rewritten_video_first(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        init_bytes = make_init_segment(traks=[(1, b"soun"), (2, b"vide")])
        upstream.app["init"] = init_bytes

        upstream_url = str(upstream.make_url("/init.mp4"))
        resp = await proxy_client.get(f"/s?u={quote(upstream_url, safe='')}&k=init&track=video")
        assert resp.status == 200
        body = await resp.read()
        assert resp.headers["Content-Type"] == "video/mp4"
        from fmp4_demux_proxy.fmp4 import extract_track_map, iter_top_level_boxes

        boxes = list(iter_top_level_boxes(body))
        assert any(h.type == b"moov" for h, _ in boxes)
        tm = extract_track_map(body)
        assert tm == {1: "video"}

    async def test_media_segment_with_cached_map_rewritten(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        init_bytes = make_init_segment(traks=[(1, b"soun"), (2, b"vide")])
        upstream.app["init"] = init_bytes
        init_url = str(upstream.make_url("/init.mp4"))
        init_resp = await proxy_client.get(f"/s?u={quote(init_url, safe='')}&k=init&track=video")
        assert init_resp.status == 200
        await init_resp.read()

        media_bytes = make_media_segment(sequence=1, trafs=[1, 2])
        upstream.app["media"] = media_bytes
        seg_url = str(upstream.make_url("/seg-1.m4s"))
        seg_resp = await proxy_client.get(f"/s?u={quote(seg_url, safe='')}&k=media&track=video")
        assert seg_resp.status == 200
        body = await seg_resp.read()
        assert len(body) < len(media_bytes)

    async def test_mpeg_ts_segment_passes_through_despite_cached_map(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        init_bytes = make_init_segment(traks=[(1, b"soun"), (2, b"vide")])
        upstream.app["init"] = init_bytes
        init_url = str(upstream.make_url("/init.mp4"))
        init_resp = await proxy_client.get(f"/s?u={quote(init_url, safe='')}&k=init&track=video")
        assert init_resp.status == 200
        await init_resp.read()

        ts_bytes = (b"\x47\x40\x00\x13" + b"\x00" * 184) * 3
        upstream.app["media"] = ts_bytes
        seg_url = str(upstream.make_url("/seg-1.m4s"))
        resp = await proxy_client.get(f"/s?u={quote(seg_url, safe='')}&k=media&track=video")
        assert resp.status == 200
        assert resp.content_type == "video/mp2t"
        body = await resp.read()
        assert body == ts_bytes

    async def test_media_without_cached_map_passes_through(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        media_bytes = make_media_segment(sequence=1, trafs=[1, 2])
        upstream.app["media"] = media_bytes
        seg_url = str(upstream.make_url("/seg-1.m4s"))
        resp = await proxy_client.get(f"/s?u={quote(seg_url, safe='')}&k=media&track=video")
        assert resp.status == 200
        body = await resp.read()
        assert body == media_bytes

    async def test_upstream_failure_returns_502(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        upstream.app["status"]["/init.mp4"] = 404
        init_url = str(upstream.make_url("/init.mp4"))
        resp = await proxy_client.get(f"/s?u={quote(init_url, safe='')}&k=init&track=video")
        assert resp.status == 502

    async def test_corrupt_init_returns_502(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        # Bytes that look like an fMP4 box but are truncated / not a valid moov.
        # Triggers fmp4.Fmp4Error in extract_track_map; handler must turn that
        # into a 502 rather than letting it bubble to a 500.
        upstream.app["init"] = b"\x00\x00\x00\x08ftypisom"
        init_url = str(upstream.make_url("/init.mp4"))
        resp = await proxy_client.get(f"/s?u={quote(init_url, safe='')}&k=init&track=video")
        assert resp.status == 502
        body = await resp.text()
        assert "fmp4 demux failed" in body

    async def test_failed_fetch_does_not_leak_lock(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        from fmp4_demux_proxy.routes.segment_route import SEGMENT_LOCKS_KEY

        app = proxy_client.app
        assert app is not None
        locks = app[SEGMENT_LOCKS_KEY]

        upstream.app["status"]["/init.mp4"] = 500
        init_url = str(upstream.make_url("/init.mp4"))

        # Three failed fetches for the same URL must not accumulate lock entries.
        for _ in range(3):
            resp = await proxy_client.get(f"/s?u={quote(init_url, safe='')}&k=init&track=video")
            assert resp.status == 502

        assert init_url not in locks


class TestUpstreamAllowlist:
    async def test_m3u8_rejects_disallowed_host(self, strict_proxy_client: TestClient) -> None:
        resp = await strict_proxy_client.get(
            f"/m3u8?u={quote('http://evil.example.com/master', safe='')}"
        )
        assert resp.status == 400
        body = await resp.text()
        assert "disallowed upstream host" in body

    async def test_m3u8_rejects_non_http_scheme(self, strict_proxy_client: TestClient) -> None:
        resp = await strict_proxy_client.get(f"/m3u8?u={quote('file:///etc/passwd', safe='')}")
        assert resp.status == 400

    async def test_m3u8_rejects_suffix_lookalike(self, strict_proxy_client: TestClient) -> None:
        # "evilttvnw.net" must NOT match suffix "ttvnw.net" — only a proper
        # subdomain ("*.ttvnw.net") or exact host should be accepted.
        resp = await strict_proxy_client.get(
            f"/m3u8?u={quote('http://evilttvnw.net/master', safe='')}"
        )
        assert resp.status == 400

    async def test_segment_rejects_disallowed_host(self, strict_proxy_client: TestClient) -> None:
        resp = await strict_proxy_client.get(
            "/s?u=" + quote("http://evil.example.com/seg.m4s", safe="") + "&k=init&track=video"
        )
        assert resp.status == 400

    async def test_empty_allowlist_permits_any_host(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        # proxy_client is built with upstream_host_allowlist=() → no restriction;
        # scheme is still enforced, so the localhost test upstream must succeed.
        upstream.app["master"] = b"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=500000\nvariant.m3u8\n"
        upstream_url = str(upstream.make_url("/master"))
        resp = await proxy_client.get(f"/m3u8?u={quote(upstream_url, safe='')}")
        assert resp.status == 200


def test_cache_key_ignores_twitch_s1_prefix() -> None:
    from fmp4_demux_proxy.routes.segment_route import _cache_key

    host = "https://64ec2c66edb9.j.cloudfront.hls.ttvnw.net"
    init = _cache_key(f"{host}/v1/segment/abc.mp4?dna=x")
    assert _cache_key(f"{host}/s1/v1/segment/def.mp4?dna=x") == init
    assert _cache_key(f"{host}/s12/v1/segment/def.mp4") == init
    assert _cache_key(f"{host}/seg/v1/segment/def.mp4") != init


class TestSecurityAndContinuity:
    async def test_m3u8_rejects_redirect_to_disallowed_host(self, aiohttp_client) -> None:
        app = create_app(config=make_test_config(upstream_host_allowlist=("127.0.0.1",)))
        client = await aiohttp_client(app)

        up = web.Application()

        async def redir(_req: web.Request) -> web.Response:
            raise web.HTTPFound(location="http://169.254.169.254/latest/meta-data")

        up.router.add_get("/master", redir)
        srv = TestServer(up)
        await srv.start_server()
        try:
            url = str(srv.make_url("/master"))
            resp = await client.get(f"/m3u8?u={quote(url, safe='')}")
            assert resp.status == 400
            assert "disallowed upstream host" in await resp.text()
        finally:
            await srv.close()

    async def test_segment_rejects_redirect_to_disallowed_host(self, aiohttp_client) -> None:
        app = create_app(config=make_test_config(upstream_host_allowlist=("127.0.0.1",)))
        client = await aiohttp_client(app)

        up = web.Application()

        async def redir(_req: web.Request) -> web.Response:
            raise web.HTTPFound(location="http://evil.example.com/seg.m4s")

        up.router.add_get("/seg.m4s", redir)
        srv = TestServer(up)
        await srv.start_server()
        try:
            url = str(srv.make_url("/seg.m4s"))
            resp = await client.get(f"/s?u={quote(url, safe='')}&k=init&track=video")
            assert resp.status == 400
            assert "disallowed upstream host" in await resp.text()
        finally:
            await srv.close()

    async def test_media_fetches_init_on_demand_via_map_param(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        init_bytes = make_init_segment(traks=[(1, b"soun"), (2, b"vide")])
        media_bytes = make_media_segment(sequence=1, trafs=[1, 2])
        upstream.app["init"] = init_bytes
        upstream.app["media"] = media_bytes

        init_url = str(upstream.make_url("/init.mp4"))
        seg_url = str(upstream.make_url("/seg-1.m4s"))
        upstream.app["variant"] = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:6\n"
            "#EXT-X-TARGETDURATION:2\n"
            "#EXT-X-MEDIA-SEQUENCE:1\n"
            f'#EXT-X-MAP:URI="{init_url}"\n'
            "#EXTINF:2.000,\n"
            f"{seg_url}\n"
        ).encode()

        m3u8_url = str(upstream.make_url("/variant"))
        m3u8_resp = await proxy_client.get(f"/m3u8?u={quote(m3u8_url, safe='')}&track=video")
        assert m3u8_resp.status == 200
        body = await m3u8_resp.text()
        seg_proxy_line = next(
            ln for ln in body.splitlines() if not ln.startswith("#") and "/s?" in ln
        )
        assert "&map=" in seg_proxy_line

        # Request media directly WITHOUT requesting init first — proxy must fetch init on demand
        parsed = urlparse(seg_proxy_line)
        seg_resp = await proxy_client.get(f"{parsed.path}?{parsed.query}")
        assert seg_resp.status == 200
        demuxed = await seg_resp.read()
        assert len(demuxed) < len(media_bytes)

    async def test_m3u8_preserves_discontinuity_sequence_across_ad_drop(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        seg_url = str(upstream.make_url("/seg-1.m4s"))
        upstream.app["variant"] = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:6\n"
            "#EXT-X-TARGETDURATION:2\n"
            "#EXT-X-MEDIA-SEQUENCE:10\n"
            "#EXTINF:2.0,\n"
            f"{seg_url}?n=10\n"
            "#EXT-X-DISCONTINUITY\n"
            "#EXTINF:2.0,\n"
            f"{seg_url}?n=11\n"
        ).encode()
        m3u8_url = str(upstream.make_url("/variant"))
        r1 = await proxy_client.get(f"/m3u8?u={quote(m3u8_url, safe='')}&track=video&k=s1")
        assert r1.status == 200

        # Slide window past segment 11 so the discontinuity tag drops off the top
        upstream.app["variant"] = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:6\n"
            "#EXT-X-TARGETDURATION:2\n"
            "#EXT-X-MEDIA-SEQUENCE:12\n"
            "#EXTINF:2.0,\n"
            f"{seg_url}?n=12\n"
            "#EXTINF:2.0,\n"
            f"{seg_url}?n=13\n"
        ).encode()
        r2 = await proxy_client.get(f"/m3u8?u={quote(m3u8_url, safe='')}&track=video&k=s1")
        assert r2.status == 200
        text2 = await r2.text()
        assert "#EXT-X-DISCONTINUITY-SEQUENCE:1" in text2

    async def test_m3u8_sanitizes_forwarded_proto_and_rejects_injected_host(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        variant_url = str(upstream.make_url("/variant"))
        upstream.app["master"] = (
            f"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=500000\n{variant_url}\n"
        ).encode()
        m3u8_url = str(upstream.make_url("/master"))

        bad = await proxy_client.get(
            f"/m3u8?u={quote(m3u8_url, safe='')}",
            headers={"X-Forwarded-Host": "evil.com/path@inject"},
        )
        assert bad.status == 400

        # Invalid X-Forwarded-Proto falls back safely to request.scheme (http)
        good = await proxy_client.get(
            f"/m3u8?u={quote(m3u8_url, safe='')}",
            headers={"X-Forwarded-Proto": "javascript", "X-Forwarded-Host": "proxy.local:8080"},
        )
        assert good.status == 200
        body = await good.text()
        assert "http://proxy.local:8080/m3u8?u=" in body

    async def test_vod_manifest_does_not_populate_break_store(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        from fmp4_demux_proxy.routes.m3u8_route import BREAK_STORE_KEY

        seg_url = str(upstream.make_url("/seg-1.m4s"))
        upstream.app["variant"] = (
            "#EXTM3U\n"
            "#EXT-X-TARGETDURATION:2\n"
            "#EXT-X-MEDIA-SEQUENCE:1\n"
            f"#EXTINF:2.0,\n{seg_url}\n"
            "#EXT-X-ENDLIST\n"
        ).encode()
        m3u8_url = str(upstream.make_url("/variant"))
        resp = await proxy_client.get(f"/m3u8?u={quote(m3u8_url, safe='')}&track=video&k=vod1")
        assert resp.status == 200
        assert len(proxy_client.app[BREAK_STORE_KEY].lists) == 0

    async def test_oversized_upstream_m3u8_returns_502(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        upstream.app["master"] = b"#EXTM3U\n" + (b"A" * (2 * 1024 * 1024 + 100))
        m3u8_url = str(upstream.make_url("/master"))
        resp = await proxy_client.get(f"/m3u8?u={quote(m3u8_url, safe='')}")
        assert resp.status == 502

    async def test_multi_init_same_directory_switches_track_map_by_map_param(
        self, aiohttp_client
    ) -> None:
        from fmp4_demux_proxy.fmp4 import iter_top_level_boxes
        from tests._fixtures import make_split_media_segment

        # Track IDs flipped between live init1 (1=video,2=audio) and ad init2 (1=audio,2=video)
        init1 = make_init_segment(traks=[(1, b"vide"), (2, b"soun")])
        init2 = make_init_segment(traks=[(1, b"soun"), (2, b"vide")])
        live_media = make_split_media_segment(1, b"\xaa" * 200, b"\xbb" * 80)
        ad_media = make_split_media_segment(1, b"\xcc" * 80, b"\xdd" * 240)

        up = web.Application()
        up.router.add_get("/v1/init_live.mp4", lambda _r: web.Response(body=init1))
        up.router.add_get("/v1/init_ad.mp4", lambda _r: web.Response(body=init2))
        up.router.add_get("/v1/seg_live.m4s", lambda _r: web.Response(body=live_media))
        up.router.add_get("/v1/seg_ad.m4s", lambda _r: web.Response(body=ad_media))

        def playlist_h(req: web.Request) -> web.Response:
            base = str(req.url.origin())
            body = (
                "#EXTM3U\n"
                "#EXT-X-VERSION:6\n"
                "#EXT-X-TARGETDURATION:2\n"
                "#EXT-X-MEDIA-SEQUENCE:1\n"
                f'#EXT-X-MAP:URI="{base}/v1/init_live.mp4"\n'
                f"#EXTINF:2.0,\n{base}/v1/seg_live.m4s\n"
                "#EXT-X-DISCONTINUITY\n"
                f'#EXT-X-MAP:URI="{base}/v1/init_ad.mp4"\n'
                f"#EXTINF:2.0,\n{base}/v1/seg_ad.m4s\n"
            )
            return web.Response(body=body.encode(), content_type="application/vnd.apple.mpegurl")

        up.router.add_get("/v1/playlist.m3u8", playlist_h)
        srv = TestServer(up)
        await srv.start_server()
        client = await aiohttp_client(create_app(config=make_test_config()))
        try:
            pl_url = str(srv.make_url("/v1/playlist.m3u8"))
            r = await client.get(f"/m3u8?u={quote(pl_url, safe='')}&track=video")
            assert r.status == 200
            seg_lines = [ln for ln in (await r.text()).splitlines() if "/s?" in ln and "seg_" in ln]
            assert len(seg_lines) == 2

            p1 = urlparse(seg_lines[0])
            d1 = await (await client.get(f"{p1.path}?{p1.query}")).read()
            mdat1 = next(
                raw[h.header_size :] for h, raw in iter_top_level_boxes(d1) if h.type == b"mdat"
            )
            assert mdat1 == b"\xaa" * 200

            p2 = urlparse(seg_lines[1])
            d2 = await (await client.get(f"{p2.path}?{p2.query}")).read()
            mdat2 = next(
                raw[h.header_size :] for h, raw in iter_top_level_boxes(d2) if h.type == b"mdat"
            )
            assert mdat2 == b"\xdd" * 240
        finally:
            await srv.close()

    async def test_concurrent_failed_fetches_do_not_leak_lock(
        self, proxy_client: TestClient, upstream: TestServer
    ) -> None:
        import asyncio

        from fmp4_demux_proxy.routes.segment_route import SEGMENT_LOCKS_KEY

        upstream.app["status"]["/init.mp4"] = 500
        init_url = str(upstream.make_url("/init.mp4"))
        resps = await asyncio.gather(
            proxy_client.get(f"/s?u={quote(init_url, safe='')}&k=init&track=video"),
            proxy_client.get(f"/s?u={quote(init_url, safe='')}&k=init&track=audio"),
        )
        assert all(r.status == 502 for r in resps)
        assert init_url not in proxy_client.app[SEGMENT_LOCKS_KEY]
