import json
from pathlib import Path
import tempfile
import unittest
from .hdr_resolve import attach_resolve, attach_regions, verify_resolve, verify_record, resolve_view
from .iso import hash_file, InventoryError

class ResolveEvidenceTests(unittest.TestCase):
    def manifest(self, root):
        source=root/'source';source.write_text('contract');refs={str(source):hash_file(source)}
        checks=[]
        for group in ('all_encodings','extended_negative_bias','extended_positive_bias'):
            for variant in ('original','corrected'):
                for route in ('vulkan','metal'):
                    bad=(2048 if group=='all_encodings' else 65536) if variant=='original' and route=='vulkan' else 0
                    checks.append(dict(group=group,variant=variant,route=route,rows=65536,mismatch_rows=bad,expected_mismatch_rows=bad,nonextended_mismatch_rows=0,status='pass'))
        result=dict(schema='rosette-hdr-resolve-v1',status='pass',checks=checks,
                    kernels=[dict(name=f'kernel{i}',status='pass',unpacks=48,pe_offset=100,observed=i<5) for i in range(10)],
                    commands=[dict(returncode=0)],source_hashes=refs,tool_hashes=refs,artifact_hashes=refs)
        path=root/'manifest.json';path.write_text(json.dumps(result));return path,source,result

    def test_expected_failure_is_separate_and_tampering_withdraws_counts(self):
        with tempfile.TemporaryDirectory() as d:
            path,source,result=self.manifest(Path(d));s={'ledger':[]}
            self.assertEqual(attach_resolve(s,path)['status'],'verified')
            self.assertIn('2,048',resolve_view(s));self.assertIn('not yet proven',resolve_view(s))
            self.assertEqual(s['ledger'],[])
            source.write_text('changed')
            self.assertEqual(verify_resolve(s)['status'],'unknown')
            self.assertNotIn('<b>2,048</b>',resolve_view(s))
            self.assertEqual(s['ledger'],[])

    def test_incomplete_or_false_baseline_claim_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            path,_,result=self.manifest(Path(d))
            result['checks'][0]['mismatch_rows']=0;path.write_text(json.dumps(result))
            with self.assertRaises(InventoryError):attach_resolve({},path)
            result['checks']=result['checks'][:-1];path.write_text(json.dumps(result))
            with self.assertRaises(InventoryError):attach_resolve({},path)

    def test_embedded_snapshot_changes_are_withdrawn(self):
        with tempfile.TemporaryDirectory() as d:
            path,_,_=self.manifest(Path(d));s={};attach_resolve(s,path)
            s['hdr_resolve']['result']['kernels'][0]['observed']=False
            self.assertEqual(verify_resolve(s)['status'],'unknown')

    def test_region_bounds_and_changed_image_are_refused(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);image=root/'image.png';image.write_bytes(b'image');refs={str(image):hash_file(image)}
            a=dict(width=320,height=180,white_samples=8,red_samples=0,white_percent=0.01,red_percent=0,regions=[dict(box=[1,1,2,4])])
            result=dict(schema='rosette-orb-regions-v1',scope='coarse <samples>',source_hashes=refs,tool_hashes=refs,
                        images=[dict(path=str(image),sha256=hash_file(image),raw=str(image),raw_sha256=hash_file(image),log=str(image),log_sha256=hash_file(image),returncode=0,analysis=a)])
            path=root/'manifest.json';path.write_text(json.dumps(result));s={};attach_regions(s,path)
            self.assertIn('coarse &lt;samples&gt;',resolve_view(s));image.write_bytes(b'changed')
            self.assertEqual(verify_record(s['orb_regions'])['status'],'unknown')
            self.assertNotIn('assets/orb-region-0.png',resolve_view(s))
            a['regions'][0]['box']=[319,1,2,4];path.write_text(json.dumps(result))
            with self.assertRaises(InventoryError):attach_regions({},path)

    def test_coarse_region_mask_has_independent_counts(self):
        import importlib.util
        path=Path(__file__).resolve().parents[1]/'vulkan/map_orb_images.py'
        spec=importlib.util.spec_from_file_location('map_orb',path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        result=module.classify(bytes([255,255,255])*8+bytes([255,0,0])*8,8,2)
        self.assertEqual((result['white_samples'],result['red_samples']),(8,8))
        self.assertEqual(result['regions'][0]['box'],[0,0,8,1])
        self.assertEqual(result['white_percent'],50)
