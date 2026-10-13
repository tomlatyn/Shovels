#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
build_dir="$repo_root/build/screenshot"
output="$repo_root/docs/dashboard.png"

cd "$repo_root"

echo "Building Shovels (Debug)..."
xcodebuild \
  -project Shovels.xcodeproj \
  -scheme Shovels \
  -configuration Debug \
  -derivedDataPath "$build_dir" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet \
  build

app="$build_dir/Build/Products/Debug/Shovels.app"

echo "Rendering screenshot..."
"$app/Contents/MacOS/Shovels" --render-screenshot "$output"

echo "Updated $output"
