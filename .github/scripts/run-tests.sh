#!/usr/bin/env bash
# Runs the headless tests in tests/. Needs an imported project (run
# headless-build.sh or open the project in the editor first). Locally:
#   GODOT=/path/to/godot .github/scripts/run-tests.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
PORT="${TEST_PORT:-7790}"
cd "$(dirname "$0")/../.."

# People run the project straight from a checkout without opening the editor,
# so there is no .godot/ import cache (and no global class_name cache). Make
# sure the dedicated server still starts that way.
echo "::group::Dedicated server from a fresh checkout (no import)"
fresh="$(mktemp -d)"
git ls-files -z | xargs -0 cp --parents -t "$fresh"
fresh_log="$(mktemp)"
timeout 60 "$GODOT" --headless --path "$fresh" --server --port="$PORT" --accounts=user://test_fresh_accounts.db --quit-after 60 2>&1 | tee "$fresh_log"
rm -rf "$fresh"
echo "::endgroup::"
if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|ERROR:' "$fresh_log" >/dev/null; then
  echo "::error::The dedicated server hits errors on a fresh checkout that hasn't been imported."
  exit 1
fi
if ! grep -q "Accounts are saved in" "$fresh_log"; then
  echo "::error::The dedicated server didn't open its accounts database on a fresh checkout."
  exit 1
fi

echo "::group::AccountStore"
"$GODOT" --headless --path . -s tests/test_account_store.gd
echo "::endgroup::"

echo "::group::Login and character select against a listen-server host"
timeout 60 "$GODOT" --headless --path . -s tests/e2e_client.gd -- --host --port="$PORT" --accounts=user://test_host_accounts.db
echo "::endgroup::"

echo "::group::Server password, login and character select against a dedicated server"
server_log="$(mktemp)"
timeout 90 "$GODOT" --headless --path . --server --port="$((PORT + 1))" --accounts=user://test_server_accounts.db --server-password="let me in" >"$server_log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do
  grep -q "Dedicated server listening" "$server_log" && break
  sleep 1
done
status=0
timeout 60 "$GODOT" --headless --path . -s tests/e2e_client.gd -- --port="$((PORT + 1))" --server-password="let me in" || status=$?
kill "$server_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true
echo "Server log:"
cat "$server_log"
echo "::endgroup::"
if [[ $status -ne 0 ]]; then
  echo "::error::End-to-end test against the dedicated server failed."
  exit "$status"
fi
if grep -E 'SCRIPT ERROR|ERROR:' "$server_log" >/dev/null; then
  echo "::error::The dedicated server logged errors during the end-to-end test."
  exit 1
fi
