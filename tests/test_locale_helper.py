import tempfile
from pathlib import Path
import unittest
import sys
from unittest.mock import call, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import locale_helper as helper


class LocaleHelperTests(unittest.TestCase):
    def test_supported_locales_accept_utf8_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "SUPPORTED"
            path.write_text("zh_CN.UTF-8 UTF-8\naa_ER UTF-8\nbe_BY@latin UTF-8\nen_US ISO-8859-1\n../bad UTF-8\n", encoding="utf-8")
            self.assertEqual(helper.supported_locales(path),
                             ["aa_ER.UTF-8", "be_BY.UTF-8@latin", "zh_CN.UTF-8"])

    def test_enable_locale_uncomments_without_duplicate(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "locale.gen"
            path.write_text("en_US.UTF-8 UTF-8\n#zh_CN.UTF-8 UTF-8  \n", encoding="utf-8")
            self.assertTrue(helper.enable_locale("zh_CN.UTF-8", path))
            self.assertFalse(helper.enable_locale("zh_CN.UTF-8", path))
            self.assertEqual(path.read_text(encoding="utf-8"),
                             "en_US.UTF-8 UTF-8\nzh_CN.UTF-8 UTF-8\n")

    def test_apply_generates_missing_locale_before_switching(self):
        with patch.object(helper.os, "geteuid", return_value=0), \
             patch.object(helper, "supported_locale_map", return_value={"aa_ER.UTF-8": "aa_ER"}), \
             patch.object(helper, "installed_locales", side_effect=[set(), {"aa_er.utf-8"}]), \
             patch.object(helper, "enable_locale") as enable, \
             patch.object(helper.subprocess, "run") as run:
            helper.apply_locale("aa_ER.UTF-8")
        enable.assert_called_once_with("aa_ER")
        self.assertEqual(run.call_args_list, [
            call(["/usr/bin/locale-gen"], check=True, capture_output=True, text=True, timeout=120),
            call(["/usr/bin/localectl", "set-locale", "LANG=aa_ER.UTF-8"],
                 check=True, capture_output=True, text=True, timeout=30),
        ])

    def test_apply_rejects_unknown_locale(self):
        with patch.object(helper.os, "geteuid", return_value=0), \
             patch.object(helper, "supported_locale_map", return_value={"en_US.UTF-8": "en_US.UTF-8"}), \
             patch.object(helper.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                helper.apply_locale("not_a_locale")
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
