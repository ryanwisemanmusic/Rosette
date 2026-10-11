"""HDR oracle edge cases and integrity; no graphics asset promotion."""
import json
from pathlib import Path
import tempfile
import struct
import unittest

from vulkan.check_hdr_float16 import bits, pack, value
from .iso import InventoryError, hash_file
from .test_run_view import parsed
from .white_orbs import GROUPS, attach_hdr, attach_video, verify_hdr, verify_video, white_orb_view
from .evidence import spirv_info


class HDROracleTests(unittest.TestCase):
    def test_extended_exponent_and_signed_zero_hand_values(self):
        self.assertEqual([value(h) for h in (0x0001, 0x03ff, 0x0400, 0x3c00, 0x7bff, 0x7c00, 0x7e00, 0x7fff)],
                         [2**-24, 1023*2**-24, 2**-14, 1, 65504, 65536, 98304, 131008])
        self.assertEqual(bits(value(0x8000)), 0x80000000)
        self.assertEqual(value(0xffff), -131008)

    def test_independent_ties_saturation_and_nan(self):
        for number, expected in [(1+2**-11, 0x3c00), (1+3*2**-11, 0x3c02),
                                 (2**-25, 0), (3*2**-25, 2), (200000, 0x7fff), (-200000, 0xffff)]:
            self.assertEqual(pack(bits(number)), expected)
        for raw, expected in [(0x7f800000, 0x7fff), (0xff800000, 0xffff),
                              (0x7fc00000, 0), (0xffa00001, 0), (0x80000000, 0x8000)]:
            self.assertEqual(pack(raw), expected)


class WhiteOrbEvidenceTests(unittest.TestCase):
    def fixture(self, root):
        proof = root/'proof.log'
        proof.write_text('safe proof')
        ref = {str(proof): hash_file(proof)}
        checks = [dict(variant=v, path=p, group=g, rows=rows, bad_decode_x=0, bad_decode_y=0,
                       bad_pack=0, bad_roundtrip=0, status='pass')
                  for v in ('original', 'rewritten') for p in ('vulkan', 'metal') for g,rows in GROUPS.items()]
        logs = 'VULKAN guards=intact input=unchanged\nMETAL device=test guards=intact input=unchanged rows=101583'
        result = dict(schema='rosette-hdr-float16-v1', status='pass', rows=sum(GROUPS.values()), checks=checks,
                      ordinary_ieee_half_decode_mismatches=2048,
                      commands=[dict(returncode=0, log=str(proof), sha256=hash_file(proof))],
                      source_hashes=ref, tool_hashes=ref, artifact_hashes=ref,
                      device_logs={'original': logs, 'rewritten': logs})
        manifest = root/'manifest.json'
        manifest.write_text(json.dumps(result))
        return manifest, proof, result

    def test_all_claims_withdrawn_on_changed_oracle_or_output(self):
        with tempfile.TemporaryDirectory() as d:
            manifest, proof, result = self.fixture(Path(d))
            snapshot = {'ledger': []}
            self.assertEqual(attach_hdr(snapshot, manifest)['passes_by_path'], {'vulkan':8, 'metal':8})
            self.assertIn('not connected to live FSI', white_orb_view(snapshot))
            self.assertEqual(snapshot['ledger'], [])
            proof.write_text('changed')
            self.assertEqual(verify_hdr(snapshot)['passes_by_path'], {'vulkan':0, 'metal':0})
            self.assertIn('claims withdrawn', white_orb_view(snapshot))

    def test_omitted_cases_and_false_passing_claims_refused(self):
        with tempfile.TemporaryDirectory() as d:
            manifest, proof, result = self.fixture(Path(d))
            result['checks'][0]['bad_pack'] = 1
            manifest.write_text(json.dumps(result))
            with self.assertRaises(InventoryError): attach_hdr({}, manifest)
            result['checks'][0]['bad_pack'] = 0
            result['checks'].pop()
            manifest.write_text(json.dumps(result))
            with self.assertRaises(InventoryError): attach_hdr({}, manifest)

    def test_sampled_view_gamma_capture_and_settings_not_inferred(self):
        run = parsed([
            'xenia_gpu_render_settings = render_target_path_vulkan=fsi readback_resolve=fast',
            'BRIGHTNESS SAMPLED RGB: frame=3072 stage=swap_texture mean_rgb=254/183/158 max_rgb=255/255/255; text',
            'BRIGHTNESS SAMPLE VIEW: frame=3072 stage=swap_texture components=5/0/3/2 known=true; text',
            'GAMMA CHANNEL CONTRACT: frame=3072 full_table_channel_pairs_differ=0; text',
            'GAMMA CHANNEL CONTRACT: frame=3072 full_table_channel_pairs_differ=1; text',
            'FRAME CAPTURE SUMMARY: enabled=false saved=0; text',
            'VULKAN CAPTURE STATUS: state=not_requested capture_file=<unset>; text',
        ])
        self.assertEqual(run['sampled_rgb'][0]['mean_rgb'], '254/183/158')
        text = white_orb_view({'run': run})
        self.assertIn('1 equal-channel ramps, 1 unequal-channel ramps', text)
        self.assertIn('occlusion_query=unknown', text)
        self.assertIn('state not_requested', text)
        self.assertIn('not proof of the binding', text)
        self.assertIn('254/183/158', text)


class VideoAndCensusTests(unittest.TestCase):
    def test_reviewed_video_hash_and_frame_change_withdraw_attribution(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);video=root/'recording.mov';frame=root/'frame.png';log=root/'extract.log'
            video.write_bytes(b'video');frame.write_bytes(b'frame');log.write_text('bounded CPU extraction')
            ref={str(log):hash_file(log)}
            result=dict(schema='rosette-white-orb-video-v1', duration=500, video=str(video),video_sha256=hash_file(video),
                        source_hashes=ref,tool_hashes=ref,
                        frames=[dict(seconds=220,note="Glare <observation>",path=str(frame),sha256=hash_file(frame))],
                        commands=[dict(returncode=0,log=str(log),sha256=hash_file(log))])
            manifest=root/'manifest.json';manifest.write_text(json.dumps(result))
            snapshot={'ledger':[]}
            self.assertEqual(attach_video(snapshot,manifest)['status'],'verified_extraction')
            # Rendering the section requires a run or HDR record as context.
            snapshot['run']={'run_id':'example'}
            self.assertIn('assets/white-orb-0.png',white_orb_view(snapshot))
            self.assertIn('&lt;observation&gt;',white_orb_view(snapshot))
            frame.write_bytes(b'changed')
            self.assertEqual(verify_video(snapshot)['status'],'unknown')
            self.assertNotIn('assets/white-orb-0.png',white_orb_view(snapshot))
            self.assertEqual(snapshot['ledger'],[])

    def test_half_census_requires_the_correct_extended_instruction_set(self):
        name=struct.unpack('<4I',b'GLSL.std.450\0\0\0\0')
        words=[0x07230203,0x10000,0,32,0,(6<<16)|11,1,*name,
               (6<<16)|12,2,3,1,58,4,(6<<16)|12,2,5,1,62,4,
               (6<<16)|12,2,6,9,58,4] # Unrelated instruction set must not count.
        info=spirv_info(struct.pack(f'<{len(words)}I',*words))
        self.assertEqual(info['half_conversion_ops'],{'pack_half2x16':1,'unpack_half2x16':1})
