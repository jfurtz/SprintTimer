#!/bin/bash
# Sprint Time Tracker - macOS (and Linux) launcher. Double-click this file.
cd "$(dirname "$0")"
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required. Install it from https://nodejs.org (the LTS version), then double-click this file again."
  read -n 1 -s -r -p "Press any key to close..."
  exit 1
fi
node server.js
