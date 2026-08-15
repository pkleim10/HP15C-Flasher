#!/bin/bash
# Open the pogo-wing node editor (same idea as lunar-lander's trace-ship.html).
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
open "${ROOT}/scripts/trace-pogo-wings.html"
