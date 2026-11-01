#!/usr/bin/env python3
"""render-digest.py — assemble the weekly ePrint digest note body.

Usage:
  render-digest.py --items <new.jsonl> --results <batch.jsonl>... --trends <trends.md>
                   --picks <picks.jsonl> --glossary <glossary.jsonl>
                   --title <title> [--append-date YYYY-MM-DD] -o <body.md>

--items is select-new.py output. --results are the per-paper LLM outputs, one JSON
object per line: {id, title_ja, summary_ja, pqc}; several batch files may be given.
--trends holds the "今週の流行" bullets written by the agent; the per-category count
line is appended here so the numbers always come from the data.
--picks holds 1-8 papers to feature, in display order: {id, overview_ja}.
--glossary holds the term explanations: {term, desc}.

The note shows only trends, picks and glossary, but every item must still have
exactly one valid result: the trends are judged from all of them, so a gap is an
error (exit 3), never a silent omission.

--append-date renders the block appended to an existing note of the same week: a
dated H2 with every other heading one level down, and no H1.

stdout: total=N and pqc=N. Exit codes: 0 ok / 2 usage error / 3 invalid input.
"""

import argparse
import json
import re
import sys

# Same order as select-new.py.
CATEGORIES = [
    "PROTOCOLS",
    "FOUNDATIONS",
    "PUBLICKEY",
    "ATTACKS",
    "IMPLEMENTATION",
    "APPLICATIONS",
    "SECRETKEY",
]
MAX_PICKS = 8
# weekly-review processes sections carrying this marker; the digest must not.
# Both colons are rejected: a Japanese-writing LLM often emits the fullwidth one.
READ_VERDICT = "読了判定:"
READ_VERDICT_RE = re.compile(r"読了判定[:：]")
# inbox-capture / weekly-review find their daily notes by this title shape.
INBOX_TITLE_RE = re.compile(r"inbox \d{4}-\d{2}")


class InputError(Exception):
    pass


def id_key(paper_id):
    year, num = paper_id.split("/")
    return int(year), int(num)


def read_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as e:
                raise InputError(f"{path} line {n}: invalid JSON ({e.msg})") from e
            if not isinstance(row, dict):
                raise InputError(f"{path} line {n}: not a JSON object")
            rows.append(row)
    return rows


def one_line(text):
    return " ".join(str(text).split())


def check_text(owner, key, value):
    if not value:
        raise InputError(f"{owner}: {key} is empty")
    if READ_VERDICT_RE.search(value):
        raise InputError(f"{owner}: {key} contains {READ_VERDICT!r}")
    return value


def load_results(paths, item_ids):
    results = {}
    for path in paths:
        for r in read_jsonl(path):
            rid = r.get("id")
            if rid not in item_ids:
                raise InputError(f"result for unknown id {rid!r} in {path}")
            if rid in results:
                raise InputError(f"duplicate result for {rid}")
            if not isinstance(r.get("pqc"), bool):
                raise InputError(f"{rid}: pqc must be true or false, got {r.get('pqc')!r}")
            for key in ("title_ja", "summary_ja"):
                r[key] = check_text(rid, key, one_line(r.get(key) or ""))
            results[rid] = r
    missing = sorted(item_ids - results.keys(), key=id_key)
    if missing:
        raise InputError(f"no result for: {', '.join(missing)}")
    return results


def load_picks(path, item_ids):
    rows = read_jsonl(path)
    if not rows:
        raise InputError("no pick: feature at least one paper")
    if len(rows) > MAX_PICKS:
        raise InputError(f"{len(rows)} picks: at most {MAX_PICKS}")
    picks, seen = [], set()
    for p in rows:
        pid = p.get("id")
        if pid not in item_ids:
            raise InputError(f"pick of unknown id {pid!r}")
        if pid in seen:
            raise InputError(f"duplicate pick {pid}")
        seen.add(pid)
        lines = [line.strip() for line in str(p.get("overview_ja") or "").splitlines()]
        overview = "\n".join(line for line in lines if line)
        check_text(pid, "overview_ja", overview)
        if any(line.startswith("#") for line in overview.splitlines()):
            raise InputError(f"{pid}: overview_ja must not contain headings")
        picks.append((pid, overview))
    return picks


