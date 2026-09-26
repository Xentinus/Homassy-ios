#!/usr/bin/env python3
"""Usage strings and privacy manifest check (X-02).

Checks:
- the built app's Info.plist has every required usage string and no forbidden key
  ("Always" location, tracking, and the microphone/speech/Siri keys, since voice is not in v1);
- the app bundle has PrivacyInfo.xcprivacy and hu/en/de InfoPlist.strings with every key;
- Homassy/InfoPlist.xcstrings translates every key into hu, en and de;
- Homassy/PrivacyInfo.xcprivacy: no tracking, no tracking domains, no collected data,
  UserDefaults reasons CA92.1 + 1C8F.1, and a reason for every declared API category.
"""
import argparse
import json
import plistlib
import subprocess
import sys
from pathlib import Path

REQUIRED_USAGE_KEYS = (
    "NSCameraUsageDescription",
    "NSLocationWhenInUseUsageDescription",
)
FORBIDDEN_KEYS = (
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NSLocationAlwaysUsageDescription",
    "NSUserTrackingUsageDescription",
    # Siri and voice input are not in v1 (spec §7).
    "NSMicrophoneUsageDescription",
    "NSSpeechRecognitionUsageDescription",
    "NSSiriUsageDescription",
)
LANGUAGES = ("hu", "en", "de")
REQUIRED_REASONS = {"NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1", "1C8F.1"}}


def load_plist(path):
    """XML, binary or old-style (.strings) property lists."""
    data = Path(path).read_bytes()
    try:
        return plistlib.loads(data)
    except Exception:
        result = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)],
                                capture_output=True, check=True)
        return json.loads(result.stdout)


def check_info_plist(info):
    errors = []
    for key in REQUIRED_USAGE_KEYS:
        value = info.get(key)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"Info.plist: {key} is missing or empty")
    for key in FORBIDDEN_KEYS:
        if key in info:
            errors.append(f"Info.plist: {key} must not be present")
    return errors


def check_catalog(catalog):
    errors = []
    strings = catalog.get("strings", {})
    for key in REQUIRED_USAGE_KEYS:
        entry = strings.get(key)
        if entry is None:
            errors.append(f"InfoPlist.xcstrings: {key} is missing")
            continue
        localizations = entry.get("localizations", {})
        for lang in LANGUAGES:
            unit = localizations.get(lang, {}).get("stringUnit", {})
            if unit.get("state") != "translated" or not str(unit.get("value", "")).strip():
                errors.append(f"InfoPlist.xcstrings: {key} [{lang}] is not translated")
    return errors


def check_privacy(manifest):
    errors = []
    if manifest.get("NSPrivacyTracking") is not False:
        errors.append("PrivacyInfo: NSPrivacyTracking must be false")
    if manifest.get("NSPrivacyTrackingDomains", []) != []:
        errors.append("PrivacyInfo: NSPrivacyTrackingDomains must be empty")
    if manifest.get("NSPrivacyCollectedDataTypes", []) != []:
        errors.append("PrivacyInfo: NSPrivacyCollectedDataTypes must be empty")
    declared = {}
    for item in manifest.get("NSPrivacyAccessedAPITypes", []):
        declared[item.get("NSPrivacyAccessedAPIType", "")] = set(item.get("NSPrivacyAccessedAPITypeReasons", []))
    for category, reasons in REQUIRED_REASONS.items():
        missing = reasons - declared.get(category, set())
        if missing:
            errors.append(f"PrivacyInfo: {category} is missing reasons {sorted(missing)}")
    for category, reasons in declared.items():
        if not reasons:
            errors.append(f"PrivacyInfo: {category} is declared without a reason")
    return errors


def check_bundle(app):
    app = Path(app)
    errors = check_info_plist(load_plist(app / "Info.plist"))
    if not (app / "PrivacyInfo.xcprivacy").exists():
        errors.append("bundle: PrivacyInfo.xcprivacy is not in the app bundle")
    for lang in LANGUAGES:
        path = app / f"{lang}.lproj" / "InfoPlist.strings"
        if not path.exists():
            errors.append(f"bundle: {lang}.lproj/InfoPlist.strings is missing")
            continue
        compiled = load_plist(path)
        for key in REQUIRED_USAGE_KEYS:
            if not str(compiled.get(key, "")).strip():
                errors.append(f"bundle: {lang}.lproj/InfoPlist.strings has no {key}")
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", help="built Homassy.app to check")
    parser.add_argument("--catalog", default="Homassy/InfoPlist.xcstrings")
    parser.add_argument("--privacy", default="Homassy/PrivacyInfo.xcprivacy")
    args = parser.parse_args(argv)

    errors = check_catalog(json.loads(Path(args.catalog).read_text(encoding="utf-8")))
    errors += check_privacy(load_plist(args.privacy))
    if args.app:
        errors += check_bundle(args.app)
    else:
        print("note: --app not given; built bundle not checked", file=sys.stderr)

    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    if not errors:
        print("OK: usage strings (hu/en/de) and privacy manifest")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
