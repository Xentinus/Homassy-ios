import copy
import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("import_web_strings", HERE / "import-web-strings.py")
iws = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(iws)

FIXTURES = HERE / "fixtures"
MAPPING = {
    "common.cancel": "common.cancel",
    "space.personal.name": "common.personal",
    "undo.action": "undo.action",
    "undo.item.delete %@": "undo.item.delete",
    "undo.collapsed.delete %lld": "undo.collapsed.delete",
    "only.english": "onlyEnglish",
    "not.in.catalog": "common.cancel",
}


def value(catalog, key, lang):
    return catalog["strings"][key]["localizations"][lang]


class FlattenTests(unittest.TestCase):
    def test_flattens_nested_keys_with_dots(self):
        flat = iws.flatten({"a": {"b": {"c": "x"}, "d": "y"}, "e": "z"})
        self.assertEqual(flat, {"a.b.c": "x", "a.d": "y", "e": "z"})

    def test_skips_non_string_leaves(self):
        self.assertEqual(iws.flatten({"a": 1, "b": ["x"], "c": "ok"}), {"c": "ok"})


class PlaceholderTests(unittest.TestCase):
    def test_count_like_names_become_integers(self):
        self.assertEqual(iws.convert_placeholders("{count} items"), "%lld items")
        self.assertEqual(iws.convert_placeholders("Step {current} of {total}"), "Step %lld of %lld")

    def test_other_names_become_objects(self):
        self.assertEqual(iws.convert_placeholders("{name} removed"), "%@ removed")
        self.assertEqual(iws.convert_placeholders("{ list }"), "%@")

    def test_text_without_placeholders_is_unchanged(self):
        self.assertEqual(iws.convert_placeholders("Undo"), "Undo")


class LocalizationTests(unittest.TestCase):
    def test_single_form_is_a_string_unit(self):
        self.assertEqual(iws.to_localization("Undo"),
                         {"stringUnit": {"state": "translated", "value": "Undo"}})

    def test_two_forms_are_one_and_other(self):
        loc = iws.to_localization("1 item removed | {count} items removed")
        plural = loc["variations"]["plural"]
        self.assertEqual(plural["one"]["stringUnit"]["value"], "1 item removed")
        self.assertEqual(plural["other"]["stringUnit"]["value"], "%lld items removed")

    def test_three_forms_are_zero_one_other(self):
        plural = iws.to_localization("none | one | {count} many")["variations"]["plural"]
        self.assertEqual(sorted(plural), ["one", "other", "zero"])

    def test_more_than_three_forms_is_an_error(self):
        with self.assertRaises(ValueError):
            iws.to_localization("a | b | c | d")

    def test_has_value(self):
        self.assertFalse(iws.has_value(None))
        self.assertFalse(iws.has_value({"stringUnit": {"state": "new", "value": ""}}))
        self.assertTrue(iws.has_value({"stringUnit": {"state": "translated", "value": "x"}}))
        self.assertTrue(iws.has_value(iws.to_localization("a | b")))


class FillTests(unittest.TestCase):
    def setUp(self):
        self.catalog = iws.read_catalog(FIXTURES / "catalog.xcstrings")
        self.web = iws.load_web_locales(FIXTURES / "web")

    def test_fills_missing_languages(self):
        iws.fill_catalog(self.catalog, MAPPING, self.web)
        self.assertEqual(value(self.catalog, "space.personal.name", "hu")["stringUnit"]["value"], "Személyes")
        self.assertEqual(value(self.catalog, "space.personal.name", "de")["stringUnit"]["value"], "Persönlich")
        self.assertEqual(value(self.catalog, "undo.item.delete %@", "de")["stringUnit"]["value"], "%@ entfernt")

    def test_never_overwrites_an_existing_value(self):
        iws.fill_catalog(self.catalog, MAPPING, self.web)
        self.assertEqual(value(self.catalog, "common.cancel", "hu")["stringUnit"]["value"], "Mégsem")
        self.assertEqual(value(self.catalog, "common.cancel", "de")["stringUnit"]["value"], "Abbrechen")

    def test_replaces_an_empty_new_value(self):
        iws.fill_catalog(self.catalog, MAPPING, self.web)
        self.assertEqual(value(self.catalog, "undo.action", "hu")["stringUnit"],
                         {"state": "translated", "value": "Visszavonás"})

    def test_converts_plurals(self):
        iws.fill_catalog(self.catalog, MAPPING, self.web)
        en = value(self.catalog, "undo.collapsed.delete %lld", "en")["variations"]["plural"]
        self.assertEqual(en["other"]["stringUnit"]["value"], "%lld items removed")
        hu = value(self.catalog, "undo.collapsed.delete %lld", "hu")
        self.assertEqual(hu["stringUnit"]["value"], "%lld tétel törölve")

    def test_reports_filled_kept_missing_and_unknown(self):
        report = iws.fill_catalog(self.catalog, MAPPING, self.web)
        self.assertIn(("common.cancel", "hu"), report["kept"])
        self.assertIn(("space.personal.name", "de"), report["filled"])
        self.assertIn(("only.english", "hu", "onlyEnglish"), report["missing_web"])
        self.assertIn(("only.english", "de", "onlyEnglish"), report["missing_web"])
        self.assertEqual(report["not_in_catalog"], ["not.in.catalog"])
        self.assertNotIn("not.in.catalog", self.catalog["strings"])

    def test_is_idempotent(self):
        iws.fill_catalog(self.catalog, MAPPING, self.web)
        once = copy.deepcopy(self.catalog)
        report = iws.fill_catalog(self.catalog, MAPPING, self.web)
        self.assertEqual(self.catalog, once)
        self.assertEqual(report["filled"], [])


class CheckTests(unittest.TestCase):
    def test_lists_every_missing_language(self):
        catalog = iws.read_catalog(FIXTURES / "catalog.xcstrings")
        missing = iws.check_catalog(catalog)
        self.assertIn(("common.cancel", "de"), missing)
        self.assertIn(("undo.action", "hu"), missing)
        self.assertNotIn(("common.cancel", "en"), missing)

    def test_skips_keys_marked_not_translatable(self):
        catalog = {"strings": {"x": {"shouldTranslate": False}}}
        self.assertEqual(iws.check_catalog(catalog), [])


class CommandLineTests(unittest.TestCase):
    def test_fill_then_check_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            catalog_path = Path(tmp) / "Localizable.xcstrings"
            catalog_path.write_text((FIXTURES / "catalog.xcstrings").read_text(encoding="utf-8"), encoding="utf-8")
            map_path = Path(tmp) / "map.json"
            mapping = {k: v for k, v in MAPPING.items() if k != "only.english"}
            map_path.write_text(json.dumps(mapping), encoding="utf-8")

            with redirect_stdout(io.StringIO()):
                self.assertEqual(iws.main(["fill", "--catalog", str(catalog_path), "--map", str(map_path),
                                           "--web-locales", str(FIXTURES / "web")]), 0)
                # only.english has no translations anywhere, so check still fails on it alone.
                self.assertEqual(iws.main(["check", str(catalog_path)]), 1)

            written = catalog_path.read_text(encoding="utf-8")
            self.assertIn('"sourceLanguage" : "en"', written)
            self.assertIn("Személyes", written)
            self.assertTrue(written.endswith("\n"))
            remaining = iws.check_catalog(json.loads(written))
            self.assertEqual({key for key, _ in remaining}, {"only.english"})


if __name__ == "__main__":
    unittest.main()
