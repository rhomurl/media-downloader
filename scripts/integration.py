#!/usr/bin/env python3
"""Credential-free, loopback-only real-tool integration; import LoopbackFixture for GUI checks."""
import argparse
import ctypes
import errno
import functools
import http.server
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time

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


class ShutdownUnconfirmed(RuntimeError):
    def __init__(self):
        super().__init__("Integration shutdown/cleanup unconfirmed; owned fixture files retained.")


class FixtureHTTPServer(http.server.ThreadingHTTPServer):
    def __init__(self, *args, **kwargs):
        self.segment_requested = threading.Event()
        self.segment_gate = threading.Event()
        self._worker_lock = threading.Lock()
        self._workers = set()
        self._requests = {}
        self._closing = False
        super().__init__(*args, **kwargs)

    def process_request(self, request, client_address):
        # Explicit tracking replaces ThreadingMixIn's daemon-thread exclusion.
        # A failed bounded join is a retention error, never permission to delete.
        with self._worker_lock:
            if self._closing:
                self.shutdown_request(request)
                return
            request.settimeout(5)
            worker = threading.Thread(target=self._serve_request,
                                      args=(request, client_address), daemon=True)
            self._workers.add(worker)
            self._requests[worker] = request
            try:
                worker.start()
            except BaseException:
                self._workers.remove(worker)
                self._requests.pop(worker)
                self.shutdown_request(request)
                raise

    def _serve_request(self, request, client_address):
        try:
            self.process_request_thread(request, client_address)
        finally:
            with self._worker_lock:
                self._requests.pop(threading.current_thread(), None)

    def server_close(self, timeout=2):
        self.segment_gate.set()
        with self._worker_lock:
            self._closing = True
            requests = list(self._requests.values())
            workers = list(self._workers)
        # shutdown wakes readers and writers even when makefile() owns another
        # reference to a socket. Closing the listening socket alone cannot do so.
        for request in requests:
            try:
                request.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            request.close()
        http.server.HTTPServer.server_close(self)
        deadline = time.monotonic() + timeout
        for worker in workers:
            worker.join(max(0, deadline - time.monotonic()))
        if any(worker.is_alive() for worker in workers):
            raise ShutdownUnconfirmed()

    def handle_error(self, *_):
        pass  # Expected socket interruption; never dump request diagnostics.


class LoopbackFixture:
    """Owns generated files and HTTP lifetime. Always call close() or use with.

    Example: with LoopbackFixture(resolve_tools()) as fixture: use fixture.url
    No fixture, server, or runtime binary is embedded in the application bundle.
    """
    def __init__(self, tools):
        self.root = Path(tempfile.mkdtemp(prefix="media-downloader-integration-"))
        # No automatic TemporaryDirectory finalizer may bypass retention.
        self._retain_root = False
        self.server = None
        self.thread = None
        try:
            self._generate(tools)
            handler = functools.partial(QuietHandler, directory=str(self.root))
            self.server = FixtureHTTPServer(("127.0.0.1", 0), handler)
            self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True)
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

    def retain_root(self):
        self._retain_root = True

    def close(self):
        try:
            if self.server is not None:
                self.server.segment_gate.set()
                if self.thread is not None and self.thread.ident is not None:
                    self.server.shutdown()
                    self.thread.join(2)
                    if self.thread.is_alive():
                        raise ShutdownUnconfirmed()
                self.server.server_close()
                self.server = None
        except BaseException:
            self.retain_root()
            raise
        if self._retain_root:
            raise ShutdownUnconfirmed()
        if self.root.exists():
            shutil.rmtree(self.root)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


class _BSDInfo(ctypes.Structure):
    # Darwin proc_bsdinfo from sys/proc_info.h; numeric identity fields only.
    _fields_ = [(name, ctypes.c_uint32) for name in (
        "flags", "status", "xstatus", "pid", "ppid", "uid", "gid", "ruid",
        "rgid", "svuid", "svgid", "reserved")]
    _fields_ += [("comm", ctypes.c_char * 16), ("name", ctypes.c_char * 32)]
    _fields_ += [(name, ctypes.c_uint32) for name in (
        "nfiles", "pgid", "jobc", "tdev", "tpgid")]
    _fields_ += [("nice", ctypes.c_int32), ("start_seconds", ctypes.c_uint64),
                ("start_microseconds", ctypes.c_uint64)]


