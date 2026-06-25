#!/usr/bin/env bash
# run_all.sh -- thin wrapper around 'make all'.
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
exec make -C "$REPO" all
