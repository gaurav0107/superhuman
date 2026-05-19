# tests/scripts/test_detect_smoke.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/profiler/detect_smoke.sh" \
        "$CLAUDE_PLUGIN_ROOT/tests/fixtures/smoke_python")

echo "$out" | jq -e '.layers | map(.name) | index("python_import_root") != null' >/dev/null \
  || { echo "FAIL python_import_root not detected"; exit 1; }
echo "$out" | jq -e '.layers | map(.name) | index("django_check") == null' >/dev/null \
  || { echo "FAIL django_check false positive"; exit 1; }

echo "OK test_detect_smoke.sh"
