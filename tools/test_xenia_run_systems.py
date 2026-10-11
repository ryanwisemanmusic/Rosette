#!/usr/bin/env python3
"""Tests for Rosetta's Xenia run supervisor and evidence manager."""

from __future__ import annotations

import contextlib
import copy
import importlib.util
import io
import json
import os
import pathlib
import shlex
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "xenia" / "scripts" / "rosette_xenia_systems.py"
SPEC = importlib.util.spec_from_file_location("rosette_xenia_systems", MODULE_PATH)
assert SPEC and SPEC.loader
systems = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(systems)
CAPTURE_INVENTORY_PATH = ROOT / "tools" / "vulkan" / "gfxr_inventory.py"
CAPTURE_INVENTORY_SPEC = importlib.util.spec_from_file_location("gfxr_inventory", CAPTURE_INVENTORY_PATH)
assert CAPTURE_INVENTORY_SPEC and CAPTURE_INVENTORY_SPEC.loader
gfxr_inventory = importlib.util.module_from_spec(CAPTURE_INVENTORY_SPEC)
CAPTURE_INVENTORY_SPEC.loader.exec_module(gfxr_inventory)
FETCH_CORPUS_PATH = ROOT / "tools" / "xenia" / "scripts" / "verify_fetch_descriptor_corpus.py"
FETCH_CORPUS_SPEC = importlib.util.spec_from_file_location("verify_fetch_descriptor_corpus", FETCH_CORPUS_PATH)
assert FETCH_CORPUS_SPEC and FETCH_CORPUS_SPEC.loader
fetch_corpus = importlib.util.module_from_spec(FETCH_CORPUS_SPEC)
FETCH_CORPUS_SPEC.loader.exec_module(fetch_corpus)


