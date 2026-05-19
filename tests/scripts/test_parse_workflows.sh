#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/profiler/parse_workflows.sh" "$CLAUDE_PLUGIN_ROOT/tests/fixtures/workflow.yml")
echo "$out" | grep -q "ruff check \."        || { echo "FAIL ruff"; exit 1; }
echo "$out" | grep -q "pytest tests/unit"     || { echo "FAIL pytest"; exit 1; }
echo "$out" | grep -q "pip install -r"        || { echo "FAIL multiline"; exit 1; }
echo "$out" | grep -q "sphinx-build docs build" || { echo "FAIL multiline2"; exit 1; }

echo "OK test_parse_workflows.sh"
