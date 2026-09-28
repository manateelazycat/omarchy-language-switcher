"""Exercise installer ownership decisions without touching system paths."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1]


class InstallScriptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.project = self.root / "project"
        self.project.mkdir()
        for name in ("install.sh", "uninstall.sh", "helper-installation.sh", "locale_helper.py"):
            shutil.copy2(SOURCE / name, self.project / name)

        self.libexec = self.root / "libexec"
        self.helper = self.libexec / "omarchy-language-switcher-helper"
        self.receipt = self.libexec / "omarchy-language-switcher-helper.receipt"
        common = self.project / "helper-installation.sh"
        common.write_text(common.read_text().replace(
            'helper_dir="/usr/local/libexec"', f'helper_dir="{self.libexec}"'))

        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        self.stub(bin_dir, "sudo", """
if [[ "$1" == install ]]; then
  shift
  args=()
  while (($#)); do
    case "$1" in
      -o|-g) shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  exec /usr/bin/install "${args[@]}"
fi
exec "$@"
""")
        self.stub(bin_dir, "stat", """
if [[ "$1" == -c && "$2" == '%u %a' ]]; then
  mode="$(/usr/bin/stat -c '%a' -- "${@: -1}")" || exit 1
  printf '0 %s\n' "$mode"
else
  exec /usr/bin/stat "$@"
fi
""")
        self.stub(bin_dir, "omarchy", """
if [[ "$1 $2" == 'plugin list' ]]; then
  echo '[{"id":"andy.language-switcher"}]'
elif [[ "$1 $2" == 'plugin remove' ]]; then
  rm -- "$XDG_CONFIG_HOME/omarchy/plugins/andy.language-switcher"
fi
""")
        self.stub(bin_dir, "omarchy-shell", "exit 0")
        self.stub(bin_dir, "jq", "cat >/dev/null")
        self.stub(bin_dir, "date", "echo 20260928123456")
        self.env = os.environ.copy()
        self.env["PATH"] = f"{bin_dir}:{self.env['PATH']}"
        self.env["XDG_CONFIG_HOME"] = str(self.root / "config")

    @staticmethod
    def stub(bin_dir, name, body):
        path = bin_dir / name
        path.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + body)
        path.chmod(0o755)

    def run_script(self, name):
        return subprocess.run(
            [str(self.project / name)], cwd=self.project, env=self.env,
            capture_output=True, text=True, timeout=10,
        )

    def test_foreign_helper_is_never_replaced_or_removed(self):
        self.libexec.mkdir()
        self.helper.write_text("foreign helper\n")
        for script in ("install.sh", "uninstall.sh"):
            result = self.run_script(script)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("安装记录不完整", result.stderr)
            self.assertEqual(self.helper.read_text(), "foreign helper\n")
            self.assertFalse(self.receipt.exists())

    def test_install_update_and_uninstall_owned_helper(self):
        config = self.root / "config" / "omarchy" / "shell.json"
        config.parent.mkdir(parents=True)
        config.write_text('{"bar": []}\n')
        result = self.run_script("install.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.helper.read_bytes(), (self.project / "locale_helper.py").read_bytes())
        self.assertTrue(self.receipt.exists())
        backups = list(config.parent.glob("shell.json.bak.language-switcher.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), config.read_bytes())

        with (self.project / "locale_helper.py").open("a") as source:
            source.write("\n# updated\n")
        result = self.run_script("install.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.helper.read_bytes(), (self.project / "locale_helper.py").read_bytes())
        backups = list(config.parent.glob("shell.json.bak.language-switcher.*"))
        self.assertEqual(len(backups), 2)
        self.assertTrue(all(path.read_bytes() == config.read_bytes() for path in backups))

        result = self.run_script("uninstall.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.helper.exists())
        self.assertFalse(self.receipt.exists())

    def test_existing_backup_symlink_is_not_followed(self):
        config = self.root / "config" / "omarchy" / "shell.json"
        config.parent.mkdir(parents=True)
        config.write_text('{"bar": []}\n')
        target = self.root / "other-user-file"
        target.write_text("keep this content\n")
        legacy_backup = config.parent / "shell.json.bak.language-switcher.20260928123456"
        legacy_backup.symlink_to(target)

        result = self.run_script("install.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(legacy_backup.is_symlink())
        self.assertEqual(target.read_text(), "keep this content\n")
        backups = [path for path in config.parent.glob("shell.json.bak.language-switcher.*")
                   if path != legacy_backup]
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), config.read_bytes())

    def test_modified_owned_helper_is_preserved(self):
        result = self.run_script("install.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.helper.write_text("changed by another administrator\n")
        for script in ("install.sh", "uninstall.sh"):
            result = self.run_script(script)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("内容已变化", result.stderr)
            self.assertEqual(self.helper.read_text(), "changed by another administrator\n")


if __name__ == "__main__":
    unittest.main()
