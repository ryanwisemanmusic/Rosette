"""Compile production-rewritten archived shaders; never create or dispatch pipelines."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from .iso import InventoryError, hash_file


def execute(command, log: Path, timeout=60):
    try:
        result = subprocess.run(command, capture_output=True, timeout=timeout, check=False)
        log.write_bytes(result.stdout + result.stderr)
        return {"status": "pass" if result.returncode == 0 else "fail", "returncode": result.returncode,
                "command": command, "log": str(log), "log_sha256": hash_file(log)}
    except (OSError, subprocess.TimeoutExpired) as error:
        log.write_text(str(error))
        return {"status": "unknown", "error": str(error), "command": command,
                "log": str(log), "log_sha256": hash_file(log)}


def executable(name):
    path = shutil.which(name)
    if path is None:
        return None
    # Preserve argv[0] for compiler/driver symlinks (clang++ -> clang).
    return str(Path(path).absolute())


def compile_shaders(snapshot, output: Path, root: Path, zig="zig", validator="spirv-val",
                    converter="MoltenVKShaderConverter", limit=None):
    archive = snapshot.get("shader_archive")
    if not archive:
        raise InventoryError("Snapshot has no shader archive")
    selected = [m for m in archive["modules"] if m["role"] == "guest" and m["current_run_guest_match"]]
    if limit is not None:
        if limit < 1:
            raise InventoryError("Compile limit must be positive")
        selected = selected[:limit]
    if output.exists():
        raise InventoryError("Compile evidence directory already exists; choose a new directory")
    output = output.resolve()
    output.mkdir(parents=True)
    input_dir, rewritten = output / "input", output / "rewritten"
    input_dir.mkdir()
    rewritten.mkdir()
    tool_names = {"zig": zig, "validator": validator, "converter": converter, "xcrun": "xcrun"}
    tools = {key: executable(value) for key, value in tool_names.items()}
    tool_evidence = {key: {"path": path, "sha256": hash_file(Path(path))} if path else None
                     for key, path in tools.items()}
    sources = [root / "tools/vulkan/prepare_fsi_shaders.zig", root / "lib/gpu/vulkan/rect_list_expand.zig",
               root / "lib/gpu/vulkan/robust_access.zig", root / "lib/gpu/vulkan/fsi/pixel_frequency.zig"]
    source_hashes = {str(p): hash_file(p) for p in sources}
    result = {"scope": "Exact logged FSI guest modules, production rectangle+pixel-frequency+robust rewrites, SPIR-V -> MSL 2.3 -> AIR. No GPU dispatch; no ISO asset mapping or visual correctness inferred.",
              "selected": len(selected), "tools": tool_evidence, "sources": source_hashes,
              "output": str(output), "rewrite": {"status": "unknown"}}
    archive["offline_check"] = result
    for module in selected:
        source = Path(module["paths"][0])
        data = source.read_bytes()
        if hashlib.sha256(data).hexdigest() != module["sha256"]:
            raise InventoryError(f"Shader changed since archive scan: {source}")
        (input_dir / (module["sha256"] + ".spv")).write_bytes(data)
        module["checks"] = {stage: {"status": "unknown"} for stage in ("rewrite", "spirv_validation", "msl_conversion", "air_compilation")}
    if not selected or not tools["zig"]:
        result["rewrite"]["reason"] = "No matched modules or Zig is unavailable"
        return result
    helper = output / "prepare"
    command = [tools["zig"], "build-exe", "-O", "ReleaseFast", "-lc", "--dep", "rect", "--dep", "robust", "--dep", "sampling",
               f"-Mroot={sources[0]}", f"-Mrect={sources[1]}", f"-Mrobust={sources[2]}", f"-Msampling={sources[3]}", f"-femit-bin={helper}"]
    result["build_helper"] = execute(command, output / "build.log")
    if result["build_helper"]["status"] != "pass":
        result["rewrite"]["reason"] = "Helper build did not pass"
        return result
    result["rewrite"] = execute([str(helper), str(input_dir), str(rewritten)], output / "rewrite.log")
    if result["rewrite"]["status"] != "pass":
        # No partially written modules are promoted after a refused rewrite.
        return result
    for n, module in enumerate(selected, 1):
        sha = module["sha256"]
        spv, metal, air = rewritten / (sha + ".spv"), output / (sha + ".metal"), output / (sha + ".air")
        checks = module["checks"]
        if not spv.is_file():
            checks["rewrite"] = {"status": "fail", "reason": "Helper omitted module"}
            continue
        checks["rewrite"] = {"status": "pass", "output_sha256": hash_file(spv), "output": str(spv)}
        if tools["validator"]:
            checks["spirv_validation"] = execute([tools["validator"], "--target-env", "vulkan1.2", str(spv)], output / (sha + ".validate.log"))
        if tools["converter"]:
            checks["msl_conversion"] = execute([tools["converter"], "-si", str(spv), "-mo", str(metal), "-mv", "2.3", "-mp", "macos", "-q"], output / (sha + ".convert.log"))
            if checks["msl_conversion"]["status"] == "pass" and not metal.is_file():
                checks["msl_conversion"] = {"status": "fail", "reason": "Converter produced no MSL"}
        if tools["xcrun"] and checks["msl_conversion"]["status"] == "pass":
            checks["air_compilation"] = execute([tools["xcrun"], "-sdk", "macosx", "metal", "-std=macos-metal2.3", "-c", str(metal), "-o", str(air)], output / (sha + ".metal.log"))
            if checks["air_compilation"]["status"] == "pass" and not air.is_file():
                checks["air_compilation"] = {"status": "fail", "reason": "Compiler produced no AIR"}
        print(f"Offline shader checks {n}/{len(selected)}", flush=True) if n % 25 == 0 else None
    (output / "manifest.json").write_text(json.dumps(result, indent=2))
    return result
