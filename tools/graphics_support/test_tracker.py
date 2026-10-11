"""Focused correctness tests; no game, Metal commands or GPU dispatch."""
import copy
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

from .coverage import attest, compare, denominator_hash, new_snapshot, revoke, states, summarize, validate
from .evidence import parse_log, shader_archive, spirv_info
from .iso import InventoryError, directory_entries, halo3_map, read_at, xiso_files
from .report import json_script, render, write_snapshot
from .checks import compile_shaders


def fixture(n=100):
    sha = "a" * 64
    assets = [{"id": f"{sha}:maps/test.map:{i:04x}:bitm", "name": f"bitmap{i}", "class": "bitm",
               "map": "maps/test.map", "tag_index": i, "category": "texture_tags", "metadata_status": "parsed",
               "subimages": [{"format": 14}], "status": "unknown", "proofs": []} for i in range(n)]
    iso = {"sha256": sha, "policy": "halo3-retail-graphics-tag-instances-v1", "assets": assets,
           "maps": [], "scope": "Synthetic test inventory", "denominator_sha256": denominator_hash(assets)}
    return new_snapshot(iso, {"build": "b" * 64, "driver": {"name": "synthetic", "info": "1"}}, scenario="synthetic")


def node(name=b"maps", left=0, right=0, sector=40, size=2048, attr=16):
    data = struct.pack("<HHIIBB", left, right, sector, size, attr, len(name)) + name
    return data + bytes((-len(data)) % 4)


def cache():
    data = bytearray(0x6000)
    data[:4] = b"head"
    struct.pack_into(">I", data, 4, 11)
    build = b"11855.07.08.20.2317.halo3_ship"
    data[284:284 + len(build)] = build
    magic = 0x40000000
    struct.pack_into(">I", data, 16, magic + 0x3100)
    struct.pack_into(">I", data, 744, magic)
    struct.pack_into(">4I", data, 0x3100, 1, magic + 0x3200, 1, magic + 0x3300)
    data[0x3200:0x320c] = b"bitm" + b"\xff" * 8
    struct.pack_into(">hHI", data, 0x3300, 0, 1, magic + 0x3500)
    struct.pack_into(">4I", data, 692, 1, 0x4000, 8, 0x4100)
    data[0x4000:0x4008] = b"example\0"
    struct.pack_into(">II", data, 0x3500 + 96, 1, magic + 0x3700)
    struct.pack_into(">HH", data, 0x3704, 128, 64)
    data[0x3708] = 1
    data[0x3709] = 0x20
    struct.pack_into(">HH", data, 0x370a, 0, 14)
    struct.pack_into(">H", data, 0x370e, 0x000a)
    struct.pack_into(">2h", data, 0x3710, -2, 3)
    data[0x3714] = 7
    data[0x3715] = 3
    struct.pack_into(">2b", data, 0x3716, -1, -1)
    struct.pack_into(">5i", data, 0x3718, 0x100, 0x400, -1, 0, 0x21)
    struct.pack_into(">II", data, 0x3500 + 0x8c, 1, magic + 0x3800)
    struct.pack_into(">II", data, 0x3800, 0x00010005, 0)
    return data


