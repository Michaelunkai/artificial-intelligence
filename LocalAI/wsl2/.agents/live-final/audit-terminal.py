#!/usr/bin/env python3
import argparse
import collections
import json
import re
from pathlib import Path


ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
RANK = re.compile(
    r"^\s*(\d+)\.\s+.+?\s+\(([\d,]+) bytes\)\s+\|\s+(.+?)\s*$"
)
FORBIDDEN = (
    "[LIVE ",
    "| Now:",
    "Gather live evidence for:",
    "Perform the actions required by:",
    "Verify the result against:",
    "Deliver the verified result for:",
)


def clean(value):
    return " ".join(ANSI.sub("", value).split())


parser = argparse.ArgumentParser()
parser.add_argument("terminal")
parser.add_argument("--expected-ranks", type=int, default=0)
args = parser.parse_args()

raw = Path(args.terminal).read_bytes().decode("utf-8", errors="replace")
physical = re.split(r"[\r\n]+", raw)
lines = [clean(line) for line in physical if clean(line)]
working = [line for line in lines if "[WORKING]" in line]
counts = collections.Counter(working)
duplicates = {line: count for line, count in counts.items() if count > 1}
forbidden_hits = {
    phrase: sum(phrase.lower() in line.lower() for line in lines)
    for phrase in FORBIDDEN
}
forbidden_hits["PLAN status"] = sum(
    re.match(r"^\s*(?:\[[^\]]+\]\s*)?PLAN\b", line, re.IGNORECASE) is not None
    for line in lines
)
forbidden_hits["WAIT status"] = sum(
    re.match(r"^\s*(?:\[[^\]]+\]\s*)?WAIT\b", line, re.IGNORECASE) is not None
    for line in lines
)
ranks = []
for line in lines:
    match = RANK.match(line)
    if match:
        ranks.append(
            {
                "rank": int(match.group(1)),
                "bytes": int(match.group(2).replace(",", "")),
                "path": match.group(3),
            }
        )

expected_sequence = list(range(1, args.expected_ranks + 1))
rank_sequence = [item["rank"] for item in ranks]
descending = all(
    ranks[index]["bytes"] >= ranks[index + 1]["bytes"]
    for index in range(len(ranks) - 1)
)
english_progress = all(
    re.search(r"[A-Za-z]{3,}", line) is not None
    and not re.search(r"\b(?:WAIT|PLAN)\b", line)
    for line in working
)
result = {
    "working_frames": len(working),
    "unique_working_frames": len(counts),
    "duplicate_groups": duplicates,
    "forbidden_hits": forbidden_hits,
    "english_progress": english_progress,
    "ranked_rows": len(ranks),
    "rank_sequence_exact": (
        rank_sequence == expected_sequence if args.expected_ranks else True
    ),
    "descending_bytes": descending,
    "first_working_frames": working[:12],
    "last_working_frames": working[-12:],
    "first_rank": ranks[0] if ranks else None,
    "last_rank": ranks[-1] if ranks else None,
}
print(json.dumps(result, indent=2))

failed = (
    bool(duplicates)
    or any(forbidden_hits.values())
    or not english_progress
    or (
        args.expected_ranks
        and (
            len(ranks) != args.expected_ranks
            or rank_sequence != expected_sequence
            or not descending
        )
    )
)
raise SystemExit(1 if failed else 0)
