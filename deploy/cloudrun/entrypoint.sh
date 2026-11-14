#!/bin/sh
# Starts mcp-auth-proxy, which runs email-mcp over stdio and serves it at /mcp.
#
# Mounted by Cloud Run:
#   /secrets/email/config.toml  Secret Manager: email-mcp config (accounts and settings)
#   /persist                    Cloud Storage bucket: proxy sign-in state, kept across cold starts
# Env (set on the service): EXTERNAL_URL, GOOGLE_CLIENT_ID, GOOGLE_ALLOWED_USERS,
#   GOOGLE_CLIENT_SECRET (from Secret Manager), PORT (from Cloud Run)
set -eu
umask 077

DATA_DIR=/tmp/proxy-data
PERSIST_DIR=/persist/proxy-data
CONFIG_DIR="$XDG_CONFIG_HOME/email-mcp"

mkdir -p "$CONFIG_DIR" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$DATA_DIR"

# Copy the config to a writable place (the server may rewrite it, e.g. refreshed OAuth tokens).
cp /secrets/email/config.toml "$CONFIG_DIR/config.toml"
[ -s "$CONFIG_DIR/config.toml" ] || { echo "[entrypoint] email-mcp config missing"; exit 1; }

# Restore the proxy's signing keys, registered clients and issued tokens.
if [ -d "$PERSIST_DIR" ]; then
  cp -R "$PERSIST_DIR/." "$DATA_DIR/" || echo "[entrypoint] restore of proxy state failed; clients must sign in again"
  chmod -R go-rwx "$DATA_DIR"
fi

save_state() {
  mkdir -p "$PERSIST_DIR" && cp -R "$DATA_DIR/." "$PERSIST_DIR/" \
    && echo "[entrypoint] proxy state saved" \
    || echo "[entrypoint] saving proxy state failed"
}

mcp-auth-proxy \
  --listen ":${PORT:-8080}" \
  --no-auto-tls \
  --external-url "$EXTERNAL_URL" \
  --data-path "$DATA_DIR" \
  --http-streaming-only \
  -- node /app/dist/main.js stdio &
PROXY_PID=$!

# Cloud Run sends SIGTERM before stopping an idle instance: stop the proxy so its
# database is closed, then save it to the bucket.
on_term() {
  kill -TERM "$PROXY_PID" 2>/dev/null || true
  wait "$PROXY_PID" 2>/dev/null || true
  save_state
  exit 0
}
trap on_term TERM INT

# No periodic saves: copying the database while the proxy has it open could save a
# torn file. If an instance is ever stopped without SIGTERM, claude.ai just signs in again.
STATUS=0
wait "$PROXY_PID" || STATUS=$?
save_state
exit "$STATUS"
