"""Extraction boundaries, provenance and conservative compiler accounting."""
import copy
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

from .iso import InventoryError, hash_file
from .iso_offline import CacheReader, PROFILE, STAGES, POLICY, check_module, compare_compilers, compiled_dependency_hashes, extract_program, inspect_vertex_fetches, offline_summary, recover_iso_checks, resume_iso_checks, shader_tag_matrix, verify_offline_artifacts
from .offline_report import offline_view, texture_view
from .test_tracker import cache, fixture


def program(stage="ps"):
    data = cache()
    magic = 0x40000000
    runtime, payload = 0x4200, 0x5100
    hs = 40 if stage == "ps" else 872
    struct.pack_into(">I",data,runtime+16,magic+payload)
    struct.pack_into(">7I",data,runtime+hs,0x102a1100+(stage=="vs"),64,28,0,0,0,32)
    struct.pack_into(">II",data,runtime+hs+32,4,24)
    data[payload:payload+28] = b"CST!" + bytes(range(24))
    block = bytearray(80)
    struct.pack_into(">I",block,76,magic+runtime)
    reader = CacheReader(io.BytesIO(data),{"offset":0,"size":len(data)},len(data))
    return data,block,reader,runtime,hs


def evidence():
    module = {"id":"ps:"+"a"*64,"stage":"ps","sha256":"a"*64,
              "checks":{s:{"status":"pass"} for s in STAGES}}
    return {"iso_sha256":"b"*64,"policy":"policy","profile":dict(PROFILE),"modules":[module],
            "tags":[{"asset_id":"tag","class":"pixl","map":"test.map","name":"test","status":"enumerated","slots":2}],
            "references":[{"asset_id":"tag","slot":0,"status":"extracted","module_id":module["id"]},
                          {"asset_id":"tag","slot":1,"status":"extracted","module_id":module["id"]}]}


class ExtractionTests(unittest.TestCase):
    def test_vertex_full_fetch_zero_stride_and_mini_are_distinct(self):
        for mini,stride,needs in [(False,0,True),(False,6,False),(True,0,False)]:
            code=struct.pack(">9I",2|(1<<12)|(1<<16),1<<12,0,0,0,0,0,(1<<30) if mini else 0,stride)
            info=inspect_vertex_fetches(code)
            self.assertEqual(info["runtime_layout_unresolved"],needs)
            self.assertEqual(info["mini_fetches"],int(mini))

    def test_pixel_and_vertex_code_and_constants_separated(self):
        for stage in ("ps","vs"):
            _,b,r,_,_ = program(stage)
            info,code,constants = extract_program(r,b,stage)
            self.assertEqual(code,bytes(range(24)))
            self.assertEqual(constants,b"CST!")
            self.assertEqual(info["code_offset"],0x5104)
            self.assertEqual(info["stage"],stage)

    def test_null_slot_is_absent_not_failure(self):
        _,_,r,_,_ = program()
        info,code,constants = extract_program(r,bytes(80),"ps")
        self.assertEqual(info["status"],"absent")
        self.assertIsNone(code)

    def test_cache_read_cannot_cross_into_another_iso_map(self):
        data,block,_,runtime,_ = program()
        struct.pack_into(">I",data,runtime+16,0x40000000+len(data)-12)
        # The backing ISO is longer than the owning map. Still refuse.
        r=CacheReader(io.BytesIO(data+b"X"*100),{"offset":0,"size":len(data)},len(data)+100)
        with self.assertRaises(InventoryError): extract_program(r,block,"ps")

    def test_bad_debug_and_code_headers_refused(self):
        for offset,value in [(40,0),(44,27),(48,2<<20),(64,63),(72,29),(76,25),(76,0)]:
            data,block,_,runtime,_ = program()
            struct.pack_into(">I",data,runtime+offset,value)
            r=CacheReader(io.BytesIO(data),{"offset":0,"size":len(data)},len(data))
            with self.subTest(offset=offset,value=value),self.assertRaises(InventoryError):
                extract_program(r,block,"ps")

    def test_no_code_header_uses_declared_total(self):
        data,block,_,runtime,hs=program()
        struct.pack_into(">I",data,runtime+hs+24,0)
        struct.pack_into(">I",data,runtime+hs+8,24)
        r=CacheReader(io.BytesIO(data),{"offset":0,"size":len(data)},len(data))
        info,code,const=extract_program(r,block,"ps")
        self.assertEqual(const,b"")
        self.assertEqual(len(code),24)
        self.assertEqual(info["constant_bytes"],0)


