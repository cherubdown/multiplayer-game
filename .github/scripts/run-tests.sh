#!/usr/bin/env bash
# Runs the headless tests in tests/. Needs an imported project (run
# headless-build.sh or open the project in the editor first). Locally:
#   GODOT=/path/to/godot .github/scripts/run-tests.sh
# With DATABASE_URL set (CI sets it), the account store tests and the
# dedicated server also run against that PostgreSQL database.
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
timeout 60 "$GODOT" --headless --path "$fresh" --server --port="$PORT" --quit-after 60 2>&1 | tee "$fresh_log"
rm -rf "$fresh"
echo "::endgroup::"
if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script' "$fresh_log" >/dev/null; then
  echo "::error::The dedicated server hits script errors on a fresh checkout that hasn't been imported."
  exit 1
fi

echo "::group::Account stores"
"$GODOT" --headless --path . -s tests/test_account_store.gd
echo "::endgroup::"

if [[ -n "${DATABASE_URL:-}" ]]; then
  echo "::group::Dedicated server refuses to start with a bad DATABASE_URL"
  bad_log="$(mktemp)"
  if DATABASE_URL="postgres://nobody:wrong@127.0.0.1:1/none?sslmode=disable" \
      timeout 60 "$GODOT" --headless --path . --server --port="$((PORT + 2))" --quit-after 600 >"$bad_log" 2>&1; then
    cat "$bad_log"
    echo "::error::The dedicated server started even though it couldn't reach its database."
    exit 1
  fi
  cat "$bad_log"
  echo "::endgroup::"
fi

echo "::group::Login and character select against a listen-server host"
timeout 60 "$GODOT" --headless --path . -s tests/e2e_client.gd -- --host --port="$PORT" --accounts=user://test_host_accounts.json
echo "::endgroup::"

echo "::group::Login and character select against a dedicated server"
server_log="$(mktemp)"
server_accounts=(--accounts=user://test_server_accounts.json)
[[ -n "${DATABASE_URL:-}" ]] && server_accounts=()
timeout 90 "$GODOT" --headless --path . --server --port="$((PORT + 1))" "${server_accounts[@]}" >"$server_log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do
  grep -q "Dedicated server listening" "$server_log" && break
  sleep 1
done
status=0
timeout 60 "$GODOT" --headless --path . -s tests/e2e_client.gd -- --port="$((PORT + 1))" || status=$?
kill "$server_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true
echo "Server log:"
cat "$server_log"
echo "::endgroup::"
if [[ $status -ne 0 ]]; then
  echo "::error::End-to-end test against the dedicated server failed."
  exit "$status"
fi
if [[ -n "${DATABASE_URL:-}" ]] && ! grep -q "Accounts are saved in PostgreSQL" "$server_log"; then
  echo "::error::DATABASE_URL is set but the dedicated server didn't keep accounts in PostgreSQL."
  exit 1
fi
if grep -E 'SCRIPT ERROR|ERROR:' "$server_log" >/dev/null; then
  echo "::error::The dedicated server logged errors during the end-to-end test."
  exit 1
fi