class _OwnedDriverTree:
    """Bounded known-PID ancestry tracking, not arbitrary daemon containment.

    Only libproc children of already proven owned PIDs are inspected. Signals
    require matching PID/start-time/UID identity. Forced outcomes always retain
    the fixture: snapshots cannot prove absence of fast fork/reparent escapes.
    """
    def __init__(self, process):
        self.process = process
        self.known = {}
        self.uncertain = False
        if sys.platform != "darwin":
            raise RuntimeError("Owned integration-driver supervision requires macOS.")
        self.lib = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
        self.lib.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64,
                                         ctypes.c_void_p, ctypes.c_int]
        self.lib.proc_listchildpids.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
        info = self.info(process.pid)
        if info is None:
            self.uncertain = True
        else:
            self.known[process.pid] = (self.identity(info), info.ppid)

    @staticmethod
    def identity(info):
        return info.pid, info.start_seconds, info.start_microseconds, info.uid

    def info(self, pid):
        info = _BSDInfo()
        ctypes.set_errno(0)
        count = self.lib.proc_pidinfo(pid, 3, 0, ctypes.byref(info), ctypes.sizeof(info))
        if count == 0 and ctypes.get_errno() == errno.ESRCH:
            return None
        if count != ctypes.sizeof(info):
            self.uncertain = True
            return None
        return info

    def current(self, pid):
        info = self.info(pid)
        if info is None:
            return None
        if self.identity(info) != self.known[pid][0]:
            self.uncertain = True  # Reused PID must never be signalled.
            return None
        if info.status == 5:  # SZOMB: no execution or open readers remain.
            return None
        if info.ppid != self.known[pid][1]:
            self.uncertain = True
        return info

    def observe(self):
        pending = list(self.known)
        visited = set()
        while pending:
            pid = pending.pop()
            if pid in visited or self.current(pid) is None:
                continue
            visited.add(pid)
            children = (ctypes.c_int * 4096)()
            ctypes.set_errno(0)
            count = self.lib.proc_listchildpids(pid, children, ctypes.sizeof(children))
            if count < 0 or count >= 4096 or (count == 0 and ctypes.get_errno() not in (0, errno.ESRCH)):
                self.uncertain = True
                continue
            for child in children[:count]:
                info = self.info(child)
                if info is None:
                    continue
                if info.ppid != pid or info.uid != os.geteuid():
                    self.uncertain = True
                    continue
                if child not in self.known:
                    if len(self.known) >= 4096:
                        self.uncertain = True
                        continue
                    self.known[child] = (self.identity(info), pid)
                pending.append(child)

    def live(self):
        return [pid for pid in self.known if self.current(pid) is not None]

    def send(self, pid, sig):
        if self.current(pid) is not None:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
            except OSError:
                self.uncertain = True

    def stop(self):
        # Stop known parents before recursive discovery; separately owned groups
        # are covered by identities, not an assumption that killpg reaches them.
        for _ in range(3):
            self.observe()
            for pid in list(self.known):
                self.send(pid, signal.SIGSTOP)
        for pid in reversed(list(self.known)):
            self.send(pid, signal.SIGTERM)
            self.send(pid, signal.SIGCONT)
        deadline = time.monotonic() + 2
        while self.live() and time.monotonic() < deadline:
            self.observe()
            self.process.poll()  # Reap only our immediate child.
            time.sleep(0.01)
        self.observe()
        for pid in reversed(list(self.known)):
            self.send(pid, signal.SIGKILL)
        # Popen owns this unreaped immediate PID even if inspection failed.
        if self.process.poll() is None:
            self.process.kill()
        try:
            self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.uncertain = True
        deadline = time.monotonic() + 2
        while self.live() and time.monotonic() < deadline:
            self.observe()
            for pid in self.live():
                self.send(pid, signal.SIGKILL)
            time.sleep(0.01)
        if self.live():
            self.uncertain = True


def run_test_driver(arguments, *, fixture, timeout=240, **kwargs):
    process = None
    tree = None
    old_term = None
    if threading.current_thread() is threading.main_thread():
        old_term = signal.getsignal(signal.SIGTERM)
        def interrupted(*_):
            raise KeyboardInterrupt()
        signal.signal(signal.SIGTERM, interrupted)
    try:
        process = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   start_new_session=True, **kwargs)
        tree = _OwnedDriverTree(process)
        deadline = time.monotonic() + timeout
        while True:
            tree.observe()
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(arguments, timeout)
            try:
                output, _ = process.communicate(timeout=min(0.05, remaining))
                break
            except subprocess.TimeoutExpired:
                continue
        tree.observe()
        remaining_live = tree.live()
        if process.returncode != 0 or tree.uncertain or remaining_live:
            fixture.retain_root()
            tree.stop()
        return subprocess.CompletedProcess(arguments, process.returncode, output)
    except BaseException:
        fixture.retain_root()
        if tree is not None:
            tree.stop()
        elif process is not None:
            process.kill()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
        raise
    finally:
        if process is not None and process.stdout is not None:
            process.stdout.close()
        if old_term is not None:
            signal.signal(signal.SIGTERM, old_term)


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    tools = resolve_tools()
    print_versions(tools)
    with LoopbackFixture(tools) as fixture:
        environment = dict(os.environ)
        environment.update({f"MEDIA_DOWNLOADER_{key}_PATH": value for key, value in tools.items()})
        environment["MEDIA_DOWNLOADER_INTEGRATION_URL"] = fixture.url
        result = run_test_driver(["/bin/bash", str(REPOSITORY / "scripts/test.sh"), "--filter", "RealToolIntegration"],
                                 fixture=fixture, cwd=REPOSITORY, env=environment)
        for line in result.stdout.decode("utf-8", "replace").splitlines():
            if "Test run with" in line:
                print(line)
    print(f"Loopback integration: {'PASS' if result.returncode == 0 else 'FAIL'}", flush=True)
    return result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        # Timeout/OS messages can include argv or paths; do not emit them.
        print(str(error) if isinstance(error, RuntimeError) else "Integration setup or execution failed.", file=sys.stderr)
        sys.exit(1)
