#!/usr/bin/env python3
"""Regression checks for test-census build graph classification."""

from __future__ import annotations

import unittest
from pathlib import Path

import test_census as census


class CensusBuildGraphTests(unittest.TestCase):
    def test_nonstandard_check_variable_records_run_artifacts(self) -> None:
        text = '''
const inline_test = b.addTest(.{ .root_module = inline_mod });
const alias_test = b.addTest(.{ .root_module = alias_mod });
const compile_test = b.addTest(.{ .root_module = compile_mod });
const focused_test = b.addTest(.{ .root_module = focused_mod });
const alias_run = b.addRunArtifact(alias_test);
check_step.dependOn(&b.addRunArtifact(inline_test).step);
check_step.dependOn(&alias_run.step);
check_step.dependOn(&compile_test.step);
block_jit_check.dependOn(&b.addRunArtifact(focused_test).step);
'''
        modules = {
            "inline_mod": "lib/inline.zig",
            "alias_mod": "lib/alias.zig",
            "compile_mod": "lib/compile.zig",
            "focused_mod": "lib/focused.zig",
        }

        artifacts = census.parse_artifacts(Path("."), text, modules)
        modes = {item["name"]: item["expected_modes"] for item in artifacts}

        self.assertEqual(["run"], modes["inline_test"])
        self.assertEqual(["run"], modes["alias_test"])
        self.assertEqual(["compile-only"], modes["compile_test"])
        self.assertEqual(["focused-only"], modes["focused_test"])

    def test_path_array_loop_records_nested_run_tests(self) -> None:
        text = '''
const check_step = b.step("check", "Run the full check suite");
for ([_][]const u8{ "../lib/first.zig", "../lib/second.zig" }, 0..) |path, index| {
    const module = b.createModule(.{ .root_source_file = b.path(path) });
    const run = b.addRunArtifact(b.addTest(.{ .root_module = module }));
    const focused = b.step("focused", "Run a focused test");
    focused.dependOn(&run.step);
    check_step.dependOn(&run.step);
}
'''

        artifacts = [
            item
            for item in census.parse_artifacts(Path("."), text, {"module": None})
            if item["artifact_kind"] == "test"
        ]

        self.assertEqual(2, len(artifacts))
        self.assertEqual(
            ["lib/first.zig", "lib/second.zig"],
            [item["root_source"] for item in artifacts],
        )
        self.assertEqual(
            [["run", "focused-only"], ["run", "focused-only"]],
            [item["expected_modes"] for item in artifacts],
        )

    def test_current_build_graph_has_no_unwired_test_artifacts(self) -> None:
        root = Path(__file__).resolve().parents[1]
        graph = census.build_graph(root)
        unwired = [
            item["name"]
            for item in graph["artifacts"]
            if item.get("expected_modes") == ["unwired"]
        ]

        self.assertEqual([], unwired)
        focused = next(
            item["expected_modes"]
            for item in graph["artifacts"]
            if item["name"] == "block_jit_test"
        )
        self.assertEqual(["focused-only"], focused)


if __name__ == "__main__":
    unittest.main(verbosity=2)
