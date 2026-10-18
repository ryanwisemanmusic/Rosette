import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import audit_source_size as size
from build_graph_sources import graph_source
import smart_shell_update as updater


class BuildOrganizationTests(unittest.TestCase):
    def test_notes_cannot_expand_an_existing_frozen_source_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "process.zig"
            source.write_text("const x = 1;\n// historical note\n")
            policy = {"default_max_lines": 3000, "limits": {"process.zig": 2}}
            self.assertEqual([], size.violations(root, ["process.zig"], policy))
            source.write_text(source.read_text() + "// another session note\n")
            self.assertEqual(1, len(size.violations(root, ["process.zig"], policy)))

    def test_new_files_have_a_limit_without_a_special_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "new.zig").write_text("// note\n" * 3001)
            self.assertEqual(1, len(size.violations(root, ["new.zig"], {"default_max_lines": 3000, "limits": {}})))

    def test_owner_module_registration_is_read_in_call_order_and_missing_owner_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            owner = root / "lib" / "processor" / "build.zig"
            owner.parent.mkdir(parents=True)
            master = root / "build.zig"
            master.write_text('@import("lib/processor/build.zig").register0(b, .{});\n')
            owner.write_text('pub fn register0(b: *std.Build, ctx: anytype) void {\n    const first = b.step("unit", "test");\n}\n')
            text, inputs = graph_source(master)
            self.assertIn('b.step("unit"', text)
            self.assertEqual({master.resolve(), owner.resolve()}, set(inputs))
            owner.write_text('pub fn register1(b: *std.Build, ctx: anytype) void {\n}\n')
            with self.assertRaises(ValueError):
                graph_source(master)

    def test_build_registration_cannot_escape_its_root(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "build.zig"
            path.write_text('@import("folders/../../outside.zig").register0(b, .{});\n')
            with self.assertRaises(ValueError):
                graph_source(path)

    def test_committing_tested_content_does_not_change_snapshot_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                subprocess.run(["git", *args], cwd=root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            git("init")
            git("config", "user.name", "Fixture")
            git("config", "user.email", "fixture@example.invalid")
            source = root / "lib/processor/ELF_processor/unit.zig"
            source.parent.mkdir(parents=True)
            source.write_text("const x = 1;\n")
            git("add", ".")
            git("commit", "-m", "base")
            initial = updater.current_source_snapshot(root)
            source.write_text("const x = 2;\n")
            dirty = updater.current_source_snapshot(root)
            self.assertNotEqual(initial["sha256"], dirty["sha256"])
            git("add", ".")
            staged = updater.current_source_snapshot(root)
            self.assertEqual(dirty["sha256"], staged["sha256"])
            git("commit", "-m", "tested bytes")
            committed = updater.current_source_snapshot(root)
            self.assertNotEqual(initial["head"], committed["head"])
            self.assertEqual(dirty["sha256"], committed["sha256"])
            self.assertEqual("elf-processor", updater.target_scope_for_paths([str(source.relative_to(root))]))
            (root / "AGENTS.md").write_text("session history\n")
            self.assertEqual(committed["sha256"], updater.current_source_snapshot(root)["sha256"])
            source.chmod(0o755)
            self.assertNotEqual(committed["sha256"], updater.current_source_snapshot(root)["sha256"])
            source.unlink()
            self.assertNotIn(str(source.relative_to(root)), updater.current_source_snapshot(root)["files"])

    def test_focused_elf_update_rebuilds_embedded_runner_and_dylib(self):
        commands = []
        with patch.object(updater, "run_checked", side_effect=lambda command, *args: commands.append(command)), \
             patch.object(updater, "install_shell"), patch.object(updater, "record_update"), \
             patch.object(updater, "refresh_identity"), patch.object(updater, "write_state"):
            updater.focused_update(Path.cwd(), Path("/read-only-xenia"), "elf-processor-block-jit")
        make = next(command for command in commands if Path(command[0]).name == "make")
        self.assertIn("exe-runner-build", make)
        self.assertIn("elf-processor-dylib", make)
        self.assertTrue(all(not arg.startswith("-") and "=" not in arg for arg in make[1:]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
