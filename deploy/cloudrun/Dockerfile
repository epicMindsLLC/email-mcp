# Cloud Run image: email-mcp (IMAP/SMTP, stdio) behind mcp-auth-proxy (OAuth 2.1 + Google sign-in).
# Build context is the repository root:  docker build -f deploy/cloudrun/Dockerfile .

FROM node:24-slim AS build
WORKDIR /app
# corepack picks the pnpm version from packageManager in package.json.
RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY patches/ patches/
RUN pnpm install --frozen-lockfile
COPY tsconfig.json tsconfig.build.json ./
COPY src/ src/
RUN pnpm build && pnpm prune --prod

FROM node:24-slim AS proxy
ARG PROXY_VERSION=v2.10.2
ARG PROXY_SHA256=1c76b230fdb6c536a0912c059232cba2229acbcf1f02a11a5d0664781326bcd6
# Cloud Build's docker does not support ADD --checksum, so verify by hand.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && curl -fsSL -o /mcp-auth-proxy \
    "https://github.com/sigbit/mcp-auth-proxy/releases/download/${PROXY_VERSION}/mcp-auth-proxy-linux-amd64" \
 && echo "${PROXY_SHA256}  /mcp-auth-proxy" | sha256sum -c - \
 && chmod 0755 /mcp-auth-proxy

FROM node:24-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tini \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/package.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=proxy /mcp-auth-proxy /usr/local/bin/mcp-auth-proxy
COPY deploy/cloudrun/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

# Only /tmp is writable on Cloud Run. Config is copied in from the mounted secret;
# state and cache are scratch space that lives as long as the instance.
ENV XDG_CONFIG_HOME=/tmp/xdg/config \
    XDG_STATE_HOME=/tmp/xdg/state \
    XDG_CACHE_HOME=/tmp/xdg/cache \
    XDG_DATA_HOME=/tmp/xdg/data \
    NODE_ENV=production \
    NO_COLOR=1

USER node
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
