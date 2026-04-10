#!/usr/bin/env python3

import argparse
import json
from pathlib import Path


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload: dict) -> None:
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def xcstrings_to_runtime(xcstrings: dict) -> dict:
    strings = xcstrings.get("strings", {})
    locales: dict[str, dict[str, str]] = {}

    for key, entry in strings.items():
        if entry.get("extractionState") == "stale":
            continue

        for locale, localized_entry in entry.get("localizations", {}).items():
            string_unit = localized_entry.get("stringUnit", {})
            value = string_unit.get("value")
            if not isinstance(value, str):
                continue
            locales.setdefault(locale, {})[key] = value

    for locale in locales:
        locales[locale] = dict(sorted(locales[locale].items(), key=lambda item: item[0]))

    return {
        "sourceLanguage": xcstrings.get("sourceLanguage", "en"),
        "locales": dict(sorted(locales.items(), key=lambda item: item[0])),
    }


def runtime_to_xcstrings(runtime_strings: dict) -> dict:
    source_language = runtime_strings.get("sourceLanguage", "en")
    locales = runtime_strings.get("locales", {})
    all_keys: set[str] = set()

    for locale_map in locales.values():
        all_keys.update(locale_map.keys())

    strings: dict[str, dict] = {}
    for key in sorted(all_keys):
        localizations: dict[str, dict] = {}
        for locale, locale_map in sorted(locales.items(), key=lambda item: item[0]):
            value = locale_map.get(key)
            if not isinstance(value, str):
                continue
            localizations[locale] = {
                "stringUnit": {
                    "state": "translated",
                    "value": value,
                }
            }
        strings[key] = {
            "extractionState": "manual",
            "localizations": localizations,
        }

    return {
        "sourceLanguage": source_language,
        "strings": strings,
        "version": "1.0",
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sync Spectra runtime JSON localization strings with Apple's Localizable.xcstrings."
    )
    parser.add_argument(
        "--direction",
        choices=("xcstrings-to-runtime", "runtime-to-xcstrings"),
        required=True,
        help="Choose which catalog is treated as the source of truth.",
    )
    parser.add_argument(
        "--xcstrings",
        type=Path,
        default=Path("Resources/Localization/Localizable.xcstrings"),
        help="Path to Localizable.xcstrings",
    )
    parser.add_argument(
        "--runtime",
        type=Path,
        default=Path("Resources/Localization/RuntimeStrings.json"),
        help="Path to RuntimeStrings.json",
    )
    args = parser.parse_args()

    if args.direction == "xcstrings-to-runtime":
        write_json(args.runtime, xcstrings_to_runtime(load_json(args.xcstrings)))
        return

    write_json(args.xcstrings, runtime_to_xcstrings(load_json(args.runtime)))


if __name__ == "__main__":
    main()
