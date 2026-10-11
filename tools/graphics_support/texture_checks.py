"""CPU-only compiler checks of Xenia's texture-loader kernels, not pixels."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path

from .checks import execute, executable
from .iso import InventoryError, hash_file

# Halo 3 retail enum values (Assembly fd14ef3c bitm layout). They are not
# interchangeable with Xenos TextureFormat or VkFormat numeric values.
HALO_FORMATS = dict(enumerate((
    "A8", "Y8", "AY8", "A8Y8", "R8", "Unused2", "R5G6B5", "Unused3", "A1R5G5B5",
    "A4R4G4B4", "X8R8G8B8", "A8R8G8B8", "Unused4", "Unused5", "DXT1", "DXT3",
    "DXT5", "A4R4G4B4 font", "Unused7", "Unused8", "Software RGBFP32", "Unused9",
    "V8U8", "G8B8", "ABGRFP32", "ABGRFP16", "Q8W8V8U8", "A2R10G10B10",
    "A16B16G16R16", "V16U16", "DXT3a", "DXT5a", "DXT3a_1111", "DXN", "CTX1",
    "DXT3a_alpha", "DXT3a_mono", "DXT5a_alpha", "DXT5a_mono", "DXN_mono_alpha")))


def texture_check(snapshot, output, root, xenia_source, zig="zig", validator="spirv-val",
                  converter="MoltenVKShaderConverter", workers=2):
    if not snapshot.get("iso_offline"):
        raise InventoryError("Extract ISO evidence with iso-check first")
    output, source = output.resolve(), xenia_source.resolve(strict=True)
    if output.exists() or source in output.parents or not 1 <= workers <= 8:
        raise InventoryError("Use a new evidence directory outside Xenia; workers must be 1..8")
    output.mkdir(parents=True)
    shader_dir = source / "src/xenia/gpu/shaders"
    paths = sorted(shader_dir.glob("texture_load_*.cs.xesl"))
    tools = {k: executable(v) for k,v in {"zig":zig, "glslang":"glslangValidator", "validator":validator,
                                         "converter":converter, "xcrun":"xcrun"}.items()}
    result = snapshot["iso_offline"]["texture_check"]
    result.update(format_names={str(k):v for k,v in HALO_FORMATS.items()},
                  loader_scope="All texture_load_*.cs.xesl kernels in the read-only Xenia source, including scaled paths. Compilation only; no GPU dispatch, texture page decode or format-to-resource readiness inference.",
                  loader_output=str(output),
                  loader_tools={k:{"path":v,"sha256":hash_file(Path(v))} if v else None for k,v in tools.items()},
                  loader_sources={str(p):hash_file(p) for p in sorted(shader_dir.glob("*.xesl*"))},
                  loaders=[{"name":p.name,"source":str(p),"sha256":hash_file(p),
                            "checks":{s:{"status":"unknown"} for s in ("glsl_to_spirv","rewrite","spirv_validation","msl_conversion","air_compilation")}} for p in paths])
    helper = output / "prepare"
    src = [root / "tools/vulkan/prepare_rect_shaders.zig", root / "lib/gpu/vulkan/rect_list_expand.zig", root / "lib/gpu/vulkan/robust_access.zig"]
    result["loader_rewrite_sources"] = {str(p):hash_file(p) for p in src}
    if not all(tools.values()):
        result["loader_build"] = {"status":"unknown","reason":"Required compiler tool unavailable"}
        return result
    result["loader_build"] = execute([tools["zig"],"build-exe","-O","ReleaseFast","-lc","--dep","rect","--dep","robust",
                                       f"-Mroot={src[0]}",f"-Mrect={src[1]}",f"-Mrobust={src[2]}",f"-femit-bin={helper}"],output/"build.log",120)
    if result["loader_build"]["status"] != "pass":
        return result

    def check(loader):
        folder = output / loader["name"]
        folder.mkdir()
        inp, rewritten = folder / "input", folder / "rewritten"
        inp.mkdir(); rewritten.mkdir()
        wrapper = folder / "loader.comp"
        # Exact XESL wrapper and define used by Xenia's build tool. File input
        # instead of stdin retains a reproducible wrapper as evidence.
        wrapper.write_text('#version 460\n#extension GL_EXT_control_flow_attributes : require\n'
                           '#extension GL_EXT_samplerless_texture_functions : require\n'
                           '#extension GL_GOOGLE_include_directive : require\n'
                           f'#include "{loader["name"]}"\n')
        spv = inp / "loader.spv"
        checks = loader["checks"]
        checks["glsl_to_spirv"] = execute([tools["glslang"],str(wrapper),"-DSHADING_LANGUAGE_GLSL_XE=1","-S","comp",
                                            "-o",str(spv),"-V",f"-I{shader_dir}"],folder/"glslang.log")
        if checks["glsl_to_spirv"]["status"] != "pass": return
        checks["glsl_to_spirv"].update(output=str(spv),output_sha256=hash_file(spv))
        checks["rewrite"] = execute([str(helper),str(inp),str(rewritten)],folder/"rewrite.log")
        if checks["rewrite"]["status"] != "pass": return
        spv = rewritten / "loader.spv"
        checks["rewrite"].update(output=str(spv),output_sha256=hash_file(spv))
        checks["spirv_validation"] = execute([tools["validator"],"--target-env","vulkan1.2",str(spv)],folder/"validate.log")
        if checks["spirv_validation"]["status"] != "pass": return
        checks["spirv_validation"].update(output=str(spv),output_sha256=hash_file(spv))
        metal, air = folder/"loader.metal",folder/"loader.air"
        checks["msl_conversion"] = execute([tools["converter"],"-si",str(spv),"-mo",str(metal),"-mv","2.3","-mp","macos","-q"],folder/"convert.log")
        if checks["msl_conversion"]["status"] != "pass": return
        checks["msl_conversion"].update(output=str(metal),output_sha256=hash_file(metal))
        checks["air_compilation"] = execute([tools["xcrun"],"-sdk","macosx","metal","-std=macos-metal2.3","-c",str(metal),"-o",str(air)],folder/"metal.log")
        if checks["air_compilation"]["status"] == "pass":
            checks["air_compilation"].update(output=str(air),output_sha256=hash_file(air))

    with ThreadPoolExecutor(max_workers=workers) as pool:
        for n, _ in enumerate(pool.map(check, result["loaders"]), 1):
            print(f"Texture-loader compiler checks {n}/{len(paths)}",flush=True) if n%10==0 or n==len(paths) else None
    (output/"manifest.json").write_text(json.dumps(result,indent=2))
    return result
