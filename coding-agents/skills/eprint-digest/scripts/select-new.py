#!/usr/bin/env python3
"""select-new.py — pick the ePrint papers not yet digested from the 7 category feeds.

Usage:
  select-new.py select --feeds-dir <dir> -o <out.jsonl> [--state <file>] [--now <ISO>] [--days N]
  select-new.py commit --max-id <YYYY/NNNN> [--state <file>]

select reads <dir>/<CAT>.xml for every category and writes one JSON object per new
paper to <out.jsonl>: {id, category, title, link, published, authors, abstract}.
Records are grouped by category (fixed order) and ascending by id within each.
stdout carries only key=value metadata, never abstracts, so the caller's context
stays small:
  mode=initial|incremental  total=N  count_<CAT>=n  max_id=<newest selected or empty>
  warn_gap=<CAT,...>  (feeds whose oldest item was still new: older papers may be missing)
  out=<path>

"New" means id greater than the stored max_id, compared as (year, number) so that
2027/0001 follows 2026/2600. With no state file, papers published within --days
(default 7) of --now are selected instead.

select never writes state. Run commit only after the digest note has been written,
so a failed run is retried instead of skipped. commit never moves the position back.

The default state file is $EPRINT_DIGEST_STATE or ~/.cache/eprint-digest/state.json.

Exit codes: 0 ok / 2 usage error / 3 a feed or the state file is missing or unreadable
(never fall back silently: advancing past an unread feed would lose its papers).
"""

import argparse
import json
import os
import re
import sys
# stdlib parser on purpose: it leaves external entities unresolved (ParseError, so
# exit 3) and expat >= 2.4.1 rejects entity amplification; see the XXE test case.
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

CATEGORIES = [
    "PROTOCOLS",
    "FOUNDATIONS",
    "PUBLICKEY",
    "ATTACKS",
    "IMPLEMENTATION",
    "APPLICATIONS",
    "SECRETKEY",
]
DC_CREATOR = "{http://purl.org/dc/elements/1.1/}creator"
ID_RE = re.compile(r"^(\d{4})/(\d{3,})$")
LINK_ID_RE = re.compile(r"/(\d{4}/\d{3,})/?$")
LINK_PREFIX = "https://eprint.iacr.org/"


class InputError(Exception):
    """A feed or the state file could not be read; exit 3."""


class UsageError(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        print(f"select-new.py: {message}", file=sys.stderr)
        sys.exit(2)


def id_key(paper_id):
    m = ID_RE.match(paper_id)
    if not m:
        raise ValueError(f"malformed ePrint id: {paper_id!r}")
    return int(m.group(1)), int(m.group(2))


def default_state():
    return os.environ.get("EPRINT_DIGEST_STATE") or os.path.expanduser(
        "~/.cache/eprint-digest/state.json"
    )


def read_state(path):
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            max_id = json.load(f)["max_id"]
        id_key(max_id)
        return max_id
    except (OSError, ValueError, KeyError, TypeError) as e:
        raise InputError(f"state file {path} is unreadable: {e}") from e


def parse_feed(path, category):
    if not os.path.exists(path):
        raise InputError(f"feed for {category} not found: {path}")
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        raise InputError(f"feed for {category} is not valid XML ({path}): {e}") from e
    channel = root.find("channel")
    if root.tag != "rss" or channel is None:
        raise InputError(f"feed for {category} is not an RSS document: {path}")
    items = channel.findall("item")
    # Each category feed carries its 100 most recent papers, so an empty one means a
    # broken response; accepting it would let the position advance past the category.
    if not items:
        raise InputError(f"feed for {category} has no items: {path}")
    papers = []
    for item in items:
        link = (item.findtext("link") or "").strip()
        m = LINK_ID_RE.search(link)
        if not m or not link.startswith(LINK_PREFIX):
            raise InputError(f"feed for {category} has an item without an ePrint link: {link!r}")
        try:
            published = parsedate_to_datetime(item.findtext("pubDate") or "")
        except (TypeError, ValueError) as e:
            raise InputError(f"feed for {category} has a bad pubDate on {m.group(1)}") from e
        # RFC 2822 "-0000" parses as a naive datetime; it still means UTC.
        if published.tzinfo is None:
            published = published.replace(tzinfo=timezone.utc)
        papers.append(
            {
                "id": m.group(1),
                "category": category,
                "title": (item.findtext("title") or "").strip(),
                "link": link,
                "published": published.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "authors": [(a.text or "").strip() for a in item.findall(DC_CREATOR)],
                "abstract": (item.findtext("description") or "").strip(),
                "_published": published,
            }
        )
    return papers


def cmd_select(args):
    max_id = read_state(args.state)
    if max_id is None:
        cutoff = args.now - timedelta(days=args.days)
        is_new = lambda p: p["_published"] >= cutoff
    else:
        floor = id_key(max_id)
        is_new = lambda p: id_key(p["id"]) > floor

    seen = set()
    selected, counts, gaps = [], {}, []
    for cat in CATEGORIES:
        papers = parse_feed(os.path.join(args.feeds_dir, f"{cat}.xml"), cat)
        fresh = [p for p in papers if is_new(p)]
        if fresh and len(fresh) == len(papers):
            gaps.append(cat)
        fresh = [p for p in fresh if p["id"] not in seen]
        seen.update(p["id"] for p in fresh)
        fresh.sort(key=lambda p: id_key(p["id"]))
        counts[cat] = len(fresh)
        selected.extend(fresh)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        for p in selected:
            p = {k: v for k, v in p.items() if not k.startswith("_")}
            f.write(json.dumps(p, ensure_ascii=False) + "\n")

    newest = max((p["id"] for p in selected), key=id_key, default="")
    print(f"mode={'initial' if max_id is None else 'incremental'}")
    print(f"total={len(selected)}")
    for cat in CATEGORIES:
        print(f"count_{cat}={counts[cat]}")
    print(f"max_id={newest}")
    print(f"warn_gap={','.join(gaps)}")
    print(f"out={args.out}")


def cmd_commit(args):
    try:
        new_key = id_key(args.max_id)
    except ValueError as e:
        print(f"select-new.py: {e}", file=sys.stderr)
        sys.exit(2)
    current = read_state(args.state)
    if current is not None and id_key(current) >= new_key:
        print(f"unchanged max_id={current}")
        return
    os.makedirs(os.path.dirname(os.path.abspath(args.state)), exist_ok=True)
    tmp = args.state + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(
            {"max_id": args.max_id, "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
            f,
        )
        f.write("\n")
    os.replace(tmp, args.state)
    print(f"saved max_id={args.max_id}")


def parse_now(value):
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not an ISO 8601 datetime: {value!r}")


def main():
    parser = UsageError(prog="select-new.py")
    sub = parser.add_subparsers(dest="cmd", parser_class=UsageError)
    sel = sub.add_parser("select")
    sel.add_argument("--feeds-dir", required=True)
    sel.add_argument("-o", "--out", required=True)
    sel.add_argument("--state", default=default_state())
    sel.add_argument("--now", type=parse_now, default=datetime.now(timezone.utc))
    sel.add_argument("--days", type=int, default=7)
    com = sub.add_parser("commit")
    com.add_argument("--max-id", required=True)
    com.add_argument("--state", default=default_state())
    args = parser.parse_args()
    if args.cmd is None:
        parser.error("a subcommand is required (select | commit)")
    try:
        (cmd_select if args.cmd == "select" else cmd_commit)(args)
    except InputError as e:
        print(f"select-new.py: {e}", file=sys.stderr)
        sys.exit(3)


if __name__ == "__main__":
    main()
