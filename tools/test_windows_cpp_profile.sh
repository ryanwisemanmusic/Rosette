#!/usr/bin/env bash
# Compile-only tests: no Xenia, Windows executable or guest code is launched.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# == 2 ]] || { echo "usage: $0 SOURCE_ROOT SUPPORT_DIR" >&2; exit 2; }
source_root="$1"
support_dir="$2"
cpp_tool_prefix="${ROSETTE_XENIA_CPP_TOOL_PREFIX:-${repo_root}/build/rosette-support/windows-cpp-tool}"
transpiler="${cpp_tool_prefix}/bin/rosette-c-fix"
compiler="$support_dir/bin/clang-cxx-wrapper"
llvm_dis="${ROSETTE_XENIA_WINDOWS_LLVM_PREFIX:+${ROSETTE_XENIA_WINDOWS_LLVM_PREFIX}/bin/llvm-objdump}"
if [[ -z "$llvm_dis" ]]; then
  llvm_dis="$(command -v llvm-objdump || true)"
fi
if [[ -z "$llvm_dis" ]] && command -v brew >/dev/null 2>&1; then
  for formula in llvm@19 llvm@18 llvm; do
    prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
    if [[ -n "$prefix" && -x "$prefix/bin/llvm-objdump" ]]; then
      llvm_dis="$prefix/bin/llvm-objdump"
      break
    fi
  done
fi
[[ -n "$llvm_dis" && -x "$llvm_dis" ]] || { echo "llvm-objdump not found; install LLVM or set ROSETTE_XENIA_WINDOWS_LLVM_PREFIX" >&2; exit 127; }
fixture_dir="$(mktemp -d /tmp/rosette-windows-cpp-test.XXXXXX)"
fixture="$repo_root/tools/guest_runtime/windows/warning_contract_test.cc"
profiles=(
  third_party/microprofile/microprofile.h
  src/xenia/base/threading_win.cc
  src/xenia/ui/windowed_app_context_win.cc
  src/xenia/hid/xinput/xinput_input_driver.cc
  src/xenia/ui/windowed_app_main_win.cc
  src/xenia/base/main_init_win.cc
  src/xenia/gpu/command_processor.h
  src/xenia/gpu/draw_util.cc
  src/xenia/base/platform_win.h
)
# Compose the fixture's eight independent, exact-token source profiles.
for index in "${!profiles[@]}"; do
  output="$fixture_dir/fixture-$index.cc"
  "$transpiler" --windows-xenia-file "${profiles[$index]}" "$fixture" > "$output"
  fixture="$output"
done
"$compiler" -std=gnu++23 -fsyntax-only "$repo_root/tools/guest_runtime/windows/header_contract_test.cc"
"$compiler" -std=gnu++23 -O1 -S -emit-llvm "$fixture" -o "$fixture_dir/contract.ll"
"$compiler" -std=gnu++23 -O1 -c "$fixture" -o "$fixture_dir/contract.obj"
"$llvm_dis" -h -s "$fixture_dir/contract.obj" > "$fixture_dir/contract-coff.txt"
# init_priority must survive compilation as an ordered constructor section,
# and minsize must be attached only to GetResolveInfo's IR attribute group.
rg -q '\.ctors\.65434' "$fixture_dir/contract-coff.txt"
rg -q 'minsize' "$fixture_dir/contract.ll"
rg -q 'GetResolveInfo' "$fixture_dir/contract.ll"
rg -q 'ordinary_function' "$fixture_dir/contract.ll"
# Verify actual immutable inputs match all repairs, not just toy fixtures.
for index in "${!profiles[@]}"; do
  "$transpiler" --windows-xenia-file "${profiles[$index]}" "$source_root/${profiles[$index]}" > "$fixture_dir/actual-$index"
  if cmp -s "$source_root/${profiles[$index]}" "$fixture_dir/actual-$index"; then
    echo "FAIL: expected ABI profile did not match ${profiles[$index]}" >&2
    exit 1
  fi
done
# The same input/output profile is idempotent.
"$transpiler" --windows-xenia-file "${profiles[0]}" "$fixture_dir/actual-0" > "$fixture_dir/twice"
cmp "$fixture_dir/actual-0" "$fixture_dir/twice"
echo "Windows C++ ABI profile: PASS (six targeted diagnostics are fatal; compile-only; evidence=$fixture_dir)"
