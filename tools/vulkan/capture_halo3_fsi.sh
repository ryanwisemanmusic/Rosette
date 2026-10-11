#!/usr/bin/env bash
# A bounded diagnostic launch; all evidence belongs to Rosette, not Xenia.
set -euo pipefail
task_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
task_root="$(cd "$task_dir/../.." && pwd)"
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  cat <<'HELP'
Usage: capture_halo3_fsi.sh [--lean] [--frame N | --profile-only] [launcher arguments]

Default: enable shader evidence and Metal validation; F10 captures one frame.
--frame N: capture one specified present frame without pressing F10.
--profile-only: CPU sampling with capture and Metal validation disabled.
--print: print the resolved launcher command without launching the game.
--lean: keep only the GFXReconstruct frame capture (no Metal shader validation,
        which is slow and stops at the first reported fault). Use this to look at a
        picture problem such as the white orbs: `capture_halo3_fsi.sh --lean --frame 1259`,
        then run capture_replay.py dump/index on the rosette-vulkan*.gfxr file written
        beside the run log (the log's VULKAN CAPTURE STATUS line names it).

Evidence is stored in Rosette's .rosette/xenia-fsi-evidence directory.
Build the current runner before capture. Validation runs are slower, so use
--profile-only for performance measurements.
HELP
  exit 0
fi
export ROSETTE_XENIA_ROSETTE_DIR="${ROSETTE_XENIA_ROSETTE_DIR:-$task_root/.rosette/xenia-fsi-evidence}"
export ROSETTE_FSI_EVIDENCE=1
export ROSETTE_VULKAN_GFXR=1
export MTL_SHADER_VALIDATION=1
export MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1
export MTL_SHADER_VALIDATION_FAIL_MODE=zerofill
export MTL_SHADER_VALIDATION_ABORT_ON_FAULT=1
export MTL_SHADER_VALIDATION_DUMP_PIPELINES=1
export ROSETTE_XENIA_SCENARIO="${ROSETTE_XENIA_SCENARIO:-halo3-fsi-shader-fault-capture}"
if [[ "${1:-}" == --lean ]]; then
  shift
  unset MTL_SHADER_VALIDATION MTL_SHADER_VALIDATION_REPORT_TO_STDERR MTL_SHADER_VALIDATION_FAIL_MODE MTL_SHADER_VALIDATION_ABORT_ON_FAULT MTL_SHADER_VALIDATION_DUMP_PIPELINES
  export ROSETTE_XENIA_SCENARIO=halo3-fsi-lean-capture
fi
case "${1:-}" in
  --profile-only)
    shift
    export ROSETTE_FSI_EVIDENCE=0 ROSETTE_VULKAN_GFXR=0 ROSETTE_HOST_PROFILE=1
    unset MTL_SHADER_VALIDATION MTL_SHADER_VALIDATION_REPORT_TO_STDERR MTL_SHADER_VALIDATION_FAIL_MODE MTL_SHADER_VALIDATION_ABORT_ON_FAULT MTL_SHADER_VALIDATION_DUMP_PIPELINES
    export ROSETTE_XENIA_SCENARIO=halo3-fsi-cpu-profile
    ;;
  --frame)
    [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || { echo "--frame requires a positive present frame" >&2; exit 2; }
    export ROSETTE_VULKAN_GFXR="frames:$2"
    shift 2
    ;;
esac
if [[ "${ROSETTE_VULKAN_GFXR}" == 1 ]]; then
  echo "FSI evidence: press F10 once while the damaged world is visible; one frame is saved."
  if [[ -n "${MTL_SHADER_VALIDATION:-}" ]]; then
    echo "Metal validation stops at the first reported shader fault. This diagnostic run is slower."
  fi
fi
exec "$task_root/tools/xenia/scripts/rosette-xenia-run.sh" "$@"
