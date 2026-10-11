"""Run-log observations stay observations: counted from Xenia's own lines, never promoted."""
from pathlib import Path
import tempfile
import unittest
import hashlib

from .evidence import parse_log
from .run_view import native_dispatch_total, run_overview, performance_overview, performance_measurements

HEADER = ["# run_id = test-run", "# build_identity_sha256 = " + "ab" * 32, "# started_utc = 2026-10-09T00:00:00Z", "media = /tmp/x.iso"]


def parsed(lines):
    with tempfile.TemporaryDirectory() as d:
        log = Path(d) / "run.log"
        log.write_text("\n".join(HEADER + lines) + "\n")
        return parse_log(log)


class RunLogTests(unittest.TestCase):
    def test_offline_performance_counts_are_withdrawn_if_source_or_log_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.zig"
            log = Path(directory) / "benchmark.log"
            source.write_text("measured source")
            log.write_text("Build Summary: 5/5 steps succeeded; 108/108 tests passed\n"
                           "FSI ready fence benchmark: groups=20000 watcher_ns=80000000 ready_ns=2000000\n"
                           "chunks_1x(before/after)=1000/500 chunks_4x=1000 draw_cap=4 recovery_max_work=2097152\n")
            record = lambda path: {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            evidence = {"sources": [record(source)], "logs": [record(log)]}
            self.assertIn("80.000 ms", performance_measurements(evidence))
            self.assertIn("cannot predict gameplay FPS", performance_measurements(evidence))
            source.write_text("changed")
            self.assertIn("withdrawn", performance_measurements(evidence))
            evidence["sources"] = [record(source)]
            log.write_text("incomplete gate")
            evidence["logs"] = [record(log)]
            self.assertIn("withdrawn", performance_measurements(evidence))

    def test_performance_uses_final_host_counters_and_keeps_new_routes_unknown(self):
        run = parsed([
            "FRAME HOST COST: present_intervals=10 total_ms=1000 mean_ms=100 max_ms=200",
            "FRAME HOST COST: stage=queue_submit calls=20 total_us=800000 max_us=50000",
            "VULKAN FSI GUARD: submission expanded_submits=1 segments=20 driver_queue_submit_calls=10 driver_submit_infos=20",
            "METAL COMMAND BUFFER POLICY: room_waits=100 room_wait_ms=200 adaptive_sample_work_cap=615384 shader_bounds_verified=true",
        ])
        text = performance_overview(run)
        self.assertIn("80.0%", text)
        self.assertIn("2.000 ms", text)
        self.assertIn("unknown/unknown", text)
        self.assertIn("not a CPU/GPU utilization breakdown or an FPS forecast", text)

    def test_ready_fence_counters_are_cumulative_and_missing_cost_is_unknown(self):
        run = parsed([
            "VULKAN FSI FENCE ROUTE: ready_checks=20 ready_completions=3",
            "VULKAN FSI FENCE ROUTE: ready_checks=30 ready_completions=7",
        ])
        text = performance_overview(run)
        self.assertIn("30/7", text)
        self.assertIn("occupied unknown", text)

    def test_vertex_typed_texture_fetch_warnings_are_counted_once_per_xenia_line(self):
        run = parsed([
            "w> 0100000C Texture fetch constant (051B5583 1000001A 00000000 00000000 00000000 00000000) is completely invalid!",
            "w> 0100000C Texture fetch constant (051B5583 1000001A 00000000 00000000 00000000 00000000) is completely invalid!",
            "w> 0100000C Texture fetch constant (05231403 1000001A 00000000 00000000 00000000 00000000) is completely invalid!",
            "error(elf): PE64 FATAL POINT: guest-warning line=w> 0100000C Texture fetch constant (05231403 1000001A 0 0 0 0) is completely invalid!",
        ])
        fetch = run["texture_fetch_warnings"]
        self.assertEqual((fetch["warnings"], fetch["distinct_constants"], fetch["types"]), (3, 2, {"vertex": 3}))

    def test_exit_isolation_and_brightness_are_read_from_their_own_lines(self):
        run = parsed([
            "runner_exit_status = 0", "finished_utc = 2026-10-09T00:11:00Z",
            "macho-processor: VULKAN FSI ISOLATION: pipeline=0x12b0f9000 shader_hash=0x446d721d33020d1f reason=tessellation_interlock; text",
            "macho-processor: BRIGHTNESS LADDER:   stage=swap_texture image=0x1 guest=0x2 format=64 extent=1152x640 channels=raw_storage mean_rgb=156/179/254 max_rgb=255/255/255 visible_gt16=1 bright_gt64=1 white_rgb_ge240=280229/737280 rgb_different=1 frame=3072",
            "macho-processor: NATIVE METAL TEXTURES: pipelines=1 modules_matched=0 dispatches(ctx1/dxt1/dxt3/dxt5)=1084/0/0/0 declined=0 pipeline_failures=0 metadata_failures=0; text",
        ])
        self.assertEqual(run["exit"]["runner_exit_status"], "0")
        self.assertEqual(run["exit"]["started_utc"], "2026-10-09T00:00:00Z")
        self.assertEqual((len(run["isolation_events"]), run["isolation_events"][0]["reason"]), (1, "tessellation_interlock"))
        self.assertEqual(run["brightness_samples"][0]["white"], 280229)
        self.assertEqual(native_dispatch_total(run), 1084)

    def test_overview_never_turns_dispatches_or_a_clean_exit_into_rendering_proof(self):
        run = parsed([
            "runner_exit_status = 0",
            "macho-processor: NATIVE METAL TEXTURES: pipelines=1 modules_matched=0 dispatches(ctx1/dxt1/dxt3/dxt5)=7/0/0/0 declined=0 pipeline_failures=0 metadata_failures=0; text",
        ])
        text = run_overview(run)
        self.assertIn("Clean exit", text)
        self.assertIn("say nothing about whether the pictures improved", text)
        self.assertIn("do not certify other scenes", text)

    def test_tessellation_warning_carries_its_traced_cause_and_how_to_falsify_it(self):
        warned = parsed(["w> 0100000C VulkanPipelineCache: Failed to create one or more tessellation shaders - tessellation will not be available"])
        text = run_overview(warned)
        self.assertIn("VPERM2F128", text)
        self.assertIn("this explanation is wrong", text)
        self.assertIn("returned success with a non-null handle", text)
        self.assertIn("should show", run_overview(parsed(["runner_exit_status = 0"])))

    def test_gpu_failure_line_makes_the_run_need_review(self):
        run = parsed(["runner_exit_status = 0", "x Caused GPU Address Fault Error (kIOGPUCommandBufferCallbackErrorPageFault)"])
        self.assertIn("Needs review", run_overview(run))

    def test_zero_dispatches_are_not_reported_as_native_use(self):
        run = parsed(["macho-processor: NATIVE METAL TEXTURES: pipelines=1 modules_matched=0 dispatches(ctx1/dxt1/dxt3/dxt5)=0/0/0/0 declined=995 pipeline_failures=0 metadata_failures=0; text"])
        self.assertEqual(native_dispatch_total(run), 0)
        self.assertEqual(run_overview({}), "")


if __name__ == "__main__":
    unittest.main()
