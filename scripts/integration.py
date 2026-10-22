#!/usr/bin/env python3
"""Credential-free, loopback-only real-tool integration; import LoopbackFixture for GUI checks."""
import argparse
import functools
import http.server
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading

REPOSITORY = Path(__file__).resolve().parent.parent
TOOLS = {"YTDLP": "yt-dlp", "FFMPEG": "ffmpeg", "FFPROBE": "ffprobe", "DENO": "deno"}


def resolve_tools():
    paths = {}
    for key, name in TOOLS.items():
        supplied = os.environ.get(f"MEDIA_DOWNLOADER_{key}_PATH")
        if supplied:
            candidate = Path(supplied)
            if not candidate.is_absolute():
                raise RuntimeError(f"{name} override must be absolute")
        else:
            candidate = next((Path(root) / name for root in ("/opt/homebrew/bin", "/usr/local/bin")
                              if os.access(Path(root) / name, os.X_OK)), None)
        if candidate is None or not candidate.is_file() or not os.access(candidate, os.X_OK):
            raise RuntimeError(f"{name} executable unavailable; install or configure it manually")
        # Keep the helper names and common FFmpeg/FFprobe directory intact.
        paths[key] = str(candidate)
    if (Path(paths["FFMPEG"]).name != "ffmpeg" or Path(paths["FFPROBE"]).name != "ffprobe"
            or Path(paths["FFMPEG"]).parent != Path(paths["FFPROBE"]).parent):
        raise RuntimeError("FFmpeg and FFprobe must use their standard names in one directory")
    return paths


def run_quiet(arguments, **kwargs):
    """Raw tool output exists only in memory; failures expose a fixed safe summary."""
    result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=120, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{Path(arguments[0]).name} fixture command failed (exit {result.returncode})")
    return result.stdout


def print_versions(tools):
    for key, name in TOOLS.items():
        arguments = [tools[key]]
        if key == "YTDLP":
            arguments += ["--ignore-config", "--no-plugin-dirs", "--no-remote-components"]
        arguments += ["-version" if key in ("FFMPEG", "FFPROBE") else "--version"]
        first = run_quiet(arguments).decode("utf-8", "replace").splitlines()[0]
        # Only a version token is printed, never unrestricted diagnostic text.
        version = re.search(r"(?:version |deno )?([0-9][0-9A-Za-z.+_-]*)", first)
        if version is None:
            raise RuntimeError(f"{name} did not report a version")
        print(f"{name}: {version.group(1)}", flush=True)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path == "/slow.ts":
            media = (Path(self.directory) / "segment-000.ts").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "video/mp2t")
            self.send_header("Content-Length", str(len(media)))
            self.end_headers()
            self.server.segment_requested.set()
            # Master/metadata stay fast. Transfer waits for the owner to release
            # the gate or close the fixture; no sleep or product test switch.
            self.server.segment_gate.wait()
            try:
                self.wfile.write(media)
            except (BrokenPipeError, ConnectionResetError):
                pass  # Expected after GUI Cancel/Quit.
            return
        if self.path == "/interrupted.ts":
            self.send_response(200)
            self.send_header("Content-Type", "video/mp2t")
            self.send_header("Content-Length", "65536")
            self.end_headers()
            # Deliberately truncate a fragment after successful preceding media.
            self.wfile.write(b"\x47" * 188)
            self.wfile.flush()
            self.close_connection = True
        else:
            super().do_GET()


class FixtureHTTPServer(http.server.ThreadingHTTPServer):
    def __init__(self, *args, **kwargs):
        self.segment_requested = threading.Event()
        self.segment_gate = threading.Event()
        super().__init__(*args, **kwargs)

    def handle_error(self, *_):
        pass  # Expected socket interruption; never dump request diagnostics.


