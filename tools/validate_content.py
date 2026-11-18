#!/usr/bin/env python3
"""Validate Content/<LEVEL>.json files.

Usage:
    python3 tools/validate_content.py                # all Content/*.json
    python3 tools/validate_content.py Content/A1.json --warnings

Errors (exit code 1):
  * schema violations: missing/extra keys, wrong types, bad ids, unknown pos
  * empty required fields (title, topic, it, ru, pattern strings)
  * duplicate words within a level (accent- and case-insensitive)
  * nouns without gender, gender on non-nouns
  * Cyrillic letters inside Italian text, Latin-only "translations"
Warnings (shown with --warnings):
  * gender that contradicts the usual ending (-o feminine, -a masculine):
    often a typo in the source, needs a human look
  * pos "other" (could not be inferred)
  * empty rule_ru (expected until the owner fills them in), counted only

No third-party dependencies: runs with the system python3.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

LEVELS = {"A1", "A2", "B1", "B2", "C1", "C2"}
POS = {"noun", "verb", "adj", "adv", "pron", "prep", "conj", "art", "num",
       "interj", "proper", "phrase", "other"}
GENDERS = {"m", "f", "mf"}

LEVEL_KEYS = {"level": str, "lessons": list}
LESSON_KEYS = {"id": str, "title": str, "grammar": list, "vocab": list, "patterns": list}
LESSON_OPTIONAL = {"source": dict}
GRAMMAR_KEYS = {"topic": str, "rule_ru": str}
VOCAB_KEYS = {"it": str, "ru": str, "pos": str}
VOCAB_OPTIONAL = {"gender": str, "number": str, "stress": str, "form_of": str, "new": bool}

CYR = re.compile("[а-яёА-ЯЁ]")
# Well-known nouns whose gender does not follow the -o/-a ending rule.
GENDER_EXCEPTIONS = {"cinema", "radio", "foto", "moto", "auto", "mano", "clima",
                     "problema", "panorama", "programma", "sistema", "tema",
                     "telegramma", "pigiama", "pianeta", "papa", "poeta",
                     "turista", "autista", "artista", "collega", "dentista",
                     "giornalista", "pilota", "eco", "dinamo", "gorilla"}
LAT = re.compile("[A-Za-z]")


def fold(s: str) -> str:
    s = unicodedata.normalize("NFD", s.lower().replace("’", "'"))
    return "".join(ch for ch in s if unicodedata.category(ch) != "Mn")


def check_rule_markup(text: str) -> list[str]:
    """Rule markup (see CLAUDE.md): `conj: verb | gloss` + 6 rows until a
    blank line, `table: a | b*` + rows of the same width until a blank line, `ex: Italian | Russian`, `! callout`, `• bullet`, paragraphs."""
    problems = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if line.startswith("conj:"):
            if line.count("|") != 1:
                problems.append(f"conj header needs 'verb | gloss': {line!r}")
            rows = []
            i += 1
            while i < len(lines) and lines[i].strip():
                rows.append(lines[i].strip())
                i += 1
            if len(rows) != 6:
                problems.append(f"conj {line[5:].split('|')[0].strip()!r} has {len(rows)} rows, expected 6")
            for r in rows:
                if len(r.split()) < 2 or r.count("|") > 1:
                    problems.append(f"bad conj row {r!r}")
            continue
        if line.startswith("table:"):
            width = line[6:].count("|") + 1
            if width < 2:
                problems.append(f"table needs at least two columns: {line!r}")
            i += 1
            n = 0
            while i < len(lines) and lines[i].strip():
                row = lines[i].strip()
                if row.count("|") + 1 != width:
                    problems.append(f"table row has {row.count('|') + 1} cells, expected {width}: {row!r}")
                if row.count("**") % 2:
                    problems.append(f"unbalanced ** in {row!r}")
                n += 1
                i += 1
            if n == 0:
                problems.append(f"table without rows: {line!r}")
            continue
        if line.startswith("ex:") and line.count("|") != 1:
            problems.append(f"example needs 'Italian | Russian': {line!r}")
        if line.count("**") % 2:
            problems.append(f"unbalanced ** in {line!r}")
        i += 1
    return problems


class Report:
    def __init__(self, path: Path):
        self.path = path
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def err(self, where: str, msg: str) -> None:
        self.errors.append(f"{where}: {msg}")

    def warn(self, where: str, msg: str) -> None:
        self.warnings.append(f"{where}: {msg}")


def check_keys(rep: Report, where: str, obj, required: dict, optional: dict | None = None) -> bool:
    if not isinstance(obj, dict):
        rep.err(where, f"expected object, got {type(obj).__name__}")
        return False
    optional = optional or {}
    for k, t in required.items():
        if k not in obj:
            rep.err(where, f"missing key '{k}'")
        elif not isinstance(obj[k], t):
            rep.err(where, f"'{k}' must be {t.__name__}")
    for k in obj:
        if k not in required and k not in optional:
            rep.err(where, f"unknown key '{k}'")
        elif k in optional and not isinstance(obj[k], optional[k]):
            rep.err(where, f"'{k}' must be {optional[k].__name__}")
    return True


def validate(path: Path) -> Report:
    rep = Report(path)
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        rep.err(str(path), f"invalid JSON: {e}")
        return rep
    if not check_keys(rep, "root", data, LEVEL_KEYS):
        return rep
    level = data.get("level", "")
    if level not in LEVELS:
        rep.err("root", f"unknown level '{level}'")
    if path.stem != level:
        rep.err("root", f"file name {path.name} does not match level '{level}'")

    seen_ids: set[str] = set()
    seen_words: dict[str, str] = {}
    for li, les in enumerate(data.get("lessons", [])):
        where = f"lessons[{li}]"
        if not check_keys(rep, where, les, LESSON_KEYS, LESSON_OPTIONAL):
            continue
        lid = les.get("id", "")
        where = lid or where
        if not re.fullmatch(rf"{level.lower()}-\d{{2}}", lid):
            rep.err(where, f"id must look like '{level.lower()}-05'")
        if lid in seen_ids:
            rep.err(where, "duplicate lesson id")
        seen_ids.add(lid)
        if not les.get("title", "").strip():
            rep.err(where, "empty title")
        if not les.get("grammar"):
            rep.err(where, "no grammar topics")
        if not les.get("vocab"):
            rep.err(where, "no vocabulary")

        for gi, g in enumerate(les.get("grammar", [])):
            gw = f"{where}.grammar[{gi}]"
            if check_keys(rep, gw, g, GRAMMAR_KEYS) and not g.get("topic", "").strip():
                rep.err(gw, "empty topic")
            for msg in check_rule_markup(g.get("rule_ru", "")):
                rep.err(f"{where} «{g.get('topic', '')}»", msg)

        for pi, p in enumerate(les.get("patterns", [])):
            if not isinstance(p, str) or not p.strip():
                rep.err(f"{where}.patterns[{pi}]", "pattern must be a non-empty string")
            elif CYR.search(p):
                rep.err(f"{where}.patterns[{pi}]", f"Cyrillic in Italian pattern: {p!r}")

        for vi, v in enumerate(les.get("vocab", [])):
            vw = f"{where}.vocab[{vi}]"
            if not check_keys(rep, vw, v, VOCAB_KEYS, VOCAB_OPTIONAL):
                continue
            it, ru, pos = v.get("it", ""), v.get("ru", ""), v.get("pos", "")
            vw = f"{where} «{it}»"
            if not it.strip():
                rep.err(vw, "empty 'it'")
            if not ru.strip():
                rep.err(vw, "empty 'ru'")
            if pos not in POS:
                rep.err(vw, f"unknown pos '{pos}'")
            if CYR.search(it):
                rep.err(vw, "Cyrillic letters in Italian word")
            if ru and not CYR.search(ru) and not re.fullmatch(r"[\d\s.,…-]+", ru):
                rep.err(vw, f"translation has no Russian text: {ru!r}")
            if "*" in it or "[" in it or "[" in ru:
                rep.err(vw, "leftover markup (* or [..])")
            if it != it.strip() or "  " in it:
                rep.err(vw, "whitespace problems")

            gender = v.get("gender")
            if pos == "noun":
                if gender is None:
                    rep.err(vw, "noun without gender")
                elif gender not in GENDERS:
                    rep.err(vw, f"bad gender '{gender}'")
                else:
                    # The head noun: first word after an article ("la carta di credito" → carta).
                    words = [w for w in re.split(r"[\s’']+", it) if w]
                    while len(words) > 1 and fold(words[0]) in {"il", "lo", "la", "i", "gli", "le", "l", "un", "uno", "una"}:
                        words = words[1:]
                    word = fold(words[0])
                    last = word[-1:]
                    if word not in GENDER_EXCEPTIONS and (
                            (last == "o" and gender == "f") or (last == "a" and gender == "m")):
                        rep.warn(vw, f"gender '{gender}' vs ending '-{last}': check (exceptions exist)")
            elif gender is not None:
                rep.err(vw, f"gender on non-noun (pos={pos})")
            if v.get("number") not in (None, "pl"):
                rep.err(vw, "number must be 'pl'")
            if "stress" in v and fold(v["stress"]) != fold(it):
                rep.err(vw, f"stress form {v['stress']!r} does not match word")

            if pos == "other":
                rep.warn(vw, "pos could not be inferred ('other')")

            key = fold(it)
            if key in seen_words:
                rep.err(vw, f"duplicate word (first in {seen_words[key]})")
            else:
                seen_words[key] = lid
    return rep


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", type=Path)
    ap.add_argument("--warnings", action="store_true", help="print warnings too")
    args = ap.parse_args()
    files = args.files or sorted((ROOT / "Content").glob("*.json"))
    if not files:
        print("no content files found")
        return 1
    failed = False
    for f in files:
        rep = validate(f)
        data = json.loads(f.read_text()) if not rep.errors or f.exists() else {}
        lessons = data.get("lessons", []) if isinstance(data, dict) else []
        words = sum(len(l.get("vocab", [])) for l in lessons)
        topics = sum(len(l.get("grammar", [])) for l in lessons)
        empty_rules = sum(1 for l in lessons for g in l.get("grammar", []) if not g.get("rule_ru"))
        print(f"{f.name}: {len(lessons)} lessons, {topics} topics, {words} words, "
              f"{len(rep.errors)} errors, {len(rep.warnings)} warnings, "
              f"{empty_rules} empty rule_ru")
        for e in rep.errors:
            print("  ERROR  ", e)
        if args.warnings:
            for w in rep.warnings:
                print("  warning", w)
        failed |= bool(rep.errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