def load_glossary(path):
    entries = []
    for g in read_jsonl(path):
        term = check_text("glossary", "term", one_line(g.get("term") or ""))
        entries.append((term, check_text(term, "desc", one_line(g.get("desc") or ""))))
    return entries


def render(items, results, trends, picks, glossary, title, append_date):
    # h(2) is the top section level of a standalone note.
    shift = 1 if append_date else 0
    h = lambda level: "#" * (level + shift)
    by_id = {p["id"]: p for p in items}
    counts = {c: sum(1 for p in items if p["category"] == c) for c in CATEGORIES}
    pqc_count = sum(1 for r in results.values() if r["pqc"])

    out = [f"## 追加分（{append_date} 実行）" if append_date else f"# {title}", ""]
    out += [f"{h(2)} 今週の流行", ""]
    out += trends.rstrip().splitlines()
    out.append(
        "- カテゴリ別: "
        + " / ".join(f"{c} {counts[c]}" for c in CATEGORIES)
        + f"（計 {len(items)} 件、うち PQC 関連 {pqc_count} 件）"
    )
    out += ["", f"{h(2)} ピックアップ"]
    for pid, overview in picks:
        item, result = by_id[pid], results[pid]
        tags = " · ".join([item["category"]] + (["PQC"] if result["pqc"] else []))
        out += ["", f"{h(3)} {result['title_ja']}", ""]
        out += [f"- [{pid}]({item['link']}) · {tags}", f"- 原題: {one_line(item['title'])}", ""]
        out += overview.splitlines()
    out += ["", f"{h(2)} 用語解説", ""]
    out += [f"- **{term}**: {desc}" for term, desc in glossary] or ["- 該当なし"]
    body = "\n".join(out) + "\n"
    if READ_VERDICT_RE.search(body):
        raise InputError(f"trends contain {READ_VERDICT!r}")
    return ("\n" + body if append_date else body), pqc_count


def main():
    parser = argparse.ArgumentParser(prog="render-digest.py")
    parser.add_argument("--items", required=True)
    parser.add_argument("--results", required=True, nargs="+")
    parser.add_argument("--trends", required=True)
    parser.add_argument("--picks", required=True)
    parser.add_argument("--glossary", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--append-date")
    parser.add_argument("-o", "--out", required=True)
    args = parser.parse_args()
    if INBOX_TITLE_RE.search(args.title):
        parser.error(f"title {args.title!r} would be picked up by inbox-capture / weekly-review")

    try:
        items = read_jsonl(args.items)
        unknown = {p["category"] for p in items} - set(CATEGORIES)
        if unknown:
            raise InputError(f"unknown category: {', '.join(sorted(unknown))}")
        item_ids = {p["id"] for p in items}
        results = load_results(args.results, item_ids)
        picks = load_picks(args.picks, item_ids)
        glossary = load_glossary(args.glossary)
        with open(args.trends, encoding="utf-8") as f:
            trends = f.read()
        # Headings in free text would not be shifted in append mode.
        if any(line.lstrip().startswith("#") for line in trends.splitlines()):
            raise InputError("trends must not contain headings")
        body, pqc_count = render(items, results, trends, picks, glossary, args.title, args.append_date)
    except (InputError, OSError) as e:
        print(f"render-digest.py: {e}", file=sys.stderr)
        sys.exit(3)

    with open(args.out, "w", encoding="utf-8") as f:
        f.write(body)
    print(f"total={len(items)}")
    print(f"pqc={pqc_count}")


if __name__ == "__main__":
    main()
