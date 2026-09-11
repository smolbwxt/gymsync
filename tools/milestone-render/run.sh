#!/usr/bin/env bash
# Render the GymSync milestone plate-stack frames headlessly.
#
#   tools/milestone-render/run.sh                 # full 51-frame set at 600x1500
#   tools/milestone-render/run.sh --preview       # frames 1/25/50 at half size
#   tools/milestone-render/run.sh --samples 128   # any render_plates.py flag passes through
#
# Set BLENDER=/path/to/blender.exe to override auto-detection.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Portable build lives outside Program Files (installed without elevation).
DEFAULT_BLENDER="/g/Tools/blender-5.2.1-windows-x64/blender.exe"

if [[ -z "${BLENDER:-}" ]]; then
  if [[ -x "$DEFAULT_BLENDER" ]]; then
    BLENDER="$DEFAULT_BLENDER"
  else
    # Fall back to a system install, newest wins.
    BLENDER="$(ls -d "/c/Program Files/Blender Foundation"/*/blender.exe 2>/dev/null | sort -V | tail -1 || true)"
  fi
fi
if [[ -z "${BLENDER:-}" || ! -x "$BLENDER" ]]; then
  echo "blender.exe not found (looked for $DEFAULT_BLENDER)." >&2
  echo "Set BLENDER=/path/to/blender.exe" >&2
  exit 1
fi

echo "Using: $BLENDER"
"$BLENDER" -b -P tools/milestone-render/render_plates.py -- \
  --out tools/milestone-render/out \
  --frames 51 \
  --size 600x1500 \
  --samples 96 \
  "$@"
