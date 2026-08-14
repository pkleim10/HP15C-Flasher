#!/bin/bash
# Release packaging. Prefer: scripts/package_dmg.sh
exec "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/package_dmg.sh" "$@"
