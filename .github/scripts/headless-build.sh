#!/usr/bin/env bash
# Headless import + export of the Godot project. Used by CI and runnable locally:
#   GODOT=/path/to/godot .github/scripts/headless-build.sh
# Exports each preset in EXPORT_PRESETS (semicolon-separated) to the
# export_path set for it in export_presets.cfg.
set -euo pipefail

GODOT="${GODOT:-godot}"
EXPORT_PRESETS="${EXPORT_PRESETS:-Windows Desktop;Windows Dedicated Server}"

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
project_file="$(find "$repo_root" -name project.godot -not -path '*/.godot/*' -not -path '*/addons/*' | sort | head -n1)"
if [[ -z "$project_file" ]]; then
  echo "::error::No project.godot found in the repository."
  exit 1
fi
project_dir="$(dirname "$project_file")"
echo "Godot project: ${project_dir#"$repo_root"/}"
cd "$project_dir"

if [[ ! -f export_presets.cfg ]]; then
  echo "::error::No export_presets.cfg next to project.godot."
  exit 1
fi

log_dir="$(mktemp -d)"

# Godot exits 0 on script parse errors, so scan the log as well as the exit code.
run_godot() {
  local step="$1"; shift
  local log="$log_dir/$(echo "$step" | tr -c 'A-Za-z0-9' '_').log"
  echo "::group::$step"
  set +e
  "$GODOT" --headless "$@" 2>&1 | tee "$log"
  local status=${PIPESTATUS[0]}
  set -e
  echo "::endgroup::"
  if [[ $status -ne 0 ]]; then
    echo "::error::$step failed with exit code $status."
    exit "$status"
  fi
  if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource' "$log" >/dev/null; then
    echo "::error::$step reported script or resource errors:"
    grep -E -A1 'SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource' "$log"
    exit 1
  fi
}

# Prints the export_path of the named preset in export_presets.cfg.
preset_export_path() {
  awk -v want="name=\"$1\"" '
    /^\[preset\.[0-9]+\]$/ { in_preset = 1; found = 0; next }
    /^\[/ { in_preset = 0 }
    in_preset && $0 == want { found = 1 }
    in_preset && found && /^export_path=/ { sub(/^export_path="/, ""); sub(/"$/, ""); print; exit }
  ' export_presets.cfg
}

# Godot 4.7.2 crashes on exit when a first import discovers a GDExtension
# (godot-sqlite), so list the extensions up front the way the editor would.
mkdir -p .godot
find . -name '*.gdextension' -not -path './.godot/*' | sed 's#^\./#res://#' | sort > .godot/extension_list.cfg

run_godot "Import" --import

IFS=';' read -r -a presets <<< "$EXPORT_PRESETS"
for preset in "${presets[@]}"; do
  out="$(preset_export_path "$preset")"
  if [[ -z "$out" ]]; then
    echo "::error::export_presets.cfg has no preset named \"$preset\" with an export_path."
    exit 1
  fi
  mkdir -p "$(dirname "$out")"
  run_godot "Export $preset" --export-release "$preset" "$out"
  if [[ ! -s "$out" ]]; then
    echo "::error::Export of \"$preset\" finished but $out is missing."
    exit 1
  fi
  echo "Exported \"$preset\":"
  ls -la "$(dirname "$out")"
done
