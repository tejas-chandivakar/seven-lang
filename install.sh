#!/bin/sh
# ============================================================
# SEVEN Language — one-line installer (Linux / WSL, x86-64)
#
#   curl -fsSL https://raw.githubusercontent.com/tejas-chandivakar/seven-lang/main/install.sh | sh
#
# No build tools needed — downloads a prebuilt static binary.
# Override install dir:   SEVEN_BIN_DIR=/usr/local/bin  (default: ~/.local/bin)
# Install a specific tag: SEVEN_VERSION=v1.0.0          (default: latest)
# ============================================================
set -eu

REPO="tejas-chandivakar/seven-lang"
BIN_DIR="${SEVEN_BIN_DIR:-$HOME/.local/bin}"
VERSION="${SEVEN_VERSION:-latest}"

# --- platform check ---------------------------------------------------------
OS="$(uname -s 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"
if [ "$OS" != "Linux" ]; then
  echo "Error: prebuilt binary supports Linux/WSL only (got: $OS)." >&2
  echo "On Windows, run this inside WSL. macOS build is not available yet." >&2
  exit 1
fi
if [ "$ARCH" != "x86_64" ]; then
  echo "Error: prebuilt binary is x86-64 only (got: $ARCH)." >&2
  exit 1
fi

# --- pick a downloader ------------------------------------------------------
if command -v curl >/dev/null 2>&1; then
  DL="curl -fsSL -o"
elif command -v wget >/dev/null 2>&1; then
  DL="wget -qO"
else
  echo "Error: need curl or wget installed." >&2
  exit 1
fi

if [ "$VERSION" = "latest" ]; then
  URL="https://github.com/$REPO/releases/latest/download/seven"
else
  URL="https://github.com/$REPO/releases/download/$VERSION/seven"
fi

# --- download ---------------------------------------------------------------
mkdir -p "$BIN_DIR"
TMP="$(mktemp)"
echo "Downloading SEVEN ($VERSION) ..."
# shellcheck disable=SC2086
$DL "$TMP" "$URL"
chmod +x "$TMP"
mv "$TMP" "$BIN_DIR/seven"
echo "Installed: $BIN_DIR/seven"

# --- install tools (spm, fmt, lint, test, profile) -------------------------
TOOLS_URL="https://raw.githubusercontent.com/$REPO/main/tools"
for tool in spm fmt lint test profile; do
  TMP="$(mktemp)"
  echo "Downloading seven-$tool ..."
  # shellcheck disable=SC2086
  $DL "$TMP" "$TOOLS_URL/$tool" 2>/dev/null && {
    chmod +x "$TMP"
    mv "$TMP" "$BIN_DIR/seven-$tool"
    echo "Installed: $BIN_DIR/seven-$tool"
  } || {
    rm -f "$TMP"
    echo "Skipped: seven-$tool (not available)"
  }
done
# spm also available as standalone 'spm'
if [ -f "$BIN_DIR/seven-spm" ]; then
  ln -sf "$BIN_DIR/seven-spm" "$BIN_DIR/spm" 2>/dev/null || true
fi

# --- PATH hint --------------------------------------------------------------
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo ""
    echo "NOTE: $BIN_DIR is not on your PATH. Add this to your shell rc:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac

# --- verify -----------------------------------------------------------------
echo ""
"$BIN_DIR/seven" version || true
echo ""
echo "Done. Try it:"
echo "  echo 'show \"Hello from SEVEN!\"' > hello.seven"
echo "  seven run hello.seven"
