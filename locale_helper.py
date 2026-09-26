#!/usr/bin/env python3
"""List UTF-8 locales, then safely generate and activate one with polkit."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

SUPPORTED = Path("/usr/share/i18n/SUPPORTED")
LOCALE_GEN = Path("/etc/locale.gen")
LOCALE_CONF = Path("/etc/locale.conf")
ISO_LANGUAGES = Path("/usr/share/iso-codes/json/iso_639-3.json")
ISO_TERRITORIES = Path("/usr/share/iso-codes/json/iso_3166-1.json")
CODE_RE = re.compile(r"^[A-Za-z0-9_@.-]+$")


def canonical_locale(code):
    base, separator, modifier = code.partition("@")
    if "." not in base:
        base += ".UTF-8"
    return base + (separator + modifier if separator else "")


def supported_locale_map(path=SUPPORTED):
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] == "UTF-8" and CODE_RE.fullmatch(parts[0]):
            result[canonical_locale(parts[0])] = parts[0]
    return result


def supported_locales(path=SUPPORTED):
    return sorted(supported_locale_map(path))


def installed_locales():
    result = subprocess.run(["/usr/bin/locale", "-a"], check=True, capture_output=True, text=True)
    return {value.lower().replace("utf8", "utf-8") for value in result.stdout.splitlines()}


def names(path, collection, keys):
    try:
        records = json.loads(path.read_text(encoding="utf-8"))[collection]
        return {record[key]: record["name"] for record in records for key in keys if record.get(key)}
    except (OSError, ValueError, KeyError):
        return {}


def display_name(code, languages, territories):
    base = code.replace(".UTF-8", "")
    modifier = base.split("@", 1)[1] if "@" in base else ""
    regionless = base.split("@", 1)[0]
    language, _, territory = regionless.partition("_")
    label = languages.get(language, language)
    if territory:
        label += " (" + territories.get(territory, territory) + ")"
    if modifier:
        label += " · " + modifier
    return label


def current_locale():
    try:
        content = LOCALE_CONF.read_text(encoding="utf-8")
    except OSError:
        return ""
    for line in content.splitlines():
        if line.startswith("LANG="):
            return line[5:].strip().strip('"\'')
    return ""


def list_locales():
    languages = names(ISO_LANGUAGES, "639-3", ("alpha_2", "alpha_3"))
    territories = names(ISO_TERRITORIES, "3166-1", ("alpha_2",))
    installed = installed_locales()
    active = current_locale()
    return [
        {"code": code, "name": display_name(code, languages, territories),
         "installed": code.lower() in installed, "active": code == active}
        for code in supported_locales()
    ]


def enable_locale(code, path=LOCALE_GEN):
    content = path.read_text(encoding="utf-8")
    target = code + " UTF-8"
    lines = content.splitlines(keepends=True)
    if any(line.strip() == target for line in lines):
        return False
    for index, line in enumerate(lines):
        if line.lstrip().startswith("#") and line.lstrip()[1:].strip() == target:
            prefix = line[:len(line) - len(line.lstrip())]
            lines[index] = prefix + target + ("\n" if line.endswith("\n") else "")
            break
    else:
        lines.append(("" if content.endswith("\n") or not content else "\n") + target + "\n")

    stat = path.stat()
    fd, temporary = tempfile.mkstemp(prefix=".locale.gen.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write("".join(lines))
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, stat.st_mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


def apply_locale(code):
    if os.geteuid() != 0:
        raise PermissionError("需要管理员授权才能修改系统语言")
    supported = supported_locale_map()
    if code not in supported:
        raise ValueError("不支持的 UTF-8 语言：" + code)
    if code.lower() not in installed_locales():
        enable_locale(supported[code])
        subprocess.run(["/usr/bin/locale-gen"], check=True, capture_output=True, text=True, timeout=120)
        if code.lower() not in installed_locales():
            raise RuntimeError("locale-gen 没有生成所选语言：" + code)
    subprocess.run(["/usr/bin/localectl", "set-locale", "LANG=" + code],
                   check=True, capture_output=True, text=True, timeout=30)


def main(argv):
    if argv == ["list"]:
        print(json.dumps({"locales": list_locales()}, ensure_ascii=False))
        return 0
    if len(argv) == 2 and argv[0] == "apply":
        apply_locale(argv[1])
        print(json.dumps({"ok": True, "code": argv[1]}))
        return 0
    print("用法：locale_helper.py list | apply <locale>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        detail = (error.stderr or "").strip() if isinstance(error, subprocess.CalledProcessError) else ""
        print(detail or str(error), file=sys.stderr)
        sys.exit(1)
