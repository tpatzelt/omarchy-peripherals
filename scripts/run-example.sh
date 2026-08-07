#!/usr/bin/env bash
# Run the standalone Quickshell example.
#
#   ./scripts/run-example.sh                        # read this machine's UPower
#   ./scripts/run-example.sh docs/sample-upower.txt # read a captured dump
#
# The second form is how you exercise the parser on a machine with nothing
# wireless paired: capture `upower --dump` from a machine that has peripherals,
# or use the sample fixture in docs/.
#
# Quickshell only scans QML inside the config directory it is pointed at, and
# Omarchy rejects symlinks inside a plugin folder — so the example cannot just
# link to ../../PeripheralsCore.qml. Instead we assemble a config directory
# containing the example plus a copy of the core, and run that.
#
# The directory is a fixed path that gets rebuilt on every run rather than a
# mktemp one that needs cleaning up: bash does not run an EXIT trap when it is
# killed by a signal, and Ctrl-C is exactly how you are expected to stop this.
# A stable path means at most one of these ever exists.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workdir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/omarchy-peripherals-example"

rm -rf "$workdir"
mkdir -p "$workdir"
cp "$repo/PeripheralsCore.qml" "$repo/examples/standalone/shell.qml" "$workdir/"

if [[ $# -gt 0 ]]; then
  # Absolute, because Quickshell is not started from this directory.
  PERIPHERALS_DUMP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  export PERIPHERALS_DUMP
  echo "Reading $PERIPHERALS_DUMP instead of upower"
fi

echo "Running the standalone example from $workdir (Ctrl-C to stop)"
exec quickshell -p "$workdir"
