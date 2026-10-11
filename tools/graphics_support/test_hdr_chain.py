"""HDR chain evidence: encoding-aware sampled RGB, probe parsing, and hash withdrawal."""
from pathlib import Path
import tempfile
import unittest

from .hdr_chain import CHAIN, IEEE, chain_view, decode_7e3, front_buffer, parse_probe, record_chain, verify_chain
from .iso import InventoryError


def probe_log(mode, overrides=None):
    values = dict(IEEE)
    values.update(overrides or {})
    lines = [f"mode=MVK_CONFIG_FAST_MATH_ENABLED={mode}"]
    lines += [f"{name:<24} {value:<14g} bits=0x00000000" for name, value in values.items()]
    return "\n".join(lines) + "\n"


RUN = ("info(elf): PE64 FRONT BUFFER: swaps_described=891 format=k_2_10_10_10_AS_16_16_16_16 (raw 54) endianness=0\n"
       "macho-processor: FSI WHITE FRAME: transition=1 frame=896 swapchain_white=895680/921600 guest_output=near_white white=716800/737280 swap_texture=near_white white=716800/737280; x\n"
       "macho-processor: FSI WHITE SOURCE ENCODING: frame=896 stage=pre_gamma_swap_texture encoding=unorm_10_10_10_2 guest_frontbuffer_format=k_2_10_10_10_AS_16_16_16_16(54) host_vk_format=64 status=read; x\n"
       "macho-processor: BRIGHTNESS LADDER:   stage=swap_texture image=0x1 format=64 extent=1152x640 channels=raw_storage mean_rgb=189/88/89 max_rgb=248/248/248 visible_gt16=1 bright_gt64=1 white_rgb_ge240=12/737280 rgb_different=1 frame=1152\n"
       "macho-processor: BRIGHTNESS LADDER:   stage=guest_output image=0x2 format=64 extent=1152x640 channels=raw_storage mean_rgb=182/31/31 max_rgb=238/238/238 visible_gt16=1 bright_gt64=1 white_rgb_ge240=0/737280 rgb_different=1 frame=1152\n"
       "macho-processor: BRIGHTNESS SAMPLED RGB: frame=896 stage=swap_texture mean_rgb=248/248/248 max_rgb=255/255/255; x\n"
       "macho-processor: BRIGHTNESS SAMPLED RGB: frame=896 stage=guest_output mean_rgb=247/248/248 max_rgb=255/255/255; x\n"
       "macho-processor: GAMMA CHANNEL CONTRACT: frame=896 ramp_format=81 full_table_channel_pairs_differ=0; x\n"
       "macho-processor: BRIGHTNESS SAMPLED RGB: frame=1152 stage=swap_texture mean_rgb=189/88/89 max_rgb=248/248/248; x\n"
       "macho-processor: BRIGHTNESS SAMPLED RGB: frame=1152 stage=guest_output mean_rgb=182/31/31 max_rgb=238/238/238; x\n"
       "macho-processor: GAMMA CHANNEL CONTRACT: frame=1152 ramp_format=81 full_table_channel_pairs_differ=0; x\n")


class HdrChainTests(unittest.TestCase):
    def test_7e3_landmarks(self):
        self.assertEqual(decode_7e3(0x180), 1.0)
        self.assertEqual(decode_7e3(0x3FF), 31.875)
        self.assertEqual(decode_7e3(0x000), 0.0)
        self.assertEqual(decode_7e3(0x07F), 127 / 128 * 0.25)

    def test_unorm_front_buffer_is_never_reinterpreted_as_7e3(self):
        rows = front_buffer(RUN)
        self.assertEqual(len(rows), 2)
        white, red = rows
        self.assertEqual(white['frame'], 896)
        self.assertEqual(white['encoding'], 'unorm_10_10_10_2')
        self.assertEqual(white['pre_gamma_mean_rgb_8bit'], [248, 248, 248])
        self.assertEqual(white['post_gamma_mean_rgb_8bit'], [247, 248, 248])
        self.assertIsNone(white['seven_e3_decode'])
        self.assertEqual(white['white_transition']['swap_texture']['white_pixels'], 716800)
        self.assertEqual(red['frame'], 1152)
        self.assertAlmostEqual(red['pre_gamma_red_over_green'], 189 / 88, places=3)
        self.assertAlmostEqual(red['post_gamma_red_over_green'], 182 / 31, places=3)
        self.assertEqual(red['gamma_channel_pairs_differ'], 0)
        self.assertEqual(red['pre_gamma_white_ge240'], {'pixels': 12, 'total': 737280})

    def test_7e3_format_does_not_decode_lossy_sampled_bytes(self):
        text = ("info(elf): PE64 FRONT BUFFER: swaps_described=1 format=k_2_10_10_10_FLOAT_EDRAM (raw 63)\n"
                "macho-processor: BRIGHTNESS SAMPLED RGB: frame=1 stage=swap_texture mean_rgb=96/96/96 max_rgb=96/96/96\n")
        row, = front_buffer(text)
        self.assertEqual(row['encoding'], 'xenos_7e3')
        self.assertIsNone(row['pre_gamma_mean_unorm'])
        self.assertIsNone(row['seven_e3_decode'])

    def test_missing_front_buffer_format_stays_unknown(self):
        row, = front_buffer("BRIGHTNESS SAMPLED RGB: frame=1 stage=swap_texture mean_rgb=96/96/96 max_rgb=96/96/96\n")
        self.assertEqual(row['encoding'], 'unknown')
        self.assertIsNone(row['pre_gamma_mean_unorm'])

    def test_probe_lines_parse_by_name(self):
        parsed = parse_probe(probe_log(1, {'NaN!=NaN': 0}))
        self.assertEqual(parsed['mode'], 1)
        self.assertEqual(parsed['results']['NaN!=NaN'], 0.0)
        self.assertEqual(parsed['results']['legacy_mul(0,inf)'], 0.0)

    def test_record_verified_then_withdrawn_and_requires_both_modes(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            disasm = root / 'disasm'
            disasm.mkdir()
            for stem, _stage, _text in CHAIN:
                (disasm / f'{stem}.0000.txt').write_text('exec')
            mode0, mode1, run = root / 'mode-0.log', root / 'mode-1.log', root / 'run.log'
            mode0.write_text(probe_log(0))
            mode1.write_text(probe_log(1, {'NaN!=NaN': 0, 'isnan(inf-inf)': 0}))
            run.write_text(RUN)
            snapshot = {}
            with self.assertRaises(InventoryError):
                record_chain(snapshot, [mode0], disasm, run, [], '')
            status = record_chain(snapshot, [mode0, mode1], disasm, run, [], 'M2 Max, MoltenVK 1.2.7')
            self.assertEqual(status['status'], 'verified')
            fast = snapshot['hdr_chain']['fast_math']
            self.assertTrue(fast['production_matches_ieee'])
            self.assertTrue(fast['setting_effective'])
            self.assertEqual(snapshot['hdr_chain']['run_frontbuffer_format']['code'], 54)
            text = chain_view(snapshot)
            self.assertIn('reaches Metal', text)
            self.assertIn('Final composite', text)
            self.assertIn('never decoded as 7e3', text)
            self.assertIn('not to the pass, shader, constant, or resource', text)
            mode0.write_text(probe_log(0, {'legacy_mul(0,inf)': 1}))
            self.assertEqual(verify_chain(snapshot)['status'], 'unknown')
            self.assertIn('Claims withdrawn', chain_view(snapshot))


if __name__ == '__main__':
    unittest.main()
