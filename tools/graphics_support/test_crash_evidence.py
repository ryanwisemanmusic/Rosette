from pathlib import Path
import struct
import tempfile
import unittest

from .evidence import parse_log, shader_archive, spirv_info


class CrashEvidenceTests(unittest.TestCase):
    def test_boundary_candidates_are_prior_successes_and_native_counts_are_observed(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'run.log'
            path.write_text('run_id = synthetic\nbuild_identity_sha256 = '+ 'a'*64 + '\n' +
                'Vulkan FSI PIPELINE: result=0 real=0x123 pipeline_hash=0x11 shader_hash=0x55 stages=4 topology=10\n' +
                'Vulkan FSI PIPELINE: result=-3 real=0x0 pipeline_hash=0x22 shader_hash=0x66\n' +
                'VULKAN FSI WATCHDOG failed: pipelines(first/last)=0x11/0x22\n' +
                'Vulkan FSI PIPELINE: result=0 real=0x234 pipeline_hash=0x22 shader_hash=0x77\n' +
                'NATIVE METAL TEXTURES: pipelines=1 dispatches(ctx1/dxt1/dxt3/dxt5)=0/0/0/0 declined=995\n')
            r=parse_log(path)
            self.assertEqual(len(r['failure_candidates']),1)
            self.assertEqual(r['failure_candidates'][0]['pipeline']['shader_hash'],0x55)
            self.assertIn('not proof',r['failure_candidates'][0]['scope'])
            self.assertEqual(r['snapshots']['native_textures']['declined'],995)

    def test_targeted_archive_checks_filenames_and_content(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            data=struct.pack('<8I',0x07230203,0x10500,0,3,0,(3<<16)|14,0,1)
            f=spirv_info(data)['fingerprint']
            (root/f'module-123-{f:x}.guest.spv').write_bytes(data)
            (root/f'module-456-{f:x}.native.spv').write_bytes(data)
            (root/'unclassified.spv').write_bytes(b'bad')
            r=shader_archive(root,{'shaders':[{'guest':0x123,'spirv_hash':f}]},{f})
            self.assertEqual(r['files_seen'],1)
            self.assertEqual(r['matched_fsi_guest_hashes'],1)
            self.assertIn('not the complete run archive',r['scope'])
            (root/f'module-123-{f:x}.guest.spv').write_bytes(b'changed')
            r=shader_archive(root,None,{f})
            self.assertEqual(len(r['unreadable']),1)

