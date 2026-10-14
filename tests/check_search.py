"""Check the actual search control without accessing the desktop clipboard."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def main():
    source = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="omarchy-search 中文 %-") as directory:
        root = Path(directory)
        plugin = root / "Plugin"
        plugin.mkdir()
        shutil.copytree(source / "CompatUi", plugin / "CompatUi")
        # Substitute only the reader in the temporary copy. The real reader's
        # resource bounds and cancellation are checked by test_clipboard_helper.
        (plugin / "clipboard_helper.py").write_text('''
import json, os, sys, time
from pathlib import Path
root = Path(__file__).parent
fixture = json.loads((root / "fixture.json").read_text())
(root / "paste.pid").write_text(str(os.getpid()))
time.sleep(fixture.get("delay", 0))
if "error" in fixture:
    print(json.dumps({"error": fixture["error"]}))
    sys.exit(1)
print(json.dumps({"text": fixture.get(sys.argv[1], fixture.get("text", "English"))}))
''')
        module = root / "SearchTestProbe"
        module.mkdir()
        (module / "qmldir").write_text("module SearchTestProbe\nplugin searchtestprobe\n")
        shutil.copy2(source / "tests/search_probe.cpp", module / "search_probe.cpp")
        flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "Qt6Gui", "Qt6Qml", "Qt6Quick"], text=True).split()
        qt_libexec = subprocess.check_output(["pkg-config", "--variable=libexecdir", "Qt6Core"], text=True).strip()
        for command in ([str(Path(qt_libexec) / "moc"), str(module / "search_probe.cpp"),
                         *[flag for flag in flags if flag.startswith("-I")],
                         "-o", str(module / "search_probe.moc")],
                        ["c++", "-std=c++17", "-fPIC", "-shared", str(module / "search_probe.cpp"),
                         "-o", str(module / "libsearchtestprobe.so"), *flags]):
            result = subprocess.run(command, capture_output=True, text=True)
            if result.returncode:
                raise SystemExit(result.stdout + result.stderr)
        for name in ("Commons", "Ui"):
            (root / name).symlink_to(Path('/usr/share/omarchy/shell') / name, target_is_directory=True)
        shutil.copy2(source / "tests/search.qml", root / "shell.qml")
        env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software",
               "QT_QUICK_CONTROLS_STYLE": "Basic", "QML_IMPORT_PATH": str(root),
               "XDG_CONFIG_HOME": str(root / "config"), "QS_DISABLE_FILE_WATCHER": "1"}
        env.pop("WAYLAND_DISPLAY", None)
        (root / "runtime").mkdir(mode=0o700)
        env["XDG_RUNTIME_DIR"] = str(root / "runtime")
        result = subprocess.run(["quickshell", "-p", str(root), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        if result.returncode or "PLUGIN_SEARCH_PASS" not in output or re.search(
                r"PLUGIN_SEARCH_FAIL|TypeError|ReferenceError|Unable to assign|ERROR:|Cannot read property", output):
            raise SystemExit(output)
        print("PASS: no eager clipboard reads; keyboard/IME, editing, scrolling, paste routes and cancellation")


if __name__ == "__main__":
    main()
