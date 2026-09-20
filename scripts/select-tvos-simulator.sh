#!/usr/bin/env bash
set -euo pipefail

# Select by UUID so model names containing parentheses remain unambiguous.
sed -nE '/^[[:space:]]*Apple TV/{s/.*\(([[:xdigit:]-]{36})\) \((Booted|Shutdown)\) *$/\1/p;}' | head -n 1
