#!/usr/bin/env python3
"""Extract the course structure from the textbook PDF into Content/<LEVEL>.json.

Usage:
    tools/.venv/bin/python tools/extract_structure.py --level A1

What is extracted (structure only):
  * lessons and their grammar topic headings (from the table of contents /
    section headings);
  * the VOCABOLARIO word lists (Italian word, Russian gloss, gender);
  * lesson titles and speech patterns come from tools/curation/<LEVEL>.json,
    which is written by hand in our own words.

`rule_ru` comes only from tools/curation/<LEVEL>.json (lessons.<id>.rules),
written by the owner (by hand or exported from the app with import_rules.py).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

import pymupdf

sys.path.insert(0, str(Path(__file__).parent))
import pdfvocab as pv  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PDF = ROOT / "source" / "bueno-base-course-2014.pdf"
APPENDIX_PAGE = 373

# Which textbook lessons make up each level (agreed with the owner).
LEVELS = {
    "A1": [("intro", n) for n in range(1, 6)] + [("main", n) for n in range(1, 16)],
    "A2": [("main", n) for n in range(16, 36)],
}

# ----------------------------------------------------------------------------
# Text normalisation
# ----------------------------------------------------------------------------
# Cyrillic look-alikes that leak into Italian words in the PDF text layer.
HOMOGLYPHS = str.maketrans({
    "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x",
    "і": "i", "к": "k", "м": "m", "т": "t", "н": "h", "в": "b",
    "А": "A", "Е": "E", "О": "O", "Р": "P", "С": "C", "Т": "T", "Н": "H",
    "К": "K", "М": "M", "В": "B", "Х": "X",
})
LIGATURES = {"ﬀ": "ff", "ﬁ": "fi", "ﬂ": "fl", "ﬃ": "ffi", "ﬄ": "ffl"}
VOWEL_ACCENTS = "àèéìíòóùú"
CYRILLIC = re.compile("[а-яё]{2,}", re.I)


def fix_ligatures(s: str) -> str:
    for k, v in LIGATURES.items():
        s = s.replace(k, v)
    # The PDF puts a stray space after each ff/fi/fl ligature: "caff è",
    # "fi nestra", "uff icio". Italian words never end in these clusters.
    return re.sub(r"(ffi|ffl|ff|fi|fl)\s+(?=[a-zàèéìíòóùú])",
                  lambda m: m.group(1), s)


def clean_space(s: str) -> str:
    s = s.replace(" ", " ").replace("\x04", "")
    return re.sub(r"\s+", " ", s).strip()


def strip_inner_stress(word: str) -> str:
    """Remove didactic stress marks that are not part of Italian spelling.

    Italian writes an accent only on a final vowel (città, però, perché).
    The textbook additionally marks stress inside words (àbito, negòzio);
    those marks are removed from `it` and kept in `stress`.
    """
    out = []
    tokens = re.split(r"(\W+)", word)
    for tok in tokens:
        chars = list(tok)
        for i, ch in enumerate(chars):
            if ch in VOWEL_ACCENTS and i != len(chars) - 1:
                chars[i] = unicodedata.normalize("NFD", ch)[0]
        out.append("".join(chars))
    return "".join(out)


HOMOGLYPH_CHARS = "аеорсухікмтнвАЕОРСТНКМВХ"


def _fix_homoglyph_token(m: re.Match) -> str:
    """Cyrillic look-alikes inside an Italian token ("russа", "е*") -> Latin."""
    tok = m.group(0)
    letters = [c for c in tok if c.isalpha()]
    if re.search(r"[A-Za-zàèéìíòóùú]", tok) or (
            letters and len(letters) <= 2 and all(c in HOMOGLYPH_CHARS for c in letters)):
        return tok.translate(HOMOGLYPHS)
    return tok


def fold(s: str) -> str:
    """Key for duplicate detection: lowercase, no accents, no apostrophe variants."""
    s = unicodedata.normalize("NFD", s.lower().replace("’", "'"))
    return "".join(ch for ch in s if unicodedata.category(ch) != "Mn")


# ----------------------------------------------------------------------------
# Raw entry -> vocab item
# ----------------------------------------------------------------------------
GENDER_TAG = re.compile(r"⟨\s*(m\s*,\s*f|m|f)\s*(?:⟩\s*⟨)?\s*(,?\s*pl)?\.?\s*⟩")
GENDER_TAIL = re.compile(r"\s(m|f)\s*,\s*pl\.?\s*$")


def parse_entry(raw: pv.RawEntry) -> dict | None:
    s = ""
    for kind, text in raw.it_parts:
        text = fix_ligatures(text.replace("\x04", ""))
        if kind == "nl":
            s += " "
        elif kind == "i":
            s += "⟨" + text + "⟩"
        else:
            s += text
    s = re.sub(r"\[[^\]]*\]?", " ", s)            # Cyrillic transcriptions
    s = s.replace("⟨⟩", "")
    s = re.sub(r"⟩(\s*)⟨", r"\1", s)                # merge adjacent italic runs

    gender, plural = None, False
    m = GENDER_TAG.search(s) or GENDER_TAIL.search(s.replace("⟨", "").replace("⟩", ""))
    if m:
        gender = "mf" if "," in m.group(1) else m.group(1)
        plural = bool(m.group(2) if m.re is GENDER_TAG else True)
        if m.re is GENDER_TAG:
            s = s[:m.start()] + " " + s[m.end():]
        else:
            s = s.replace("⟨", "").replace("⟩", "")
            s = GENDER_TAIL.sub("", s)

    form_of = None
    def paren(mm: re.Match) -> str:
        nonlocal form_of
        inner = mm.group(1)
        plain = clean_space(inner.replace("⟨", "").replace("⟩", ""))
        if re.match(r"^io\s", plain):
            return " "                            # conjugation hint, e.g. (io cammino)
        first_word = plain.split()[0] if plain.split() else ""
        if "⟨" not in inner and VERB_INF.search(first_word) and mm.start() > 0:
            form_of = plain                       # "sto bene (stare bene)"
            return " "
        v = re.match(r"^v\.?\s+(.+)$", plain) or (
            "⟨" in inner and re.match(r"^v\.?\s*(.+)$", plain))
        if v:                                     # "(v dire)" = form of dire
            form_of = v.group(1)
            return " "
        if "⟨" in inner:
            if re.match(r"^(io|tu|lui|lei)\b", plain):
                return " "                        # conjugation hint, e.g. (io àbito)
            if re.fullmatch(r"v\.?", plain):
                return " "
        return "(" + plain + ")"
    s = re.sub(r"\(([^()]*)\)?", paren, s)
    s = s.replace("⟨", "").replace("⟩", "")

    s = re.sub(r"\S+", _fix_homoglyph_token, s)
    extra_ru = re.findall(r"[а-яёА-ЯЁ][а-яёА-ЯЁ .,\-]*", s)
    for frag in extra_ru:
        s = s.replace(frag, " ")
    extra_ru = [clean_space(f) for f in extra_ru if clean_space(f)]

    head = clean_space(s).replace("( )", "").replace("()", "")
    head = re.sub(r"(\w)-\s+(?=[a-zàèéìòù])", r"\1", head)   # "condiziona- tore"
    if re.search(r",?\s*\bpl\.?$", head) and gender:          # stray ", pl"
        head, plural = re.sub(r",?\s*\bpl\.?$", "", head), True
    contraction = re.search(r"\s(\w+\s*\+\s*\w+)$", head)      # "sul su+il"
    if contraction:
        head = head[:contraction.start()]
        extra_ru.insert(0, f"({contraction.group(1).replace(' ', '')})")
    new = "*" in head
    head = clean_space(head.replace("*", "")).translate(HOMOGLYPHS)
    head = head.strip(" ,;")
    if not head:
        return None

    ru = "".join(raw.ru_parts)
    if extra_ru:
        sep = " " if extra_ru[0].startswith("(") else ", "
        ru = ru.rstrip(" ,") + (sep if ru.strip() else "") + " ".join(extra_ru)
    ru = fix_ligatures(ru)
    # rejoin words hyphenated across lines, but keep real hyphens like "по-итальянски"
    ru = re.sub(r"(?<!\bпо)(?<!\bкое)-\s*\n\s*(?=[а-яё])", "", ru)
    ru = re.sub(r"-\s*\n\s*", "-", ru)
    ru = re.sub(r"\[[^\]]*\]", " ", ru.replace("\x04", ""))
    ru = clean_space(ru.replace("\n", " "))
    ru = ru.strip(" ,;")
    if ru.startswith(")"):                     # tail of a wrapped "(io leggo)" hint
        ru = ru[1:].strip()

    it = strip_inner_stress(head)
    item = {"it": it, "ru": ru}
    if it != head:
        item["stress"] = head
    item["_gender"] = gender
    item["_plural"] = plural
    item["_form_of"] = clean_space(form_of).translate(HOMOGLYPHS) if form_of else None
    item["_new"] = new
    item["_page"] = raw.page
    return item


# ----------------------------------------------------------------------------
# Part of speech (the book only marks gender, so the rest is inferred)
# ----------------------------------------------------------------------------
CLOSED = {
    "prep": "a di da in con su per tra fra senza verso dopo prima sopra sotto "
            "dentro fuori davanti dietro vicino lontano presso".split(),
    "conj": "e ed o oppure ma però perché se quando mentre anche neanche "
            "nemmeno né che come invece quindi allora poi dunque cioè".split(),
    "pron": "io tu lui lei noi voi loro esso essa mi ti ci vi si lo la li le "
            "gli ne me te ce ve se mio mia miei mie tuo tua tuoi tue suo sua "
            "suoi sue nostro nostra nostri nostre vostro vostra vostri vostre "
            "questo questa questi queste quello quella quelli quelle chi cosa "
            "qualcuno qualcosa niente nulla nessuno ognuno tutto tutti "
            "qualche alcuni alcune".split(),
    "num": "zero uno una due tre quattro cinque sei sette otto nove dieci undici "
           "dodici tredici quattordici quindici sedici diciassette diciotto "
           "diciannove venti trenta quaranta cinquanta sessanta settanta "
           "ottanta novanta cento mille primo secondo terzo quarto quinto "
           "sesto settimo ottavo nono decimo".split(),
    "art": "il lo la i gli le un uno una un'".split(),
    "adv": "molto poco tanto troppo bene male meglio peggio sempre mai spesso "
           "già ancora adesso ora oggi ieri domani qui qua lì là dove come "
           "quando presto tardi subito insieme anche più meno così forse "
           "molto non sì no purtroppo davvero proprio solo soltanto "
           "abbastanza".split(),
}
PREP_START = set("a al alla ai agli all' allo da dal dalla dai dagli di del della dei "
                 "degli in nel nella nei negli su sul sulla per con".split())
INTERJ = set("ciao grazie prego buongiorno buonasera buonanotte arrivederci "
             "basta scusa scusi scusate salve ecco".split())
NUMERAL = re.compile(r"(venti|trenta|quaranta|cinquanta|sessanta|settanta|ottanta|"
                     r"novanta|cento|mille)(uno|due|tre|quattro|cinque|sei|sette|otto|nove)?")
VERB_INF = re.compile(r"(are|ere|ire|arsi|ersi|irsi|urre|orre)$")


def infer_pos(it: str, ru: str, gender: str | None, form_of: str | None) -> str:
    w = fold(it).rstrip("!?")
    glosses = [g.strip().lower() for g in re.split(r"[,;]", ru) if g.strip()]
    glosses = [re.sub(r"^(зд\.|г\.)\s*", "", g) for g in glosses]
    first = glosses[0] if glosses else ""
    if gender:
        words = w.replace("’", "'").split()
        if len(words) > 2 or (len(words) == 2 and words[0] in PREP_START):
            return "phrase"
        return "noun"
    if w in INTERJ:
        return "interj"
    if NUMERAL.fullmatch(w):
        return "num"
    if form_of:
        return "verb"
    if len(w.split()) > 1:
        return "phrase"
    # conjugated forms are glossed with a pronoun: "я знаю", "у меня есть"
    if re.match(r"^(я|ты|он|она|оно|мы|вы|они|\(?(он|они|она)\)?)\s+\S", first) \
            or first.startswith("у меня") or re.match(r"^у (тебя|него|нее|нас|вас|них)\b", first):
        return "verb"
    for pos in ("art", "num", "prep", "conj", "pron", "adv"):
        if w in CLOSED[pos]:
            return pos
    if it[:1].isupper():
        return "proper"
    if re.fullmatch(r"\d+", first):
        return "num"
    if VERB_INF.search(w):
        return "verb"
    if w.endswith("mente"):
        return "adv"
    for g in glosses:
        head = g.split()[0] if g.split() else ""
        if re.search(r"(ый|ий|ой|ая|яя|ое|ее|ые|ие)$", head):
            return "adj"
    if re.search(r"(ть|ться|ти)$", first.split()[0] if first else ""):
        return "verb"
    return "other"


# ----------------------------------------------------------------------------
def apply_merges(items: list[dict], merges: list[list[str]]) -> list[dict]:
    """Join entries whose Italian head was wrapped onto the next table line
    ("cotoletta alla" + "milanese"). The pairs are listed by hand in the
    curation file because the layout gives no reliable signal."""
    out = list(items)
    i = 0
    while i < len(out) - 1:
        a, b = out[i], out[i + 1]
        if [fold(a["it"]), fold(b["it"])] in merges:
            m = dict(a)
            m["it"] = a["it"] + " " + b["it"]
            m["ru"] = (a["ru"] + " " + b["ru"]).strip()
            if a.get("stress") or b.get("stress"):
                m["stress"] = a.get("stress", a["it"]) + " " + b.get("stress", b["it"])
            m["_gender"] = a["_gender"] or b["_gender"]
            m["_plural"] = a["_plural"] or b["_plural"]
            out[i:i + 2] = [m]          # may merge again with the next line
            continue
        i += 1
    return out


def build_level(level: str) -> dict:
    doc = pymupdf.open(PDF)
    toc = pv.parse_toc(doc)
    ranges = pv.lesson_ranges(toc, APPENDIX_PAGE - 1)
    by_key = {(l.part, l.number): l for l in toc}

    curation_path = ROOT / "tools" / "curation" / f"{level}.json"
    curation = json.loads(curation_path.read_text()) if curation_path.exists() else {}
    lessons_cur = curation.get("lessons", {})
    overrides = curation.get("vocab_overrides", {})
    drop = {fold(w) for w in curation.get("vocab_drop", [])}
    merges = [[fold(w) for w in m] for m in curation.get("vocab_merge", [])]
    overrides = {fold(k): v for k, v in overrides.items()}

    seen: dict[str, str] = {}
    lessons = []
    for idx, key in enumerate(LEVELS[level], start=1):
        toc_les = by_key[key]
        pages = ranges[key]
        lid = f"{level.lower()}-{idx:02d}"
        cur = lessons_cur.get(lid, {})
        # Owner-written rules: curation lessons.<id>.rules = {"<topic>": "text"}
        rules = cur.get("rules", {})

        if key[0] == "intro":
            topics = pv.intro_headings(doc, pages)
        else:
            topics = toc_les.topics

        for unknown in set(rules) - set(topics):
            print(f"warning: {lid}: rule for unknown topic {unknown!r}", file=sys.stderr)

        items = [parse_entry(r) for r in pv.vocab_blocks(doc, pages, toc_les.text_title)]
        items = apply_merges([i for i in items if i], merges)
        vocab = []
        for item in items:
            k = fold(item["it"])
            if k in drop:
                continue
            ov = overrides.get(k, {})
            gender = ov.get("gender", item["_gender"])
            pos = ov.get("pos") or infer_pos(item["it"], item["ru"], gender,
                                             item["_form_of"])
            if k in seen:
                continue           # first occurrence in the level wins
            seen[k] = lid
            out = {"it": ov.get("it", item["it"]), "ru": ov.get("ru", item["ru"]),
                   "pos": pos}
            if pos == "noun":
                out["gender"] = gender
                if ov.get("number", "pl" if item["_plural"] else None):
                    out["number"] = "pl"
            if item.get("stress"):
                out["stress"] = item["stress"]
            form_of = ov.get("form_of", item["_form_of"])
            if form_of:
                out["form_of"] = strip_inner_stress(form_of)
            if item["_new"]:
                out["new"] = True          # marked with * in the book: new in this lesson
            if "stress" in out and fold(out["stress"]) != fold(out["it"]):
                del out["stress"]
            vocab.append(out)

        lessons.append({
            "id": lid,
            "source": {"part": key[0], "lesson": key[1],
                       "pages": [pages.start, pages.stop - 1]},
            "title": cur.get("title", ""),
            "grammar": [{"topic": t, "rule_ru": rules.get(t, "")} for t in topics],
            "vocab": vocab,
            "patterns": cur.get("patterns", []),
        })
    return {"level": level, "lessons": lessons}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--level", default="A1", choices=sorted(LEVELS))
    ap.add_argument("--out", type=Path)
    args = ap.parse_args()
    data = build_level(args.level)
    out = args.out or ROOT / "Content" / f"{args.level}.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    n_words = sum(len(l["vocab"]) for l in data["lessons"])
    print(f"{out.relative_to(ROOT)}: {len(data['lessons'])} lessons, {n_words} words")


if __name__ == "__main__":
    main()
