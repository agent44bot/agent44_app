#!/usr/bin/env bash
# Run the apply runner (headed) against the live queue on the Mac Mini.
set -euo pipefail
cd "$(dirname "$0")"
export AGENT44_API_TOKEN="${AGENT44_API_TOKEN:-$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.openclaw/credentials/agent44.json")))["AGENT44_API_TOKEN"])')}"
exec node apply_runner.mjs "$@"
