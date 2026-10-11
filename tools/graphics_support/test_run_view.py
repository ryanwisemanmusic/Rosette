"""Run-log observations stay observations: counted from Xenia's own lines, never promoted."""
from pathlib import Path
import tempfile
import unittest

from .evidence import parse_log
from .run_view import native_dispatch_total, run_overview

HEADER = ["# run_id = test-run", "# build_identity_sha256 = " + "ab" * 32, "# started_utc = 2026-10-09T00:00:00Z", "media = /tmp/x.iso"]


def parsed(lines):
    with tempfile.TemporaryDirectory() as d:
        log = Path(d) / "run.log"
        log.write_text("\n".join(HEADER + lines) + "\n")
        return parse_log(log)


class RunLogTests(unittest.TestCase):
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
