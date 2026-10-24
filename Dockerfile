# Debian trixie ships SQLite 3.46.1, which has the WAL-reset corruption bug
# (https://sqlite.org/wal.html#walresetbug). Hermes keeps its state in SQLite,
# so build a fixed library the same way upstream's own Dockerfile does.
FROM debian:trixie AS sqlite_build
ARG SQLITE_AUTOCONF_VERSION=3530400
ARG SQLITE_SHA256=0e9483900e92cd5de8fd48d16bf9200145a61f7fd5be542a5ac81d8a9516eb9c
RUN apt-get update && apt-get install -y --no-install-recommends build-essential ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL --retry 3 -o /tmp/sqlite.tar.gz "https://sqlite.org/2026/sqlite-autoconf-${SQLITE_AUTOCONF_VERSION}.tar.gz" \
    && echo "${SQLITE_SHA256}  /tmp/sqlite.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/sqlite.tar.gz -C /tmp \
    && cd "/tmp/sqlite-autoconf-${SQLITE_AUTOCONF_VERSION}" \
    && CFLAGS="-O2 -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 \
        -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_UNLOCK_NOTIFY -DSQLITE_ENABLE_DBSTAT_VTAB \
        -DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_SECURE_DELETE -DSQLITE_THREADSAFE=1 -DSQLITE_MAX_VARIABLE_NUMBER=250000" \
        ./configure --prefix=/opt/sqlite-fixed --disable-static \
    && make -j"$(nproc)" && make install

FROM python:3.14-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates ripgrep ffmpeg \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Prefer the fixed SQLite over the distro library, and fail the build if Python still links the buggy one.
COPY --from=sqlite_build /opt/sqlite-fixed/lib/libsqlite3.so.3.53.4 /usr/local/lib/
RUN ln -sf libsqlite3.so.3.53.4 /usr/local/lib/libsqlite3.so.0 \
    && printf '/usr/local/lib\n' > /etc/ld.so.conf.d/000-sqlite-fixed.conf \
    && ldconfig \
    && python -c "import sqlite3, sys; sys.exit('SQLite %s still has the WAL-reset bug' % sqlite3.sqlite_version) if sqlite3.sqlite_version_info < (3, 51, 3) else None"

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

RUN git clone --recurse-submodules https://github.com/NousResearch/hermes-agent.git /opt/hermes-agent

WORKDIR /opt/hermes-agent
# Upstream hermes-agent declares its core dependencies only for Python >= 3.14,
# so an older interpreter installs none of them and the CLI fails on import.
# Messaging platforms (Telegram) and the Google Workspace skill are opt-in extras upstream,
# no longer part of [all], so install them explicitly.
RUN uv venv venv --python 3.14 \
    && VIRTUAL_ENV=/opt/hermes-agent/venv uv pip install -e ".[all,messaging,google]" \
    && venv/bin/python -c "import sqlite3, sys; sys.exit('venv SQLite %s still has the WAL-reset bug' % sqlite3.sqlite_version) if sqlite3.sqlite_version_info < (3, 51, 3) else None"

ENV PATH="/opt/hermes-agent/venv/bin:$PATH"

RUN mkdir -p /root/.hermes/{cron,sessions,logs,memories,skills,pairing,hooks,image_cache,audio_cache} \
    && cp cli-config.yaml.example /root/.hermes/config.yaml \
    && touch /root/.hermes/.env

COPY auth_proxy.py /auth_proxy.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
