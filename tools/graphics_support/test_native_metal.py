import json
from pathlib import Path
import tempfile
import unittest

from .coverage import summarize
from .iso import InventoryError, hash_file
from .native_metal import attach_native, native_view, texture_contract_summary, verify_native
from .test_tracker import fixture


class NativeEvidenceTests(unittest.TestCase):
    def manifest(self, root):
        proof=root/"proof";proof.write_bytes(b"bounded check")
        ref={str(proof):hash_file(proof)}
        data={"schema":"rosette-native-metal-contracts-v1","status":"pass","scope":"Synthetic components only",
              "device":"<device>","source_hashes":ref,"tools":ref,"artifact_hashes":ref,
              "oracle_script":{"path":str(proof),"sha256":hash_file(proof)},
              "build":[{"returncode":0,"log":str(proof),"log_sha256":hash_file(proof)}],
              "checks":[{"name":"<check>","status":"pass","oracle":"<oracle>","seconds":0.01}]}
        manifest=root/"manifest.json";manifest.write_text(json.dumps(data));return manifest,proof

    def test_native_checks_never_promote_iso_rendering_or_payload_support(self):
        with tempfile.TemporaryDirectory() as d:
            s=fixture();manifest,_=self.manifest(Path(d));result=attach_native(s,manifest)
            self.assertEqual(result["pass"],1)
            self.assertEqual(summarize(s)["coverage"]["all"]["confirmed"],0)
            view=native_view(s)
            self.assertIn("&lt;check&gt;",view)
            self.assertIn("No ISO texture is marked supported",view)
            self.assertIn("standalone components",view)

    def test_changed_missing_or_tampered_native_evidence_withdraws_claims(self):
        for kind in ("changed","missing","snapshot"):
            with self.subTest(kind=kind),tempfile.TemporaryDirectory() as d:
                s=fixture();manifest,proof=self.manifest(Path(d));attach_native(s,manifest)
                if kind=="changed":proof.write_bytes(b"changed")
                if kind=="missing":proof.unlink()
                if kind=="snapshot":s["native_metal"]["result"]["checks"][0]["name"]="tampered"
                result=verify_native(s)
                self.assertEqual((result["pass"],result["unknown"]),(0,1))
                self.assertTrue(result["stale"])

    def test_success_without_provenance_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            manifest,_=self.manifest(Path(d));data=json.loads(manifest.read_text());data["artifact_hashes"]={};manifest.write_text(json.dumps(data))
            with self.assertRaises(InventoryError):attach_native(fixture(),manifest)

    def test_format_census_does_not_certify_iso_pixels_or_untested_decoders(self):
        with tempfile.TemporaryDirectory() as d:
            s=fixture(1);s["iso"]["assets"][0]["subimages"]=[{"format":14},{"format":14},{"format":16}]
            manifest,_=self.manifest(Path(d));data=json.loads(manifest.read_text())
            data["checks"][0]["name"]="DXT1 RGBA8 selectors"
            manifest.write_text(json.dumps(data));attach_native(s,manifest)
            rows={r["name"]:r for r in texture_contract_summary(s)}
            self.assertEqual((rows["DXT1"]["enumerated_subimages"],rows["DXT1"]["pass"]),(2,1))
            self.assertEqual((rows["DXT5"]["enumerated_subimages"],rows["DXT5"]["checks"]),(1,0))
            self.assertTrue(all(r["iso_payload_status"]=="unknown" for r in rows.values()))
            self.assertEqual(summarize(s)["coverage"]["all"]["confirmed"],0)

    def test_stale_decoder_checks_stay_unknown_with_stable_inventory(self):
        with tempfile.TemporaryDirectory() as d:
            s=fixture(1);s["iso"]["assets"][0]["subimages"]=[{"format":15}]
            manifest,proof=self.manifest(Path(d));data=json.loads(manifest.read_text())
            data["checks"][0]["name"]="DXT3 alpha"
            manifest.write_text(json.dumps(data));attach_native(s,manifest)
            proof.write_bytes(b"changed");verify_native(s)
            row=next(r for r in texture_contract_summary(s) if r["name"]=="DXT3")
            self.assertEqual((row["enumerated_subimages"],row["pass"],row["unknown"]),(1,0,1))

    def test_one_failed_decoder_does_not_claim_an_iso_format_failure(self):
        with tempfile.TemporaryDirectory() as d:
            s=fixture();manifest,_=self.manifest(Path(d));data=json.loads(manifest.read_text())
            data["status"]="fail";data["checks"][0].update(name="DXT5 alpha",status="fail")
            manifest.write_text(json.dumps(data));attach_native(s,manifest)
            row=next(r for r in texture_contract_summary(s) if r["name"]=="DXT5")
            self.assertEqual(row["fail"],1)
            self.assertEqual(row["iso_payload_status"],"unknown")
            self.assertEqual(summarize(s)["coverage"]["all"]["known_failure"],0)


if __name__=="__main__":unittest.main()
