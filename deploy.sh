#!/bin/bash
# Antigravity Safe Deploy (macOS)
# Re-packages dist/ into the app.asar inside Antigravity.app
# Usage: bash deploy.sh

set -e

echo "============================================"
echo "  Antigravity Safe Deploy Script (macOS)"
echo "============================================"

# 1. Kill Antigravity
echo ""
echo "[1/6] Stopping Antigravity..."
pkill -f "Antigravity" 2>/dev/null || true
pkill -f "language_server" 2>/dev/null || true
sleep 3
echo "   OK"

# 2. Define paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASAR_PATH="/Applications/Antigravity.app/Contents/Resources/app.asar"
BACKUP_ASAR="${ASAR_PATH}.backup"
TEMP_DIR="$(mktemp -d -t antigravity_safe_deploy)"

# 3. Backup check - if no backup exists, back up the current asar
ASAR_UNPACKED="${ASAR_PATH}.unpacked"
BACKUP_ASAR_UNPACKED="${BACKUP_ASAR}.unpacked"

if [ -f "$BACKUP_ASAR" ]; then
    echo "[2/6] Backup found: $BACKUP_ASAR"
    if [ -d "$ASAR_UNPACKED" ] && [ ! -d "$BACKUP_ASAR_UNPACKED" ]; then
        echo "   Creating backup of unpacked directory..."
        cp -R "$ASAR_UNPACKED" "$BACKUP_ASAR_UNPACKED"
        echo "   Backup unpacked directory created."
    fi
elif [ -f "$ASAR_PATH" ]; then
    echo "[2/6] No backup found - creating backup of current asar..."
    cp "$ASAR_PATH" "$BACKUP_ASAR"
    if [ -d "$ASAR_UNPACKED" ]; then
        cp -R "$ASAR_UNPACKED" "$BACKUP_ASAR_UNPACKED"
    fi
    echo "   Backup created."
else
    echo "[2/6] ERROR: app.asar not found: $ASAR_PATH"
    exit 1
fi

# 4. Extract backup asar to temp directory
echo "[3/6] Extracting backup asar..."
rm -rf "$TEMP_DIR"
NODE_OPTIONS="--max-old-space-size=4096" npx -y @electron/asar extract "$BACKUP_ASAR" "$TEMP_DIR"

if [ $? -ne 0 ]; then
    echo "   ERROR: asar extract failed!"
    exit 1
fi
echo "   OK - Temp directory: $TEMP_DIR"

# 5. Copy dist/ from project and clean up
echo "[4/6] Updating dist/ and cleaning up..."
rm -rf "$TEMP_DIR/.git" 2>/dev/null || true
rm -rf "$TEMP_DIR/scratch" 2>/dev/null || true

SRC_DIST="$SCRIPT_DIR/dist"
DEST_DIST="$TEMP_DIR/dist"

rm -rf "$DEST_DIST"
cp -R "$SRC_DIST" "$DEST_DIST"
echo "   OK - dist copied."

# Also copy repack.ps1 and deploy.sh (updated versions)
SRC_REPACK="$SCRIPT_DIR/repack.ps1"
if [ -f "$SRC_REPACK" ]; then
    cp "$SRC_REPACK" "$TEMP_DIR/repack.ps1"
fi
SRC_REPACK_SH="$SCRIPT_DIR/repack.sh"
if [ -f "$SRC_REPACK_SH" ]; then
    cp "$SRC_REPACK_SH" "$TEMP_DIR/repack.sh"
fi

# 6. Re-pack app.asar
echo "[5/6] Packaging app.asar..."
rm -rf "$ASAR_UNPACKED"

npx -y @electron/asar pack "$TEMP_DIR" "$ASAR_PATH" --unpack-dir "node_modules"

if [ $? -ne 0 ]; then
    echo "   ERROR: Packaging failed! Restoring backup..."
    cp "$BACKUP_ASAR" "$ASAR_PATH"
    if [ -d "$BACKUP_ASAR_UNPACKED" ]; then
        rm -rf "$ASAR_UNPACKED"
        cp -R "$BACKUP_ASAR_UNPACKED" "$ASAR_UNPACKED"
    fi
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "   OK"

# Cleanup
rm -rf "$TEMP_DIR"

# 7. Relaunch Antigravity
echo "[6/6] Launching Antigravity..."
if [ -d "/Applications/Antigravity.app" ]; then
    open "/Applications/Antigravity.app"
    echo ""
    echo "============================================"
    echo "  SUCCESS! Antigravity restarted."
    echo "============================================"
else
    echo "  Warning: Antigravity.app not found. Launch manually."
fi
