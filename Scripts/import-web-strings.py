#!/usr/bin/env python3
"""Fill missing hu/en/de translations in an Xcode string catalog from the Homassy web app's i18n JSON.

fill:  python3 Scripts/import-web-strings.py fill --catalog Homassy/Localizable.xcstrings
check: python3 Scripts/import-web-strings.py check Homassy/Localizable.xcstrings

Existing catalog values are never overwritten. Only keys already present in the catalog are filled.
"""
import argparse
import json
import re
import sys
from pathlib import Path

LANGUAGES = ("en", "hu", "de")
DEFAULT_WEB_LOCALES = Path("/Users/xentinus/Development/Homassy/Homassy.Web/i18n/locales")
DEFAULT_MAP = Path(__file__).resolve().parent / "web-string-map.json"
PLACEHOLDER = re.compile(r"\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}")
INTEGER_PLACEHOLDERS = {"count", "n", "total", "current", "days", "seconds", "items"}
PLURAL_FORMS = {2: ("one", "other"), 3: ("zero", "one", "other")}


def flatten(tree, prefix=""):
    flat = {}
    for key, value in tree.items():
        dotted = f"{prefix}.{key}" if prefix else key
        if isinstance(value, dict):
            flat.update(flatten(value, dotted))
        elif isinstance(value, str):
            flat[dotted] = value
    return flat


def convert_placeholders(text):
    return PLACEHOLDER.sub(lambda m: "%lld" if m.group(1) in INTEGER_PLACEHOLDERS else "%@", text)


def _unit(text):
    return {"stringUnit": {"state": "translated", "value": convert_placeholders(text)}}


def to_localization(web_value):
    parts = [part.strip() for part in web_value.split("|")]
    if len(parts) == 1:
        return _unit(parts[0])
    if len(parts) not in PLURAL_FORMS:
        raise ValueError(f"Unsupported plural with {len(parts)} forms: {web_value!r}")
    return {"variations": {"plural": {form: _unit(part) for form, part in zip(PLURAL_FORMS[len(parts)], parts)}}}


def has_value(localization):
    if not localization:
        return False
    unit = localization.get("stringUnit")
    if unit is not None:
        return bool(unit.get("value"))
    return bool(localization.get("variations"))


def fill_catalog(catalog, mapping, web):
    report = {"filled": [], "kept": [], "missing_web": [], "not_in_catalog": []}
    strings = catalog.setdefault("strings", {})
    for key, web_key in sorted(mapping.items()):
        if key not in strings:
            report["not_in_catalog"].append(key)
            continue
        localizations = strings[key].setdefault("localizations", {})
        for lang in LANGUAGES:
            if has_value(localizations.get(lang)):
                report["kept"].append((key, lang))
                continue
            web_value = web.get(lang, {}).get(web_key)
            if web_value is None:
                report["missing_web"].append((key, lang, web_key))
                continue
            localizations[lang] = to_localization(web_value)
            report["filled"].append((key, lang))
        if not localizations:
            del strings[key]["localizations"]
    return report


def check_catalog(catalog):
    missing = []
    for key, entry in sorted(catalog.get("strings", {}).items()):
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations", {})
        for lang in LANGUAGES:
            if not has_value(localizations.get(lang)):
                missing.append((key, lang))
    return missing


def load_web_locales(directory):
    directory = Path(directory)
    web = {}
    for lang in LANGUAGES:
        path = directory / f"{lang}.json"
        web[lang] = flatten(json.loads(path.read_text(encoding="utf-8"))) if path.exists() else {}
    return web


def read_catalog(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_catalog(path, catalog):
    text = json.dumps(catalog, indent=2, sort_keys=True, ensure_ascii=False, separators=(",", " : "))
    Path(path).write_text(text + "\n", encoding="utf-8")


def _print_report(report):
    for key, lang in report["filled"]:
        print(f"filled   {lang}  {key}")
    for key, lang, web_key in report["missing_web"]:
        print(f"missing  {lang}  {key}  (web key {web_key})")
    for key in report["not_in_catalog"]:
        print(f"skipped      {key}  (not in this catalog)")
    print(f"{len(report['filled'])} filled, {len(report['kept'])} kept, "
          f"{len(report['missing_web'])} missing in web, {len(report['not_in_catalog'])} not in catalog")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    fill = commands.add_parser("fill", help="fill missing translations from the web app")
    fill.add_argument("--catalog", required=True)
    fill.add_argument("--map", default=str(DEFAULT_MAP))
    fill.add_argument("--web-locales", default=str(DEFAULT_WEB_LOCALES))

    check = commands.add_parser("check", help="fail if any key lacks en, hu or de")
    check.add_argument("catalogs", nargs="+")

    args = parser.parse_args(argv)

    if args.command == "fill":
        catalog = read_catalog(args.catalog)
        mapping = json.loads(Path(args.map).read_text(encoding="utf-8"))
        report = fill_catalog(catalog, mapping, load_web_locales(args.web_locales))
        write_catalog(args.catalog, catalog)
        _print_report(report)
        return 0

    failed = False
    for path in args.catalogs:
        missing = check_catalog(read_catalog(path))
        for key, lang in missing:
            print(f"{path}: {key} has no {lang} value")
        failed = failed or bool(missing)
    if not failed:
        print("All keys have en, hu and de values.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
