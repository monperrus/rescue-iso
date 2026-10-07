"""Print the .apk file names needed to install PACKAGES from an Alpine APKINDEX.

usage: python3 closure.py APKINDEX.tar.gz PACKAGE...
"""

from __future__ import annotations

import re
import sys
import tarfile


def parse(path: str) -> list[dict[str, list[str]]]:
    with tarfile.open(path) as tar:
        member = tar.extractfile("APKINDEX")
        assert member is not None
        text = member.read().decode()
    records = []
    for block in text.split("\n\n"):
        record: dict[str, list[str]] = {}
        for line in block.splitlines():
            if len(line) > 2 and line[1] == ":":
                record.setdefault(line[0], []).append(line[2:])
        if "P" in record:
            records.append(record)
    return records


def closure(records: list[dict[str, list[str]]], wanted: list[str]) -> list[str]:
    by_name = {}
    provider = {}
    for r in records:
        by_name[r["P"][0]] = r
        for item in " ".join(r.get("p", [])).split():
            provider.setdefault(item.split("=")[0], r)

    seen: dict[str, dict[str, list[str]]] = {}
    todo = list(wanted)
    while todo:
        dep = todo.pop()
        if dep.startswith("!"):
            continue
        name = re.split(r"[<>=~]", dep, maxsplit=1)[0]
        record = by_name.get(name) or provider.get(name)
        if record is None:
            sys.exit(f"unresolvable dependency: {dep}")
        if record["P"][0] in seen:
            continue
        seen[record["P"][0]] = record
        todo.extend(" ".join(record.get("D", [])).split())
    return sorted(f"{r['P'][0]}-{r['V'][0]}.apk" for r in seen.values())


def main() -> None:
    index, *wanted = sys.argv[1:]
    print("\n".join(closure(parse(index), wanted)))


if __name__ == "__main__":
    main()
