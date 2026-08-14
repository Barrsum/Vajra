#!/usr/bin/env sh
# Launches VAJRA on Linux and macOS. The Windows equivalent is PLAY.bat.
#
# Godot is not committed to this repo, so this goes looking for it: a copy in
# ./godot/, a $GODOT environment variable, or anything named godot on PATH.

set -e
cd "$(dirname "$0")"

GODOT_BIN=""

# 1. A copy inside the repo (godot/ is gitignored).
for f in ./godot/Godot_v* ./godot/godot ./godot/Godot.app/Contents/MacOS/Godot; do
	if [ -x "$f" ]; then GODOT_BIN="$f"; break; fi
done

# 2. An explicit override.
if [ -z "$GODOT_BIN" ] && [ -n "$GODOT" ] && [ -x "$GODOT" ]; then
	GODOT_BIN="$GODOT"
fi

# 3. On PATH, under any of the names the builds ship with.
if [ -z "$GODOT_BIN" ]; then
	for n in godot godot4 Godot; do
		if command -v "$n" >/dev/null 2>&1; then GODOT_BIN="$(command -v "$n")"; break; fi
	done
fi

# 4. The standard macOS install location.
if [ -z "$GODOT_BIN" ] && [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
	GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
fi

if [ -z "$GODOT_BIN" ]; then
	cat <<'EOF'

  Could not find Godot.

  VAJRA needs Godot 4.7.1 (Standard, not .NET). It is a single portable
  binary - there is nothing to install.

    1. Download it:  https://godotengine.org/download/archive/
    2. Put it in a folder called  godot  next to this script,
       or set GODOT=/path/to/godot
    3. Run ./play.sh again

EOF
	exit 1
fi

echo "Launching with $GODOT_BIN"
exec "$GODOT_BIN" --path . "$@"
