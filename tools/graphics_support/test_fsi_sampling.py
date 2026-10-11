"""Semantic proof integrity does not confer ISO or runtime rendering coverage."""
import json
from pathlib import Path
import tempfile
import unittest

from .fsi_sampling import attach_sampling, sampling_view, verify_sampling
from .iso import InventoryError, hash_file


class SamplingEvidenceTests(unittest.TestCase):
    def fixture(self, root):
        artifact = root / 'probe.txt'
        artifact.write_text('bounded probe evidence')
        cases = []
        for v in (0, 1):
            for o in (0, 1):
                for s in (1, 2, 4):
                    for m in (5, 15):
                        for d in (1, 7):
                            cases.append(dict(normalized=v, order=o, samples=s, mask=m, draws=d,
                                              xy_bad=int(not v and s > 1), z_bad=0, z_parity_bad=0, count_bad=0,
                                              invocation_bad=0, guards='intact'))
        result = dict(schema='rosette-fsi-pixel-frequency-v1', status='pass', device_profile='test device',
                      cases=cases, source_hashes={str(artifact): hash_file(artifact)},
                      tool_hashes={str(artifact): hash_file(artifact)}, artifact_hashes={str(artifact): hash_file(artifact)},
                      commands=[dict(returncode=0, log=str(artifact), sha256=hash_file(artifact))])
        path = root / 'manifest.json'
        path.write_text(json.dumps(result))
        return path, artifact, result

    def test_unchanged_proof_then_changed_source_withdraws_all_counts(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest, source, result = self.fixture(Path(directory))
            snapshot = {'ledger': [], 'iso': {'assets': []}}
            self.assertEqual(attach_sampling(snapshot, manifest)['pass'], 24)
            text = sampling_view(snapshot)
            self.assertIn('does not prove the cause', text)
            self.assertIn('Depth unverified', text)
            self.assertEqual(snapshot['ledger'], [])
            source.write_text('changed')
            self.assertEqual(verify_sampling(snapshot)['pass'], 0)
            self.assertIn('Claims withdrawn', sampling_view(snapshot))

    def test_missing_negative_control_or_failed_semantic_check_refuses_success(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest, source, result = self.fixture(Path(directory))
            result['cases'][0]['invocation_bad'] = 1
            manifest.write_text(json.dumps(result))
            with self.assertRaises(InventoryError):
                attach_sampling({}, manifest)
            result['cases'][0]['invocation_bad'] = 0
            result['cases'].pop()
            manifest.write_text(json.dumps(result))
            with self.assertRaises(InventoryError):
                attach_sampling({}, manifest)

    def test_runtime_frequency_counts_are_independent_of_rendering_proof(self):
        from .test_run_view import parsed
        run = parsed(['macho-processor: VULKAN FSI PIXEL FREQUENCY: enabled=true moltenvk=true normalized=235 explicit_sample_preserved=0 complex_preserved=0 allocation_failures=0 driver_rejections=0; text'])
        self.assertEqual(run['snapshots']['fsi_pixel_frequency']['normalized'], 235)
        self.assertEqual(run['snapshots']['fsi_pixel_frequency']['driver_rejections'], 0)
        with tempfile.TemporaryDirectory() as directory:
            manifest, source, result = self.fixture(Path(directory))
            snapshot = {'run': run}
            attach_sampling(snapshot, manifest)
            self.assertIn('235 corrected modules logged in this run', sampling_view(snapshot))
            self.assertNotIn('predates this correction', sampling_view(snapshot))


if __name__ == '__main__':
    unittest.main()
