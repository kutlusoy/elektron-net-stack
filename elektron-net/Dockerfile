############################
# Build stage              #
############################
FROM debian:bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake pkgconf python3 \
        libevent-dev libboost-dev libsqlite3-dev libzmq3-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .

# WITH_ZMQ=ON: elektron-net-ppool's .env.example supports an optional
# zmqpubrawblock hint (faster than 30s polling); BUILD_GUI=OFF since this
# is a headless seed/RPC node.
RUN cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_GUI=OFF \
        -DWITH_ZMQ=ON \
    && cmake --build build -j"$(nproc)" \
    && cmake --install build

############################
# Runtime stage            #
############################
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        libevent-2.1-7 libevent-pthreads-2.1-7 \
        libsqlite3-0 libzmq5 \
        ca-certificates gosu \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r elektron && useradd -r -g elektron -d /data -s /usr/sbin/nologin elektron \
    && mkdir -p /data && chown elektron:elektron /data

# Pull every elektron-* binary produced by the build (elektrond, elektron-cli,
# elektron-tx, elektron-util, elektron-wallet, elektron-node, ...).
COPY --from=build /usr/local/bin/elektron* /usr/local/bin/

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

VOLUME ["/data"]

# 8333 = P2P (public, seed node). 8332 = RPC (never publish to the host;
# only reachable from other containers on the same Docker network).
EXPOSE 8333 8332

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["elektrond", "-conf=/data/bitcoin.conf", "-datadir=/data", "-printtoconsole"]
