#!/usr/bin/env python3
"""Prove that a refactor commit moved Zig code without changing what it does.

Splitting a large Zig file into many keeps every function body, but rewrites
how bodies call each other: a method `self.foo(a)` becomes a free function
`process_impl_x.foo(self, a)`, constants gain module prefixes, and the old
method often stays behind as a one-line wrapper that forwards to the new
function. None of that changes behaviour; anything else might.

This audit takes a parent and a child commit, extracts the given source
directories of each with `git archive` (the working tree is never touched),
normalises those mechanical rewrites in every function body, and reports, for
every function of the child, whether an identical body existed in the parent:

    CHANGED  a function whose body differs after normalisation
    ADDED    a function name the parent did not have
    REMOVED  a function name the child no longer has (often test helpers
             moved to files this audit skips: names containing "test")

A split that only moves code reports no CHANGED rows. A CHANGED row is either
a deliberate edit that travelled with the split, or a regression to read.

Usage:
    tools/audit_refactor_equivalence.py PARENT CHILD DIR [DIR...]
    tools/audit_refactor_equivalence.py --diff NAME PARENT CHILD DIR [DIR...]

Example (the 2026-10-11 ELF processor split):
    tools/audit_refactor_equivalence.py 4ac0fcc2 bfe3eaa9 lib/processor/ELF_processor
"""

import collections
import difflib
import os
import re
import subprocess
import sys
import tarfile
import tempfile


def strip(text):
    """Blank out comments, string and char literals and multiline-string
    lines, keeping every offset, so braces can be matched safely."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        if text.startswith("//", i) or text.startswith("\\\\", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    j += 1
                j += 1
            for k in range(i + 1, min(j, n)):
                out[k] = " "
            i = j + 1
            continue
        if c == "'":
            j = i + 1
            while j < n and text[j] != "'":
                if text[j] == "\\":
                    j += 1
                j += 1
            if j - i <= 12:
                for k in range(i + 1, j):
                    out[k] = " "
                i = j + 1
                continue
        i += 1
    return "".join(out)


FN = re.compile(r"(?m)^[ \t]*(?:pub\s+)?(?:inline\s+|export\s+|noinline\s+)?fn\s+([A-Za-z_]\w*)\s*\(")


def functions(text):
    """name -> [body] for every fn with a body, at any nesting depth."""
    s = strip(text)
    out = collections.defaultdict(list)
    for m in FN.finditer(s):
        i, depth = m.end(), 1
        while depth > 0 and i < len(s):
            if s[i] == "(":
                depth += 1
            elif s[i] == ")":
                depth -= 1
            i += 1
        # The body is the brace group that ends its line. A return type
        # can hold brace groups of its own - `error{Unsafe}!?T`,
        # `?struct { a: u64 }` - and those are followed on the same line by
        # more of the type (`!`, `?`, a name, the body's `{`).
        j = s.find("{", i)
        semi = s.find(";", i)
        if j < 0 or (0 <= semi < j):
            continue
        while True:
            depth, k = 0, j
            while k < len(s):
                if s[k] == "{":
                    depth += 1
                elif s[k] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                k += 1
            rest = s[k + 1 :]
            line_rest = rest[: rest.find("\n")] if "\n" in rest else rest
            following = line_rest.strip()
            if following and following[0] not in ";,)":
                nxt = s.find("{", k + 1)
                if nxt < 0:
                    break
                j = nxt
                continue
            break
        out[m.group(1)].append(text[j : k + 1])
    return out


def normalize(body):
    b = re.sub(r"//[^\n]*", "", body)
    b = re.sub(r"\s+", " ", b)
    b = re.sub(r"\(\s+", "(", b)
    b = re.sub(r"\s+\)", ")", b)
    b = re.sub(r",\s*\)", ")", b)
    b = re.sub(r"\b__[A-Za-z]+_", "", b)
    b = re.sub(r"\b__ProcessInternals\._(\w+)\(\)\.\*", r"\1", b)
    b = re.sub(r"\b__ProcessInternals\._", "", b)
    b = re.sub(r"\b[A-Za-z_]\w*_impl_\w+\.", "", b)
    b = re.sub(r"\b(?:[a-z][a-z0-9_]*\.)+(\w+)\(self([,)])", r"\1(self\2", b)
    b = re.sub(r"\b(\w+)\(self, ?", r"self.\1(", b)
    b = re.sub(r"\b(\w+)\(self\)", r"self.\1()", b)
    b = re.sub(r"\bself\.self\.", "self.", b)
    b = re.sub(r"@This\(\)", "Self", b)
    # `const name = module._name;` re-exports a moved file adds at the top
    # of a body: aliases, not statements.
    b = re.sub(r"const (\w+) = (?:\w+\.)+_?\1; ?", "", b)
    return b.strip()


def is_forwarder(name, body):
    return re.fullmatch(r"\{ (return )?(try )?(?:self\.|(?:[\w@()]+\.)+)?" + re.escape(name) + r"\(.*\); \}", body) is not None


def extract(commit, dirs, into):
    archive = subprocess.run(["git", "archive", commit, *dirs], check=True, capture_output=True).stdout
    path = os.path.join(into, "archive.tar")
    with open(path, "wb") as handle:
        handle.write(archive)
    with tarfile.open(path) as tar:
        tar.extractall(into, filter="data")


def table(root, dirs):
    t = collections.defaultdict(list)
    for d in dirs:
        for dp, _, files in os.walk(os.path.join(root, d)):
            for name in files:
                if not name.endswith(".zig") or "test" in name:
                    continue
                with open(os.path.join(dp, name), errors="replace") as handle:
                    for fn, bodies in functions(handle.read()).items():
                        t[fn] += [normalize(b) for b in bodies]
    return t


def main(argv):
    show = None
    if argv and argv[0] == "--diff":
        show, argv = argv[1], argv[2:]
    if len(argv) < 3:
        print(__doc__)
        return 2
    parent, child, dirs = argv[0], argv[1], argv[2:]
    with tempfile.TemporaryDirectory() as work:
        before, after = os.path.join(work, "parent"), os.path.join(work, "child")
        os.makedirs(before)
        os.makedirs(after)
        extract(parent, dirs, before)
        extract(child, dirs, after)
        old, new = table(before, dirs), table(after, dirs)
    if show:
        def stmts(b):
            return b.replace("; ", ";\n").replace("{ ", "{\n").replace("} ", "}\n").split("\n")
        for body in new.get(show, []):
            if is_forwarder(show, body):
                continue
            best = min((list(difflib.unified_diff(stmts(p), stmts(body), lineterm="", n=0)) for p in old.get(show, [""])), key=len)
            print("\n".join(line for line in best if not line.startswith(("@@", "---", "+++"))))
        return 0
    changed, added = [], []
    for name, bodies in new.items():
        remaining = collections.Counter(old.get(name, []))
        for body in bodies:
            if is_forwarder(name, body):
                continue
            if name not in old:
                added.append(name)
            elif remaining[body] > 0:
                remaining[body] -= 1
            else:
                changed.append(name)
    removed = sorted(name for name in old if name not in new)
    total = sum(len(v) for v in new.values())
    for name in sorted(set(changed)):
        print(f"CHANGED {name}")
    for name in sorted(set(added)):
        print(f"ADDED {name}")
    for name in removed:
        print(f"REMOVED {name}")
    print(f"summary: {total} function bodies in {child}; changed={len(changed)} added={len(added)} removed={len(removed)} relative to {parent}")
    return 1 if changed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
