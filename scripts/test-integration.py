#!/usr/bin/env python3
"""Synthetic harness lifecycle regressions: no tools, browsers, or remote sites."""
import _thread
import importlib.util
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import threading
import time
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location("integration", Path(__file__).with_name("integration.py"))
integration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(integration)


class SyntheticFixture(integration.LoopbackFixture):
    def _generate(self, _):
        (self.root / "segment-000.ts").write_bytes(b"x" * (4 * 1024 * 1024))


def stopped(pid):
    # Test-owned PIDs only. Zombies have ceased execution even before launchd reaps.
    result = subprocess.run(["/bin/ps", "-o", "stat=", "-p", str(pid)], stdout=subprocess.PIPE)
    return result.returncode != 0 or result.stdout.lstrip().startswith(b"Z")


def close_fixture(fixture):
    try:
        fixture.close()
    except RuntimeError:
        pass  # Expected fail-closed retention on a forced/uncertain outcome.


class HarnessLifecycleTests(unittest.TestCase):
    def driver_case(self, interrupt, terminate=False):
        fixture = SyntheticFixture({})
        root = fixture.root
        known = []
        script = """
import os, pathlib, signal, subprocess, sys, time
root=pathlib.Path(sys.argv[1])
child=subprocess.Popen([sys.executable,'-c','import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(60)'], start_new_session=True)
(root/'pids').write_text(str(os.getpid())+' '+str(child.pid))
time.sleep(60)
"""
        callback = (lambda: os.kill(os.getpid(), signal.SIGTERM)) if terminate else _thread.interrupt_main
        timer = threading.Timer(0.5, callback) if interrupt else None
        try:
            if timer:
                timer.start()
            expected = KeyboardInterrupt if interrupt else subprocess.TimeoutExpired
            with self.assertRaises(expected):
                integration.run_test_driver([sys.executable, "-c", script, str(root)],
                                            fixture=fixture, timeout=2 if interrupt else 0.5)
            known = [int(value) for value in (root / "pids").read_text().split()]
            close_fixture(fixture)
            self.assertTrue(all(stopped(pid) for pid in known), "owned driver/independent-group descendant survived")
            self.assertTrue(root.exists(), "forced driver outcome must retain fixture root")
        finally:
            if timer:
                timer.cancel()
                timer.join()
            if not known and (root / "pids").exists():
                known = [int(value) for value in (root / "pids").read_text().split()]
            for pid in reversed(known):
                if not stopped(pid):
                    os.kill(pid, signal.SIGKILL)
            close_fixture(fixture)
            # Regression owns these exact generated files and known synthetic PIDs.
            # Removal is safe after the explicit post-failure test cleanup.
            for pid in known:
                deadline = time.monotonic() + 3
                while not stopped(pid) and time.monotonic() < deadline:
                    time.sleep(0.01)
            if root.exists() and all(stopped(pid) for pid in known):
                import shutil
                shutil.rmtree(root)

    def test_timeout_stops_separate_group_descendant_and_retains_root(self):
        self.driver_case(False)

    def test_interruption_stops_separate_group_descendant_and_retains_root(self):
        self.driver_case(True)

    def test_sigterm_stops_separate_group_descendant_and_retains_root(self):
        self.driver_case(True, terminate=True)

    def test_nonzero_driver_retains_root(self):
        fixture = SyntheticFixture({})
        root = fixture.root
        try:
            result = integration.run_test_driver([sys.executable, "-c", "raise SystemExit(7)"], fixture=fixture)
            self.assertEqual(result.returncode, 7)
            close_fixture(fixture)
            self.assertTrue(root.exists())
        finally:
            close_fixture(fixture)
            if root.exists():
                import shutil
                shutil.rmtree(root)

    def test_incomplete_process_inspection_retains_root(self):
        fixture = SyntheticFixture({})
        root = fixture.root
        try:
            with mock.patch.object(integration._OwnedDriverTree, "info", return_value=None):
                result = integration.run_test_driver([sys.executable, "-c", "pass"], fixture=fixture)
            self.assertEqual(result.returncode, 0)
            close_fixture(fixture)
            self.assertTrue(root.exists())
        finally:
            close_fixture(fixture)
            if root.exists():
                import shutil
                shutil.rmtree(root)

    def test_uncertainty_first_discovered_in_final_live_lookup_retains_root(self):
        # No process/socket is created. Keep the real live()/current() behavior;
        # inspection first becomes uncertain only inside the final predicate.
        process = mock.Mock(returncode=0)
        process.communicate.return_value = (b"", None)
        tree = integration._OwnedDriverTree.__new__(integration._OwnedDriverTree)
        tree.process = process
        tree.known = {123: ((123, 1, 0, 501), 1)}
        tree.uncertain = False
        tree.observe = mock.Mock()
        tree.stop = mock.Mock()
        def unavailable_at_final_lookup(pid):
            self.assertFalse(tree.uncertain)
            tree.uncertain = True
            return None
        tree.info = mock.Mock(side_effect=unavailable_at_final_lookup)
        fixture = mock.Mock()
        with mock.patch.object(integration.subprocess, "Popen", return_value=process), \
             mock.patch.object(integration, "_OwnedDriverTree", return_value=tree):
            result = integration.run_test_driver(["/synthetic/driver"], fixture=fixture)
        self.assertEqual(result.returncode, 0)
        tree.info.assert_called_once_with(123)
        self.assertTrue(tree.uncertain)
        fixture.retain_root.assert_called_once_with()
        tree.stop.assert_called_once_with()

    def test_unjoinable_http_worker_retains_root(self):
        fixture = SyntheticFixture({})
        root = fixture.root
        entered = threading.Event()
        release = threading.Event()
        class StalledHandler(integration.QuietHandler):
            def handle(self):
                entered.set()
                release.wait()
        fixture.server.RequestHandlerClass = StalledHandler
        client = socket.create_connection(("127.0.0.1", fixture.server.server_port), timeout=2)
        try:
            self.assertTrue(entered.wait(2))
            started = time.monotonic()
            with self.assertRaises(integration.ShutdownUnconfirmed):
                fixture.close()
            self.assertLess(time.monotonic() - started, 3)
            self.assertTrue(root.exists())
        finally:
            release.set()
            client.close()
            close_fixture(fixture)
            if root.exists():
                import shutil
                shutil.rmtree(root)

    def test_successful_driver_cleans_root(self):
        with SyntheticFixture({}) as fixture:
            root = fixture.root
            result = integration.run_test_driver([sys.executable, "-c", "pass"], fixture=fixture)
            self.assertEqual(result.returncode, 0)
        self.assertFalse(root.exists())

    def test_partial_http_request_worker_is_joined_before_cleanup(self):
        self.http_case(False)

    def test_stalled_http_writer_is_joined_before_cleanup(self):
        self.http_case(True)

    def http_case(self, writer):
        fixture = SyntheticFixture({})
        root = fixture.root
        baseline = set(threading.enumerate())
        client = socket.create_connection(("127.0.0.1", fixture.server.server_port), timeout=2)
        try:
            client.sendall(b"GET /slow.ts HTTP/1.1\r\nHost: localhost\r\n" + (b"\r\n" if writer else b""))
            if writer:
                self.assertTrue(fixture.wait_for_segment(2))
            deadline = time.monotonic() + 2
            workers = []
            while not workers and time.monotonic() < deadline:
                workers = list(set(threading.enumerate()) - baseline)
                time.sleep(0.01)
            self.assertTrue(workers)
            started = time.monotonic()
            fixture.close()
            self.assertLess(time.monotonic() - started, 3)
            self.assertTrue(all(not worker.is_alive() for worker in workers), "HTTP worker survived fixture deletion")
            self.assertFalse(root.exists())
        finally:
            client.close()
            close_fixture(fixture)
            for worker in locals().get("workers", []):
                worker.join(3)


if __name__ == "__main__":
    unittest.main()
