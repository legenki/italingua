"""Low-level helpers: read the textbook PDF and pull out the raw structure
(lesson page ranges, grammar headings, two-column VOCABOLARIO tables).

Only structural data is extracted: headings and word/translation pairs.
Explanations, dialogues, texts and exercises are never read into the output.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

import pymupdf

# --- page layout constants (measured on the 2016 AST edition) ---------------
BODY_SIZE = (10.5, 12.1)       # vocabulary table font size (up to 12pt accented glyphs)
SMALL_MIN = 7.5                # small glyphs (accented letters) inside entries
HEADING_MIN_SIZE = 12.5        # anything this large ends a vocab block
ROW_DX = (55, 115)             # distance between Italian and Russian columns
LINE_TOL = 3.0                 # same-line y tolerance


@dataclass
class Span:
    page: int
    text: str
    x: float
    y: float
    size: float
    font: str
    x1: float = 0.0

    @property
    def bold(self) -> bool:
        return "Bold" in self.font

    @property
    def italic(self) -> bool:
        return "It" in self.font or "Italic" in self.font


@dataclass
class RawEntry:
    page: int
    it_parts: list[tuple[str, str]] = field(default_factory=list)  # (kind, text)
    ru_parts: list[str] = field(default_factory=list)


def page_spans(doc: pymupdf.Document, pno: int) -> list[Span]:
    """All non-empty spans of a page (1-based pno), de-duplicated.

    Some pages carry a doubled text layer, so identical spans are dropped.
    """
    seen = set()
    out = []
    for bl in doc[pno - 1].get_text("dict")["blocks"]:
        for ln in bl.get("lines", []):
            for sp in ln["spans"]:
                if not sp["text"].strip():
                    continue
                key = (sp["text"], round(sp["bbox"][0]), round(sp["bbox"][1]))
                if key in seen:
                    continue
                seen.add(key)
                out.append(Span(pno, sp["text"], sp["bbox"][0], sp["bbox"][1],
                                sp["size"], sp["font"], sp["bbox"][2]))
    return out


# --- table of contents -------------------------------------------------------
TOC_PAGES = range(412, 417)


@dataclass
class TocLesson:
    part: str            # "intro" | "main"
    number: int
    page: int
    topics: list[str] = field(default_factory=list)
    text_title: str | None = None


def parse_toc(doc: pymupdf.Document) -> list[TocLesson]:
    text = "\n".join(doc[p - 1].get_text() for p in TOC_PAGES)
    lines = [re.sub(r"\s+", " ", l).strip() for l in text.split("\n")]
    # Re-join headings that wrap onto a second line before the page number.
    merged: list[str] = []
    for l in lines:
        if not l or re.fullmatch(r"\d{3}", l) or l == "СОДЕРЖАНИЕ":
            continue
        if merged and not re.search(r"\d\s*$", merged[-1]) and not merged[-1].startswith("УРОК"):
            merged[-1] = merged[-1] + " " + l
        else:
            merged.append(l)

    lessons: list[TocLesson] = []
    part = None
    for l in merged:
        body = re.sub(r"(\s*\.\s*)+\s*\d+\s*$", "", l).strip()
        m_page = re.search(r"(\d+)\s*$", l)
        if body.startswith("ВВОДНЫЙ КУРС"):
            part = "intro"
            continue
        if body.startswith("ОСНОВНОЙ КУРС"):
            part = "main"
            continue
        if body.startswith(("ПРИЛОЖЕНИЯ", "КЛЮЧИ")):
            part = None
            continue
        if part is None:
            continue
        m = re.match(r"УРОК (\d+)", body)
        if m:
            lessons.append(TocLesson(part, int(m.group(1)), int(m_page.group(1))))
            continue
        if not lessons:
            continue
        if body.startswith("Текст:"):
            lessons[-1].text_title = body.split(":", 1)[1].strip()
        elif body.startswith("УПРАЖНЕНИЯ"):
            continue
        else:
            # "§ 2. Глаголы ..." or an unnumbered sub-heading
            topic = re.sub(r"^(§\s*)?\d+\.\s*", "", body).strip()
            # TOC sometimes glues the next heading without a page number
            topic = re.split(r"\s+Текст:", topic)[0]
            lessons[-1].topics.append(topic)
    return lessons


def lesson_ranges(lessons: list[TocLesson], last_page: int) -> dict[tuple[str, int], range]:
    out = {}
    for i, les in enumerate(lessons):
        if i + 1 < len(lessons):
            end = lessons[i + 1].page
            if lessons[i + 1].part != les.part and les.part == "intro":
                end = lessons[i + 1].page - 1   # skip "ОСНОВНОЙ КУРС" divider
        else:
            end = last_page + 1
        out[(les.part, les.number)] = range(les.page, end)
    return out


# --- in-page grammar headings (intro lessons are not detailed in the TOC) ----
def intro_headings(doc: pymupdf.Document, pages: range) -> list[str]:
    """Large semibold-italic section headings: '§ 1. ...', 'Правила чтения', ..."""
    heads: list[str] = []
    prev_y = None
    prev_page = None
    for p in pages:
        for bl in doc[p - 1].get_text("dict")["blocks"]:
            for ln in bl.get("lines", []):
                sp = [s for s in ln["spans"] if s["text"].strip()]
                if not sp:
                    continue
                s0 = sp[0]
                if round(s0["size"]) != 16 or "It" not in s0["font"]:
                    continue
                t = "".join(s["text"] for s in sp).strip()
                y = s0["bbox"][1]
                if heads and prev_page == p and prev_y is not None and y - prev_y < 25:
                    heads[-1] = heads[-1].rstrip(":") + (": " if heads[-1].endswith(":") else " ") + t
                else:
                    heads.append(t)
                prev_y, prev_page = y, p
    clean = []
    for h in heads:
        h = re.sub(r"^§\s*\d+\.\s*", "", h)
        h = re.sub(r"\s+", " ", h).strip()
        if h not in clean:
            clean.append(h)
    return clean


# --- vocabulary tables -------------------------------------------------------
def _is_body(sp: Span) -> bool:
    return BODY_SIZE[0] <= sp.size <= BODY_SIZE[1]


def _find_columns(spans: list[Span]) -> list[tuple[float, float]]:
    """Detect (italian_x, russian_x) column pairs from rows that have a bold
    Italian head and a regular translation on the same line."""
    pairs = []
    for b in spans:
        if not (b.bold and _is_body(b)):
            continue
        for r in spans:
            if r is b or r.bold or r.italic or not _is_body(r):
                continue
            dx = r.x - b.x
            if abs(r.y - b.y) < LINE_TOL and ROW_DX[0] < dx < ROW_DX[1]:
                pairs.append((b.x, r.x))
    cols: list[list[tuple[float, float]]] = []
    for it_x, ru_x in sorted(pairs):
        for c in cols:
            if abs(c[0][0] - it_x) < 6:
                c.append((it_x, ru_x))
                break
        else:
            cols.append([(it_x, ru_x)])
    def col_pair(c: list[tuple[float, float]]) -> tuple[float, float]:
        return (min(p[0] for p in c), sorted(p[1] for p in c)[len(c) // 2])

    result = [col_pair(c) for c in cols if len(c) >= 3]
    if len(result) < 2:
        all_cols = [col_pair(c) for c in cols]
        for a in all_cols:
            for b in all_cols:
                if 175 < b[0] - a[0] < 195:
                    return [a, b]
    return sorted(result)


def vocab_blocks(doc: pymupdf.Document, pages: range,
                 fallback_title: str | None = None) -> list[RawEntry]:
    """Collect raw entries from every VOCABOLARIO table within `pages`.

    A block starts at a VOCABOLARIO heading and runs until the next large
    heading. A few lessons print the table without the heading; for those,
    pass the lesson text title as `fallback_title`: the block then starts at
    that title and runs until the exercises heading.
    """
    has_heading = any(
        "VOCABOLARIO" in sp.text for p in pages for sp in page_spans(doc, p))
    fallback = not has_heading and fallback_title is not None
    entries: list[RawEntry] = []
    active = False
    for p in pages:
        spans = sorted(page_spans(doc, p), key=lambda s: (s.y, s.x))
        region: list[Span] = []
        for sp in spans:
            txt = sp.text.strip()
            if txt.startswith("VOCABOLARIO") or (
                    fallback and sp.size > 13.5 and sp.bold
                    and txt == fallback_title.strip()):
                if region:
                    entries += _parse_region(region)
                region = []
                active = True
                continue
            if sp.size >= HEADING_MIN_SIZE:
                if fallback and active and not txt.startswith("УПРАЖНЕНИЯ"):
                    continue
                if active:
                    entries += _parse_region(region)
                    region = []
                active = False
                continue
            if active and SMALL_MIN <= sp.size <= BODY_SIZE[1] and sp.y < 700:  # y>=700: footer
                region.append(sp)
        if active and region:
            entries += _parse_region(region)
    return entries


CYR = re.compile("[а-яёА-ЯЁ]")


def _split_line(line: list[Span], ru_x: float) -> tuple[list[Span], list[Span]]:
    """Split one table line into Italian-side and Russian-side spans.

    Russian text is recognised by its script (it is sometimes set a few points
    left of the translation column); Cyrillic inside [...] is a transcription
    and stays on the Italian side, where it is discarded later.
    """
    it_side, ru_side = [], []
    in_bracket = False
    for sp in line:
        t = sp.text
        if in_bracket or "[" in t:
            it_side.append(sp)
            if "[" in t:
                in_bracket = "]" not in t.split("[", 1)[1]
            elif "]" in t:
                in_bracket = False
            continue
        if CYR.search(t) and not sp.bold:
            ru_side.append(sp)
        elif sp.x >= ru_x - 4 and not (sp.italic and re.fullmatch(r"\s*[mf]\s*", t)):
            ru_side.append(sp)
        else:
            it_side.append(sp)
    return it_side, ru_side


def _join(spans: list[Span]) -> str:
    out = ""
    prev = None
    for sp in spans:
        if prev is not None and sp.x > prev.x1 + 1.0 and not out.endswith(" ") \
                and not sp.text.startswith(" "):
            out += " "
        out += sp.text
        prev = sp
    return out


def _parse_region(region: list[Span]) -> list[RawEntry]:
    if not region:
        return []
    body = [s for s in region if _is_body(s)]
    cols = _find_columns(body)
    if not cols:
        return []
    by_col: dict[int, list[Span]] = {i: [] for i in range(len(cols))}
    for sp in region:
        idx = None
        for i, (it_x, _) in enumerate(cols):
            if sp.x >= it_x - 4:
                idx = i
        if idx is not None:
            by_col[idx].append(sp)
    out: list[RawEntry] = []
    for i, (it_x, ru_x) in enumerate(cols):
        cur: RawEntry | None = None
        for line in _group_lines(by_col[i]):
            it_side, ru_side = _split_line(line, ru_x)
            first = it_side[0] if it_side else None
            prev_it = "".join(t for k, t in cur.it_parts if k != "nl").strip() if cur else ""
            hyphen_wrap = prev_it.endswith("-") and not cur.ru_parts[1:]
            ft = first.text.strip() if first else ""
            paren_cont = ft.startswith("[") or (ft.startswith("(") and (ft == "(" or ft.rstrip("* ").endswith(")")))
            if first is not None and first.bold and abs(first.x - it_x) < 5 \
                    and not paren_cont and not hyphen_wrap:
                cur = RawEntry(first.page)
                out.append(cur)
            if cur is None:
                continue
            if it_side:
                if cur.it_parts:
                    cur.it_parts.append(("nl", " "))
                prev = None
                for sp in it_side:
                    kind = "i" if sp.italic else ("b" if sp.bold else "r")
                    gap = prev is not None and sp.x > prev.x1 + 1.0
                    cur.it_parts.append((kind, (" " if gap else "") + sp.text))
                    prev = sp
            if ru_side:
                if cur.ru_parts:
                    cur.ru_parts.append("\n")
                cur.ru_parts.append(_join(ru_side))
    return out


def _group_lines(spans: list[Span]) -> list[list[Span]]:
    lines: list[list[Span]] = []
    for sp in sorted(spans, key=lambda s: s.y):
        if lines and abs(sp.y - lines[-1][0].y) < LINE_TOL + (1.5 if sp.size < 10 else 0):
            lines[-1].append(sp)
        else:
            lines.append([sp])
    return [sorted(l, key=lambda s: s.x) for l in lines]
