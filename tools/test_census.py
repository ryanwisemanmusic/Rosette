#!/usr/bin/env python3
"""Create an auditable census of Zig declarations and check artifacts.

The Zig build graph is the execution authority. This tool records the source
population separately, maps each named and anonymous declaration to the most
specific test artifact whose root can own it, and keeps run-required artifacts
separate from compile-only artifacts. It deliberately does not infer that a
source declaration ran merely because its file compiled.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

from build_graph_sources import graph_source


TEST_RE = re.compile(r'^\s*test\s+"([^"]*)"')
ANONYMOUS_TEST_RE = re.compile(r'^\s*test\s*\{')
MODULE_BLOCK_RE = re.compile(
    r"\bconst\s+(\w+)\s*=\s*b\.(?:createModule|addModule)\(\.\{"
    r"(?P<body>.*?)\n\s*\}\);",
    re.DOTALL,
)
ROOT_SOURCE_RE = re.compile(r'\.root_source_file\s*=\s*b\.path\("([^"]+)"')
ADD_TEST_RE = re.compile(
    r"(?:(?:const|var)\s+(\w+)\s*=\s*)?b\.addTest\(\.\{"
    r"\s*\.root_module\s*=\s*(\w+)\s*\}\s*\)",
    re.DOTALL,
)
NESTED_RUN_TEST_ALIAS_RE = re.compile(
    r"(?:const|var)\s+(\w+)\s*=\s*b\.addRunArtifact\(\s*"
    r"b\.addTest\(\.\{\s*\.root_module\s*=\s*(\w+)\s*\}\s*\)\s*\)"
)
PATH_ARRAY_LOOP_RE = re.compile(
    r"for\s*\(\s*\[_\]\[\]const\s+u8\s*\{(?P<paths>.*?)\}\s*,"
    r"\s*0\.\.\)\s*\|\s*path\s*,\s*\w+\s*\|\s*\{",
    re.DOTALL,
)
RUN_INLINE_RE = re.compile(
    r"check_step\.dependOn\(&b\.addRunArtifact\(\s*(\w+)\s*\)\.step\)"
)
RUN_ALIAS_RE = re.compile(
    r"(?:const|var)\s+(\w+)\s*=\s*b\.addRunArtifact\(\s*(\w+)\s*\)"
)
RUN_REFERENCE_RE = re.compile(r"check_step\.dependOn\(&\s*(\w+)\.step\)")
COMPILE_REFERENCE_RE = re.compile(r"check_step\.dependOn\(&\s*(\w+)\.step\)")
ANY_DEPENDENCY_RE = re.compile(
    r"\b(\w+)\.dependOn\(&\s*(?:b\.addRunArtifact\(\s*(\w+)\s*\)|(\w+))\.step\)"
)
PASS_RE = re.compile(r"\brun test (\d+) pass\b")
BUILD_SUMMARY_RE = re.compile(r"Build Summary:\s*(.*)")
IMPORT_RE = re.compile(r'@import\("([^"]+)"\)')

# The shell helper is intentionally built by the Makefile target rather than
# the Zig test graph: its macOS @cImport surface is a CLI executable boundary,
# not a test-library boundary. Keep that distinction explicit in the manifest
# while still assigning every declaration in the source census.
EXTERNAL_COMPILE_ONLY = (
    {
        "name": "compile-only:make-shell-helper",
        "root_module": "make-shell-helper",
        "root_source": "src/shell/global_config/rosette_shell.zig",
        "check_step_reference": "make shell-helper-build",
        "artifact_kind": "external-compile-only",
        "expected_modes": ["compile-only"],
        "expected_mode": "compile-only",
    },
)


@dataclass(frozen=True)
class Declaration:
    path: str
    line: int
    name: str
    kind: str


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for directory in ("ISA", "lib", "src", "pkg"):
        base = root / directory
        if not base.exists():
            continue
        for path in base.rglob("*.zig"):
            if any(part in {".zig-cache", "zig-out", "__pycache__"} for part in path.parts):
                continue
            files.append(path)
    return sorted(files)


def declarations(path: Path, root: Path) -> list[Declaration]:
    result: list[Declaration] = []
    for line_number, line in enumerate(
        path.read_text(encoding="utf-8", errors="replace").splitlines(), 1
    ):
        match = TEST_RE.match(line)
        if match:
            result.append(
                Declaration(str(path.relative_to(root)), line_number, match.group(1), "named")
            )
            continue
        if ANONYMOUS_TEST_RE.match(line):
            result.append(
                Declaration(
                    str(path.relative_to(root)),
                    line_number,
                    f"<anonymous>@{line_number}",
                    "anonymous",
                )
            )
    return result


def normalize_source(root: Path, source: str | None) -> str | None:
    if not source:
        return None
    path = Path(source)
    if path.parts and path.parts[0] == "..":
        path = Path(*path.parts[1:])
    return path.as_posix()


def parse_modules(root: Path, text: str) -> dict[str, str | None]:
    modules: dict[str, str | None] = {}
    for match in MODULE_BLOCK_RE.finditer(text):
        source_match = ROOT_SOURCE_RE.search(match.group("body"))
        modules[match.group(1)] = normalize_source(
            root, source_match.group(1) if source_match else None
        )
    return modules


def quoted_array(text: str, name: str) -> list[str]:
    match = re.search(
        rf"const\s+{re.escape(name)}\s*=.*?\{{(?P<body>.*?)\n\s*\}};",
        text,
        re.DOTALL,
    )
    return re.findall(r'"([^"]+)"', match.group("body")) if match else []


def dynamic_sources(text: str, module: str, match_start: int) -> list[str]:
    """Resolve source lists used by comptime test-artifact loops."""
    if module == "module":
        # Some folder build registrations create a test module from each path
        # in a local array, then pass that module to addTest inside the loop.
        # Resolve only the enclosing path-array loop that also constructs the
        # module from `path`; unrelated loops in the build graph stay opaque.
        for loop in reversed(list(PATH_ARRAY_LOOP_RE.finditer(text, 0, match_start))):
            body = text[loop.end() : match_start]
            if re.search(r"\.root_source_file\s*=\s*b\.path\(path\)", body):
                return re.findall(r'"([^"\n]+\.zig)"', loop.group("paths"))
    if module == "tp_mod":
        return [f"third_party/{item}" for item in quoted_array(text, "third_party_test_files")]
    if module == "subsystem_mod":
        block = re.search(
            r"const\s+subsystems\s*=.*?\{(?P<body>.*?)\n\s*\};",
            text,
            re.DOTALL,
        )
        return re.findall(r'\.root\s*=\s*"([^"]+)"', block.group("body")) if block else []
    if module == "package_mod":
        # The Win32 DLL catalogue has one test artifact per package, but the
        # build graph declares those roots through a single package-spec loop.
        # Keep the census aligned with that expansion instead of counting the
        # loop body as one anonymous artifact.
        dll_specs_at = text.find("const dll_win32_package_specs")
        dll_loop_at = text.find("for (dll_win32_package_specs)", dll_specs_at)
        common_loop_at = text.find("inline for (common_package_roots)", dll_loop_at)
        if (
            dll_specs_at >= 0
            and dll_loop_at >= 0
            and common_loop_at >= 0
            and dll_loop_at < match_start < common_loop_at
        ):
            block_end = text.find("    };", dll_specs_at)
            block = text[dll_specs_at:block_end] if block_end >= 0 else ""
            return re.findall(r'root_source_file\s*=\s*"([^"]+)"', block)
        common_at = text.rfind("inline for (common_package_roots)", 0, match_start)
        route_at = text.rfind("inline for (route_package_roots)", 0, match_start)
        if common_at > route_at:
            return quoted_array(text, "common_package_roots")
        if route_at >= 0:
            return quoted_array(text, "route_package_roots")
    if module == "source_test_mod":
        return quoted_array(text, "source_test_specs")
    return []


def parse_artifacts(root: Path, text: str, modules: dict[str, str | None]) -> list[dict]:
    artifacts: list[dict] = []
    used_names: set[str] = set()
    test_matches = list(ADD_TEST_RE.finditer(text))
    test_names_by_start: dict[int, str] = {}
    for index, match in enumerate(test_matches, 1):
        declared_name = match.group(1)
        module = match.group(2).strip()
        base_name = declared_name or f"anonymous_add_test_{index}"
        test_names_by_start[match.start()] = base_name
        sources = dynamic_sources(text, module, match.start())
        if not sources:
            sources = [modules.get(module)]
        for source_index, source in enumerate(sources):
            name = base_name if len(sources) == 1 else f"{base_name}[{source_index}]"
            if name in used_names:
                suffix = 2
                while f"{name}#{suffix}" in used_names:
                    suffix += 1
                name = f"{name}#{suffix}"
            used_names.add(name)
            artifacts.append(
                {
                    "name": name,
                    "root_module": module,
                    "root_source": normalize_source(root, source),
                    "check_step_reference": f"{name}.step",
                    "artifact_kind": "test",
                }
            )

    # Inline run dependencies name the actual test artifact; aliases are used
    # by the dynamic-linker portion of build.zig.
    run_artifacts: set[str] = set(RUN_INLINE_RE.findall(text))
    aliases = {alias: artifact for alias, artifact in RUN_ALIAS_RE.findall(text)}
    # Folder registrations sometimes construct a test directly inside
    # addRunArtifact. Associate that run alias with the same test artifact
    # instead of treating it as an unrelated build step.
    for alias_match in NESTED_RUN_TEST_ALIAS_RE.finditer(text):
        test_match = next(
            (
                item
                for item in test_matches
                if item.start() >= alias_match.start()
                and item.start() < alias_match.end()
            ),
            None,
        )
        if test_match is not None:
            aliases[alias_match.group(1)] = test_names_by_start[test_match.start()]
    for alias in RUN_REFERENCE_RE.findall(text):
        if alias in aliases:
            run_artifacts.add(aliases[alias])

    # The direct form is compile-only unless the same artifact is also named
    # by a run dependency. Conditional third-party branches are retained as
    # conditional so the manifest does not pretend the host-independent mode
    # is the only possible execution mode.
    compile_artifacts: set[str] = set(COMPILE_REFERENCE_RE.findall(text))
    compile_artifacts.difference_update(aliases)

    # Tests attached to a named focused build target (for example
    # `block-jit-check`) are intentional test artifacts, but they do not run
    # as part of the repository-wide `check` census. Record them explicitly
    # so they are not mistaken for either default-check tests or unconnected
    # tests. The default check variable is `check_step` in build/build.zig.
    focused_artifacts: set[str] = set()
    for step_name, inline_artifact, dependency in ANY_DEPENDENCY_RE.findall(text):
        if step_name == "check_step":
            continue
        if inline_artifact:
            focused_artifacts.add(inline_artifact)
        elif dependency in aliases:
            focused_artifacts.add(aliases[dependency])
        elif dependency:
            focused_artifacts.add(dependency)

    for artifact in artifacts:
        name = artifact["name"]
        base_name = name.split("[", 1)[0].split("#", 1)[0]
        modes: list[str] = []
        # The third-party loop contains a compile-time-only exception for
        # llvm.zig: it reaches host C runtime symbols that a bare Zig test
        # binary cannot link. The source text contains both branches, so the
        # lexical run-dependency scan sees `tp_test` as runnable even though
        # the selected comptime branch only depends on its compile step.
        compile_only_dynamic = (
            artifact["root_module"] == "tp_mod"
            and artifact["root_source"] == "third_party/llvm/llvm.zig"
        )
        if (name in run_artifacts or base_name in run_artifacts) and not compile_only_dynamic:
            modes.append("run")
        if compile_only_dynamic or name in compile_artifacts or base_name in compile_artifacts:
            modes.append("compile-only")
        if name in focused_artifacts or base_name in focused_artifacts:
            modes.append("focused-only")
        if not modes:
            modes = ["unwired"]
        artifact["expected_modes"] = modes
        artifact["expected_mode"] = modes[0] if len(modes) == 1 else "conditional"
        source = artifact["root_source"]
        if source and (root / source).is_file():
            artifact["root_source_sha256"] = sha256_bytes((root / source).read_bytes())
        else:
            artifact["root_source_sha256"] = "0" * 64

    # A module imported by a run artifact is still a real compile-only
    # obligation even when its own tests are not rooted by b.addTest. Keeping
    # these dependency artifacts explicit prevents a declaration in (for
    # example) lib/io from being misreported as executed by a Mach-O test.
    represented_sources = {
        item["root_source"] for item in artifacts if item.get("root_source")
    }
    for module, source in modules.items():
        if not source or source in represented_sources:
            continue
        name = f"compile-only:{module}"
        if name in used_names:
            continue
        used_names.add(name)
        artifact = {
            "name": name,
            "root_module": module,
            "root_source": source,
            "check_step_reference": f"dependency:{module}",
            "artifact_kind": "dependency-compile-only",
            "expected_modes": ["compile-only"],
            "expected_mode": "compile-only",
        }
        source_path = root / source
        artifact["root_source_sha256"] = (
            sha256_bytes(source_path.read_bytes()) if source_path.is_file() else "0" * 64
        )
        artifacts.append(artifact)

    for template in EXTERNAL_COMPILE_ONLY:
        if any(item["root_source"] == template["root_source"] for item in artifacts):
            continue
        artifact = dict(template)
        source_path = root / artifact["root_source"]
        artifact["root_source_sha256"] = (
            sha256_bytes(source_path.read_bytes()) if source_path.is_file() else "0" * 64
        )
        artifacts.append(artifact)
    return artifacts


def build_graph(root: Path) -> dict:
    path = root / "build" / "build.zig"
    text, registration_inputs = graph_source(path)
    module_roots = parse_modules(root, text)
    artifacts = parse_artifacts(root, text, module_roots)
    graph_inputs = [*registration_inputs, root / "build" / "Makefile"]
    graph_hash = hashlib.sha256()
    for input_path in graph_inputs:
        graph_hash.update(str(input_path.relative_to(root)).encode())
        graph_hash.update(b"\0")
        graph_hash.update(input_path.read_bytes())
        graph_hash.update(b"\0")
    return {
        "path": str(path.relative_to(root)),
        "sha256": sha256_bytes(path.read_bytes()),
        "graph_sha256": graph_hash.hexdigest(),
        "module_roots": module_roots,
        "artifacts": artifacts,
    }


def artifact_ownership(
    declaration: Declaration, artifacts: list[dict], root: Path
) -> tuple[list[str], str | None, str]:
    # All graph paths are normalized relative to root. Keep this hot loop
    # string-based: the census can contain thousands of declarations and the
    # ownership relation is lexical, not a symlink-following operation.
    _ = root
    path = declaration.path.replace("\\", "/")
    candidates: list[tuple[int, str]] = []
    for artifact in artifacts:
        source = artifact.get("root_source")
        if not source:
            continue
        source = source.replace("\\", "/")
        if path == source:
            candidates.append((100_000, artifact["name"]))
            continue
        parent = source.rsplit("/", 1)[0] if "/" in source else ""
        prefix = f"{parent}/" if parent else ""
        if not path.startswith(prefix):
            continue
        # A root.zig/test_root.zig owns its directory. More-specific roots win;
        # ties remain visible in candidate_artifacts rather than being silently
        # discarded.
        relative_depth = path[len(prefix) :].count("/") + 1 if prefix else path.count("/") + 1
        score = 1_000 + parent.count("/") * 10 - relative_depth
        candidates.append((score, artifact["name"]))
    candidates.sort(key=lambda value: (-value[0], value[1]))
    owners = [name for _, name in candidates]
    primary = owners[0] if owners else None
    return owners, primary, "mapped" if primary else "unassigned"


def declaration_hash(item: Declaration) -> str:
    canonical = f"{item.path}\0{item.line}\0{item.kind}\0{item.name}".encode()
    return sha256_bytes(canonical)


def run_check(root: Path, expected_artifacts: list[dict]) -> dict:
    command = [
        "zig",
        "build",
        "-j1",
        "check",
        "--summary",
        "all",
    ]
    # The Zig test graph can emit more than a pipe's capacity from diagnostic
    # and negative-path tests. Capturing that output with PIPE while waiting
    # for the child deadlocks: Zig's run step also waits for its test process
    # to finish before forwarding the captured output. Serialize test steps
    # and spool their output to a file so the test process can always drain
    # its output and finish.
    with tempfile.TemporaryFile(mode="w+b") as output_file:
        completed = subprocess.run(
            command,
            # This repository's Zig build root is build/. Run from there so
            # the test artifacts use the same working directory as the
            # project-supported `zig build check` invocation.
            cwd=root / "build",
            stdout=output_file,
            stderr=subprocess.STDOUT,
            check=False,
        )
        output_file.seek(0)
        output_bytes = output_file.read()
    check_log = root / ".rosette" / "test-census-check.log"
    check_log.parent.mkdir(parents=True, exist_ok=True)
    check_log.write_bytes(output_bytes)
    output = output_bytes.decode("utf-8", errors="replace")
    counts = [int(value) for value in PASS_RE.findall(output)]
    run_required = [
        artifact["name"]
        for artifact in expected_artifacts
        if "run" in artifact.get("expected_modes", [])
    ]
    compile_only = [
        artifact["name"]
        for artifact in expected_artifacts
        if artifact.get("expected_modes") == ["compile-only"]
    ]
    summaries = BUILD_SUMMARY_RE.findall(output)
    return {
        "command": command,
        "exit_code": completed.returncode,
        "output_sha256": sha256_bytes(output_bytes),
        "output_log": str(check_log),
        "executed_artifact_count": len(counts),
        "executed_test_count": sum(counts),
        "artifact_pass_counts": counts,
        "expected_run_artifact_count": len(run_required),
        "expected_run_artifacts": run_required,
        "expected_compile_only_artifacts": compile_only,
        "run_artifact_count_matches": len(counts) == len(run_required),
        "build_summary": summaries[-1] if summaries else None,
        # Some Rosette tests intentionally print the text "failed command" as
        # part of a recovery-path assertion. Keep the count for diagnostics,
        # but never use it as the process verdict; exit_code is authoritative.
        "intentional_failure_text_count": output.count("failed command"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--run-check",
        action="store_true",
        help="run zig build check and record the executed artifact/test counts",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="fail when the requested check does not exit successfully or the census is incomplete",
    )
    args = parser.parse_args()
    root = args.root.resolve()

    source_units = []
    all_declarations: list[Declaration] = []
    for path in source_files(root):
        raw = path.read_bytes()
        found = declarations(path, root)
        all_declarations.extend(found)
        source_units.append(
            {
                "path": str(path.relative_to(root)),
                "sha256": sha256_bytes(raw),
                "declaration_count": len(found),
                "named_declaration_count": sum(item.kind == "named" for item in found),
                "anonymous_declaration_count": sum(item.kind == "anonymous" for item in found),
                "declarations": [
                    {
                        "line": item.line,
                        "name": item.name,
                        "kind": item.kind,
                        "declaration_sha256": declaration_hash(item),
                    }
                    for item in found
                ],
            }
        )

    graph = build_graph(root)
    declaration_records = []
    for item in all_declarations:
        owners, primary, mapping = artifact_ownership(item, graph["artifacts"], root)
        declaration_records.append(
            {
                "path": item.path,
                "line": item.line,
                "name": item.name,
                "kind": item.kind,
                "declaration_sha256": declaration_hash(item),
                "candidate_artifacts": owners,
                "artifact": primary,
                "mapping": mapping,
            }
        )

    named_count = sum(item.kind == "named" for item in all_declarations)
    anonymous_count = sum(item.kind == "anonymous" for item in all_declarations)
    unassigned = [item for item in declaration_records if item["mapping"] != "mapped"]
    duplicate_artifacts = len(graph["artifacts"]) - len(
        {item["name"] for item in graph["artifacts"]}
    )
    graph["artifact_count"] = len(graph["artifacts"])
    graph["run_required_artifact_count"] = sum(
        "run" in item.get("expected_modes", []) for item in graph["artifacts"]
    )
    graph["compile_only_artifact_count"] = sum(
        item.get("expected_modes") == ["compile-only"] for item in graph["artifacts"]
    )
    graph["unwired_artifact_count"] = sum(
        item.get("expected_modes") == ["unwired"] for item in graph["artifacts"]
    )

    execution = (
        run_check(root, graph["artifacts"]) if args.run_check else {"status": "not-run"}
    )
    execution_identity = None
    if execution.get("output_sha256"):
        execution_identity = sha256_bytes(
            (graph["graph_sha256"] + execution["output_sha256"]).encode()
        )
    execution["current_binary_identity"] = execution_identity
    execution["binary_identity_basis"] = "current build-graph digest plus exact check output"
    execution["source_declarations_are_not_execution_proof"] = True

    contract = {
        "all_named_and_anonymous_declarations_listed": len(declaration_records)
        == named_count + anonymous_count,
        "all_declarations_assigned": len(unassigned) == 0,
        "artifact_names_unique": duplicate_artifacts == 0,
        "artifact_modes_explicit": graph["unwired_artifact_count"] == 0,
        "run_artifact_count_matches": execution.get("run_artifact_count_matches", False),
        "check_process_succeeded": execution.get("exit_code") == 0,
        "authentic_ready": (
            len(unassigned) == 0
            and duplicate_artifacts == 0
            and graph["unwired_artifact_count"] == 0
            and execution.get("run_artifact_count_matches", False)
            and execution.get("exit_code") == 0
        ),
    }

    report = {
        "schema_version": 2,
        "source_roots": ["ISA", "lib", "src", "pkg"],
        "source_unit_count": len(source_units),
        "source_declaration_count": len(all_declarations),
        "named_declaration_count": named_count,
        "anonymous_declaration_count": anonymous_count,
        "source_units": source_units,
        "declaration_manifest": declaration_records,
        "unassigned_declarations": unassigned,
        "build_graph": graph,
        "execution": execution,
        "contract": contract,
        "interpretation": (
            "Source declarations, compile-only artifacts, and executed check "
            "artifacts are separate evidence classes. The execution identity "
            "binds this report to the current graph and exact check output; it "
            "does not claim that every imported declaration executed independently."
        ),
    }

    output = args.output if args.output.is_absolute() else root / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(
        "test-census: source_declarations={} named={} anonymous={} files={} "
        "artifacts={} run_required={} compile_only={} unassigned={} "
        "executed_artifacts={} executed_tests={} exit_code={} contract={} output={}".format(
            report["source_declaration_count"],
            named_count,
            anonymous_count,
            report["source_unit_count"],
            graph["artifact_count"],
            graph["run_required_artifact_count"],
            graph["compile_only_artifact_count"],
            len(unassigned),
            execution.get("executed_artifact_count", 0),
            execution.get("executed_test_count", 0),
            execution.get("exit_code", "not-run"),
            contract["authentic_ready"],
            output,
        )
    )
    if args.strict and (
        execution.get("exit_code") != 0 or not contract["authentic_ready"]
    ):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
