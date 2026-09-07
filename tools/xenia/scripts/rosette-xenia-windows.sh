#!/usr/bin/env bash
# Rosette-owned Windows cross-build capsule for Xenia.
#
# Xenia's upstream build generates version data, dependency headers, shader
# bytecode, and resource inputs in its source tree. This adapter mirrors a
# complete checkout into the build directory first, then puts all compatibility
# wrappers and generated state beside that mirror.

set -euo pipefail

script_dir="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
template_dir="$repo_root/tools/xenia/windows"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

env_value() {
    printenv "$1" 2>/dev/null || true
}

help() {
    cat <<'EOF'
Rosette Xenia Windows build capsule

  rosette-xenia-windows.sh --source-root /path/to/complete/xenia \
    --build-dir /tmp/rosette-xenia-windows --configure --build --bundle

  rosette-xenia-windows.sh --source-root /path/to/complete/xenia \
    --build-dir /tmp/rosette-xenia-windows --prepare

Options:
  --source-root PATH       Complete Xenia checkout, including submodules.
  --build-dir PATH         Isolated source mirror, CMake tree, and support.
  --bundle-dir PATH        Directory receiving the executable and DLLs.
  --media-image PATH       Optional ISO copied beside the executable.
  --config NAME            CMake configuration (default: Release).
  --target NAME            CMake target (default: xenia-app).
  --jobs N                 Parallel build jobs.
  --prepare                Mirror the source and generate support files.
  --configure              Configure with Ninja Multi-Config.
  --build                  Build the selected target.
  --bundle                 Copy the executable, runtime DLLs, and manifest.
  --print                  Print resolved paths and toolchain facts.
  --help                   Show this help.

Tool overrides:
  ROSETTE_XENIA_WINDOWS_LLVM_PREFIX
  ROSETTE_XENIA_WINDOWS_CLANG / ROSETTE_XENIA_WINDOWS_CLANGXX
  ROSETTE_XENIA_WINDOWS_WINDRES / ROSETTE_XENIA_WINDOWS_MINGW_ROOT
  ROSETTE_XENIA_WINDOWS_CMAKE / ROSETTE_XENIA_WINDOWS_NINJA
  ROSETTE_XENIA_WINDOWS_DXC or FXC_PATH
  ROSETTE_XENIA_WINDOWS_SHADER_LAUNCHER
  ROSETTE_XENIA_WINDOWS_JOBS

The source checkout must already be populated. This adapter does not clone,
download, install, or mutate dependencies.
EOF
}

