#!/bin/bash

set -o pipefail

NODE_DIR="/home/container/node"
BUN_DIR="/usr/local/bun"
GO_DIR="/usr/local/go"

export PLAYWRIGHT_BROWSERS_PATH="/usr/local/share/playwright"
export NODE_PATH="$NODE_DIR/lib/node_modules"

mkdir -p "$NODE_DIR"

export PATH="$NODE_DIR/bin:$BUN_DIR/bin:$GO_DIR/bin:$PATH"

cat > /home/container/.bashrc <<EOF
export PATH="$NODE_DIR/bin:$BUN_DIR/bin:$GO_DIR/bin:\$PATH"
export NODE_PATH="$NODE_DIR/lib/node_modules"
export PLAYWRIGHT_BROWSERS_PATH="$PLAYWRIGHT_BROWSERS_PATH"
EOF

if [ -n "$NODE_VERSION" ]; then

    CURRENT_VER="none"

    if [ -x "$NODE_DIR/bin/node" ]; then
        CURRENT_VER=$("$NODE_DIR/bin/node" -v)
    fi

    if [ "$CURRENT_VER" = "none" ]; then
        CURRENT_VER=$(node -v 2>/dev/null || echo "none")
    fi

    PREFIX="${NODE_VERSION#v}"

    TARGET_VER=$(curl -fsSL https://nodejs.org/dist/index.json | \
        jq -r --arg prefix "v${PREFIX}" \
        '[.[] | select(.version | startswith($prefix))][0].version // empty' 2>/dev/null)

    if [ -z "$TARGET_VER" ]; then
        echo "ERROR: Node.js version ${NODE_VERSION} tidak ditemukan."
        exit 1
    fi

    if [ "$CURRENT_VER" != "$TARGET_VER" ]; then

        echo "Installing Node.js ${TARGET_VER}..."

        ARCH=$(dpkg --print-architecture)

        case "$ARCH" in
            amd64) NODE_ARCH="x64" ;;
            arm64) NODE_ARCH="arm64" ;;
            *)
                echo "Unsupported architecture: $ARCH"
                exit 1
                ;;
        esac

        rm -rf "$NODE_DIR"/*
        mkdir -p "$NODE_DIR"

        cd /tmp

        curl -fL \
            "https://nodejs.org/dist/${TARGET_VER}/node-${TARGET_VER}-linux-${NODE_ARCH}.tar.gz" \
            -o node.tar.gz || exit 1

        tar -xzf node.tar.gz \
            --strip-components=1 \
            -C "$NODE_DIR" || exit 1

        rm -f node.tar.gz

        export PATH="$NODE_DIR/bin:$BUN_DIR/bin:$GO_DIR/bin:$PATH"

        echo "Installing global Node.js packages..."

        npm install -g \
            pm2 \
            pnpm \
            yarn \
            playwright \
            --loglevel=error || exit 1

        echo "Installing Playwright browsers..."

        playwright install || exit 1

        cd /home/container

        echo "Node.js installation completed."
    fi
fi

if [[ "$ENABLE_CF_TUNNEL" == "true" || "$ENABLE_CF_TUNNEL" == "1" ]]; then

    if [ -n "$CF_TOKEN" ]; then

        if command -v cloudflared >/dev/null 2>&1; then

            pkill -x cloudflared 2>/dev/null || true

            nohup cloudflared tunnel run \
                --token "$CF_TOKEN" \
                > /home/container/.cloudflared.log 2>&1 &

            echo "Cloudflare Tunnel started."

        else
            echo "ERROR: cloudflared is not installed."
        fi

    else
        echo "WARNING: CF_TOKEN is empty."
    fi
fi

clear 2>/dev/null || true

echo "----------------------------------------------------------"
echo "                         PIANTECH                           "
echo "----------------------------------------------------------"

COUNTRY=$(curl -fsSL --max-time 5 https://ipinfo.io/country 2>/dev/null || echo "Unknown")

OS=$(grep -oP '(?<=^PRETTY_NAME=).+' /etc/os-release | tr -d '"' || echo "Unknown")

CPU=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //' || echo "Unknown")

CORES=$(grep -c ^processor /proc/cpuinfo)

UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "Unknown")

RAM=$(free -m | awk '/Mem:/ {print $3" MB / "$2" MB"}')

DISK=$(df -h / | awk 'NR==2 {print $3" / "$2" ("$5")"}')

echo "Location   : $COUNTRY"
echo "OS         : $OS"
echo "CPU        : $CPU ($CORES Cores)"
echo "Uptime     : $UPTIME"
echo ""
echo "RAM Usage  : $RAM"
echo "Disk Usage : $DISK"

echo "----------------------------------------------------------"
echo "                     RUNTIME VERSIONS                     "
echo "----------------------------------------------------------"

NODE_VER=$(node -v 2>/dev/null || echo "Not Installed")
BUN_VER=$(bun -v 2>/dev/null || echo "Not Installed")
GO_VER=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go/v/' )
PYTHON_VER=$(python3 --version 2>/dev/null | awk '{print "v"$2}')
PLAYWRIGHT_VER=$(playwright --version 2>/dev/null | head -n 1)

echo "Node.js    : ${NODE_VER}"
echo "Bun        : ${BUN_VER:-Not Installed}"
echo "Golang     : ${GO_VER:-Not Installed}"
echo "Python     : ${PYTHON_VER:-Not Installed}"
echo "Playwright : ${PLAYWRIGHT_VER:-Not Installed}"
echo "Cloudflared: $(cloudflared --version 2>/dev/null | head -n 1 || echo 'Not Installed')"

echo "----------------------------------------------------------"
echo "                   PIANTECH RUNTIME READY                 "
echo "----------------------------------------------------------"

cd /home/container

exec /bin/bash
