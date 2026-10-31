FROM debian:bookworm-slim

LABEL author="piantech"
LABEL maintainer="alpincodeid@gmail.com"
LABEL org.opencontainers.image.title="Piantech"
LABEL org.opencontainers.image.description="Piantech Container Runtime"

ARG TARGETARCH=amd64

ENV DEBIAN_FRONTEND=noninteractive \
    USER=container \
    HOME=/home/container \
    NODE_INSTALL_DIR=/home/container/node \
    BUN_INSTALL=/usr/local/bun \
    PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/playwright \
    GO_VERSION=1.24.0 \
    PYTHON_VERSION=3.13.0

ENV PATH="/home/container/node/bin:/usr/local/bun/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

RUN apt-get update -o Acquire::Retries=5 \
    && apt-get install -y --no-install-recommends \
    curl wget git zip unzip tar gzip bzip2 \
    jq nano vim sudo ca-certificates gnupg \
    net-tools iputils-ping dnsutils procps \
    build-essential make gcc g++ \
    libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev libncursesw5-dev \
    xz-utils tk-dev libffi-dev liblzma-dev \
    libgdbm-dev libnss3-dev uuid-dev \
    p7zip-full zstd ffmpeg imagemagick \
    graphicsmagick webp mediainfo \
    fonts-liberation fonts-noto-color-emoji \
    libfontconfig1 libfreetype6 \
    libasound2 libgbm1 libgtk-3-0 \
    libnss3 libnspr4 libatk1.0-0 \
    libatk-bridge2.0-0 libcups2 libdrm2 \
    libdbus-1-3 libexpat1 libx11-xcb1 \
    libxcb-dri3-0 libxss1 libxtst6 \
    && rm -rf /var/lib/apt/lists/*

RUN case "$TARGETARCH" in \
    amd64) CF_ARCH=amd64 ;; \
    arm64) CF_ARCH=arm64 ;; \
    *) echo "Unsupported architecture: $TARGETARCH" && exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" \
    -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared \
    && cloudflared --version

RUN case "$TARGETARCH" in \
    amd64) GO_ARCH=amd64 ;; \
    arm64) GO_ARCH=arm64 ;; \
    *) echo "Unsupported architecture: $TARGETARCH" && exit 1 ;; \
    esac \
    && wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" \
    -O /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz

RUN cd /tmp \
    && wget -q "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz" -O Python.tgz \
    && tar -xzf Python.tgz \
    && cd "Python-${PYTHON_VERSION}" \
    && ./configure --with-ensurepip=install \
    && make -j2 altinstall \
    && ln -sf /usr/local/bin/python3.13 /usr/local/bin/python3 \
    && ln -sf /usr/local/bin/pip3.13 /usr/local/bin/pip3 \
    && cd /tmp \
    && rm -rf "Python-${PYTHON_VERSION}" Python.tgz \
    && python3 --version \
    && pip3 --version

RUN case "$TARGETARCH" in \
    amd64) BUN_ARCH=x64 ;; \
    arm64) BUN_ARCH=aarch64 ;; \
    *) echo "Unsupported architecture: $TARGETARCH" && exit 1 ;; \
    esac \
    && cd /tmp \
    && wget -q "https://github.com/oven-sh/bun/releases/latest/download/bun-linux-${BUN_ARCH}.zip" -O bun.zip \
    && unzip -q bun.zip \
    && mkdir -p "${BUN_INSTALL}/bin" \
    && mv "bun-linux-${BUN_ARCH}/bun" "${BUN_INSTALL}/bin/bun" \
    && chmod +x "${BUN_INSTALL}/bin/bun" \
    && rm -rf "bun-linux-${BUN_ARCH}" bun.zip \
    && bun --version

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update -o Acquire::Retries=5 \
    && apt-get install -y --no-install-recommends nodejs \
    && node --version \
    && npm --version \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}" \
    && npm install -g playwright \
    && node --version \
    && npm --version \
    && playwright --version \
    && playwright install --with-deps chromium \
    && chmod -R 777 "${PLAYWRIGHT_BROWSERS_PATH}"

RUN useradd -m -d /home/container container \
    && mkdir -p /home/container/node \
    && chown -R container:container /home/container \
    && chmod 755 /usr/local/bin/cloudflared

COPY ./entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

USER container

WORKDIR /home/container

CMD ["/bin/bash", "/entrypoint.sh"]
