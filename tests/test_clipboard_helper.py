"""Exercise bounded transfers using disposable readers, never the real clipboard."""

import os
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import clipboard_helper as helper


class ClipboardTests(unittest.TestCase):
    def read(self, code, **options):
        return helper.read_clipboard(command=[sys.executable, "-c", code], **options)

    def rejected(self, reason, code, **options):
        with self.assertRaises(helper.ClipboardError) as raised:
            self.read(code, **options)
        self.assertEqual(str(raised.exception), reason)

    def test_unicode_plain_text_and_single_line(self):
        text = "中文\tEnglish\r\n日本語\u2028العربية\0"
        self.assertEqual(self.read(f"import os; os.write(1, {text!r}.encode())"),
                         "中文 English 日本語 العربية")

    def test_empty_clipboard(self):
        self.assertEqual(self.read("pass"), "")

    def test_exact_byte_limit(self):
        self.assertEqual(self.read("import os; os.write(1, b'x' * 4096)"), "x" * 4096)

    def test_limit_counts_bytes_not_characters(self):
        self.rejected("too-large", "import os; os.write(1, '中'.encode() * 1366)")

    def test_huge_clipboard_rejected_without_partial_result(self):
        self.rejected("too-large", "import os; os.write(1, b'x' * 10_000_000)")

    def test_continuous_transfer_rejected(self):
        self.rejected("too-large", "import os\nwhile True: os.write(1, b'x' * 4096)")

    def test_invalid_utf8(self):
        self.rejected("invalid-text", "import os; os.write(1, b'\\xff')")

    def test_no_data_deadline(self):
        started = time.monotonic()
        self.rejected("timeout", "import time; time.sleep(10)", timeout=0.2)
        self.assertLess(time.monotonic() - started, 1)

    def test_absolute_deadline_despite_frequent_chunks(self):
        started = time.monotonic()
        self.rejected("timeout", "import os, time\nwhile True:\n os.write(1, b'x')\n time.sleep(0.02)", timeout=0.2)
        self.assertLess(time.monotonic() - started, 1)

    def test_partial_transfer_that_never_finishes(self):
        self.rejected("timeout", "import os, time; os.write(1, b'English'); time.sleep(10)", timeout=0.2)

    def test_eof_does_not_bypass_child_exit_deadline(self):
        self.rejected("timeout", "import os, time; os.close(1); time.sleep(10)", timeout=0.2)

    def test_failed_reader_cannot_publish_partial_text(self):
        self.rejected("unavailable", "import os; os.write(1, b'partial'); exit(1)")

    def test_stderr_is_discarded(self):
        self.assertEqual(self.read("import os; os.write(2, b'x' * 1_000_000); os.write(1, b'English')"), "English")

    def test_missing_reader(self):
        with self.assertRaisesRegex(helper.ClipboardError, "unavailable"):
            helper.read_clipboard(command=["/nonexistent/clipboard-reader"])

    def test_cli_reports_unavailable_clipboard_without_desktop_access(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [sys.executable, "-I", helper.__file__, "clipboard"],
                env={**os.environ, "XDG_RUNTIME_DIR": directory, "WAYLAND_DISPLAY": "missing-test-clipboard"},
                capture_output=True, text=True, timeout=2,
            )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout), {"error": "unavailable"})
        self.assertEqual(result.stderr, "")

    @staticmethod
    def is_alive(pid):
        path = Path(f"/proc/{pid}/stat")
        return path.exists() and path.read_text().split(") ", 1)[1][0] != "Z"

    def check_cancel(self, cancellation, grandchild=False):
        with tempfile.TemporaryDirectory() as directory:
            pid_file = Path(directory) / "reader.pid"
            child_code = f"import os, time; open({str(pid_file)!r}, 'w').write(str(os.getpid())); time.sleep(10)"
            descendant_file = Path(directory) / "descendant.pid"
            if grandchild:
                descendant_code = (
                    "import os, signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                    f"open({str(descendant_file)!r}, 'w').write(str(os.getpid())); time.sleep(10)"
                )
                child_code = (
                    "import os, subprocess, sys, time; "
                    f"open({str(pid_file)!r}, 'w').write(str(os.getpid())); "
                    f"subprocess.Popen([sys.executable, '-c', {descendant_code!r}]); time.sleep(10)"
                )
            parent_code = (
                f"import sys, signal; sys.path.insert(0, {str(Path(helper.__file__).parent)!r}); "
                "import clipboard_helper as helper\n"
                "def cancel(*args): raise helper.ClipboardError('cancelled')\n"
                "signal.signal(signal.SIGTERM, cancel)\n"
                "try:\n"
                f" helper.read_clipboard(command=[sys.executable, '-c', {child_code!r}], timeout=10)\n"
                "except helper.ClipboardError: pass\n"
            )
            process = subprocess.Popen([sys.executable, "-c", parent_code],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 2
                while (not pid_file.exists() or (grandchild and not descendant_file.exists())) and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(pid_file.exists(), "reader did not start")
                reader_pid = int(pid_file.read_text())
                descendants = [int(descendant_file.read_text())] if grandchild else []
                process.send_signal(cancellation)
                _, errors = process.communicate(timeout=2)
                self.assertEqual(errors, b"")
                deadline = time.monotonic() + 1
                while self.is_alive(reader_pid) and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertFalse(self.is_alive(reader_pid), "reader survived owner cancellation")
                for descendant_pid in descendants:
                    deadline = time.monotonic() + 1
                    while self.is_alive(descendant_pid) and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertFalse(self.is_alive(descendant_pid), "reader descendant survived owner cancellation")
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate()
                for path in (pid_file, descendant_file):
                    if path.exists():
                        pid = int(path.read_text())
                        if self.is_alive(pid):
                            os.kill(pid, signal.SIGKILL)

    def test_sigterm_cancels_and_reaps_reader(self):
        self.check_cancel(signal.SIGTERM)

    def test_abrupt_owner_death_kills_reader(self):
        self.check_cancel(signal.SIGKILL)

    def test_sigterm_kills_reader_descendants(self):
        self.check_cancel(signal.SIGTERM, grandchild=True)

    def test_abrupt_owner_death_kills_reader_descendants(self):
        self.check_cancel(signal.SIGKILL, grandchild=True)


if __name__ == "__main__":
    unittest.main()