class LoopbackFixture:
    """Owns generated files and HTTP lifetime. Always call close() or use with.

    Example: with LoopbackFixture(resolve_tools()) as fixture: use fixture.url
    No fixture, server, or runtime binary is embedded in the application bundle.
    """
    def __init__(self, tools):
        self._temporary = tempfile.TemporaryDirectory(prefix="media-downloader-integration-")
        self.root = Path(self._temporary.name)
        self.server = None
        self.thread = None
        try:
            self._generate(tools)
            handler = functools.partial(QuietHandler, directory=str(self.root))
            self.server = FixtureHTTPServer(("127.0.0.1", 0), handler)
            self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
            self.thread.start()
            self.base_url = f"http://127.0.0.1:{self.server.server_port}"
            self.url = self.base_url + "/master.m3u8"
            self.slow_url = self.base_url + "/slow-master.m3u8"
            self.long_title_url = self.base_url + "/long-title.html"
        except BaseException:
            self.close()
            raise

    def _generate(self, tools):
        run_quiet([tools["FFMPEG"], "-nostdin", "-hide_banner", "-loglevel", "error",
                   "-f", "lavfi", "-i", "testsrc=size=320x180:rate=15",
                   "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100", "-t", "2",
                   "-c:v", "libx264", "-pix_fmt", "yuv420p", "-b:v", "256k",
                   "-c:a", "aac", "-b:a", "64k", "-f", "hls", "-hls_time", "1",
                   "-hls_playlist_type", "vod", "-hls_segment_filename", "segment-%03d.ts",
                   "-master_pl_name", "master.m3u8", "-var_stream_map", "v:0,a:0", "media.m3u8"], cwd=self.root)
        run_quiet([tools["FFMPEG"], "-nostdin", "-hide_banner", "-loglevel", "error",
                   "-i", "media.m3u8", "-c", "copy", "direct.mp4"], cwd=self.root)
        run_quiet([tools["FFMPEG"], "-nostdin", "-hide_banner", "-loglevel", "error",
                   "-i", "media.m3u8", "-vn", "-c:a", "copy", "-f", "hls", "-hls_playlist_type", "vod",
                   "-hls_segment_filename", "audio-%03d.ts", "audio.m3u8"], cwd=self.root)
        (self.root / "audio-master.m3u8").write_text(
            '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"\naudio.m3u8\n')
        (self.root / "metadata-unavailable.html").write_text(
            "<!doctype html><html><head><title>Fixture without media</title></head><body>No media.</body></html>")
        (self.root / "interrupted-master.m3u8").write_text(
            '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=352000,CODECS="avc1.64000c,mp4a.40.2"\ninterrupted.m3u8\n')
        (self.root / "interrupted.m3u8").write_text(
            "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:0\n"
            "#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:2.0,\nsegment-000.ts\n#EXTINF:2.0,\ninterrupted.ts\n#EXT-X-ENDLIST\n")

        (self.root / "missing-fragment-master.m3u8").write_text(
            (self.root / "interrupted-master.m3u8").read_text().replace("interrupted.m3u8", "missing-fragment.m3u8"))
        (self.root / "missing-fragment.m3u8").write_text(
            (self.root / "interrupted.m3u8").read_text().replace("interrupted.ts", "absent-fragment.ts"))

        (self.root / "slow-master.m3u8").write_text(
            (self.root / "interrupted-master.m3u8").read_text().replace("interrupted.m3u8", "slow.m3u8"))
        (self.root / "slow.m3u8").write_text(
            "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:0\n"
            "#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:2.0,\nslow.ts\n#EXT-X-ENDLIST\n")
        title = "Synthetic long title 🎬 % (title)s / " * 12
        (self.root / "long-title.html").write_text(
            f'<!doctype html><html><head><title>{title}</title></head>'
            '<body><video controls src="master.m3u8"></video></body></html>')

    def release_segments(self):
        """Release a controlled slow transfer (also done by close())."""
        self.server.segment_gate.set()

    def wait_for_segment(self, timeout=10):
        """True after a slow-segment request arrives; useful for GUI observation."""
        return self.server.segment_requested.wait(timeout)

    def close(self):
        if self.server is not None:
            self.server.segment_gate.set()
            if self.thread is not None:
                self.server.shutdown()
                self.thread.join()
            self.server.server_close()
            self.server = None
        self._temporary.cleanup()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    tools = resolve_tools()
    print_versions(tools)
    with LoopbackFixture(tools) as fixture:
        environment = dict(os.environ)
        environment.update({f"MEDIA_DOWNLOADER_{key}_PATH": value for key, value in tools.items()})
        environment["MEDIA_DOWNLOADER_INTEGRATION_URL"] = fixture.url
        result = subprocess.run(["/bin/bash", str(REPOSITORY / "scripts/test.sh"), "--filter", "RealToolIntegration"],
                                cwd=REPOSITORY, env=environment, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=240)
        for line in result.stdout.decode("utf-8", "replace").splitlines():
            if "Test run with" in line:
                print(line)
        print(f"Loopback integration: {'PASS' if result.returncode == 0 else 'FAIL'}", flush=True)
        return result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        # Timeout/OS messages can include argv or paths; do not emit them.
        print(str(error) if isinstance(error, RuntimeError) else "Integration setup or execution failed.", file=sys.stderr)
        sys.exit(1)
