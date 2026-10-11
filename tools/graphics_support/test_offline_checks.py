"""Offline checks stay offline: parsed from the logs they came from, withdrawn when those change."""
from pathlib import Path
import tempfile
import unittest

from .offline_checks import checks_view, parse_oracles, parse_zpd, record_checks, verify_checks

ZPD = """ZPD aa.spv msaa=1x depth=0 counter=5120 covered_samples=5120 ratio=1.0000
ZPD aa.spv msaa=4x depth=1 counter=20480 covered_samples=20480 ratio=1.0000
ZPD bb.spv msaa=1x depth=0 counter=0 covered_samples=5120 ratio=0.0000
ZPD bb.spv msaa=4x depth=1 counter=40960 covered_samples=20480 ratio=2.0000
"""
ORACLE = ("operand roles: checked 239 three-register VEX forms, 0 differ\n"
          "memory operands: checked 577 forms with a ModR/M memory operand, 0 differ\n")


class OfflineCheckTests(unittest.TestCase):
    def test_zpd_counts_split_exact_zero_and_over(self):
        zpd = parse_zpd(ZPD)
        self.assertEqual(zpd['modules'], 2)
        self.assertEqual(zpd['configs']['1x'], {'exact': 1, 'zero': 1, 'other': 0, 'over': 0})
        self.assertEqual(zpd['configs']['4x'], {'exact': 1, 'zero': 0, 'other': 1, 'over': 1})

    def test_oracle_summaries_are_read_from_the_zig_test_output(self):
        self.assertEqual(parse_oracles(ORACLE), {'operand_roles': {'checked': 239, 'differ': 0},
                                                 'memory_operands': {'checked': 577, 'differ': 0}})

    def test_record_is_verified_then_withdrawn_when_a_log_changes(self):
        with tempfile.TemporaryDirectory() as d:
            zpd, oracle, source = Path(d) / 'zpd.log', Path(d) / 'zig.log', Path(d) / 'probe.c'
            zpd.write_text(ZPD)
            oracle.write_text(ORACLE)
            source.write_text('probe')
            snapshot = {}
            record_checks(snapshot, zpd, oracle, [source], 'M2 Max, MoltenVK 1.2.7')
            text = checks_view(snapshot)
            self.assertIn('1 of 2 production-rewritten Halo FSI shaders count exactly', text)
            self.assertIn('1 too many', text)
            self.assertIn('239', text)
            self.assertIn('not evidence the orbs are fixed', text)
            source.write_text('edited')
            self.assertEqual(verify_checks(snapshot)['status'], 'unknown')
            self.assertIn('Claims withdrawn', checks_view(snapshot))

    def test_logs_without_the_expected_lines_are_refused(self):
        with tempfile.TemporaryDirectory() as d:
            empty = Path(d) / 'empty.log'
            empty.write_text('nothing')
            with self.assertRaises(Exception):
                record_checks({}, empty, empty, [], '')
            self.assertEqual(checks_view({}), '')


if __name__ == '__main__':
    unittest.main()
