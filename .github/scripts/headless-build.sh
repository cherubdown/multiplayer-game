#!/usr/bin/env bash
# Headless import + export of the Godot project. Used by CI and runnable locally:
#   GODOT=/path/to/godot .github/scripts/headless-build.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
EXPORT_PRESET="${EXPORT_PRESET:-Linux}"
OUT_DIR="${OUT_DIR:-build/linux}"

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
project_file="$(find "$repo_root" -name project.godot -not -path '*/.godot/*' -not -path '*/addons/*' | sort | head -n1)"
if [[ -z "$project_file" ]]; then
  echo "::error::No project.godot found in the repository."
  exit 1
fi
project_dir="$(dirname "$project_file")"
echo "Godot project: ${project_dir#"$repo_root"/}"
cd "$project_dir"

log_dir="$(mktemp -d)"

# Godot exits 0 on script parse errors, so scan the log as well as the exit code.
check_log() {
  local log="$1" step="$2"
  if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource' "$log" >/dev/null; then
    echo "::error::$step reported script or resource errors:"
    grep -E -A1 'SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource' "$log"
    exit 1
  fi
}

echo "::group::Import"
set +e
"$GODOT" --headless --import 2>&1 | tee "$log_dir/import.log"
status=${PIPESTATUS[0]}
set -e
echo "::endgroup::"
if [[ $status -ne 0 ]]; then
  echo "::error::Import failed with exit code $status."
  exit "$status"
fi
check_log "$log_dir/import.log" "Import"

# Use the project's own export preset when it has one; otherwise add a
# throwaway Linux preset so CI still proves the project exports.
if [[ -f export_presets.cfg ]] && grep -q "^name=\"$EXPORT_PRESET\"" export_presets.cfg; then
  echo "Using export preset \"$EXPORT_PRESET\" from export_presets.cfg"
else
  if [[ -f export_presets.cfg ]]; then
    echo "::error::export_presets.cfg has no preset named \"$EXPORT_PRESET\"."
    exit 1
  fi
  echo "No export_presets.cfg; generating a temporary \"$EXPORT_PRESET\" preset"
  cat > export_presets.cfg <<PRESET
[preset.0]

name="$EXPORT_PRESET"
platform="Linux"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="$OUT_DIR/game.x86_64"

[preset.0.options]

binary_format/embed_pck=false
binary_format/architecture="x86_64"
PRESET
  trap 'rm -f "$project_dir/export_presets.cfg"' EXIT
fi

mkdir -p "$OUT_DIR"
echo "::group::Export"
set +e
"$GODOT" --headless --export-release "$EXPORT_PRESET" "$OUT_DIR/game.x86_64" 2>&1 | tee "$log_dir/export.log"
status=${PIPESTATUS[0]}
set -e
echo "::endgroup::"
if [[ $status -ne 0 ]]; then
  echo "::error::Export failed with exit code $status."
  exit "$status"
fi
check_log "$log_dir/export.log" "Export"

if [[ ! -s "$OUT_DIR/game.x86_64" ]]; then
  echo "::error::Export finished but $OUT_DIR/game.x86_64 is missing."
  exit 1
fi
echo "Exported:"
ls -la "$OUT_DIR"
