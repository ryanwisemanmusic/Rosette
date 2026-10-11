"""Progress records are exact counts against a hashed earlier report, never rendering claims."""
import json
from pathlib import Path
import tempfile
import unittest

from .iso import InventoryError
from .iso_offline import STAGES, offline_summary
from .progress import attach_progress, progress_view
from .test_iso_offline import evidence


def snapshot_with(status, run_id):
    result = evidence()
    result["modules"][0]["checks"] = {s: {"status": status} for s in STAGES}
    result["summary"] = offline_summary(result)
    return {"iso": {"sha256": "b" * 64}, "iso_offline": result, "run": {"run_id": run_id, "snapshots": {}}}


class ProgressTests(unittest.TestCase):
    def write(self, root, snapshot):
        path = root / "previous.json"
        path.write_text(json.dumps(snapshot))
        return path

    def test_gained_programs_are_counted_exactly_and_labelled_as_testing(self):
        with tempfile.TemporaryDirectory() as d:
            previous = self.write(Path(d), snapshot_with("unknown", "old-run"))
            current = snapshot_with("pass", "new-run")
            record = attach_progress(current, previous)
            self.assertEqual((record["compiler"]["gained"], record["compiler"]["lost"]), (1, 0))
            self.assertEqual((record["compiler"]["ready_before"], record["compiler"]["ready_after"]), (0, 1))
            text = progress_view(current)
            self.assertIn("old-run", text)
            self.assertIn("not shader fixes", text)
            self.assertIn("no rendering coverage changes", text)
            self.assertIn("scene coverage can change the count", text)
            self.assertNotIn("Earlier archive selected failed-group boundary candidates only", text)

    def test_previous_vertex_checks_are_not_mislabeled_as_unrun(self):
        with tempfile.TemporaryDirectory() as d:
            old=snapshot_with('pass','old')
            old['iso_offline']['neutral_vertex_layout']={'summary':{'ready':299,'variants':299}}
            old['iso_offline']['vertex_format_matrix']={'summary':{'ready':176,'variants':176}}
            now=snapshot_with('pass','now')
            attach_progress(now,self.write(Path(d),old))
            text=progress_view(now)
            self.assertIn('299 of 299',text)
            self.assertIn('176 of 176',text)
            self.assertNotIn('not run',text)

    def test_a_different_iso_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            other = snapshot_with("pass", "x")
            other["iso"]["sha256"] = "c" * 64
            with self.assertRaises(InventoryError):
                attach_progress(snapshot_with("pass", "y"), self.write(Path(d), other))

    def test_missing_compiler_evidence_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            bare = {"iso": {"sha256": "b" * 64}}
            with self.assertRaises(InventoryError):
                attach_progress(snapshot_with("pass", "y"), self.write(Path(d), bare))

    def test_view_is_empty_without_a_record(self):
        self.assertEqual(progress_view({}), "")


if __name__ == "__main__":
    unittest.main()
