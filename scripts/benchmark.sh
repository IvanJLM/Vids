#!/bin/zsh
# Measures what Vids costs while it plays a video: memory (as Activity Monitor
# shows it), CPU, energy impact (Activity Monitor's Energy column), idle
# wake-ups per second and threads. With --compare it also measures
# IINA (if installed) on the same file. QuickTime Player is left out: it opens
# videos paused and starting it needs an automation permission prompt.
# Usage: ./scripts/benchmark.sh /path/to/video.mp4 [--compare]
set -euo pipefail
cd "$(dirname "$0")/.."
VIDEO="${1:?Usage: $0 /path/to/video [--compare]}"
WARMUP=8
SAMPLES=10

xcodegen generate --quiet
xcodebuild -project Vids.xcodeproj -scheme Vids -configuration Release \
  -derivedDataPath build/Bench -quiet build
VIDS="$PWD/build/Bench/Build/Products/Release/Vids.app"
# The benchmark copy must not ask to become the default player.
defaults write com.ivanjlm.vids AskedToBecomeDefault -bool true

measure() {  # name, app path, process name
  local name="$1" app="$2" process="$3"
  osascript -e "quit app \"$process\"" 2>/dev/null || true
  while pgrep -xq "$process"; do sleep 0.2; done
  open -a "$app" "$VIDEO"
  sleep $WARMUP
  local pid=$(pgrep -xn "$process")
  local stats=$(top -l $((SAMPLES + 1)) -s 1 -pid $pid -stats cpu,power,idlew,th | tr -d '+-' \
    | awk 'NR>1 && $1 ~ /^[0-9.]+$/' | tail -n $SAMPLES)
  local cpu=$(echo "$stats" | awk '{ s += $1 } END { printf "%.1f", s / NR }')
  local energy=$(echo "$stats" | awk '{ s += $2 } END { printf "%.1f", s / NR }')
  local wakeups=$(echo "$stats" | awk 'NR == 1 { a = $3 } { b = $3 } END { printf "%.0f", (b - a) / (NR - 1) }')
  local threads=$(echo "$stats" | tail -1 | awk '{ print $4 }' | cut -d/ -f1)
  local memory=$(footprint -p $pid 2>/dev/null | sed -nE 's/.*Footprint: ([0-9.]+ [KMG]?B).*/\1/p' | head -1)
  local size=$(du -sh "$app" | cut -f1)
  printf "| %-6s | %8s | %6s %% | %6s | %8s | %7s | %5s |\n" "$name" "$memory" "$cpu" "$energy" "$wakeups" "$threads" "$size"
  osascript -e "quit app \"$process\"" 2>/dev/null || kill $pid
  while pgrep -xq "$process"; do sleep 0.2; done
}

echo "Playing $(basename "$VIDEO"), averaged over $SAMPLES s after $WARMUP s:"
echo "| App    |   Memory |    CPU | Energy | Wake-ups | Threads |  Size |"
echo "|--------|----------|--------|--------|----------|---------|-------|"
measure "Vids" "$VIDS" Vids
if [[ "${2:-}" == "--compare" ]]; then
  [[ -d /Applications/IINA.app ]] && measure "IINA" /Applications/IINA.app IINA
fi
