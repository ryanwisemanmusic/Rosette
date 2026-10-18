"""Expand owner-module registrations in call order for build graph audits."""
from pathlib import Path
import re

CALL = re.compile(r'@import\("([^"\n]+\.zig)"\)\.(register\d*)\(b,\s*\.\{.*?\}\);', re.S)


def graph_source(path: Path) -> tuple[str, list[Path]]:
    root = path.resolve().parent
    inputs = {path.resolve()}
    active = set()

    def expand(text: str) -> str:
        def replace(match: re.Match) -> str:
            child = (root / match[1]).resolve()
            if not child.is_relative_to(root):
                raise ValueError("build registration escapes repository root: " + match[1])
            key = (child, match[2])
            if key in active:
                raise ValueError("recursive build registration: " + match[1])
            inputs.add(child)
            source = child.read_text(encoding="utf-8")
            function = re.search(r'^pub fn ' + re.escape(match[2]) + r'\([^\n]+\) void \{\n(.*?)^\}', source, re.M | re.S)
            if not function:
                raise ValueError("missing owner registration: " + match[1] + "." + match[2])
            active.add(key)
            body = expand(function[1])
            active.remove(key)
            return "{\n" + body + "}\n"
        return CALL.sub(replace, text)

    return expand(path.read_text(encoding="utf-8")), sorted(inputs)
