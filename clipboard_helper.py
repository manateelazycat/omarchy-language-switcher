#!/usr/bin/env python3
"""Read a small clipboard selection without blocking the shared shell."""

import ctypes
import json
import os
import re
import resource
import selectors
import signal
import subprocess
import sys
import time

MAX_BYTES = 4096
TIMEOUT = 1.0
CHILD_MEMORY_LIMIT = 128 * 1024 * 1024


class ClipboardError(Exception):
    pass


def read_clipboard(primary=False, *, command=None, max_bytes=MAX_BYTES, timeout=TIMEOUT):
    """Collect at most max_bytes, including an absolute deadline for child exit.

    command is only used by isolated tests; the CLI always executes wl-paste.
    Nothing is published until the transfer completes successfully.
    """
    if command is None:
        command = ["/usr/bin/wl-paste", "--no-newline", "--type", "text"]
        if primary:
            command.append("--primary")
    deadline = time.monotonic() + timeout
    parent_pid = os.getpid()
    libc = ctypes.CDLL(None, use_errno=True)
    # wl-paste forks cat. On parent death the timeout supervisor receives an
    # alarm and kills its entire group, even if Python cannot run its cleanup.
    reader = ["/usr/bin/timeout", "--signal=KILL", f"{timeout}s", *command]

    def prepare_child():
        # This helper is single-threaded and runs only on Linux. Also kill the
        # supervisor if the QML owner kills this helper before its finally block.
        if libc.prctl(1, signal.SIGALRM, 0, 0, 0) != 0:
            os._exit(1)
        if os.getppid() != parent_pid:
            os._exit(1)
        resource.setrlimit(resource.RLIMIT_AS, (CHILD_MEMORY_LIMIT, CHILD_MEMORY_LIMIT))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

    try:
        process = subprocess.Popen(reader, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                   start_new_session=True, preexec_fn=prepare_child,
                                   env={**os.environ, "PATH": "/usr/bin:/bin"})
    except (OSError, subprocess.SubprocessError) as error:
        raise ClipboardError("unavailable") from error
    try:
        data = bytearray()
        os.set_blocking(process.stdout.fileno(), False)
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise ClipboardError("timeout")
                chunk = os.read(process.stdout.fileno(), max_bytes + 1 - len(data))
                if not chunk:
                    break
                data.extend(chunk)
                if len(data) > max_bytes:
                    raise ClipboardError("too-large")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ClipboardError("timeout")
        try:
            status = process.wait(timeout=remaining)
        except subprocess.TimeoutExpired as error:
            raise ClipboardError("timeout") from error
        if status != 0:
            raise ClipboardError("unavailable")
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError as error:
            raise ClipboardError("invalid-text") from error
        # Search stays on one line; never interpret clipboard content as markup.
        return re.sub(r"[\r\n\t\u2028\u2029]+", " ", text).replace("\0", "")
    finally:
        # Kill the whole reader group, close the pipe, and reap our child on
        # success, rejection, timeout, or SIGTERM cancellation.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.stdout.close()
        process.wait()


def main():
    cancelled = False

    def cancel(_signal, _frame):
        nonlocal cancelled
        if cancelled:
            return
        cancelled = True
        raise ClipboardError("cancelled")

    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)
    if sys.argv[1:] not in (["clipboard"], ["primary"]):
        return 2
    try:
        text = read_clipboard(primary=sys.argv[1] == "primary")
        result = {"text": text}
        status = 0
    except ClipboardError as error:
        result = {"error": str(error)}
        status = 1
    print(json.dumps(result, ensure_ascii=False))
    return status


if __name__ == "__main__":
    sys.exit(main())
