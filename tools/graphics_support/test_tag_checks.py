import json
from pathlib import Path
import struct
import tempfile
import unittest

from .iso import InventoryError, hash_file
from .tag_checks import inspect, layout, tag_summary, tag_view
from .test_tracker import fixture
from .coverage import summarize


class Reader:
    magic = 0x40000000
    def __init__(self, data): self.data = data
    def read(self, offset, size):
        if offset < 0 or offset + size > len(self.data): raise InventoryError('outside owning map')
        return self.data[offset:offset + size]
    def pointer(self, ptr, size): return self.read(ptr - self.magic, size)


class TagChecksTests(unittest.TestCase):
    def example(self, datum=0x10000, cls=b'bitm', value=2.0):
        data = bytearray(80)
        struct.pack_into('>II', data, 0, 1, Reader.magic + 32)
        data[32:36] = cls
        struct.pack_into('>I', data, 44, datum)
        struct.pack_into('>f', data, 48, value)
        schema = {'size': 12, 'fields': [{'kind': 'tagblock', 'offset': 0, 'size': 20, 'name': 'Parts', 'fields': [
            {'kind': 'tagRef', 'offset': 0, 'name': 'Bitmap'}, {'kind': 'float32', 'offset': 16, 'components': 1, 'name': 'Brightness'}]}]}
        asset = {'id': 'source', 'name': '<name>', 'class': 'effe', 'map': 'map', 'metadata_offset': 0}
        tags = [{'class': 'bitm', 'parents': ('xxxx','yyyy'), 'salt': 1}]
        return Reader(data), asset, schema, tags, {('map',0): 'target'}

    def test_nested_reference_resolves_and_keeps_numeric_value(self):
        r = inspect(*self.example())
        self.assertEqual(r['status'], 'pass')
        self.assertEqual(r['references'][0]['target_asset_id'], 'target')
        self.assertEqual(r['numeric_fields'][0]['values'], [2.0])
        self.assertEqual(r['references'][0]['offset'], 32)

    def test_null_and_salt_class_and_index_mismatches(self):
        self.assertEqual(inspect(*self.example(0xffffffff))['references'][0]['status'], 'null')
        for datum, cls in ((0x20000,b'bitm'),(0x10001,b'bitm'),(0x10000,b'ligh')):
            r = inspect(*self.example(datum,cls))
            self.assertEqual(r['status'], 'needs_review')
            self.assertEqual(r['references'][0]['status'], 'unresolved')
        self.assertEqual(inspect(*self.example(0x10000,b'xxxx'))['status'], 'pass')

    def test_bad_extents_counts_and_cycles_remain_unknown(self):
        for ptr, count in ((Reader.magic + 76,1),(Reader.magic + 32,8193),(0,1),(Reader.magic,1)):
            args = self.example(); data = bytearray(args[0].data);struct.pack_into('>II',data,0,count,ptr)
            args[0].data = data
            self.assertEqual(inspect(*args)['status'], 'unknown')

    def test_nonfinite_metadata_is_review_not_render_failure(self):
        r = inspect(*self.example(value=float('nan')))
        self.assertEqual(r['status'], 'needs_review')
        self.assertEqual(r['numeric_fields'][0]['values'],[None])
        json.dumps(r,allow_nan=False)

    def test_layout_entity_and_outside_fields_refused(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'effe.xml'
            for text in ('<!DOCTYPE plugin><plugin/>','<plugin game="Halo3" baseSize="12"><tagRef name="Bad" offset="0"/></plugin>'):
                p.write_text(text)
                with self.assertRaises(InventoryError): layout(p)

    def test_evidence_staleness_and_no_render_promotion(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'evidence';p.write_text('tool and schema fixture')
            result={'assets':[inspect(*self.example())],'tool':str(p),'tool_sha256':hash_file(p),
                    'layouts':{},'scope':'synthetic selected fields'}
            manifest=Path(d)/'manifest.json';manifest.write_text(json.dumps(result))
            snapshot=fixture();snapshot['tag_checks']={'manifest':str(manifest),'sha256':hash_file(manifest),'result':result}
            self.assertEqual(tag_summary(snapshot)['groups']['effe']['pass'],1)
            self.assertIn('&lt;name&gt;',tag_view(snapshot))
            self.assertEqual(summarize(snapshot)['coverage']['all']['confirmed'],0)
            p.write_text('changed')
            self.assertEqual(tag_summary(snapshot)['groups']['effe']['pass'],0)
            self.assertEqual(tag_summary(snapshot)['groups']['effe']['unknown'],1)