class CompilerAccountingTests(unittest.TestCase):
    def continuation(self, root):
        e=evidence();e["policy"]=POLICY;e["xenia_source"]=str(root/"xenia");e["compilation_output"]=str(root/"prior")
        paths=[root/"prior/native-build/iso_shader_translate",root/"prior/prepare",root/"driver",root/"source",root/"tool"]
        for path in paths:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b"original")
        e.update(translator_sha256=hash_file(paths[0]),rewrite_helper_sha256=hash_file(paths[1]),
                 translation_source_hashes={str(paths[3]):hash_file(paths[3])},tools={"validator":{"path":str(paths[4]),"sha256":hash_file(paths[4])}})
        e["profile"].update(driver_path=str(paths[2]),driver_sha256=hash_file(paths[2]),feature_mask=1)
        modules=[]
        for n,state in enumerate(("pass","fail","unknown","unknown","unknown")):
            m=copy.deepcopy(e["modules"][0]);m["id"]=str(n);m["sha256"]=str(n)*64
            m["checks"]={s:{"status":state} for s in STAGES}
            if n==2:m["checks"]["translation"].update(returncode=6,command=["translator"])
            modules.append(m)
        e["modules"]=modules;e["references"]=[]
        return {"iso":{"sha256":e["iso_sha256"]},"iso_offline":e},paths

    def test_resume_preserves_pass_fail_and_runtime_inputs_and_limits_pending_work(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);snapshot,_=self.continuation(root)
            original=copy.deepcopy(snapshot["iso_offline"]["modules"][:3])
            def query(command,log):log.write_text(json.dumps({"feature_mask":1}));return {"status":"pass"}
            def checked(module,*args):module["checks"]={s:{"status":"pass"} for s in STAGES};module["checks"]["translation"]["command"]=["translator"]
            with patch("graphics_support.iso_offline.verify_offline_artifacts"),patch("graphics_support.iso_offline.execute",side_effect=query),patch("graphics_support.iso_offline.check_module",side_effect=checked) as run:
                result=resume_iso_checks(snapshot,root/"next",workers=1,limit=1)
            self.assertEqual(run.call_count,1)
            self.assertEqual(run.call_args.args[0]["id"],"3")
            self.assertEqual(result["modules"][:3],original)
            self.assertEqual(result["modules"][4]["checks"]["translation"]["status"],"unknown")
            self.assertEqual(result["continuations"][0]["selected"],1)

    def test_resume_refuses_changed_tools_sources_and_profiles_before_compilation(self):
        for kind in ("source","tool","driver","profile"):
            with self.subTest(kind=kind),tempfile.TemporaryDirectory() as d:
                root=Path(d);snapshot,_=self.continuation(root)
                if kind!="profile":(root/kind).write_bytes(b"changed")
                def query(command,log):log.write_text(json.dumps({"feature_mask":-1}));return {"status":"pass"}
                with patch("graphics_support.iso_offline.verify_offline_artifacts"),patch("graphics_support.iso_offline.execute",side_effect=query),patch("graphics_support.iso_offline.check_module") as run,self.assertRaises(InventoryError):
                    resume_iso_checks(snapshot,root/"next",workers=1,limit=1)
                run.assert_not_called()

    def test_unknown_reasons_distinguish_missing_runtime_inputs_and_untested(self):
        e=evidence()
        for s in STAGES:e["modules"][0]["checks"][s]={"status":"unknown"}
        self.assertEqual(offline_summary(e)["unknown_reasons"],{"untested":1})
        e["modules"][0]["checks"]["translation"].update(command=["translator"],returncode=6)
        self.assertEqual(offline_summary(e)["unknown_reasons"],{"runtime vertex layout":1})
        e["modules"][0]["checks"]["rewrite"]["reason"]="Saved compiler input/log/output missing or changed"
        self.assertEqual(offline_summary(e)["unknown_reasons"],{"stale evidence":1})

    def test_recovery_keeps_unfinished_checks_unknown_and_rejects_wrong_iso(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);e=evidence();e["policy"]=POLICY
            for stage in STAGES:e["modules"][0]["checks"][stage]={"status":"unknown"}
            (p/"checkpoint-baseline.json").write_text(json.dumps(e))
            s={"iso":{"sha256":e["iso_sha256"]},"iso_offline":copy.deepcopy(e)}
            r=recover_iso_checks(s,p)
            self.assertEqual(r["sweep"]["uncheckpointed_programs"],1)
            self.assertEqual(r["summary"]["compiler_ready"],0)
            s["iso"]["sha256"]="wrong"
            with self.assertRaises(InventoryError):recover_iso_checks(s,p)

    def test_actual_compiler_dependency_paths_with_spaces(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);source=p/"source with spaces.cc";source.write_bytes(b"source")
            (p/"source.o.d").write_text("source.o: \\\n  "+str(source).replace(" ","\\ ")+"\n")
            self.assertEqual(compiled_dependency_hashes(p),{str(source):hash_file(source)})

    def test_unique_programs_and_reference_weighting_are_separate(self):
        e=evidence(); s=offline_summary(e)
        self.assertEqual(s["unique_programs"],1)
        self.assertEqual(s["extracted_references"],2)
        self.assertEqual(s["compiler_ready_references"],2)
        self.assertEqual(s["tag_mapping"]["tag_states"], {"compiler_ready":1})

    def test_shader_tag_matrix_separates_null_slots_failures_and_unknowns(self):
        e=evidence()
        failed=copy.deepcopy(e["modules"][0]);failed["id"]="failed"
        failed["checks"]["air_compilation"]={"status":"fail"}
        unknown=copy.deepcopy(e["modules"][0]);unknown["id"]="unknown"
        unknown["checks"]["translation"]={"status":"unknown"}
        e["modules"].extend((failed,unknown))
        e["tags"].extend([{"asset_id":"empty","name":"empty","map":"m","class":"pixl","status":"enumerated","slots":1},
                          {"asset_id":"fault","name":"fault","map":"m","class":"vtsh","status":"enumerated","slots":1},
                          {"asset_id":"gap","name":"gap","map":"m","class":"vtsh","status":"enumerated","slots":1}])
        e["references"].extend([{"asset_id":"empty","slot":0,"status":"absent"},
                                {"asset_id":"fault","slot":0,"status":"extracted","module_id":"failed"},
                                {"asset_id":"gap","slot":0,"status":"extracted","module_id":"unknown"}])
        summary, rows=shader_tag_matrix(e)
        self.assertEqual(summary["tag_states"], {"compiler_failed":1,"compiler_ready":1,"compiler_unknown":1,"no_compiled_program":1})
        self.assertEqual(summary["absent_slots"],1)
        self.assertEqual(summary["compiler_failed_slots"],1)
        self.assertEqual(summary["unknown_slots"],1)
        self.assertEqual(len(rows),4)

    def test_unknown_and_absent_do_not_become_unsupported(self):
        e=evidence(); e["modules"][0]["checks"]["translation"]={"status":"unknown","reason":"runtime layout"}
        for stage in STAGES[1:]: e["modules"][0]["checks"][stage]={"status":"unknown"}
        e["references"].append({"status":"absent"})
        e["tags"].append({"status":"enumerated","slots":0})
        s=offline_summary(e)
        self.assertEqual((s["compiler_unknown"],s["compiler_fail"],s["absent_slots"],s["empty_tags"]),(1,0,1,1))

    def test_failure_counted_once_at_any_stage(self):
        e=evidence()
        for stage in STAGES: e["modules"][0]["checks"][stage]={"status":"fail"}
        s=offline_summary(e)
        self.assertEqual(s["compiler_fail"],1)
        self.assertEqual(s["compiler_ready"],0)

    def test_no_extracted_programs_has_no_percentage(self):
        e=evidence();e["modules"]=[];e["references"]=[]
        self.assertIsNone(offline_summary(e)["compiler_ready_percent"])

    def test_comparison_requires_identical_denom_profile_and_iso(self):
        before=evidence()
        for key,value in [("iso_sha256","changed"),("policy","changed"),("modules",[])]:
            after=copy.deepcopy(before);after[key]=value
            with self.assertRaises(InventoryError):compare_compilers(before,after)
        after=copy.deepcopy(before);after["profile"]["feature_mask"]=1
        with self.assertRaises(InventoryError):compare_compilers(before,after)

    def test_progress_returns_exact_gained_and_lost_ids(self):
        before=evidence();after=copy.deepcopy(before)
        before["modules"][0]["checks"]["translation"]={"status":"unknown"}
        c=compare_compilers(before,after,100)
        self.assertEqual(c["gained"],[after["modules"][0]["id"]])
        self.assertEqual(c["percentage_point_change"],100)
        self.assertEqual(c["additional_ready_programs_needed"],0)

    def test_runtime_layout_return_never_reaches_host_compilers(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);code=p/"code.vs";code.write_bytes(bytes(12))
            m={"stage":"vs","sha256":hash_file(code),"path":str(code),"checks":{s:{"status":"unknown"} for s in STAGES}}
            with patch("graphics_support.iso_offline.execute",return_value={"status":"fail","returncode":6}) as run:
                check_module(m,p/"translator",p/"helper",p,{}, {"feature_mask":0,"max_storage_buffer_range":0,"spirv_version":0})
            self.assertEqual(run.call_count,1)
            self.assertEqual(m["checks"]["translation"]["status"],"unknown")
            saved=json.loads((p/("vs-"+m["sha256"])/"result.json").read_text())
            self.assertEqual(saved["checks"]["translation"]["status"],"unknown")

    def test_failed_translation_preserves_checkpoint_and_diagnostics(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);code=p/"code.ps";code.write_bytes(bytes(12))
            m={"stage":"ps","sha256":hash_file(code),"path":str(code),"checks":{s:{"status":"unknown"} for s in STAGES}}
            with patch("graphics_support.iso_offline.execute",return_value={"status":"fail","returncode":4}):
                check_module(m,p/"translator",p/"helper",p,{}, {"feature_mask":0,"max_storage_buffer_range":0,"spirv_version":0})
            saved=json.loads((p/("ps-"+m["sha256"])/"result.json").read_text())
            self.assertEqual(saved["checks"]["translation"]["status"],"fail")
            self.assertEqual(saved["checks"]["air_compilation"]["status"],"unknown")

    def test_texture_browser_keeps_all_subimages_and_unknown_payloads(self):
        s=fixture()
        a=s["iso"]["assets"][0]
        a["subimages"]=[{"index":i,"width":16<<i,"height":16,"depth":1,"mip_count":2,"format":14,"type":0,"curve":3,"payload_status":"unverified"} for i in range(2)]
        block,rows=texture_view(s)
        selected=[r for r in rows if r[0]==a["id"]]
        self.assertEqual(len(selected),2)
        self.assertEqual([r[3] for r in selected],[0,1])
        self.assertTrue(all(r[-1]=="unverified" for r in selected))
        self.assertIn("Pixel previews and payload decoding remain unavailable",block)

    def test_changed_extracted_bytes_refused_before_compilation(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);code=p/"code.ps";code.write_bytes(b"changed")
            m={"stage":"ps","sha256":"a"*64,"path":str(code),"checks":{s:{"status":"unknown"} for s in STAGES}}
            with patch("graphics_support.iso_offline.execute") as run,self.assertRaises(InventoryError):
                check_module(m,p/"translator",p/"helper",p,{}, {})
            run.assert_not_called()

    def test_dashboard_does_not_convert_compilation_to_rendering_proof(self):
        s=fixture();s["iso_offline"]=evidence();s["iso_offline"]["scope"]="Compiler test"
        s["iso_offline"]["tags"][0]["name"]="<script>bad</script>"
        block,rows,tag_rows=offline_view(s)
        self.assertIn("100.000%",block)
        self.assertIn("Texture payload support is unknown",block)
        self.assertIn("not the percentage of Halo 3",block)
        self.assertIn("Compiler outcomes mapped to ISO shader tags",block)
        self.assertEqual(tag_rows[0][4],"compiler_ready")
        self.assertEqual(rows[0][5],["<script>bad</script>"])

    def test_changed_or_missing_compiler_proof_withdraws_claims(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);code=p/"code";code.write_bytes(b"code")
            log=p/"log";log.write_bytes(b"compiler returned success")
            out=p/"out";out.write_bytes(b"compiled result")
            e=evidence();m=e["modules"][0]
            m.update(path=str(code),sha256=hash_file(code))
            for stage in STAGES:
                m["checks"][stage]={"status":"pass","log":str(log),"log_sha256":hash_file(log),
                                    "output":str(out),"output_sha256":hash_file(out)}
            self.assertEqual(verify_offline_artifacts(e)["withdrawn_stage_claims"],[])
            out.write_bytes(b"changed")
            self.assertEqual(len(verify_offline_artifacts(e)["withdrawn_stage_claims"]),len(STAGES))
            self.assertEqual(offline_summary(e)["compiler_unknown"],1)


if __name__ == "__main__": unittest.main()
