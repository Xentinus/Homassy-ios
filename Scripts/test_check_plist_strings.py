"""Tests for check_plist_strings.py. Run: python3 -m unittest discover -s Scripts -p 'test_*.py' -v"""
import json
import plistlib
import tempfile
import unittest
from pathlib import Path

import check_plist_strings as checker

REPO = Path(__file__).resolve().parent.parent
KEYS = checker.REQUIRED_USAGE_KEYS


def good_info():
    return {key: f"{key} text" for key in KEYS} | {"CFBundleIdentifier": "com.homassy.app"}


def good_catalog():
    return {"sourceLanguage": "en", "version": "1.0", "strings": {
        key: {"localizations": {lang: {"stringUnit": {"state": "translated", "value": f"{key} {lang}"}}
                                for lang in ("hu", "en", "de")}}
        for key in KEYS}}


def good_privacy():
    return {
        "NSPrivacyTracking": False,
        "NSPrivacyTrackingDomains": [],
        "NSPrivacyCollectedDataTypes": [],
        "NSPrivacyAccessedAPITypes": [{
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
            "NSPrivacyAccessedAPITypeReasons": ["CA92.1", "1C8F.1"],
        }],
    }


def make_bundle(root, info=None, languages=("hu", "en", "de"), privacy=True):
    app = Path(root) / "Homassy.app"
    app.mkdir()
    (app / "Info.plist").write_bytes(plistlib.dumps(info or good_info(), fmt=plistlib.FMT_BINARY))
    if privacy:
        (app / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps(good_privacy()))
    for lang in languages:
        (app / f"{lang}.lproj").mkdir()
        (app / f"{lang}.lproj" / "InfoPlist.strings").write_bytes(
            plistlib.dumps({key: f"{key} {lang}" for key in KEYS}, fmt=plistlib.FMT_BINARY))
    return app


class InfoPlistTests(unittest.TestCase):
    def test_good_info_passes(self):
        self.assertEqual(checker.check_info_plist(good_info()), [])

    def test_missing_key_fails(self):
        info = good_info()
        del info["NSLocationWhenInUseUsageDescription"]
        self.assertTrue(any("NSLocationWhenInUseUsageDescription" in e for e in checker.check_info_plist(info)))

    def test_empty_value_fails(self):
        info = good_info() | {"NSCameraUsageDescription": "  "}
        self.assertTrue(any("NSCameraUsageDescription" in e for e in checker.check_info_plist(info)))

    def test_always_location_is_forbidden(self):
        info = good_info() | {"NSLocationAlwaysAndWhenInUseUsageDescription": "x"}
        self.assertTrue(any("must not" in e for e in checker.check_info_plist(info)))

    def test_voice_and_siri_keys_are_forbidden_in_v1(self):
        for key in ("NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription", "NSSiriUsageDescription"):
            info = good_info() | {key: "x"}
            self.assertTrue(any(key in e and "must not" in e for e in checker.check_info_plist(info)), key)


class CatalogTests(unittest.TestCase):
    def test_good_catalog_passes(self):
        self.assertEqual(checker.check_catalog(good_catalog()), [])

    def test_missing_hungarian_fails(self):
        catalog = good_catalog()
        del catalog["strings"]["NSLocationWhenInUseUsageDescription"]["localizations"]["hu"]
        self.assertTrue(any("NSLocationWhenInUseUsageDescription [hu]" in e for e in checker.check_catalog(catalog)))

    def test_untranslated_state_fails(self):
        catalog = good_catalog()
        catalog["strings"]["NSCameraUsageDescription"]["localizations"]["de"]["stringUnit"]["state"] = "needs_review"
        self.assertTrue(any("NSCameraUsageDescription [de]" in e for e in checker.check_catalog(catalog)))

    def test_missing_key_fails(self):
        catalog = good_catalog()
        del catalog["strings"]["NSCameraUsageDescription"]
        self.assertTrue(any("NSCameraUsageDescription" in e for e in checker.check_catalog(catalog)))


class PrivacyTests(unittest.TestCase):
    def test_good_manifest_passes(self):
        self.assertEqual(checker.check_privacy(good_privacy()), [])

    def test_tracking_true_fails(self):
        self.assertTrue(checker.check_privacy(good_privacy() | {"NSPrivacyTracking": True}))

    def test_tracking_domains_fail(self):
        self.assertTrue(checker.check_privacy(good_privacy() | {"NSPrivacyTrackingDomains": ["example.com"]}))

    def test_collected_data_fails(self):
        self.assertTrue(checker.check_privacy(good_privacy() | {"NSPrivacyCollectedDataTypes": [{"NSPrivacyCollectedDataType": "x"}]}))

    def test_missing_app_group_reason_fails(self):
        manifest = good_privacy()
        manifest["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"] = ["CA92.1"]
        self.assertTrue(any("1C8F.1" in e for e in checker.check_privacy(manifest)))

    def test_category_without_reason_fails(self):
        manifest = good_privacy()
        manifest["NSPrivacyAccessedAPITypes"].append({
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
            "NSPrivacyAccessedAPITypeReasons": []})
        self.assertTrue(any("FileTimestamp" in e for e in checker.check_privacy(manifest)))


class BundleTests(unittest.TestCase):
    def test_good_bundle_passes(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(checker.check_bundle(make_bundle(root)), [])

    def test_missing_language_fails(self):
        with tempfile.TemporaryDirectory() as root:
            errors = checker.check_bundle(make_bundle(root, languages=("en", "de")))
            self.assertTrue(any("hu.lproj" in e for e in errors))

    def test_missing_manifest_in_bundle_fails(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertTrue(any("PrivacyInfo" in e for e in checker.check_bundle(make_bundle(root, privacy=False))))


class RepositoryTests(unittest.TestCase):
    def test_repository_catalog_and_manifest_pass(self):
        catalog = json.loads((REPO / "Homassy/InfoPlist.xcstrings").read_text(encoding="utf-8"))
        manifest = checker.load_plist(REPO / "Homassy/PrivacyInfo.xcprivacy")
        self.assertEqual(checker.check_catalog(catalog) + checker.check_privacy(manifest), [])


if __name__ == "__main__":
    unittest.main()