class IsoTests(unittest.TestCase):
    def test_bounded_reads(self):
        for offset, length in ((-1, 1), (3, 2), (0, 17 << 20)):
            with self.assertRaises(InventoryError):
                read_at(io.BytesIO(b"1234"), offset, length, 4)
        with self.assertRaises(InventoryError):
            read_at(io.BytesIO(b"1"), 0, 2, 4)

    def test_directory_tree_and_malformed_links(self):
        data = node(b"a", right=4, attr=0) + node(b"b", attr=0)
        self.assertEqual([n[0] for n in directory_entries(data)], ["a", "b"])
        for bad in (node(b"a", right=99), node(b".."), node(b"a/b"), node(b"a", right=4) + node(b"b", left=4),
                    node(b"a", right=4) + node(b"A"), node(b"abcdef", right=1)):
            with self.assertRaises(InventoryError):
                directory_entries(bad)

    def test_iso_outside_extent_and_directory_alias(self):
        data = bytearray(0x18000)
        data[0x10000:0x10014] = b"MICROSOFT*XBOX*MEDIA"
        struct.pack_into("<II", data, 0x10014, 40, 2048)
        data[40*2048:40*2048 + 16] = node(b"a", sector=10000, size=100, attr=0)
        with self.assertRaises(InventoryError):
            xiso_files(io.BytesIO(data), len(data))
        data[40*2048:40*2048 + 16] = node(b"a", sector=40, size=2048)
        with self.assertRaises(InventoryError):
            xiso_files(io.BytesIO(data), len(data))

    def test_bitmap_metadata_and_unknown_payload(self):
        data = cache()
        info, assets = halo3_map(io.BytesIO(data), {"path": "maps/test.map", "offset": 0, "size": len(data)}, len(data), "a"*64)
        self.assertEqual(info["graphics_tags"], 1)
        self.assertEqual(assets[0]["name"], "example")
        image = assets[0]["subimages"][0]
        self.assertEqual(image, {"index": 0, "width": 128, "height": 64, "depth": 1,
                         "xbox_flags": 0x20, "type": 0, "format": 14, "format_flags": 0x000a,
                         "registration_point": [-2, 3], "mip_count": 7, "curve": 3,
                         "interleaved_interop_index": -1, "interleaved_texture_index": -1,
                         "pixel_data_offset": 0x100, "pixel_data_size": 0x400,
                         "high_res_pixels_offset": -1, "high_res_pixels_size": 0,
                         "hardware_format": 0x21,
                         "resource_reference": {"kind": "ordinary", "slot": 0, "datum_raw": 0x00010005},
                         "resource_reference_status": "indexed", "payload_status": "unresolved_resource_pages"})
        self.assertEqual(assets[0]["hardware_textures"], [{"slot": 0, "datum_raw": 0x00010005, "padding": 0}])
        self.assertEqual(assets[0]["interleaved_hardware_textures"], [])
        self.assertEqual(assets[0]["status"], "unknown")

    def test_bitmap_keeps_subimage_when_resource_reference_table_is_malformed(self):
        data = cache()
        struct.pack_into(">II", data, 0x3500 + 0x8c, 1, 0)
        _, assets = halo3_map(io.BytesIO(data), {"path": "maps/test.map", "offset": 0, "size": len(data)},
                              len(data), "a"*64)
        self.assertEqual(assets[0]["metadata_status"], "partial")
        self.assertEqual(assets[0]["subimages"][0]["pixel_data_size"], 0x400)
        self.assertEqual(assets[0]["subimages"][0]["resource_reference_status"], "not_present_in_tag_block")
        self.assertIn("Null bitmap hardware texture pointer", assets[0]["metadata_errors"][0])

    def test_unknown_build_and_bad_table_refused(self):
        for offset, value in ((4, 12), (0x3100, 999), (692, 2)):
            data = cache()
            struct.pack_into(">I", data, offset, value)
            with self.assertRaises(InventoryError):
                halo3_map(io.BytesIO(data), {"path": "test.map", "offset": 0, "size": len(data)}, len(data), "a"*64)

    def test_shared_resource_is_not_counted_supported(self):
        data = cache()
        struct.pack_into(">I", data, 16, 0)
        info, assets = halo3_map(io.BytesIO(data), {"path": "shared.map", "offset": 0, "size": len(data)}, len(data), "a"*64)
        self.assertEqual(info["status"], "resource_container")
        self.assertEqual(assets, [])

    def test_bad_bitmap_stays_in_fixed_denominator(self):
        data = cache()
        struct.pack_into(">I", data, 0x3500 + 100, 0xffffffff)
        _, assets = halo3_map(io.BytesIO(data), {"path": "test.map", "offset": 0, "size": len(data)}, len(data), "a"*64)
        self.assertEqual(len(assets), 1)
        self.assertEqual(assets[0]["metadata_status"], "unparsed")


class ProgressTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.proof = self.directory / "proof.txt"
        self.proof.write_text("Synthetic parity evidence, not game compatibility")
        self.snapshot = fixture()

    def tearDown(self):
        self.temp.cleanup()

    def record(self, count, stage="correct_render", outcome="pass", snapshot=None):
        snapshot = self.snapshot if snapshot is None else snapshot
        return attest(snapshot, {"asset_ids": [a["id"] for a in snapshot["iso"]["assets"][:count]], "stage": stage,
                                 "outcome": outcome, "proof_path": "proof.txt", "note": "Synthetic test only"}, self.directory)

    def test_no_evidence_is_unknown_not_unsupported(self):
        counts = summarize(self.snapshot)["coverage"]["all"]
        self.assertEqual(counts["unknown"], 100)
        self.assertIsNone(counts["pass_percent_of_evaluated"])

    def test_exact_38_to_40_and_target(self):
        self.record(38)
        before = copy.deepcopy(self.snapshot)
        self.record(40)
        diff = compare(before, self.snapshot, 42)
        self.assertEqual(diff["percentage_point_change"], 2)
        self.assertEqual(len(diff["changes"]["correct_render"]["gained"]), 2)
        self.assertEqual(diff["additional_confirmed_instances_needed"], 2)

    def test_compile_stage_cannot_promote_rendering(self):
        self.record(100, stage="shader_translation")
        self.assertEqual(summarize(self.snapshot)["coverage"]["all"]["confirmed"], 0)

    def test_duplicate_attestation_idempotent(self):
        self.record(38)
        self.record(38)
        self.assertEqual(len(self.snapshot["ledger"]), 1)

    def test_failure_conflict_and_audited_revocation(self):
        self.record(38)
        failed = self.record(1, outcome="fail")
        self.assertEqual(summarize(self.snapshot)["coverage"]["all"]["conflict"], 1)
        revoke(self.snapshot, failed, "Mistaken test input corrected with evidence")
        self.assertEqual(summarize(self.snapshot)["coverage"]["all"]["confirmed"], 38)

    def test_changed_build_driver_scenario_does_not_inherit(self):
        self.record(38)
        for key, value in (("build", "c"*64), ("driver", {"name": "different"}), ("scenario", "different")):
            changed = copy.deepcopy(self.snapshot)
            changed["context"][key] = value
            self.assertEqual(summarize(changed)["coverage"]["all"]["confirmed"], 0)

    def test_changed_iso_policy_denominator_rejects_comparison(self):
        for key, value in (("sha256", "d"*64), ("policy", "future"), ("denominator_sha256", "d"*64)):
            changed = copy.deepcopy(self.snapshot)
            changed["iso"][key] = value
            with self.assertRaises(InventoryError):
                compare(self.snapshot, changed)

    def test_duplicate_asset_identity_rejected(self):
        self.snapshot["iso"]["assets"].append(self.snapshot["iso"]["assets"][0])
        with self.assertRaises(InventoryError):
            validate(self.snapshot)

    def test_changed_or_missing_proof_refuses_coverage(self):
        self.record(38)
        self.proof.write_text("changed")
        with self.assertRaises(InventoryError):
            states(self.snapshot)
        self.proof.unlink()
        with self.assertRaises(InventoryError):
            states(self.snapshot)

    def test_unknown_asset_or_missing_context_rejected(self):
        request = {"asset_ids": ["unknown"], "stage": "correct_render", "outcome": "pass", "proof_path": "proof.txt", "note": "test"}
        with self.assertRaises(InventoryError):
            attest(self.snapshot, request, self.directory)
        self.snapshot["context"]["build"] = None
        with self.assertRaises(InventoryError):
            self.record(1)

    def test_tampered_record_and_nonfinite_target_refused(self):
        self.record(38)
        changed = copy.deepcopy(self.snapshot)
        changed["ledger"][0]["outcome"] = "fail"
        with self.assertRaises(InventoryError):
            states(changed)
        with self.assertRaises(InventoryError):
            compare(self.snapshot, self.snapshot, float("nan"))

    def test_html_escapes_untrusted_names_and_output_preserved(self):
        malicious = '</script><script>alert("bad")</script>'
        self.snapshot["iso"]["assets"][0]["name"] = malicious
        rendered = render(self.snapshot)
        self.assertNotIn(malicious, rendered)
        self.assertEqual(json.loads(json_script([malicious]))[0], malicious)
        output = self.directory / "report"
        write_snapshot(self.snapshot, output)
        with self.assertRaises(ValueError):
            write_snapshot(self.snapshot, output)


