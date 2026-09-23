#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 1 && -f "$1" ]] || { echo 'usage: verify_universal.sh <Mach-O executable>' >&2; exit 2; }
ARCHITECTURES="$(/usr/bin/lipo -archs "$1")"
for architecture in arm64 x86_64; do
  case " $ARCHITECTURES " in
    *" $architecture "*) ;;
    *) echo "Missing required architecture: $architecture ($ARCHITECTURES)" >&2; exit 1 ;;
  esac
done
