#!/usr/bin/env bash
# Downloads a pinned Node.js runtime and installs wrangler into it, then stages a
# self-contained runtime under Sources/WranglerMac/Runtime/ that the app bundles
# and invokes directly. Re-run to update the pinned versions.
set -euo pipefail

NODE_VERSION="v24.18.0"
ARCH="$(uname -m)"        # arm64 or x86_64
case "$ARCH" in
  arm64)  NODE_ARCH="arm64" ;;
  x86_64) NODE_ARCH="x64" ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$ROOT/Runtime"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Downloading Node $NODE_VERSION ($NODE_ARCH)"
TARBALL="node-${NODE_VERSION}-darwin-${NODE_ARCH}.tar.gz"
curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${TARBALL}" -o "$WORK/node.tar.gz"
tar -xzf "$WORK/node.tar.gz" -C "$WORK"
NODE_HOME="$WORK/node-${NODE_VERSION}-darwin-${NODE_ARCH}"

echo "==> Installing wrangler with bundled npm"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
( cd "$STAGE"
  "$NODE_HOME/bin/node" "$NODE_HOME/bin/npm" init -y >/dev/null
  "$NODE_HOME/bin/node" "$NODE_HOME/bin/npm" install wrangler \
      --omit=dev --no-audit --no-fund --loglevel=error )

echo "==> Staging runtime into $RUNTIME_DIR"
rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR/bin"
cp "$NODE_HOME/bin/node" "$RUNTIME_DIR/bin/node"
chmod +x "$RUNTIME_DIR/bin/node"
cp -R "$STAGE/node_modules" "$RUNTIME_DIR/node_modules"

# Trim workerd's fallback binary copies (~240MB). The authoritative binary that
# miniflare resolves is @cloudflare/workerd-<platform>/bin/workerd; the copies in
# workerd/bin and workerd/lib/downloaded-* are only used when that optional dep
# can't be resolved, which never happens in our self-contained bundle.
rm -f "$RUNTIME_DIR"/node_modules/workerd/bin/workerd \
      "$RUNTIME_DIR"/node_modules/workerd/lib/downloaded-* 2>/dev/null || true

# Record versions for the About/Settings screen.
WRANGLER_VER="$("$NODE_HOME/bin/node" -e "console.log(require('$STAGE/node_modules/wrangler/package.json').version)")"
cat > "$RUNTIME_DIR/runtime.json" <<JSON
{ "node": "$NODE_VERSION", "wrangler": "$WRANGLER_VER", "arch": "$NODE_ARCH" }
JSON

echo "==> Done. node $NODE_VERSION / wrangler $WRANGLER_VER / $NODE_ARCH"
du -sh "$RUNTIME_DIR"
