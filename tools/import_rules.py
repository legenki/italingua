#!/usr/bin/env python3
"""Merge grammar rules exported from the app into tools/curation/<LEVEL>.json.

Usage:
    python3 tools/import_rules.py ~/Downloads/italingua-rules.json
    tools/.venv/bin/python tools/extract_structure.py --level A1   # regenerate JSON

The export looks like {"rules": {"a1-01": {"<topic>": "<text>"}}}. Each rule
goes to lessons.<id>.rules.<topic> of the curation file for the lesson's
level (the id prefix). Topics that do not exist in Content/<LEVEL>.json are
reported and skipped. After regenerating and rebuilding the app, the app
drops its local copies of rules that now match the bundled text.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    export = json.loads(Path(sys.argv[1]).expanduser().read_text())
    by_level: dict[str, dict[str, dict[str, str]]] = {}
    for lesson_id, rules in export.get("rules", {}).items():
        level = lesson_id.split("-")[0].upper()
        by_level.setdefault(level, {})[lesson_id] = rules

    status = 0
    for level, lessons in sorted(by_level.items()):
        cur_path = ROOT / "tools" / "curation" / f"{level}.json"
        content_path = ROOT / "Content" / f"{level}.json"
        curation = json.loads(cur_path.read_text()) if cur_path.exists() else {}
        content = json.loads(content_path.read_text())
        topics = {l["id"]: {g["topic"] for g in l["grammar"]} for l in content["lessons"]}

        changed = 0
        for lesson_id, rules in sorted(lessons.items()):
            if lesson_id not in topics:
                print(f"skip: unknown lesson {lesson_id}", file=sys.stderr)
                status = 1
                continue
            entry = curation.setdefault("lessons", {}).setdefault(lesson_id, {})
            target = entry.setdefault("rules", {})
            for topic, text in rules.items():
                if topic not in topics[lesson_id]:
                    print(f"skip: {lesson_id}: unknown topic {topic!r}", file=sys.stderr)
                    status = 1
                    continue
                text = text.strip()
                if target.get(topic) != text:
                    target[topic] = text
                    changed += 1
        cur_path.write_text(json.dumps(curation, ensure_ascii=False, indent=2) + "\n")
        print(f"{cur_path.relative_to(ROOT)}: {changed} rule(s) updated")
    return status


if __name__ == "__main__":
    sys.exit(main())