class RunSystemsTests(unittest.TestCase):
    def test_fetch_descriptor_corpus_source_uses_decoded_vertex_contract(self) -> None:
        generated = fetch_corpus._zig_source([{
            "raw": "05232583 1000001A 00000000 00000000 00000000 00000000",
            "decode": {
                "parse_status": "ok",
                "type_name": "vertex",
                "vertex_fetch": {"address_bytes": 0x05232580, "size_words": 6, "endian_code": 2},
            },
        }])
        self.assertIn("vertex.VertexFetch.decode(case.raw)", generated)
        self.assertIn("0x05232583, 0x1000001a", generated)
        self.assertIn("expectEqual(case.address_bytes, decoded.addressBytes())", generated)

    def test_gfxr_inventory_parses_trimmed_frames_and_capture_completion(self) -> None:
        info = gfxr_inventory.parse_info("""File info:
\tTotal frames: 1 (trimmed frame range 1036-1036)
Vulkan application info:
\tTarget API version: 4202496 (1.2.0)
\tUsed resolutions: 1280x720
Vulkan physical device info:
\tDevice name: Apple M2 Max
\tAPI version: 4202771 (1.2.275)
Vulkan device memory allocation info:
\tTotal allocations: 139
Vulkan pipeline info:
\tTotal graphics pipelines: 438
\tTotal compute pipelines: 33
Annotations:
\tGFXR version: 1.0.5 (df6c07a) RelWithDebInfo
\tCapture timestamp: 2026-10-10T00:30:54Z
""")
        self.assertEqual((1036, 1036), (info["frame_start"], info["frame_end"]))
        self.assertEqual("Apple M2 Max", info["device_name"])
        self.assertEqual((438, 33), (info["graphics_pipelines"], info["compute_pipelines"]))
        captures = gfxr_inventory.parse_capture_log("""[gfxrecon] INFO - Recording graphics API capture to /tmp/one.gfxr
[gfxrecon] INFO - WriteResourceMemoryState() saved in 5129 ms
[gfxrecon] INFO - WriteState() saved in 6026 ms
[gfxrecon] INFO - Finished recording graphics API capture
[gfxrecon] INFO - Recording graphics API capture to /tmp/two.gfxr
""")
        self.assertTrue(captures["one.gfxr"]["finished"])
        self.assertEqual(5129, captures["one.gfxr"]["resource_memory_state_ms"])
        self.assertFalse(captures["two.gfxr"]["finished"])

    def test_fetch_warning_audit_distinguishes_vertex_descriptors_from_textures(self) -> None:
        text = "\n".join([
            "# run_id = audit-test-1",
            "macho-processor: Vulkan FSI SHADER: module_id=17 guest=0xfffff5000002fcb1 native=0x1 spirv_hash=0x22134b6e5a740a65 bytes=399444 execution_models=0x10",
            "w> 0100000C Texture fetch constant (05232583 1000001A 00000000 00000000 00000000 00000000) is completely invalid!",
            "error(elf): PE64 FATAL POINT: guest-warning label=vertex-fetch-descriptor-in-texture-path occurrence=1 step=42 rip=0x140001234 line=w> 0100000C Texture fetch constant (05232583 1000001A 00000000 00000000 00000000 00000000) is completely invalid! classification=type=vertex emitted_by='GPU Commands (0100000C)'",
            "w> 0100000C Texture fetch constant (05232583 1000001A 00000000 00000000 00000000 00000000) is completely invalid!",
            "macho-processor: Vulkan FSI PIPELINE: ordinal=29 result=0 real=0x1 module_id=17 shader_hash=0x22134b6e5a740a65 pipeline_hash=0xabc stages=2 topology=4 samples=1",
            "w> 0100000C Texture fetch constant (00000002 00000000 00000000 00000000 00000000 00000000) is completely invalid!",
        ])

        audit = systems.fetch_constant_diagnostics.audit_log_text(text, "synthetic.log", "a" * 64)

        self.assertEqual("audit-test-1", audit["source"]["run_id"])
        self.assertEqual(3, audit["counts"]["warning_occurrences"])
        self.assertEqual(2, audit["counts"]["unique_descriptors"])
        self.assertEqual({"texture": 1, "vertex": 2}, audit["counts"]["warning_type_counts"])
        self.assertEqual({"texture": 1, "vertex": 1}, audit["counts"]["unique_type_counts"])
        vertex = next(row for row in audit["descriptors"] if row["decode"]["type_name"] == "vertex")
        self.assertEqual(2, len(vertex["occurrences"]))
        self.assertEqual(0x05232580, vertex["decode"]["vertex_fetch"]["address_bytes"])
        self.assertEqual(24, vertex["decode"]["vertex_fetch"]["size_bytes"])
        self.assertEqual(42, vertex["occurrences"][0]["fatal_point"]["step"])
        nearby = vertex["occurrences"][0]["nearby_vulkan_context"]["events"]
        self.assertEqual(["shader_module", "pipeline"], [item["kind"] for item in nearby])
        self.assertIn("not a proven", vertex["occurrences"][0]["nearby_vulkan_context"]["relationship"])
        self.assertEqual("requires_matching_texture_payload_format_and_native_case", audit["interpretation"]["texture_support_status"])

    def test_fetch_warning_audit_marks_all_vertex_records_as_texture_n_a(self) -> None:
        text = "\n".join([
            "w> Texture fetch constant (050F0003 1000001A 00000000 00000000 00000000 00000000) is completely invalid!",
            "w> Texture fetch constant (050F001B 1000001A 00000000 00000000 00000000 00000000) is completely invalid!",
        ])
        audit = systems.fetch_constant_diagnostics.audit_log_text(text)
        self.assertEqual(2, audit["counts"]["unique_descriptors"])
        self.assertEqual(0, audit["counts"]["texture_typed_unique_descriptors"])
        self.assertEqual(2, audit["counts"]["vertex_typed_unique_descriptors"])
        self.assertEqual("not_evaluated_no_texture_typed_warning_descriptors", audit["interpretation"]["texture_support_status"])

    def test_gfxr_inventory_includes_nonempty_trigger_trims_and_ignores_empty_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            run_dir = pathlib.Path(temporary)
            (run_dir / "rosette-vulkan.gfxr").write_bytes(b"")
            (run_dir / "rosette-vulkan_trim_trigger_20261009T172912.gfxr").write_bytes(b"capture-one")
            (run_dir / "rosette-vulkan_trim_trigger_20261009T172928.gfxr").write_bytes(b"capture-two")
            (run_dir / "unrelated.gfxr").write_bytes(b"ignored")

            artifacts = systems.gfxr_artifacts(run_dir)

            self.assertEqual(3, len(artifacts))
            usable = [item for item in artifacts if item["usable"]]
            self.assertEqual(2, len(usable))
            self.assertEqual(["trimmed", "trimmed"], [item["kind"] for item in usable])
            self.assertEqual([11, 11], [item["bytes"] for item in usable])

    @unittest.skipIf(systems.tomllib is None, "Python tomllib/tomli is required for safe TOML preflight")
    def test_preflight_leaves_valid_xenia_toml_untouched(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            bundle = pathlib.Path(temporary) / "bundle"
            bundle.mkdir()
            config = bundle / "xenia-canary.config.toml"
            original = b"[GPU]\nrender_target_path = \"vulkan\"\n"
            config.write_bytes(original)

            result = systems.preflight_xenia_config(bundle)

            self.assertEqual("valid", result["action"])
            self.assertEqual(original, config.read_bytes())
            self.assertFalse((bundle / "xenia-canary.config.toml.rosette-invalid").exists())

    @unittest.skipIf(systems.tomllib is None, "Python tomllib/tomli is required to read Xenia GPU settings")
    def test_bundle_gpu_render_settings_reports_effective_fsi_and_readback_values(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            bundle = pathlib.Path(temporary) / "bundle"
            bundle.mkdir()
            (bundle / "xenia-canary.config.toml").write_text(
                "[GPU]\nrender_target_path_vulkan = 'fbo'\nreadback_resolve = 'none'\n",
                encoding="utf-8",
            )
            # An absent occlusion_query is None, never a guessed default: the
            # launcher log says "unset-xenia-default-fast" instead.
            self.assertEqual(
                {"render_target_path_vulkan": "fbo", "readback_resolve": "none", "occlusion_query": None},
                systems.bundle_gpu_render_settings(bundle),
            )
            (bundle / "xenia-canary.config.toml").write_text(
                "[GPU]\nrender_target_path_vulkan = 'fsi'\nreadback_resolve = 'fast'\nocclusion_query = 'strict'\n",
                encoding="utf-8",
            )
            self.assertEqual(
                {"render_target_path_vulkan": "fsi", "readback_resolve": "fast", "occlusion_query": "strict"},
                systems.bundle_gpu_render_settings(bundle),
            )
            (bundle / "xenia-canary.config.toml").write_text("[GPU]\nocclusion_query = 3\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                systems.bundle_gpu_render_settings(bundle)

    @unittest.skipIf(systems.tomllib is None, "Python tomllib/tomli is required for safe TOML preflight")
    def test_preflight_preserves_and_repairs_malformed_config_in_one_bounded_sidecar(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            bundle = pathlib.Path(temporary) / "bundle"
            bundle.mkdir()
            config = bundle / "xenia-canary.config.toml"
            backup = bundle / "xenia-canary.config.toml.rosette-invalid"
            malformed = b"[\x00\x00\x00]\nvideo = \x90\n"
            config.write_bytes(malformed)

            repaired = systems.preflight_xenia_config(bundle)

            self.assertEqual("repaired", repaired["action"])
            self.assertEqual(malformed, backup.read_bytes())
            self.assertEqual(repaired["sha256"], repaired["backup_sha256"])
            self.assertEqual(1, len(list(bundle.glob("*.rosette-invalid"))))
            systems.tomllib.loads(config.read_text(encoding="utf-8"))

            malformed_again = b"[broken\nvalue = true\n"
            config.write_bytes(malformed_again)
            repaired_again = systems.preflight_xenia_config(bundle)
            self.assertEqual("repaired", repaired_again["action"])
            self.assertEqual(malformed_again, backup.read_bytes())
            self.assertEqual(1, len(list(bundle.glob("*.rosette-invalid"))))

    def test_prepare_cli_accepts_launch_arguments_that_start_with_dashes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            repo = root / "rosette"
            source = root / "xenia"
            bundle = repo / "bundle"
            run_root = repo / ".rosette" / "xenia-runs"
            for directory in (repo, source, bundle):
                directory.mkdir(parents=True, exist_ok=True)
            (source / "CMakeLists.txt").write_text("# reference only\n", encoding="utf-8")
            executable = bundle / "xenia_canary.exe"
            runner = repo / "rosette_exe_runner"
            executable.write_bytes(b"pe-image")
            runner.write_bytes(b"runner")

            result = subprocess.run(
                [
                    sys.executable,
                    str(MODULE_PATH),
                    "prepare",
                    "--run-root", str(run_root),
                    "--repo-root", str(repo),
                    "--source-root", str(source),
                    "--bundle", str(bundle),
                    "--executable", str(executable),
                    "--runner", str(runner),
                    "--supervisor-pid", str(os.getpid()),
                    "--launch-arg=--arg",
                    "--launch-arg=--log_level=1",
                    "--launch-arg=argument with spaces",
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(0, result.returncode, result.stderr)
            emitted = dict(line.split("=", 1) for line in result.stdout.splitlines())
            manifest_path = pathlib.Path(shlex.split(emitted["run_manifest"])[0])
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual(
                ["--arg", "--log_level=1", "argument with spaces"],
                manifest["inputs"]["launch_arguments"],
            )

    def test_prepare_records_unique_run_identity_without_hashing_media(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            repo = root / "rosette"
            source = root / "xenia"
            bundle = repo / "bundle"
            run_root = repo / ".rosette" / "xenia-runs"
            for directory in (repo, source, bundle):
                directory.mkdir(parents=True, exist_ok=True)
            (source / "CMakeLists.txt").write_text("# reference only\n", encoding="utf-8")
            (bundle / "xenia-canary.config.toml").write_text("gpu = 'vulkan'\n", encoding="utf-8")
            (bundle / "xconfig.settings").write_text("present_interval=1\n", encoding="utf-8")
            (bundle / "recent.toml").write_text("title='halo3'\n", encoding="utf-8")
            (bundle / "rosette-xenia-windows.json").write_text("{}\n", encoding="utf-8")
            (bundle / "gamecontrollerdb.txt").write_text("03000000,test\n", encoding="utf-8")
            executable = bundle / "xenia_canary.exe"
            runner = repo / "rosette_exe_runner"
            media = root / "halo3.iso"
            executable.write_bytes(b"pe-image")
            runner.write_bytes(b"runner")
            media.write_bytes(b"large media identity is stat-only")

            args = type("Args", (), {
                "run_root": str(run_root),
                "source_root": str(source),
                "repo_root": str(repo),
                "bundle": str(bundle),
                "executable": str(executable),
                "runner": str(runner),
                "media": str(media),
                "run_log": "",
                "trace_log": "",
                "scenario": "Halo 3 / Last Resort / Custom Games",
                "supervisor_pid": 1,
                "launch_arg": ["--log_level=1"],
            })()
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(0, systems.prepare(args))
            emitted = dict(line.split("=", 1) for line in stdout.getvalue().splitlines())
            manifest_path = pathlib.Path(emitted["run_manifest"].strip("'\""))
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual("running", manifest["status"])
            self.assertEqual("Halo 3 / Last Resort / Custom Games", manifest["scenario"])
            self.assertEqual(["--log_level=1"], manifest["inputs"]["launch_arguments"])
            self.assertIsNone(manifest["inputs"]["media"]["sha256"])
            self.assertEqual(media.stat().st_size, manifest["inputs"]["media"]["size_bytes"])
            self.assertTrue(pathlib.Path(manifest["paths"]["run_log"]).parent.is_dir())

    def test_prepare_reuses_one_stable_run_slot_and_prunes_prior_managed_run_folders(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            repo = root / "rosette"
            source = root / "xenia"
            bundle = repo / "bundle"
            run_root = source / ".rosette" / "xenia-runs"
            for directory in (repo, source, bundle, run_root):
                directory.mkdir(parents=True, exist_ok=True)
            (source / "CMakeLists.txt").write_text("# reference only\n", encoding="utf-8")
            (bundle / "xenia-canary.config.toml").write_text("gpu = 'vulkan'\n", encoding="utf-8")
            executable = bundle / "xenia_canary.exe"
            runner = repo / "rosette_exe_runner"
            executable.write_bytes(b"pe-image")
            runner.write_bytes(b"runner")

            old_run = run_root / "20260924T134727Z-aed022cbf32a"
            old_run.mkdir()
            (old_run / "manifest.json").write_text(json.dumps({"status": "complete"}), encoding="utf-8")
            (old_run / "rosette-xenia.log").write_text("old run\n", encoding="utf-8")

            args = type("Args", (), {
                "run_root": str(run_root),
                "run_slot": "current",
                "source_root": str(source),
                "repo_root": str(repo),
                "bundle": str(bundle),
                "executable": str(executable),
                "runner": str(runner),
                "media": "",
                "run_log": "",
                "trace_log": "",
                "scenario": "stable-slot",
                "supervisor_pid": os.getpid(),
                "launch_arg": [],
            })()

            def run_prepare() -> dict[str, str]:
                stdout = io.StringIO()
                with contextlib.redirect_stdout(stdout):
                    self.assertEqual(0, systems.prepare(args))
                return dict(line.split("=", 1) for line in stdout.getvalue().splitlines())

            first = run_prepare()
            first_manifest_path = pathlib.Path(shlex.split(first["run_manifest"])[0])
            first_manifest = json.loads(first_manifest_path.read_text(encoding="utf-8"))
            self.assertEqual("current", first_manifest_path.parent.name)
            self.assertFalse(old_run.exists())
            first_id = first_manifest["run_id"]

            first_manifest["status"] = "complete"
            first_manifest_path.write_text(json.dumps(first_manifest), encoding="utf-8")
            (first_manifest_path.parent / "evidence.json").write_text("old evidence", encoding="utf-8")
            second = run_prepare()
            second_manifest_path = pathlib.Path(shlex.split(second["run_manifest"])[0])
            second_manifest = json.loads(second_manifest_path.read_text(encoding="utf-8"))
            self.assertNotEqual(first_id, second_manifest["run_id"])
            self.assertEqual(first_manifest_path.parent, second_manifest_path.parent)
            self.assertFalse((second_manifest_path.parent / "evidence.json").exists())
            self.assertEqual(["current"], sorted(path.name for path in run_root.iterdir() if path.is_dir()))

    def test_prepare_refuses_outputs_inside_xenia_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            source = root / "xenia"
            repo = root / "rosette"
            bundle = repo / "bundle"
            for directory in (source, repo, bundle):
                directory.mkdir(parents=True, exist_ok=True)
            (source / "CMakeLists.txt").touch()
            (bundle / "xenia_canary.exe").touch()
            (repo / "runner").touch()
            args = type("Args", (), {
                "run_root": str(source / "runs"),
                "source_root": str(source),
                "repo_root": str(repo),
                "bundle": str(bundle),
                "executable": str(bundle / "xenia_canary.exe"),
                "runner": str(repo / "runner"),
                "media": "",
                "run_log": "",
                "trace_log": "",
                "scenario": "test",
                "supervisor_pid": 1,
                "launch_arg": [],
            })()
            with self.assertRaisesRegex(ValueError, "under its .rosette data directory"):
                systems.prepare(args)

    def test_prepare_allows_run_records_in_xenia_rosette_data_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            source = root / "xenia"
            repo = root / "rosette"
            bundle = repo / "bundle"
            run_root = source / ".rosette" / "xenia-runs"
            for directory in (source, repo, bundle):
                directory.mkdir(parents=True, exist_ok=True)
            (source / "CMakeLists.txt").touch()
            (bundle / "xenia_canary.exe").touch()
            (repo / "runner").touch()
            args = type("Args", (), {
                "run_root": str(run_root),
                "source_root": str(source),
                "repo_root": str(repo),
                "bundle": str(bundle),
                "executable": str(bundle / "xenia_canary.exe"),
                "runner": str(repo / "runner"),
                "media": "",
                "run_log": "",
                "trace_log": "",
                "scenario": "test",
                "supervisor_pid": 1,
                "launch_arg": [],
            })()
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(0, systems.prepare(args))
            emitted = dict(line.split("=", 1) for line in stdout.getvalue().splitlines())
            manifest_path = pathlib.Path(emitted["run_manifest"].strip("'\""))
            run_log_path = pathlib.Path(emitted["run_log"].strip("'\""))
            self.assertTrue(systems.is_within(manifest_path, source / ".rosette"))
            self.assertTrue(systems.is_within(run_log_path, source / ".rosette"))

    def test_prepare_still_refuses_custom_logs_elsewhere_inside_xenia(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            source = root / "xenia"
            repo = root / "rosette"
            bundle = repo / "bundle"
            for directory in (source, repo, bundle):
                directory.mkdir(parents=True, exist_ok=True)
            (source / "CMakeLists.txt").touch()
            (bundle / "xenia_canary.exe").touch()
            (repo / "runner").touch()
            args = type("Args", (), {
                "run_root": str(source / ".rosette" / "xenia-runs"),
                "source_root": str(source),
                "repo_root": str(repo),
                "bundle": str(bundle),
                "executable": str(bundle / "xenia_canary.exe"),
                "runner": str(repo / "runner"),
                "media": "",
                "run_log": str(source / "build" / "run.log"),
                "trace_log": "",
                "scenario": "test",
                "supervisor_pid": 1,
                "launch_arg": [],
            })()
            with self.assertRaisesRegex(ValueError, "under its .rosette data directory"):
                systems.prepare(args)

    def test_parser_keeps_latest_readiness_and_tracks_texture_and_fallback_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            log = pathlib.Path(temporary) / "run.log"
            log.write_text(
                "\n".join([
                    "PE64 RUN CONTEXT: run_id=run-123 build_identity_sha256=abc",
                    "PE64 FIRST FRAME CHAIN: 0/2 observable preconditions met (0 unobservable)",
                    "PE64 FIRST FRAME CHAIN:   vulkan_instance owner=rosette unmet (downstream)",
                    "PE64 FIRST FRAME CHAIN:   guest_surface owner=xenia unmet (downstream)",
                    "PE64 GUEST OUTPUT CHAIN: 0/1 observable stages met (0 not observable in this image)",
                    "PE64 GUEST OUTPUT CHAIN:   title_output owner=title unmet (downstream)",
                    "w> Texture fetch constant (05232583 1000001A 00000000 00000000 00000000 00000000) is completely invalid!",
                    "w> Texture fetch constant (05232583 1000001A 00000000 00000000 00000000 00000000) is completely invalid!",
                    "w> Texture fetch constant (052941A3 1000001A 00000000 00000000 00000000 00000000) is completely invalid!",
                    "FRAME GENERATION RATE: picture_frame=42 picture_fps=2.5 first_observed_picture_raw_present=2 initial_to_picture_ms=23151",
                    "PE64 FRAME COST: swaps=42 instructions_per_swap(mean_last_32/min/max/lifetime_mean)=10/2/20/11 interpreter_rate=100 instructions/s -> 9.09 swaps/s possible; 30 swaps/s needs 330 instructions/s (3.3x this run)",
                    "PE64 STEP BUDGET: interpreted=1000 elapsed=10s rate(window/run)=90/100 instructions/s",
                    "PE64 XENIA TIME PLANE: status=advancing window(host_ms/xbox_ms)=100/99 xbox_speed=0.99",
                    "PE64 BLOCK JIT LANE: fallback_calls=12 tlb(considers/fills/refused/invalidations/flushes)=1/1/0/0/0",
                    "PE64 BLOCK JIT FALLBACK OPS: mov=10(83%,estimated_ns=500,samples=2)",
                    "PE64 BLOCK JIT FALLBACK LEDGER: calls=12 reasons(missing_native_template/native_slow_path/hook_observation/vector_policy_disabled)=4/3/3/2 samples=2 sampled_host_ns=100 estimated_interpreter_ns=500 per_op_sample_period=1024",
                    "PE64 BLOCK JIT WORKER FALLBACK LEDGER: calls=40 reasons(missing_native_template/native_slow_path/hook_observation/vector_policy_disabled)=30/5/4/1 samples=4 sampled_host_ns=200 estimated_interpreter_ns=900 per_op_sample_period=1024",
                    "PE64 BLOCK JIT WORKER TLB: direct_route=true fills=77 refused=3 cross_thread_invalidations=5 raced_fills_retired=0; with the direct route",
                    "PE64 WINDOWS FAST IMPORTS: crt memcpy=500 memmove=20 memset=300 shared_runtime_lock_bypassed=true; each ran through copyGuestRange/fillGuestMemory",
                    "PE64 WINDOWS FAST IMPORTS: GetSystemTimePreciseAsFileTime calls=1234 QueryPerformanceCounter=9000 QueryPerformanceFrequency=3 new_since_report=4 shared_runtime_lock_bypassed=true",
                    "PE64 BLOCK JIT WORKER THREAD: slot=23 name='MAIN_THREAD (F8000014)' table=262144 growths=1 live=60000 compiled=90000 evictions=4000 hotness_replacements=9000 resets=0 code_mib(used/reserved)=140/1024 executions=5000000 retired=90000000 interpreted(cold/refused/reset_pending)=3000000/1000/0 fallback_calls=10 revalidations=0 dropped_stale=0 dispatch(entries/relinks/native_hops)=40000/9000/4000000 retired_per_dispatch=2250 chain_exits(budget/break/miss)=30000/2000/7000 tlb_fills=123; an interpreted step",
                    "PE64 BLOCK JIT WORKER THREAD:   slot=23 interpreted rank=1 region=0xa0a67d00 at=generated-code:x samples=10..12 of 50 (one per 64 cold steps)",
                    "PE64 HOST PROFILE THREAD slot=4 'Main XThread (F8000008)': samples=500 over 1000ms (interval 1000us, failures=0, dropped=0, distinct_pcs=9); this worker's wall time: translated_title=40.0% translated_xenia=20.5% translated_unattributed=0.0% rosette=9.5% vulkan_driver=0.0% metal=0.0% system_and_waits=30.0% other=0.0% unknown=0.0%; sampled from a second thread",
                    "PE64 HOST PROFILE THREAD slot=4 'Main XThread (F8000008)' HOST: rank=1 share=9.5% samples=47 at=rosette!blockJitRead",
                    "RECT EXPAND: rewritten=2 transform_refused=0 non_vertex_skipped=0 draws_tagged=20 declined_foreign_index=0 overflow(modules/pipelines)=0/0 driver_rejections=0",
                    "GRAPHICS ROUTE: descriptors(updates/native_writes/binds_forwarded/binds_rejected)=4/5/6/0 presented_sources(sampled/transfer/upload/unresolved)=42/0/0/0",
                    "macho-processor: VULKAN DRIVER: name=llvmpipe info=Mesa 24.0.0 (LLVM 17.0.6) id=13(MESA_LLVMPIPE) api=1.3.274 conformance=1.3.1.1 VULKAN_SDK=<unset> VK_ICD_FILENAMES=<unset> VK_DRIVER_FILES=<unset>; an earlier probe",
                    "macho-processor: VULKAN DRIVER: name=MoltenVK info=1.2.7 id=14(MOLTENVK) api=1.2.275 conformance=1.2.0.0 VULKAN_SDK=/sdk/1.3.275.0/macOS VK_ICD_FILENAMES=<unset> VK_DRIVER_FILES=<unset>; every Metal-backed driver reports the GPU as its adapter name",
                    "PE64 FIRST FRAME CHAIN: 2/2 observable preconditions met (0 unobservable)",
                    "PE64 FIRST FRAME CHAIN:   vulkan_instance owner=rosette met (instance_creations=1)",
                    "PE64 FIRST FRAME CHAIN:   guest_surface owner=xenia met (surface_creations=1)",
                    "PE64 GUEST OUTPUT CHAIN: 1/1 observable stages met (0 not observable in this image)",
                    "PE64 GUEST OUTPUT CHAIN:   title_output owner=title met (frames=42)",
                ]) + "\n",
                encoding="utf-8",
            )
            evidence = systems.parse_log(log, {"run_id": "run-123"})
            metrics = evidence["metrics"]
            self.assertTrue(evidence["runtime_run_id_matches"])
            self.assertEqual(3, metrics["invalid_texture_warning_lines"])
            self.assertEqual(2, metrics["invalid_texture_distinct_descriptors"])
            self.assertEqual({"vertex": 3}, metrics["invalid_texture_descriptor_type_counts"])
            self.assertEqual({"vertex": 2}, metrics["invalid_texture_distinct_descriptor_type_counts"])
            self.assertEqual(0, metrics["invalid_texture_unparsed_warning_lines"])
            vertex_example = metrics["vertex_fetch_descriptor_examples"][0]
            self.assertEqual(0x05232580, vertex_example["vertex_fetch"]["address_bytes"])
            self.assertEqual(6, vertex_example["vertex_fetch"]["size_words"])
            self.assertTrue(vertex_example["trailing_words_zero"])
            self.assertEqual(12, metrics["fallback_calls"])
            self.assertEqual(4, metrics["fallback_ledger"]["missing_native_template"])
            self.assertEqual(3, metrics["fallback_ledger"]["native_slow_path"])
            self.assertEqual(500, metrics["fallback_ops"]["mov"]["estimated_ns"])
            self.assertEqual(0, metrics["block_jit_tlb_invalidations"])
            self.assertEqual(30, metrics["worker_fallback_ledger"]["missing_native_template"])
            self.assertEqual(5, metrics["worker_fallback_ledger"]["native_slow_path"])
            self.assertEqual({"direct_route": True, "fills": 77, "refused": 3, "cross_thread_invalidations": 5, "raced_fills_retired": 0}, metrics["worker_tlb"])
            self.assertEqual(1234, metrics["fast_time_imports"])
            self.assertEqual({"QueryPerformanceCounter": 9000, "QueryPerformanceFrequency": 3}, metrics["fast_counter_imports"])
            self.assertEqual({"memcpy": 500, "memmove": 20, "memset": 300}, metrics["fast_crt_imports"])
            self.assertEqual(1, len(metrics["worker_translators"]))
            main_translator = metrics["worker_translators"][0]
            self.assertEqual(("MAIN_THREAD (F8000014)", 262144, 1, 3000000), (main_translator["name"], main_translator["table"], main_translator["growths"], main_translator["interpreted_cold"]))
            self.assertEqual((40000, 9000, 4000000, 2250), (main_translator["dispatch_entries"], main_translator["dispatch_relinks"], main_translator["native_hops"], main_translator["retired_per_dispatch"]))
            self.assertEqual((30000, 2000, 7000, 123), (main_translator["chain_exits_budget"], main_translator["chain_exits_break"], main_translator["chain_exits_miss"], main_translator["tlb_fills"]))
            self.assertTrue(any("worker 'MAIN_THREAD (F8000014)' interpreted 3.2%" in finding for finding in evidence["findings"]))
            self.assertEqual(1, len(metrics["worker_profiles"]))
            self.assertEqual("Main XThread (F8000008)", metrics["worker_profiles"][0]["name"])
            self.assertEqual(40.0, metrics["worker_profiles"][0]["translated_title"])
            self.assertEqual(30.0, metrics["worker_profiles"][0]["system_and_waits"])
            summary = systems.render_summary(
                {"run_id": "run-123", "status": "complete", "runner_exit_status": 0, "started_utc": "s", "finished_utc": "f", "inputs": {}},
                evidence,
            )
            self.assertIn("direct TLB route True; fills 77", summary)
            self.assertIn("slot 4 'Main XThread (F8000008)' translated=60.5%", summary)
            self.assertIn("Worker translator: slot 23 'MAIN_THREAD (F8000014)' table=262144 growths=1", summary)
            self.assertIn("chain_exits(budget/break/miss)=30000/2000/7000 tlb_fills=123", summary)
            self.assertIn('"memcpy": 500', summary)
            # The last driver line wins; a spaced Mesa info string still parses.
            self.assertEqual({"name": "MoltenVK", "info": "1.2.7", "id": "MOLTENVK", "api": "1.2.275"}, metrics["vulkan_driver"])
            self.assertIn("- Vulkan driver: MoltenVK 1.2.7 (Vulkan 1.2.275)", summary)
            self.assertEqual(2, metrics["readiness_chains"]["first_frame_chain"]["met"])
            self.assertEqual(1, metrics["readiness_chains"]["guest_output_chain"]["met"])
            self.assertEqual("blocked", evidence["promotion"]["status"])
            self.assertTrue(any("invalid texture" in finding for finding in evidence["findings"]))
            self.assertTrue(any("type=vertex" in finding for finding in evidence["findings"]))
            self.assertTrue(any("vertex-typed fetch slot" in item for item in evidence["unknowns"]))

    def test_comparison_requires_same_scenario_build_runner_media_and_profile(self) -> None:
        base = {
            "run_id": "one",
            "scenario": "Halo 3 / Last Resort / Custom Games",
            "host": {"system": "Darwin", "release": "26", "machine": "arm64"},
            "inputs": {
                "profile_sha256": "profile",
                "build_identity_sha256": "build",
                "runner": {"sha256": "runner"},
                "executable": {"sha256": "xenia"},
                "media": {"path": "/media/halo.iso", "size_bytes": 100, "mtime_ns": 1, "sha256": None},
                "bundle": {
                    "config": {"sha256": "config"},
                    "settings": {"sha256": "settings"},
                    "recent": {"sha256": "recent"},
                    "manifest": {"sha256": "manifest"},
                    "controller_database": {"sha256": "controllers"},
                },
                "launch_arguments": ["--log_level=1"],
            },
            "evidence": {"metrics": {"frame": {"picture_fps": 1.5}, "step_budget": {"run_instructions_per_second": 1000}}},
        }
        right = copy.deepcopy(base)
        right["run_id"] = "two"
        right["inputs"]["build_identity_sha256"] = "new-build"
        right["inputs"]["runner"]["sha256"] = "new-runner"
        self.assertTrue(systems.compare_runs(base, right)["valid_for_performance_claim"])
        self.assertTrue(systems.compare_runs(base, right)["software_versions"]["rosette_implementation_changed"])
        right["scenario"] = "different map"
        comparison = systems.compare_runs(base, right)
        self.assertFalse(comparison["valid_for_performance_claim"])
        self.assertIn("scenario labels differ", comparison["reasons_not_comparable"])

    def test_artifact_gate_checks_current_test_and_global_shell_records(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            rosette = root / ".rosette"
            rosette.mkdir()
            identity = rosette / "build-identity.json"
            census = rosette / "test-census.json"
            shell_update = rosette / "shell-update.json"
            identity.write_text(json.dumps({
                "rosette": {
                    "source_tree": {"hash": systems.ZERO_SHA256},
                    "generated_tree": {
                        "hash": systems.current_tree_hash(
                            root,
                            ("include/generated", "pkg/generated", "src/generated", "build/generated", "zig-out/generated"),
                            "rosette-generated",
                        ),
                    },
                    "build_graph": {"hash": systems.ZERO_SHA256},
                    "vendor_libraries": {"hash": systems.ZERO_SHA256},
                },
            }) + "\n", encoding="utf-8")
            census.write_text(json.dumps({
                "execution": {"exit_code": 0, "run_artifact_count_matches": True},
                "contract": {"authentic_ready": True},
            }), encoding="utf-8")
            census_hash = systems.sha256_file(census)
            shell_update.write_text(json.dumps({
                "test_census_sha256": census_hash,
                "installed_matches_built": True,
            }), encoding="utf-8")
            manifest = {
                "run_id": "run-1",
                "status": "complete",
                "runner_exit_status": 0,
                "inputs": {"build_identity_sha256": systems.sha256_file(identity)},
                "evidence": {
                    "runtime_run_id_matches": True,
                    "promotion": {"status": "eligible_pending_artifact_checks", "findings": [], "unknowns": []},
                },
            }
            self.assertEqual([], systems.manifest_artifact_gate(manifest, root))
            shell_update.write_text(json.dumps({
                "test_census_sha256": census_hash,
                "installed_matches_built": False,
            }), encoding="utf-8")
            self.assertTrue(any(
                "installed global shell" in finding
                for finding in systems.manifest_artifact_gate(manifest, root)
            ))


if __name__ == "__main__":
    unittest.main(verbosity=2)
