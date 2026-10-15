import unittest
from timing_inventory import parse


class InventoryTests(unittest.TestCase):
    def test_units_name_identity_and_latest_peak(self):
        data = parse([
            "info: Vulkan host time by entry point: rank=1 name=vkQueueSubmit calls=8 host_ms=90 max_ms=20",
            "info: Vulkan host time by entry point: rank=2 name=vkQueueSubmit calls=9 host_ms=91 max_ms=21",
            "info: VULKAN SHADER HOST STAGE: stage=driver calls=2 total_us=100 max_us=70",
            "macho-processor: FRAME CADENCE JITTER: mean_ms=4 max_ms=50",
            "macho-processor: FRAME CADENCE JITTER: mean_ms=3 max_ms=10",
        ])
        self.assertEqual(len(data["maxima"]), 3)
        self.assertEqual([x["max_ms"] for x in data["maxima"]], [21, .07, 10])
        self.assertEqual(data["maxima"][-1]["peak_reported_ms"], 50)
        self.assertEqual(data["maxima"][0]["line"], 2)

    def test_absent_maximum_and_sampleless_are_unknown(self):
        data = parse([
            "PE64 IMPORT HISTOGRAM: import=CRT!foo calls=200 mean_ns=12 estimated_ms=2",
            "PE64 BLOCK JIT WORKER FALLBACK OPS: add=100(50%,estimated_ns=1000,samples=0)",
            "PE64 IMPORT TIMING: import=CRT!bar calls=7 samples=0 sampled_ns=0 sampled_max_ns=0 sample_period=64",
        ])
        self.assertEqual(data["estimates"][0]["max_ms"], None)
        self.assertEqual(data["estimates"][1]["total_ms"], None)
        self.assertEqual(data["maxima"][0]["max_ms"], None)

    def test_multiple_maxima_and_composite_wait(self):
        data = parse([
            "info: METAL COMMAND BUFFER POLICY: room_wait_ms=123 room_wait_max_ms=5",
            "macho-processor: GRAPHICS PACING: completion_wait(calls/mean_us/max_us)=5/2/77",
            "info: IO: max_worker_us=609719 max_host_wait_us=8077",
        ])
        self.assertEqual([r["max_ms"] for r in data["maxima"]], [5, .077, 609.719, 8.077])

    def test_sampled_max_is_never_scaled_into_all_call_max(self):
        data = parse(["PE64 IMPORT TIMING: import=CRT!foo calls=128 samples=2 sampled_ns=2000 sampled_max_ns=1500 sample_period=64"])
        self.assertEqual(data["estimates"][0]["total_ms"], .128)
        self.assertEqual(data["maxima"][0]["max_ms"], .0015)
        self.assertEqual(data["maxima"][0]["coverage"], "timed samples only")

    def test_policy_requests_and_ticks_do_not_become_host_elapsed(self):
        data = parse(["PE64 PAUSE BACKOFF: requested_max_us=100 max_host_wait_us=8000", "PE64 WAIT COST: key=0xa kind=srw max_ticks=7000"])
        self.assertEqual(len(data["maxima"]), 1)
        self.assertEqual(data["limits"][0]["limit_ms"], .1)
        self.assertEqual(data["unconverted"][0]["ticks"], 7000)

    def test_explicit_guest_tick_conversion_stays_separate_from_cpu(self):
        data = parse(["PE64 WAIT COST: key=0xa kind=srw max_ticks=7050"], ticks_per_ms=1000)
        self.assertEqual(data["maxima"][0]["max_ms"], 7.05)
        self.assertEqual(data["maxima"][0]["basis"], "guest elapsed")
        self.assertFalse(data["unconverted"])

    def test_composite_handoff_and_fence_maxima(self):
        data = parse(["PE64 WINDOWS UI HANDOFF TIMING: queued_ms(total/max/last)=1000/747/1 ran_ms(total/max/last)=900/771/1", "VULKAN FSI GUARD: completion_ms_per_group(mean/p50/p95/p99/max)=2/5/20/20/105"])
        self.assertEqual([r["max_ms"] for r in data["maxima"]], [747, 771, 105])
        self.assertEqual([r["total_ms"] for r in data["maxima"]], [1000, 900, None])
        self.assertIn("not GPU execution", data["maxima"][-1]["coverage"])

    def test_no_calls_is_not_a_measured_zero_maximum(self):
        data = parse(["FRAME HOST COST: stage=cpu_capture calls=0 total_us=0 max_us=0"])
        self.assertIsNone(data["maxima"][0]["max_ms"])
        self.assertEqual(data["maxima"][0]["total_ms"], 0)

    def test_cpu_totals_are_not_operation_maxima(self):
        data = parse(["PE64 WORKER HOST CPU: slot=2 name='RENDER' cpu_us=2000 elapsed_us=10000"])
        self.assertEqual(data["cpu"][0]["total_ms"], 2)
        self.assertEqual(data["cpu"][0]["max_ms"], None)
        self.assertFalse(data["maxima"])

    def test_decimal_cumulative_duration_keeps_logged_precision(self):
        data = parse(["Vulkan host time: calls=5 host_ms=12.456 max_ms=3.789"])
        self.assertEqual(data["maxima"][0]["total_ms"], 12.456)
        self.assertEqual(data["maxima"][0]["max_ms"], 3.789)

    def test_fence_wait_sample_cpu_and_elapsed_have_different_bases(self):
        data = parse(["VULKAN FSI OBSERVER HOST CPU: scope=inline_wait samples=3 sampled_cpu_ns=2000 sampled_cpu_max_ns=1000 sampled_elapsed_ns=50000 sampled_elapsed_max_ns=20000"])
        self.assertEqual([r["basis"] for r in data["maxima"]], ["thread CPU", "elapsed"])
        self.assertEqual([r["max_ms"] for r in data["maxima"]], [.001, .02])
        self.assertEqual([r["total_ms"] for r in data["maxima"]], [.002, .05])
        self.assertEqual([r["coverage"] for r in data["maxima"]], ["timed samples only"] * 2)

    def test_sampleless_fence_cpu_is_unknown(self):
        data = parse(["VULKAN FSI OBSERVER HOST CPU: scope=watcher samples=0 sampled_cpu_max_ns=0 sampled_elapsed_max_ns=0"])
        self.assertEqual([r["max_ms"] for r in data["maxima"]], [None, None])

    def test_detailed_ledger_supersedes_ranked_aliases_but_keeps_evidence(self):
        data = parse([
            "PE64 IMPORT HISTOGRAM: import=CRT!foo calls=128 mean_ns=100 estimated_ms=1 samples=2 sampled_max_ns=800",
            "PE64 BLOCK JIT WORKER FALLBACK OPS: add=200(50%,estimated_ns=2000,samples=2)",
            "PE64 IMPORT TIMING: import=CRT!foo calls=256 samples=4 sampled_ns=1000 sampled_max_ns=500",
            "PE64 FALLBACK TIMING: scope='WORKER ' op=add calls=300 samples=3 sampled_ns=3000 sampled_max_ns=1200",
        ])
        self.assertEqual(len(data["estimates"]), 2)
        self.assertEqual(len(data["maxima"]), 2)
        self.assertEqual(len(data["aliases"]), 3)
        self.assertEqual(data["maxima"][0]["max_ms"], .0005)
        self.assertAlmostEqual(data["maxima"][0]["peak_reported_ms"], .0008)

    def test_newer_ranked_summary_is_not_hidden_by_an_older_full_record(self):
        data = parse([
            "PE64 IMPORT TIMING: import=CRT!foo calls=128 samples=2 sampled_ns=1000 sampled_max_ns=500",
            "PE64 IMPORT HISTOGRAM: import=CRT!foo calls=256 mean_ns=100 estimated_ms=1 samples=4 sampled_max_ns=800",
        ])
        self.assertEqual(len(data["estimates"]), 2)
        self.assertEqual(len(data["maxima"]), 2)
        self.assertFalse(data["aliases"])


if __name__ == "__main__":
    unittest.main()
