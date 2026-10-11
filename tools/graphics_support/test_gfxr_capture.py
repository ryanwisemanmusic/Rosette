import json
from pathlib import Path
import tempfile
import unittest

from .gfxr_capture import audit_jsonl, attach_capture, capture_view, verify_capture_record


class GfxrCaptureTests(unittest.TestCase):
    def fixture(self, root):
        capture = root / "capture.gfxr"
        capture.write_bytes(b"synthetic capture")
        converter = root / "gfxrecon-convert"
        converter.write_bytes(b"synthetic converter")
        jsonl = root / "capture.jsonl"
        records = [
            {"state": {"marker_type": "BeginMarker", "frame_number": 1225}},
            {"index": 1, "function": {"name": "vkCreateRenderPass", "args": {
                "pRenderPass": 7, "pCreateInfo": {"attachmentCount": 0, "subpassCount": 1}}}},
            {"index": 2, "function": {"name": "vkCreateFramebuffer", "args": {
                "pFramebuffer": 8, "pCreateInfo": {"renderPass": 7, "attachmentCount": 0,
                "width": 8192, "height": 8192, "layers": 1}}}},
            {"index": 3, "function": {"name": "vkCreateImage", "args": {
                "pImage": 11, "pCreateInfo": {"format": "VK_FORMAT_BC3_UNORM_BLOCK",
                "extent": {"width": 256, "height": 128, "depth": 1}, "mipLevels": 4, "arrayLayers": 1}}}},
            {"index": 4, "function": {"name": "vkCreateImageView", "args": {
                "pView": 12, "pCreateInfo": {"image": 11, "format": "VK_FORMAT_BC3_UNORM_BLOCK",
                "viewType": "VK_IMAGE_VIEW_TYPE_2D"}}}},
            {"index": 5, "function": {"name": "vkCreateShaderModule", "args": {
                "pShaderModule": 13, "pCreateInfo": {"codeSize": 64, "pCode": "[Binary data]"}}}},
            {"index": 6, "function": {"name": "vkCreateGraphicsPipelines", "args": {
                "pPipelines": [14], "pCreateInfos": [{"stageCount": 1,
                "pStages": [{"stage": "VK_SHADER_STAGE_FRAGMENT_BIT", "module": 13}],
                "pInputAssemblyState": {"topology": "VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST"}}]}}},
            {"index": 7, "function": {"name": "vkUpdateDescriptorSets", "args": {
                "pDescriptorWrites": [{"dstSet": 20, "dstBinding": 0, "dstArrayElement": 0,
                "descriptorType": "VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE", "descriptorCount": 1,
                "pImageInfo": [{"imageView": 12, "imageLayout": "VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL"}]}]}}},
            {"index": 8, "function": {"name": "vkCmdBeginRenderPass", "args": {
                "commandBuffer": 30, "pRenderPassBegin": {"framebuffer": 8}}}},
            {"index": 9, "function": {"name": "vkCmdBindPipeline", "args": {
                "commandBuffer": 30, "pipelineBindPoint": "VK_PIPELINE_BIND_POINT_GRAPHICS", "pipeline": 14}}},
            {"index": 10, "function": {"name": "vkCmdBindDescriptorSets", "args": {
                "commandBuffer": 30, "pipelineBindPoint": "VK_PIPELINE_BIND_POINT_GRAPHICS",
                "firstSet": 0, "pDescriptorSets": [20]}}},
            {"index": 11, "function": {"name": "vkCmdDrawIndexed", "args": {
                "commandBuffer": 30, "indexCount": 6, "instanceCount": 1}}},
            {"index": 12, "function": {"name": "vkCmdEndRenderPass", "args": {"commandBuffer": 30}}},
        ]
        jsonl.write_text("[gfxrecon] INFO - prelude\n" + "\n".join(json.dumps(r) for r in records))
        return capture, converter, jsonl

    def test_identifies_fsi_draw_and_resolves_bound_image_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            capture, converter, jsonl = self.fixture(root)
            result = audit_jsonl(jsonl, capture, converter)
        self.assertEqual(result["capture"]["frames"], [1225])
        self.assertEqual(result["fsi"]["draw_calls"], 1)
        self.assertEqual(result["fsi"]["unique_pipelines"], 1)
        self.assertEqual(result["fsi"]["unique_shader_modules"], 1)
        self.assertEqual(result["fsi"]["unique_images"], 1)
        self.assertEqual(result["fsi"]["image_descriptors_by_format"][0]["format"],
                         "VK_FORMAT_BC3_UNORM_BLOCK")
        self.assertEqual(result["fsi"]["shader_archive_module_counts"], {"not_requested": 1})
        self.assertFalse(result["analysis"]["gpu_replay"])

    def test_later_descriptor_set_write_is_reported_without_rewriting_draw_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            capture, converter, jsonl = self.fixture(root)
            records = [json.loads(line) for line in jsonl.read_text().splitlines()[1:]]
            records.insert(-1, {"index": 11, "function": {"name": "vkUpdateDescriptorSets", "args": {
                "pDescriptorWrites": [{"dstSet": 20, "dstBinding": 0, "dstArrayElement": 0,
                "descriptorType": "VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE", "descriptorCount": 1,
                "pImageInfo": [{"imageView": 999, "imageLayout": "VK_IMAGE_LAYOUT_GENERAL"}]}]}}})
            jsonl.write_text("\n".join(json.dumps(r) for r in records))
            result = audit_jsonl(jsonl, capture, converter)
        self.assertEqual(result["fsi"]["bound_sets_rewritten_later_in_api_order"], 1)
        self.assertEqual(result["fsi"]["unique_images"], 1)

    def test_compute_pipeline_binding_does_not_replace_graphics_draw_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            capture, converter, jsonl = self.fixture(root)
            records = [json.loads(line) for line in jsonl.read_text().splitlines()[1:]]
            at = next(i for i, record in enumerate(records)
                      if record.get("function", {}).get("name") == "vkCmdDrawIndexed")
            records.insert(at, {"function": {"name": "vkCmdBindPipeline", "args": {
                "commandBuffer": 30, "pipelineBindPoint": "VK_PIPELINE_BIND_POINT_COMPUTE", "pipeline": 99}}})
            jsonl.write_text("\n".join(json.dumps(r) for r in records))
            result = audit_jsonl(jsonl, capture, converter)
        self.assertEqual(result["fsi"]["top_pipelines"][0]["pipeline"], 14)
        self.assertEqual(result["fsi"]["unique_shader_modules"], 1)

    def test_attach_hash_verification_and_report_do_not_promote_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            capture, converter, jsonl = self.fixture(root)
            result = audit_jsonl(jsonl, capture, converter)
            manifest = {"schema": 1, "captures": [result], "analysis_scope": "test"}
            manifest_path = root / "audit.json"
            manifest_path.write_text(json.dumps(manifest))
            snapshot = {"gfxr_capture_audit": None}
            attach_capture(snapshot, manifest_path)
            self.assertTrue(verify_capture_record(snapshot["gfxr_capture_audit"]))
            view = capture_view(snapshot)
        self.assertIn("Offline GFXReconstruct capture audit", view)
        self.assertIn("not replayed", view)
        self.assertNotIn("confirmed rendering", view)

    def test_changed_capture_source_invalidates_audit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            capture, converter, jsonl = self.fixture(root)
            result = audit_jsonl(jsonl, capture, converter)
            capture.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "capture changed"):
                verify_capture_record({"schema": 1, "captures": [result]})


if __name__ == "__main__":
    unittest.main()
