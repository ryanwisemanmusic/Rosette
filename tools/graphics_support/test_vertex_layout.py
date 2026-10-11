"""Declared-layout vertex checks: exact field patches, honest labels, withdrawn stale claims."""
import copy
import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from .iso import InventoryError, hash_file
from .iso_offline import STAGES, offline_summary, verify_offline_artifacts
from .vertex_layout import FORMATS, NEUTRAL, fetch_indices, patch_vertex_microcode, vertex_layout_view


def program(fetches):
    """One EXEC clause at triple 2 followed by vertex fetches; True marks a mini fetch."""
    sequence = sum(1 << (2*n) for n in range(len(fetches)))
    words = [2 | (len(fetches) << 12) | (sequence << 16), 1 << 12, 0, 0, 0, 0]
    for mini in fetches:
        words += [0, (1 << 30) if mini else 0, 0]
    return struct.pack(f">{len(words)}I", *words)


def fields(code):
    words = struct.unpack(f">{len(code)//4}I", code)
    rows = []
    for index in fetch_indices(list(words)):
        w0, w1, w2 = words[index*3:index*3+3]
        rows.append({"format": (w1 >> 16) & 63, "signed": (w1 >> 12) & 1, "integer": (w1 >> 13) & 1,
                     "rf": (w1 >> 14) & 1, "mini": (w1 >> 30) & 1, "stride": w2 & 255,
                     "offset": (w2 >> 8) & 0x7fffff, "opcode": w0 & 31})
    return rows


class PatchTests(unittest.TestCase):
    def test_float4_layout_interleaves_a_full_fetch_and_its_mini_fetches(self):
        patched, report = patch_vertex_microcode(program([False, True, True]))
        rows = fields(patched)
        self.assertEqual([r["format"] for r in rows], [FORMATS["k_32_32_32_32_FLOAT"]]*3)
        self.assertEqual([(r["stride"], r["offset"]) for r in rows], [(12, 0), (0, 4), (0, 8)])
        self.assertEqual(report["strides_dwords"], [12])
        self.assertEqual(report["layout"], NEUTRAL["name"])

    def test_separate_full_fetches_are_separate_attribute_groups(self):
        rows = fields(patch_vertex_microcode(program([False, True, False]))[0])
        self.assertEqual([(r["stride"], r["offset"]) for r in rows], [(8, 0), (0, 4), (4, 0)])

    def test_only_the_declared_fields_change(self):
        original = program([False, True])
        patched, _ = patch_vertex_microcode(original)
        before, after = struct.unpack(">12I", original), struct.unpack(">12I", patched)
        self.assertEqual(before[:6], after[:6])
        for index in (2, 3):
            self.assertEqual(before[index*3], after[index*3])
            self.assertEqual(before[index*3+1] & ~((63 << 16) | (7 << 12)), after[index*3+1] & ~((63 << 16) | (7 << 12)))
            self.assertEqual(before[index*3+2] & (1 << 31), after[index*3+2] & (1 << 31))

    def test_predicate_condition_bit_is_preserved(self):
        words = list(struct.unpack(">9I", program([False])))
        words[8] = 1 << 31
        patched, _ = patch_vertex_microcode(struct.pack(">9I", *words))
        self.assertEqual(struct.unpack(">9I", patched)[8] >> 31, 1)

    def test_flag_variants_set_only_signedness_normalization_and_fraction_bits(self):
        for signed, integer, rf in ((0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 1, 0), (1, 1, 0)):
            with self.subTest(signed=signed, integer=integer, rf=rf):
                row = fields(patch_vertex_microcode(program([False]), "k_8_8_8_8", signed, integer, rf)[0])[0]
                self.assertEqual((row["format"], row["signed"], row["integer"], row["rf"]), (6, signed, integer, rf))

    def test_mini_fetch_without_a_full_fetch_cannot_declare_a_stride(self):
        with self.assertRaises(InventoryError):
            patch_vertex_microcode(program([True]))

    def test_program_without_a_vertex_fetch_is_refused(self):
        with self.assertRaises(InventoryError):
            patch_vertex_microcode(struct.pack(">6I", 0, 0, 0, 0, 0, 0))

    def test_unknown_format_and_oversized_stride_are_refused(self):
        with self.assertRaises(InventoryError):
            patch_vertex_microcode(program([False]), "k_not_a_format", 0, 0, 0)
        with mock.patch.dict(NEUTRAL, {"stride_dwords_per_attribute": 100}):
            with self.assertRaises(InventoryError):
                patch_vertex_microcode(program([False, True, True]))


def result_with(records, matrix=None):
    return {"neutral_vertex_layout": {"scope": "scope text", "layout": NEUTRAL, "modules": records,
                                      "summary": {"programs": len(records), "variants": len(records), "ready": len(records), "failed": 0,
                                                  "unknown": 0, "stages": {s: {"pass": len(records), "fail": 0, "unknown": 0} for s in STAGES}}},
            **({"vertex_format_matrix": matrix} if matrix else {})}


class ViewAndEvidenceTests(unittest.TestCase):
    def test_view_labels_the_layout_and_never_claims_runtime_support(self):
        text = vertex_layout_view(result_with([{"base_id": "vs:a"}]))
        self.assertIn("declared float4 layout", text)
        self.assertIn("never change the main compiler-ready count", text)
        self.assertIn("do not show that any ISO vertex shader draws correctly", text)
        self.assertEqual(vertex_layout_view({}), "")

    def test_neutral_records_do_not_change_the_main_compiler_count(self):
        base = {"modules": [{"id": "vs:a", "stage": "vs", "sha256": "a", "checks": {s: {"status": "unknown"} for s in STAGES}}],
                "references": [], "tags": []}
        base["modules"][0]["checks"]["translation"]["returncode"] = 6
        before = offline_summary(copy.deepcopy(base))
        base.update(result_with([{"base_id": "vs:a", "checks": {s: {"status": "pass"} for s in STAGES}}]))
        after = offline_summary(base)
        self.assertEqual((before["compiler_ready"], before["compiler_unknown"]), (after["compiler_ready"], after["compiler_unknown"]))
        self.assertEqual(after["unknown_reasons"], {"runtime vertex layout": 1})

    def test_changed_patched_microcode_withdraws_the_neutral_claim(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            microcode, log, out = root / "m.vs", root / "log", root / "out"
            for p, content in ((microcode, b"patched"), (log, b"log"), (out, b"output")):
                p.write_bytes(content)
            checks = {s: {"status": "pass", "log": str(log), "log_sha256": hash_file(log), "output": str(out), "output_sha256": hash_file(out)}
                      for s in STAGES}
            record = {"id": "vs:p", "stage": "vs", "sha256": hash_file(microcode), "path": str(microcode), "base_id": "vs:a", "checks": checks}
            result = {"modules": [], "references": [], "tags": [], **result_with([record])}
            verify_offline_artifacts(result)
            self.assertTrue(all(c["status"] == "pass" for c in record["checks"].values()))
            microcode.write_bytes(b"tampered")
            verify_offline_artifacts(result)
            self.assertTrue(all(c["status"] == "unknown" for c in record["checks"].values()))


if __name__ == "__main__":
    unittest.main()
