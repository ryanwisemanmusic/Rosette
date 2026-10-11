"""Hand-calculated contract vectors; these tests never use the GPU."""
import unittest
from .check_support import (bc4_block_words, bc4_palette, bc45_oracle, color565, dxt_oracle, dxt_fixture)


class DxtOracleTests(unittest.TestCase):
    selectors = sum((i%4)*(4**i) for i in range(16))

    def test_565_primaries_and_bit_replication(self):
        self.assertEqual(color565(0xf800),(255,0,0))
        self.assertEqual(color565(0x07e0),(0,255,0))
        self.assertEqual(color565(0x001f),(0,0,255))
        self.assertEqual(color565((4<<11)|(16<<5)|8),(33,65,66))

    def test_dxt1_opaque_red_blue(self):
        row=bytes((255,0,0,255, 0,0,255,255, 170,0,85,255, 85,0,170,255))
        self.assertEqual(dxt_oracle([(0x001ff800,self.selectors)],4,4,1,1),row*4)

    def test_dxt1_punchthrough_and_equal(self):
        row=bytes((0,0,255,255, 255,0,0,255, 127,0,127,255, 0,0,0,0))
        self.assertEqual(dxt_oracle([(0xf800001f,self.selectors)],4,4,1,1),row*4)
        row=bytes((0,255,0,255, 0,255,0,255, 0,255,0,255, 0,0,0,0))
        self.assertEqual(dxt_oracle([(0x07e007e0,self.selectors)],4,4,1,1),row*4)

    def test_dxt3_keeps_four_colors_and_all_alpha_nibbles(self):
        a=sum(i*(16**i) for i in range(16))
        data=dxt_oracle([(a&0xffffffff,a>>32,0xf800001f,self.selectors)],4,4,1,3)
        self.assertEqual(data[:16],bytes((0,0,255,0, 255,0,0,17, 85,0,170,34, 170,0,85,51)))
        self.assertEqual(list(data[3::4]),[i*17 for i in range(16)])

    def test_dxt5_six_and_eight_step_alphas(self):
        codes=sum((i%8)*(8**i) for i in range(16))
        for a0,a1,expected in ((255,0,[255,0,218,182,145,109,72,36]),(0,255,[0,255,51,102,153,204,0,255]),(103,103,[103]*6+[0,255])):
            packed=a0|(a1<<8)|(codes<<16)
            data=dxt_oracle([(packed&0xffffffff,packed>>32,0xf800001f,self.selectors)],4,4,1,5)
            self.assertEqual(list(data[3::4]),expected*2)

    def test_cropped_padded_rows_do_not_borrow_padding_blocks(self):
        blocks=dxt_fixture(1,6,"greater")
        padded=dxt_oracle(blocks,7,5,3,1)
        compact=dxt_oracle([blocks[i] for i in (0,1,3,4)],7,5,2,1)
        self.assertEqual(padded,compact)
        self.assertEqual(len(padded),7*5*4)


class Bc45OracleTests(unittest.TestCase):
    def test_bc4_eight_step_six_step_and_equal_palettes(self):
        self.assertEqual(bc4_palette(255,0),[255,0,218,182,145,109,72,36])
        self.assertEqual(bc4_palette(0,255),[0,255,51,102,153,204,0,255])
        self.assertEqual(bc4_palette(103,103),[103]*6+[0,255])

    def test_dxt5a_reads_each_selector_in_raster_order(self):
        data=bc45_oracle([bc4_block_words(255,0,0)],4,4,1,1)
        self.assertEqual(list(data),[255,0,218,182,145,109,72,36]*2)

    def test_dxn_uses_the_first_half_for_red_and_second_for_green(self):
        words=bc4_block_words(255,0,0)+bc4_block_words(0,255,0)
        data=bc45_oracle([words],4,4,1,2)
        self.assertEqual(list(data[0::2]),[255,0,218,182,145,109,72,36]*2)
        self.assertEqual(list(data[1::2]),[0,255,51,102,153,204,0,255]*2)

    def test_dxt3a_expands_every_alpha_nibble(self):
        nibbles=sum(i*(16**i) for i in range(16))
        data=bc45_oracle([(nibbles&0xffffffff,nibbles>>32)],4,4,1,3)
        self.assertEqual(list(data),[i*17 for i in range(16)])

    def test_cropped_padded_rows_do_not_borrow_padding_blocks(self):
        blocks=[bc4_block_words(i*17%256,(i*31+9)%256,i) for i in range(6)]
        padded=bc45_oracle(blocks,7,5,3,1)
        compact=bc45_oracle([blocks[i] for i in (0,1,3,4)],7,5,2,1)
        self.assertEqual(padded,compact)
        self.assertEqual(len(padded),7*5)


if __name__=="__main__":unittest.main()