class RunAndShaderTests(unittest.TestCase):
    def test_log_snapshots_deduplicate_and_creation_not_correctness(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "run.log"
            shader = "Vulkan FSI SHADER: module_id=1 guest=0x10 spirv_hash=0x20"
            pipeline = "Vulkan FSI PIPELINE: ordinal=1 real=0x30 result=0 fragment_identity_known=true"
            path.write_text("# run_id = example\n# build_identity_sha256 = " + "a"*64 + "\nVULKAN FSI GUARD: splits=2\nVULKAN FSI GUARD: splits=8\n" +
                            shader + "\n" + shader + "\n" + pipeline + "\n" + pipeline + "\nFRAME HUD RATE: accepted_presents=10 presented_fps=3.2\n"*2)
            run = parse_log(path)
            self.assertEqual(run["snapshots"]["guard"]["splits"], 8)
            self.assertEqual(len(run["shaders"]), 1)
            self.assertEqual(len(run["cadence"]), 1)
            self.assertEqual(run["pipeline_creation"]["accepted"], 1)
            self.assertIn("unknown", run["shader_to_iso_asset_mapping"])
            path.write_text(path.read_text() + "\n# run_id = second")
            with self.assertRaises(InventoryError):
                parse_log(path)

    def test_shader_stream_and_exact_guest_matching(self):
        words = (0x07230203, 0x10000, 0, 10, 0, (2<<16)|17, 1)
        data = struct.pack("<7I", *words)
        info = spirv_info(data)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            name = f"module-10-{info['fingerprint']:x}"
            (root / (name + ".guest.spv")).write_bytes(data)
            (root / (name + ".native.spv")).write_bytes(data)
            (root / f"module-11-{info['fingerprint']:x}.guest.spv").write_bytes(data)
            archive = shader_archive(root, {"shaders": [{"guest": 16, "spirv_hash": info["fingerprint"]}]})
            self.assertEqual(len(archive["modules"]), 2)
            self.assertEqual(sum(m["current_run_guest_match"] for m in archive["modules"]), 1)
            self.assertEqual(archive["matched_fsi_guest_hashes"], 1)
        for bad in (data[:19], struct.pack("<5I", 1, 0, 0, 1, 0), struct.pack("<6I", 0x07230203, 0x10000, 0, 1, 0, 0)):
            with self.assertRaises(InventoryError):
                spirv_info(bad)

    def test_missing_compiler_stays_unknown_and_does_not_certify_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            file = root / "module.spv"
            data = struct.pack("<5I", 0x07230203, 0x10000, 0, 1, 0)
            file.write_bytes(data)
            import hashlib
            snapshot = fixture(1)
            snapshot["shader_archive"] = {"modules": [{"role": "guest", "current_run_guest_match": True,
                                                      "sha256": hashlib.sha256(data).hexdigest(), "paths": [str(file)]}]}
            with patch("graphics_support.checks.executable", return_value=None):
                compile_shaders(snapshot, root / "checks", Path(__file__).resolve().parents[2])
            self.assertEqual(snapshot["shader_archive"]["modules"][0]["checks"]["air_compilation"]["status"], "unknown")
            self.assertEqual(summarize(snapshot)["coverage"]["all"]["confirmed"], 0)

    def test_refused_rewrite_batch_never_promotes_partial_modules(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "module.spv"
            data = struct.pack("<5I", 0x07230203, 0x10000, 0, 1, 0)
            source.write_bytes(data)
            import hashlib
            import sys
            sha = hashlib.sha256(data).hexdigest()
            snapshot = fixture(1)
            snapshot["shader_archive"] = {"modules": [{"role": "guest", "current_run_guest_match": True,
                                                      "sha256": sha, "paths": [str(source)]}]}
            calls = []

            def fake_execute(command, log, timeout=60):
                calls.append(command)
                if len(calls) == 1:
                    return {"status": "pass"}
                (root / "checks/rewritten" / (sha + ".spv")).write_bytes(data)
                return {"status": "fail", "reason": "Later module was unsafe"}

            with patch("graphics_support.checks.executable", return_value=sys.executable), patch("graphics_support.checks.execute", side_effect=fake_execute):
                compile_shaders(snapshot, root / "checks", Path(__file__).resolve().parents[2])
            checks = snapshot["shader_archive"]["modules"][0]["checks"]
            self.assertEqual(len(calls), 2)
            self.assertTrue(all(c["status"] == "unknown" for c in checks.values()))

    def test_bad_archive_fingerprint_does_not_become_a_module(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "module-10-0.guest.spv").write_bytes(struct.pack("<5I", 0x07230203, 0x10000, 0, 1, 0))
            archive = shader_archive(root)
            self.assertEqual(len(archive["unreadable"]), 1)
            self.assertEqual(archive["modules"], [])


if __name__ == "__main__":
    unittest.main()
