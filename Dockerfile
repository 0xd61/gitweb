ARG BASE_IMAGE=nginx:mainline-alpine
ARG MAKE_THREADS=8
FROM ${BASE_IMAGE} AS zerotier_builder


RUN apk add --update alpine-sdk linux-headers openssl-dev curl gcc libgcc musl-dev openssl openssl-dev

RUN curl -sSL sh.rustup.rs >/usr/local/bin/rustup-dl && chmod +x /usr/local/bin/rustup-dl && /usr/local/bin/rustup-dl -y --default-toolchain stable

RUN git clone --quiet https://github.com/zerotier/ZeroTierOne.git /src \
  && cd /src \
  && make -j ${MAKE_THREADS} -f make-linux.mk

FROM ${BASE_IMAGE}-perl

# Zerotier install
COPY --from=zerotier_builder /src/zerotier-one /usr/sbin/

RUN    apk add --no-cache --purge --clean-protected libc6-compat libstdc++ \
    && mkdir -p /var/lib/zerotier-one \
    && ln -s /usr/sbin/zerotier-one /usr/sbin/zerotier-idtool \
    && ln -s /usr/sbin/zerotier-one /usr/sbin/zerotier-cli

# Netbird install
ENV \
    NETBIRD_BIN="/usr/sbin/netbird" \
    NB_USE_NETSTACK_MODE="true" \
    NB_ENABLE_NETSTACK_LOCAL_FORWARDING="true" \
    NB_CONFIG="/var/lib/netbird/config.json" \
    NB_STATE_DIR="/var/lib/netbird" \
    NB_DAEMON_ADDR="unix:///var/lib/netbird/netbird.sock" \
    NB_LOG_FILE="console,/var/lib/netbird/client.log" \
    NB_DISABLE_DNS="true" \
    NB_ENTRYPOINT_SERVICE_TIMEOUT="5" \
    NB_ENTRYPOINT_LOGIN_TIMEOUT="1"

COPY --from=netbirdio/netbird:latest /usr/local/bin/netbird-entrypoint.sh /netbird-service.sh
COPY --from=netbirdio/netbird:latest /usr/local/bin/netbird /usr/sbin/netbird

# Gitweb install
RUN    apk update \
    && apk upgrade \
    && apk add git git-gitweb git-daemon openssh fcgiwrap perl-cgi spawn-fcgi rsync highlight bash \
    && rm -rf /var/cache/apk/*

RUN    sed -i 's/#UseDNS no/UseDNS no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config


RUN ln -sf /dev/stdout /var/log/nginx/access.log && ln -sf /dev/stderr /var/log/nginx/error.log

COPY service.sh /service.sh
COPY sync.sh /sync.sh
COPY init.template /init.template

CMD ["/service.sh"]

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD nc -vz -w 2 localhost 80 && nc -vz -w 2 localhost 22 || exit 1
