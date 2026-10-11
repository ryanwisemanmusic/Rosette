import json
from pathlib import Path
import tempfile
import unittest
from .live_metal import attach_live, verify_live, live_view
from .iso import hash_file, InventoryError
from .test_tracker import fixture
from .coverage import summarize

class LiveEvidenceTests(unittest.TestCase):
    def saved(self, root):
        proof=root/'proof';proof.write_text('bounded synthetic evidence')
        manifest=root/'manifest.json'
        sha=hash_file(proof)
        result={'schema':'rosette-live-metal-texture-v1','status':'pass','checks':[{'name':'<synthetic>','status':'pass'}],
                'commands':[{'returncode':0,'log':str(proof),'sha256':sha}], 'source_hashes':{str(proof):sha},'tools':{str(proof):sha},
                'artifact_hashes':{str(proof):sha},'loader_identities':[{'name':'synthetic'}],'xenia_pe':{'path':str(proof),'sha256':sha}}
        manifest.write_text(json.dumps(result));return manifest,proof
    def test_no_iso_promotion_and_html_escapes(self):
        with tempfile.TemporaryDirectory() as d:
            manifest,_=self.saved(Path(d));snapshot=fixture()
            self.assertEqual(attach_live(snapshot,manifest)['pass'],1)
            self.assertEqual(summarize(snapshot)['coverage']['all']['confirmed'],0)
            self.assertIn('&lt;synthetic&gt;',live_view(snapshot))
            self.assertIn('Rebuild needed',live_view(snapshot))
    def test_changed_artifact_withdraws_checks(self):
        with tempfile.TemporaryDirectory() as d:
            manifest,proof=self.saved(Path(d));snapshot=fixture();attach_live(snapshot,manifest)
            proof.write_text('changed');s=verify_live(snapshot)
            self.assertEqual(s['status'],'unknown');self.assertEqual(s['pass'],0)
            self.assertEqual(s['runtime_status'],'not_verified_after_rebuild')
    def test_incomplete_success_refused(self):
        with tempfile.TemporaryDirectory() as d:
            manifest,_=self.saved(Path(d));result=json.loads(manifest.read_text());result['tools']={};manifest.write_text(json.dumps(result))
            with self.assertRaises(InventoryError):attach_live(fixture(),manifest)
