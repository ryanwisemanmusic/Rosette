#!/usr/bin/env python3
"""Focused regression checks for the change-aware shell update policy."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import build_identity_manifest as identity
import build_guest_fork_manifest as fork_manifest
import smart_shell_update as updater


REPO_ROOT = Path(__file__).resolve().parents[1]


class ShellUpdatePolicyTests(unittest.TestCase):
    def test_runtime_output_roots_are_not_source_changes(self) -> None:
        status = " M src/gpu.cc\n?? .rosette/\n?? .rosette/captures/frame.gfxr\n"
        self.assertEqual(" M src/gpu.cc", identity.filter_xenia_status(status))
        self.assertEqual("src/gpu.cc", identity.filter_xenia_paths(".rosette/run.log\nsrc/gpu.cc\n"))
        self.assertTrue(fork_manifest.is_generated_runtime_path("./.rosette/xenia-runs/log.txt"))
        self.assertFalse(fork_manifest.is_generated_runtime_path("src/gpu.cc"))

    def test_shell_snapshot_ignores_runtime_outputs_and_decodes_paths(self) -> None:
        status = ' M "lib/Mach-O/file with spaces.zig"\n?? .rosette/\n?? zig-out/\n'
        self.assertEqual(
            ["lib/Mach-O/file with spaces.zig"], updater.parse_status_paths(status)
        )

    def test_only_declared_processor_subtrees_get_fast_scopes(self) -> None:
        self.assertEqual(
            "elf-processor-process-impl",
            updater.target_scope_for_paths(
                ["lib/processor/ELF_processor/process/impl/execution.zig"]
            ),
        )
        self.assertEqual(
            "elf-processor-block-jit",
            updater.target_scope_for_paths(["lib/processor/ELF_processor/block_jit/core.zig"]),
        )
        self.assertEqual(
            "elf-processor-block-jit",
            updater.target_scope_for_paths(["lib/processor/ELF_processor/block_jit.zig"]),
        )
        self.assertEqual(
            "elf-processor-windows-runtime",
            updater.target_scope_for_paths(["src/x64-ASM/windows_runtime.zig"]),
        )
        self.assertEqual(
            "elf-processor-windows-runtime",
            updater.target_scope_for_paths(["src/x64-ASM/windows_runtime/core_imports.zig"]),
        )
        self.assertEqual(
            "elf-processor",
            updater.target_scope_for_paths(["lib/processor/ELF_processor/process/state.zig"]),
        )
        self.assertEqual(
            "macho-processor",
            updater.target_scope_for_paths(["lib/Mach-O/process.zig"]),
        )
        self.assertEqual(
            "dyld-forwarder",
            updater.target_scope_for_paths(["lib/linker/dyld/forwarder/fsi_submission.zig"]),
        )
        self.assertIsNone(updater.target_scope_for_paths(["build.zig"]))
        self.assertIsNone(
            updater.target_scope_for_paths(
                ["lib/processor/ELF_processor/process/impl/execution.zig", "build/Makefile"]
            )
        )
        self.assertIsNone(
            updater.target_scope_for_paths(
                ["src/x64-ASM/windows_runtime/core_imports.zig", "build.zig"]
            )
        )

    def test_relink_requires_exact_artifact_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative in updater.SOURCE_ARTIFACTS:
                artifact = root / relative
                artifact.parent.mkdir(parents=True, exist_ok=True)
                artifact.write_bytes(relative.encode())
            expected = updater.artifact_hashes(root)
            self.assertEqual([], updater.artifact_issues(root, expected))
            changed = root / updater.SOURCE_ARTIFACTS[0]
            changed.write_bytes(b"stale build")
            self.assertEqual(1, len(updater.artifact_issues(root, expected)))
            changed.unlink()
            issues = updater.artifact_issues(root, expected)
            self.assertIn("missing artifact " + updater.SOURCE_ARTIFACTS[0], issues)
            self.assertTrue(updater.artifact_issues(root, None))

    def test_path_fingerprint_tracks_nested_content(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "source"
            directory.mkdir()
            source = directory / "unit.zig"
            source.write_text("const x = 1;\n", encoding="utf-8")
            first = updater.hash_path(directory)
            source.write_text("const x = 2;\n", encoding="utf-8")
            self.assertNotEqual(first, updater.hash_path(directory))

    def test_xenia_manifests_ignore_runtime_output_content(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "src").mkdir()
            (root / "src" / "gpu.cc").write_text("source\n", encoding="utf-8")
            subprocess.run(["git", "-C", str(root), "add", "src/gpu.cc"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(root),
                    "-c",
                    "user.name=Test",
                    "-c",
                    "user.email=test@example.invalid",
                    "commit",
                    "-qm",
                    "fixture",
                ],
                check=True,
            )
            runtime = root / ".rosette" / "captures"
            runtime.mkdir(parents=True)
            capture = runtime / "frame.gfxr"
            capture.write_bytes(b"first capture")

            source_hash_before = identity.hash_git_tree(root, "xenia-source")
            manifest_before = fork_manifest.build_manifest(root, None)
            capture.write_bytes(b"different run output")
            source_hash_after = identity.hash_git_tree(root, "xenia-source")
            manifest_after = fork_manifest.build_manifest(root, None)

            self.assertEqual(source_hash_before, source_hash_after)
            self.assertEqual(
                manifest_before["identity_hash"], manifest_after["identity_hash"]
            )
            self.assertEqual([], manifest_after["entries"])
            self.assertEqual([".rosette"], manifest_after["excluded_generated_roots"])

            (root / "src" / "gpu.cc").write_text("changed source\n", encoding="utf-8")
            self.assertNotEqual(
                source_hash_after, identity.hash_git_tree(root, "xenia-source")
            )

    def test_shell_update_records_an_absent_xenia_checkout_explicitly(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tools = root / "tools"
            tools.mkdir()
            # external_fingerprint calls this script through run_checked; the
            # fake runner below records exactly the unavailable manifest that
            # the real CLI is contract-tested to emit.
            script = tools / "build_guest_fork_manifest.py"
            script.write_text("# test stub\n", encoding="utf-8")
            missing_xenia = root / "external-drive" / "xenia"

            def write_explicitly_unavailable(command: list[str], cwd: Path) -> None:
                self.assertIn("--allow-missing-root", command)
                manifest = Path(command[command.index("--output") + 1])
                manifest.parent.mkdir(parents=True, exist_ok=True)
                manifest.write_text(json.dumps({
                    "status": "unavailable",
                    "root_present": False,
                    "identity_hash": fork_manifest.ZERO_HASH,
                }), encoding="utf-8")

            with patch.object(updater, "run_checked", side_effect=write_explicitly_unavailable):
                external = updater.external_fingerprint(root, missing_xenia)

            self.assertEqual("false", external["xenia_root_present"])
            self.assertEqual("unavailable", external["xenia_status"])
            self.assertEqual(fork_manifest.ZERO_HASH, external["xenia_identity"])

    def test_missing_xenia_manifest_cli_is_opt_in_and_existing_bad_root_stays_strict(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            missing = directory / "not-mounted" / "xenia"
            output = directory / "manifest.json"
            script = REPO_ROOT / "tools/build_guest_fork_manifest.py"
            base_command = [
                sys.executable, str(script), "--root", str(missing),
                "--output", str(output),
            ]
            strict = subprocess.run(base_command, capture_output=True, text=True)
            self.assertEqual(1, strict.returncode)
            self.assertEqual("unavailable", json.loads(output.read_text())["status"])

            allowed = subprocess.run(
                [*base_command, "--allow-missing-root"], capture_output=True, text=True
            )
            self.assertEqual(0, allowed.returncode, allowed.stderr)

            existing_bad_root = directory / "empty-xenia"
            existing_bad_root.mkdir()
            strict_existing = subprocess.run(
                [
                    sys.executable, str(script), "--root", str(existing_bad_root),
                    "--output", str(output), "--allow-missing-root",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(1, strict_existing.returncode)
            self.assertTrue(json.loads(output.read_text())["root_present"])

    def test_shell_identity_may_be_incomplete_only_for_absent_xenia_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            root = directory / "rosette"
            root.mkdir()
            missing_xenia = directory / "unmounted" / "xenia"
            output = directory / "identity.json"
            script = REPO_ROOT / "tools/build_identity_manifest.py"
            base_command = [
                sys.executable, str(script), "--root", str(root),
                "--xenia-root", str(missing_xenia), "--output", str(output),
            ]
            strict = subprocess.run(base_command, capture_output=True, text=True)
            self.assertEqual(1, strict.returncode)
            self.assertFalse(output.exists())

            allowed = subprocess.run(
                [*base_command, "--allow-unavailable-xenia"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(0, allowed.returncode, allowed.stderr)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertFalse(report["admission"]["complete"])
            self.assertFalse(report["xenia"]["root_present"])

            present_bad_root = directory / "present-but-invalid-xenia"
            present_bad_root.mkdir()
            rejected_output = directory / "rejected-identity.json"
            existing = subprocess.run(
                [
                    sys.executable, str(script), "--root", str(root),
                    "--xenia-root", str(present_bad_root), "--output", str(rejected_output),
                    "--allow-unavailable-xenia",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(1, existing.returncode)
            self.assertFalse(rejected_output.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