resolve_tool() {
    local requested="$1"
    local fallback="$2"
    local resolved=""
    if [[ -n "$requested" ]]; then
        if [[ "$requested" == */* ]]; then
            resolved="$requested"
        else
            resolved="$(command -v "$requested" 2>/dev/null || true)"
        fi
    else
        resolved="$(command -v "$fallback" 2>/dev/null || true)"
    fi
    [[ -n "$resolved" && -x "$resolved" ]] ||
        die "required executable is not available: $requested"
    (
        cd "$(dirname "$resolved")"
        printf '%s/%s\n' "$(pwd)" "$(basename "$resolved")"
    )
}

existing_dir() {
    [[ -d "$1" ]] || die "directory does not exist: $1"
    (cd "$1" && pwd)
}

output_dir() {
    mkdir -p "$1"
    (cd "$1" && pwd)
}

sed_escape() {
    printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

validate_source() {
    local missing=0
    local relative
    for relative in \
        CMakeLists.txt xenia-build.py src/xenia/app/CMakeLists.txt \
        src/xenia/gpu/shaders third_party/CMakeLists.txt \
        third_party/DirectX-Headers/include/directx/d3d12.h \
        third_party/DirectXShaderCompiler/include/dxc/dxcapi.h \
        third_party/FFmpeg/libavcodec/avcodec.h \
        third_party/SDL2/CMakeLists.txt \
        third_party/SPIRV-Tools/CMakeLists.txt \
        third_party/Vulkan-Headers/include/vulkan/vulkan.h \
        third_party/capstone/CMakeLists.txt third_party/fmt/CMakeLists.txt \
        third_party/glslang/CMakeLists.txt \
        third_party/libusb/libusb/libusbi.h \
        third_party/snappy/CMakeLists.txt \
        third_party/xbyak/xbyak/xbyak.h \
        third_party/zlib-ng/CMakeLists.txt third_party/zstd/lib/zstd.h \
        third_party/zstd/build/cmake/CMakeLists.txt; do
        if [[ ! -e "$original_source_root/$relative" ]]; then
            echo "ERROR: Xenia source is incomplete; missing $relative" >&2
            missing=1
        fi
    done
    (( missing == 0 )) ||
        die "use a checkout with populated submodules; no dependency fetch is performed"
}

mirror_source() {
    [[ "$source_mirror" != "$original_source_root" ]] ||
        die "the build directory cannot be the source checkout"
    command -v rsync >/dev/null 2>&1 ||
        die "rsync is required to create the isolated Xenia source mirror"
    mkdir -p "$source_mirror"
    # Keep generated state from an earlier isolated run, but never delete
    # anything from the selected build directory.
    rsync -a \
        --exclude '.git' \
        --exclude 'CMakeCache.txt' \
        --exclude 'CMakeFiles' \
        --exclude 'cmake_install.cmake' \
        --exclude 'build.ninja' \
        --exclude 'build-*.ninja' \
        --exclude 'rules.ninja' \
        --exclude 'compile_commands.json' \
        "$original_source_root/" "$source_mirror/"
}

discover_tools() {
    local llvm_prefix
    local clang_request
    local clangxx_request
    local windres_request
    local mingw_request
    local lld_request
    local windres_dir
    local windres_parent
    llvm_prefix="$(env_value ROSETTE_XENIA_WINDOWS_LLVM_PREFIX)"
    clang_request="$(env_value ROSETTE_XENIA_WINDOWS_CLANG)"
    clangxx_request="$(env_value ROSETTE_XENIA_WINDOWS_CLANGXX)"
    windres_request="$(env_value ROSETTE_XENIA_WINDOWS_WINDRES)"
    mingw_request="$(env_value ROSETTE_XENIA_WINDOWS_MINGW_ROOT)"
    lld_request="$(env_value ROSETTE_XENIA_WINDOWS_LLD)"

    if [[ -z "$llvm_prefix" && -x /opt/homebrew/opt/llvm@19/bin/clang ]]; then
        llvm_prefix=/opt/homebrew/opt/llvm@19/bin
    fi
    [[ -z "$llvm_prefix" ]] || llvm_prefix="$(existing_dir "$llvm_prefix")"
    if [[ -z "$clang_request" && -n "$llvm_prefix" && -x "$llvm_prefix/clang" ]]; then
        clang_request="$llvm_prefix/clang"
    fi
    if [[ -z "$clangxx_request" && -n "$llvm_prefix" && -x "$llvm_prefix/clang++" ]]; then
        clangxx_request="$llvm_prefix/clang++"
    fi
    clang="$(resolve_tool "$clang_request" clang)"
    clangxx="$(resolve_tool "$clangxx_request" clang++)"
    [[ -n "$llvm_prefix" ]] || llvm_prefix="$(cd "$(dirname "$clang")" && pwd)"

    if [[ -z "$lld_request" ]]; then
        lld_request="$(command -v ld.lld 2>/dev/null || command -v lld 2>/dev/null || true)"
    fi
    if [[ -z "$lld_request" ]]; then
        local llvm_root
        local candidate
        llvm_root="$(cd -P "$(dirname "$clang")/.." && pwd)"
        for candidate in \
            "$llvm_root"/../../lld*/*/bin/ld.lld \
            "$llvm_root"/../../../opt/lld*/bin/ld.lld \
            "$llvm_root"/../lld*/bin/ld.lld \
            "$llvm_root"/../llvm*/bin/ld.lld; do
            if [[ -x "$candidate" ]]; then
                lld_request="$candidate"
                break
            fi
        done
    fi
    lld="$(resolve_tool "$lld_request" ld.lld)"

    local ar_request="$llvm_prefix/llvm-ar"
    local ranlib_request="$llvm_prefix/llvm-ranlib"
    [[ -z "$(env_value ROSETTE_XENIA_WINDOWS_LLVM_AR)" ]] ||
        ar_request="$(env_value ROSETTE_XENIA_WINDOWS_LLVM_AR)"
    [[ -z "$(env_value ROSETTE_XENIA_WINDOWS_LLVM_RANLIB)" ]] ||
        ranlib_request="$(env_value ROSETTE_XENIA_WINDOWS_LLVM_RANLIB)"
    llvm_ar="$(resolve_tool "$ar_request" llvm-ar)"
    llvm_ranlib="$(resolve_tool "$ranlib_request" llvm-ranlib)"
    cmake="$(resolve_tool "$(env_value ROSETTE_XENIA_WINDOWS_CMAKE)" cmake)"
    ninja="$(resolve_tool "$(env_value ROSETTE_XENIA_WINDOWS_NINJA)" ninja)"
    python3_bin="$(resolve_tool "$(env_value ROSETTE_XENIA_WINDOWS_PYTHON)" python3)"
    windres="$(resolve_tool "$windres_request" x86_64-w64-mingw32-windres)"

    if [[ -n "$mingw_request" ]]; then
        mingw_root="$(existing_dir "$mingw_request")"
    else
        windres_dir="$(cd "$(dirname "$windres")" && pwd)"
        windres_parent="$(dirname "$windres_dir")"
        mingw_root="$(existing_dir "$windres_parent/x86_64-w64-mingw32")"
    fi
    mingw_parent="$(cd "$(dirname "$mingw_root")" && pwd)"
    [[ -f "$mingw_root/include/windows.h" ]] ||
        die "MinGW root has no Windows headers: $mingw_root"
    [[ -f "$mingw_root/lib/libkernel32.a" ]] ||
        die "MinGW root has no Windows import libraries: $mingw_root"

    if [[ "$need_shader_tools" == 1 ]]; then
        local shader_request
        shader_request="$(env_value ROSETTE_XENIA_WINDOWS_DXC)"
        [[ -n "$shader_request" ]] || shader_request="$(env_value FXC_PATH)"
        shader_compiler="$(resolve_tool "$shader_request" dxc 2>/dev/null || true)"
        [[ -n "$shader_compiler" ]] || shader_compiler="$(resolve_tool "" fxc)"
        glslang="$(resolve_tool "$(env_value ROSETTE_XENIA_WINDOWS_GLSLANG)" glslangValidator)"
        spirv_opt="$(resolve_tool "$(env_value ROSETTE_XENIA_WINDOWS_SPIRV_OPT)" spirv-opt)"
        spirv_dis="$(resolve_tool "$(env_value ROSETTE_XENIA_WINDOWS_SPIRV_DIS)" spirv-dis)"
        if ! "$spirv_opt" --help 2>/dev/null | grep -q -- '--canonicalize-ids'; then
            die "spirv-opt lacks --canonicalize-ids: $spirv_opt"
        fi
        vulkan_sdk_root="$(env_value VULKAN_SDK)"
        if [[ -z "$vulkan_sdk_root" ]]; then
            local sdk_candidate
            sdk_candidate="$(cd "$(dirname "$glslang")/.." && pwd)"
            if [[ -x "$sdk_candidate/bin/glslangValidator" ]]; then
                vulkan_sdk_root="$sdk_candidate"
            fi
        fi
    fi
}

render_template() {
    local source_escaped="$(sed_escape "$source_mirror")"
    local inner_escaped="$(sed_escape "$inner_build")"
    local support_escaped="$(sed_escape "$support_dir")"
    local support_bin_escaped="$(sed_escape "$support_bin")"
    local support_tmp_escaped="$(sed_escape "$support_tmp")"
    local clang_escaped="$(sed_escape "$clang")"
    local clangxx_escaped="$(sed_escape "$clangxx")"
    local windres_escaped="$(sed_escape "$windres")"
    local llvm_ar_escaped="$(sed_escape "$llvm_ar")"
    local llvm_ranlib_escaped="$(sed_escape "$llvm_ranlib")"
    local lld_escaped="$(sed_escape "$lld")"
    local mingw_escaped="$(sed_escape "$mingw_root")"
    local mingw_parent_escaped="$(sed_escape "$mingw_parent")"
    local libusb_escaped="$(sed_escape "$libusb_config_dir")"
    local icon_escaped="$(sed_escape "$source_mirror/assets/icon/icon.ico")"
    local launcher_escaped="$(sed_escape "$(env_value ROSETTE_XENIA_WINDOWS_SHADER_LAUNCHER)")"
    sed \
        -e "s|@SOURCE_ROOT@|$source_escaped|g" \
        -e "s|@INNER_BUILD@|$inner_escaped|g" \
        -e "s|@SUPPORT_DIR@|$support_escaped|g" \
        -e "s|@SUPPORT_BIN@|$support_bin_escaped|g" \
        -e "s|@SUPPORT_TMP@|$support_tmp_escaped|g" \
        -e "s|@CLANG@|$clang_escaped|g" \
        -e "s|@CLANGXX@|$clangxx_escaped|g" \
        -e "s|@WINDRES@|$windres_escaped|g" \
        -e "s|@LLVM_AR@|$llvm_ar_escaped|g" \
        -e "s|@LLVM_RANLIB@|$llvm_ranlib_escaped|g" \
        -e "s|@LLD@|$lld_escaped|g" \
        -e "s|@MINGW_ROOT@|$mingw_escaped|g" \
        -e "s|@MINGW_PARENT@|$mingw_parent_escaped|g" \
        -e "s|@LIBUSB_CONFIG@|$libusb_escaped|g" \
        -e "s|@ICON_PATH@|$icon_escaped|g" \
        -e "s|@SHADER_LAUNCHER@|$launcher_escaped|g" \
        "$1" > "$2"
}

write_version_header() {
    local branch=tarball
    local commit=':(-dont-do-this'
    local short=':('
    if git -C "$original_source_root" rev-parse --git-dir >/dev/null 2>&1; then
        branch="$(git -C "$original_source_root" symbolic-ref --short HEAD 2>/dev/null || true)"
        [[ -n "$branch" ]] || branch=detached
        commit="$(git -C "$original_source_root" rev-parse HEAD)"
        short="$(printf '%s' "$commit" | cut -c1-8)"
    fi
    source_commit="$commit"
    {
        printf '%s\n' '// Autogenerated by Rosette''s Xenia Windows build capsule.'
        printf '%s\n' '#ifndef GENERATED_VERSION_H_' '#define GENERATED_VERSION_H_'
        printf '#define XE_BUILD_BRANCH "%s"\n' "$branch"
        printf '#define XE_BUILD_COMMIT "%s"\n' "$commit"
        printf '#define XE_BUILD_COMMIT_SHORT "%s"\n' "$short"
        printf '%s\n' '#define XE_BUILD_DATE __DATE__' '#endif  // GENERATED_VERSION_H_'
    } > "$build_dir/version.h"
}

generate_support() {
    mkdir -p "$support_dir/cmake-wrapper" "$support_bin" "$support_dir/include" \
        "$support_tmp" "$libusb_config_dir"
    if [[ "$need_shader_tools" == 1 ]]; then
        mkdir -p "$vulkan_tool_root/bin"
        ln -sfn "$glslang" "$vulkan_tool_root/bin/glslangValidator"
        ln -sfn "$spirv_opt" "$vulkan_tool_root/bin/spirv-opt"
        ln -sfn "$spirv_dis" "$vulkan_tool_root/bin/spirv-dis"
        if [[ -n "$vulkan_sdk_root" && -d "$vulkan_sdk_root/lib" ]]; then
            ln -sfn "$vulkan_sdk_root/lib" "$vulkan_tool_root/lib"
        fi
    fi
    render_template "$template_dir/CMakeLists.windows.in" \
        "$support_dir/cmake-wrapper/CMakeLists.txt"
    render_template "$template_dir/windows-toolchain.cmake.in" \
        "$support_dir/windows-toolchain.cmake"
    render_template "$template_dir/clang-c-wrapper.sh.in" "$support_bin/clang-c-wrapper"
    render_template "$template_dir/clang-cxx-wrapper.sh.in" "$support_bin/clang-cxx-wrapper"
    render_template "$template_dir/windres-wrapper.sh.in" "$support_bin/windres-wrapper"
    render_template "$template_dir/wine.in" "$support_bin/wine"
    render_template "$template_dir/xenia_cxx_compat.h.in" \
        "$support_dir/include/xenia_cxx_compat.h"
    render_template "$template_dir/intrin.h.in" "$support_dir/include/intrin.h"
    cp "$template_dir/xenia_windows_compat.h" "$support_dir/include/xenia_windows_compat.h"
    cp "$template_dir/DXProgrammableCapture.h" "$support_dir/include/DXProgrammableCapture.h"
    cp "$template_dir/ShlObj_core.h" "$support_dir/include/ShlObj_core.h"
    cp "$template_dir/libusb-config.h" "$libusb_config_dir/config.h"
    chmod +x "$support_bin/clang-c-wrapper" "$support_bin/clang-cxx-wrapper" \
        "$support_bin/windres-wrapper" "$support_bin/wine"
}

print_configuration() {
    printf 'Rosette Xenia Windows capsule\n'
    printf 'source root: %s\nsource mirror: %s\n' "$original_source_root" "$source_mirror"
    printf 'build directory: %s\nsupport directory: %s\nbundle directory: %s\n' \
        "$build_dir" "$support_dir" "$bundle_dir"
    printf 'configuration: %s\ntarget: %s\njobs: %s\n' "$config" "$target" "$jobs"
    printf 'clang: %s\nclang++: %s\nlld: %s\nwindres: %s\nMinGW root: %s\n' \
        "$clang" "$clangxx" "$lld" "$windres" "$mingw_root"
    if [[ "$need_shader_tools" == 1 ]]; then
        printf 'shader compiler: %s\nglslangValidator: %s\nspirv-opt: %s\nspirv-dis: %s\n' \
            "$shader_compiler" "$glslang" "$spirv_opt" "$spirv_dis"
    fi
}

build_environment() {
    export PATH="$support_bin:$PATH"
    export FXC_PATH="$shader_compiler"
    if [[ "$need_shader_tools" == 1 ]]; then
        export VULKAN_SDK="$vulkan_tool_root"
    fi
    unset BASH_ENV CMAKE_C_COMPILER_LAUNCHER CMAKE_CXX_COMPILER_LAUNCHER
}

configure_xenia() {
    write_version_header
    (
        build_environment
        "$cmake" -S "$support_dir/cmake-wrapper" -B "$build_dir" \
            -G "Ninja Multi-Config" \
            -DCMAKE_TOOLCHAIN_FILE="$support_dir/windows-toolchain.cmake" \
            -DCMAKE_MAKE_PROGRAM="$ninja" \
            -DCMAKE_C_COMPILER="$support_bin/clang-c-wrapper" \
            -DCMAKE_CXX_COMPILER="$support_bin/clang-cxx-wrapper" \
            -DCMAKE_RC_COMPILER="$support_bin/windres-wrapper" \
            -DXENIA_BUILD_TESTS=OFF -DXENIA_BUILD_MISC=OFF \
            -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    )
}

build_xenia() {
    [[ -f "$build_dir/CMakeCache.txt" ]] ||
        die "CMake has not been configured in $build_dir; pass --configure first"
    (
        build_environment
        "$cmake" --build "$build_dir" --config "$config" --target "$target" \
            --parallel "$jobs"
    )
}

sha256_file() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        command -v sha256sum >/dev/null 2>&1 || die "shasum or sha256sum is required"
        sha256sum "$1" | awk '{print $1}'
    fi
}

bundle_xenia() {
    local executable="$build_dir/bin/Windows/$config/xenia_canary.exe"
    local name candidate source=""
    local media_destination=""
    [[ -f "$executable" ]] || die "built Xenia executable is missing: $executable"
    mkdir -p "$bundle_dir"
    cp -p "$executable" "$bundle_dir/xenia_canary.exe"
    for name in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll; do
        for candidate in "$build_dir/bin/Windows/$config/$name" "$mingw_root/bin/$name"; do
            if [[ -f "$candidate" ]]; then
                source="$candidate"
                break
            fi
        done
        [[ -n "$source" ]] || die "required MinGW runtime DLL is missing: $name"
        [[ "$source" == "$bundle_dir/$name" ]] || cp -p "$source" "$bundle_dir/$name"
        source=""
    done
    if [[ -n "$media_image" ]]; then
        [[ -f "$media_image" ]] || die "media image does not exist: $media_image"
        media_destination="$bundle_dir/$(basename "$media_image")"
        [[ "$media_image" == "$media_destination" ]] || cp -p "$media_image" "$media_destination"
    fi

    local manifest="$bundle_dir/rosette-xenia-windows.json"
    "$python3_bin" - "$manifest" "$bundle_dir" "$original_source_root" "$source_mirror" \
        "$source_commit" "$config" "$target" "$media_destination" <<'PY'
import hashlib
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
bundle_dir = pathlib.Path(sys.argv[2])

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

artifacts = []
for path in sorted(bundle_dir.iterdir()):
    if path.is_file() and path != manifest_path:
        artifacts.append({"name": path.name, "size": path.stat().st_size,
                          "sha256": digest(path)})

media = sys.argv[8]
payload = {
    "schema_version": 1,
    "kind": "rosette-xenia-windows-build",
    "source": {"root": sys.argv[3], "mirror": sys.argv[4], "commit": sys.argv[5]},
    "build": {"configuration": sys.argv[6], "target": sys.argv[7],
              "platform": "Windows", "architecture": "x86_64",
              "source_mutation_policy": "isolated-source-mirror"},
    "artifacts": artifacts,
    "media": None if not media else {
        "name": pathlib.Path(media).name, "sha256": digest(pathlib.Path(media))
    },
}
manifest_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
    printf 'bundle: %s\nexecutable: %s\n' "$bundle_dir" "$bundle_dir/xenia_canary.exe"
    printf 'executable sha256: %s\nmanifest: %s\n' \
        "$(sha256_file "$bundle_dir/xenia_canary.exe")" "$manifest"
}

original_source_root="$(env_value ROSETTE_XENIA_WINDOWS_SOURCE_ROOT)"
[[ -n "$original_source_root" ]] || original_source_root="$(env_value XENIA_ROOT)"
build_dir="$(env_value ROSETTE_XENIA_WINDOWS_BUILD_DIR)"
[[ -n "$build_dir" ]] || build_dir="$repo_root/.rosette/xenia-windows"
bundle_dir="$(env_value ROSETTE_XENIA_WINDOWS_BUNDLE_DIR)"
media_image="$(env_value ROSETTE_XENIA_WINDOWS_MEDIA_IMAGE)"
config=Release
target=xenia-app
jobs="$(env_value ROSETTE_XENIA_WINDOWS_JOBS)"
prepare=0
configure=0
build=0
bundle=0
print=0
source_commit=""
shader_compiler=""
glslang=""
spirv_opt=""
spirv_dis=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-root) [[ $# -ge 2 ]] || die "--source-root requires a path"; original_source_root="$2"; shift 2 ;;
        --build-dir) [[ $# -ge 2 ]] || die "--build-dir requires a path"; build_dir="$2"; shift 2 ;;
        --bundle-dir) [[ $# -ge 2 ]] || die "--bundle-dir requires a path"; bundle_dir="$2"; shift 2 ;;
        --media-image) [[ $# -ge 2 ]] || die "--media-image requires a path"; media_image="$2"; shift 2 ;;
        --config) [[ $# -ge 2 ]] || die "--config requires a value"; config="$2"; shift 2 ;;
        --target) [[ $# -ge 2 ]] || die "--target requires a value"; target="$2"; shift 2 ;;
        --jobs) [[ $# -ge 2 ]] || die "--jobs requires a number"; jobs="$2"; shift 2 ;;
        --prepare) prepare=1; shift ;;
        --configure) configure=1; shift ;;
        --build) build=1; shift ;;
        --bundle) bundle=1; shift ;;
        --print) print=1; shift ;;
        --help|-h) help; exit 0 ;;
        *) die "unknown argument: $1 (use --help)" ;;
    esac
done

if [[ "$prepare$configure$build$bundle$print" == 00000 ]]; then
    configure=1
    build=1
    bundle=1
fi
if [[ "$configure$build$bundle" != 000 ]]; then
    prepare=1
fi
[[ -n "$original_source_root" ]] || die "--source-root or XENIA_ROOT is required"
original_source_root="$(existing_dir "$original_source_root")"
build_dir="$(output_dir "$build_dir")"
source_mirror="$build_dir/source"
support_dir="$build_dir/rosette-support"
support_bin="$support_dir/bin"
support_tmp="$support_dir/tmp"
libusb_config_dir="$support_dir/libusb-config"
vulkan_tool_root="$support_dir/vulkan-sdk"
inner_build="$build_dir/xenia-inner"
[[ -n "$bundle_dir" ]] || bundle_dir="$build_dir/bundle"
bundle_dir="$(output_dir "$bundle_dir")"
[[ "$config" =~ ^[A-Za-z0-9_.-]+$ ]] || die "invalid CMake configuration: $config"
[[ "$target" =~ ^[A-Za-z0-9_.-]+$ ]] || die "invalid CMake target: $target"
[[ -n "$jobs" ]] || jobs="$(sysctl -n hw.ncpu 2>/dev/null || printf '4')"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die "jobs must be a positive integer: $jobs"
need_shader_tools=0
[[ "$build" == 1 ]] && need_shader_tools=1

validate_source
discover_tools
if [[ "$print" == 1 ]]; then
    print_configuration
    [[ "$prepare$configure$build$bundle" == 0000 ]] && exit 0
fi
if [[ "$prepare" == 1 ]]; then
    mirror_source
    write_version_header
    generate_support
fi
[[ "$configure" == 1 ]] && configure_xenia
[[ "$build" == 1 ]] && build_xenia
[[ "$bundle" == 1 ]] && bundle_xenia
printf 'rosette Xenia Windows capsule: PASS\n'
