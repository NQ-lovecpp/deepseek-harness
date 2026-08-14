FROM docker:29-cli AS docker-cli

FROM node:24-bookworm-slim AS builder

ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0

WORKDIR /app

RUN sed -i \
      -e 's|http://deb.debian.org/debian-security|http://mirrors.tuna.tsinghua.edu.cn/debian-security|g' \
      -e 's|http://deb.debian.org/debian|http://mirrors.tuna.tsinghua.edu.cn/debian|g' \
      /etc/apt/sources.list.d/debian.sources \
    && apt-get -o Acquire::ForceIPv4=true -o Acquire::Retries=3 update \
    && apt-get install --yes --no-install-recommends git python3 make g++

RUN corepack enable && corepack prepare pnpm@11.7.0 --activate

COPY . .

RUN pnpm install --frozen-lockfile && pnpm run build

FROM node:24-bookworm-slim

ARG DOCKER_GID=988

ENV DSH_HOME=/dsh-state/dsh \
    HOME=/dsh-state/home \
    PATH=/app/node_modules/.bin:${PATH}

RUN sed -i \
      -e 's|http://deb.debian.org/debian-security|http://mirrors.tuna.tsinghua.edu.cn/debian-security|g' \
      -e 's|http://deb.debian.org/debian|http://mirrors.tuna.tsinghua.edu.cn/debian|g' \
      /etc/apt/sources.list.d/debian.sources \
    && apt-get -o Acquire::ForceIPv4=true -o Acquire::Retries=3 update \
    && apt-get install --yes --no-install-recommends ca-certificates curl systemd util-linux \
    && groupadd --gid "${DOCKER_GID}" docker-host \
    && usermod --append --groups docker-host node

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=builder --chown=node:node /app /app
COPY deploy/spark/entrypoint.sh /usr/local/bin/dsh-entrypoint
COPY deploy/spark/settings.yaml /opt/dsh-seed/settings.yaml
COPY deploy/spark/cordis.patch.yml /opt/dsh-seed/cordis.patch.yml

RUN chmod 0755 /usr/local/bin/dsh-entrypoint \
    && mkdir --parents /dsh-state/dsh /dsh-state/home \
    && chown --recursive node:node /dsh-state

ENTRYPOINT ["/usr/local/bin/dsh-entrypoint"]
