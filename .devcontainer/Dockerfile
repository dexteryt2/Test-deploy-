FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash curl unzip ca-certificates uuid-runtime tmux jq iproute2 procps \
       openssl python3 python3-pip \
    && pip3 install --break-system-packages --no-cache-dir speedtest-cli \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /etc/xray

COPY config.json /etc/xray/config.json
COPY setup.sh /tmp/setup.sh

RUN chmod +x /tmp/setup.sh && /tmp/setup.sh && rm /tmp/setup.sh

COPY show-link.sh /usr/local/bin/show-link.sh
COPY start.sh /usr/local/bin/start.sh
COPY debug.sh /usr/local/bin/debug.sh
COPY speedtest.sh /usr/local/bin/speedtest.sh

RUN chmod +x /usr/local/bin/show-link.sh \
    && chmod +x /usr/local/bin/start.sh \
    && chmod +x /usr/local/bin/debug.sh \
    && chmod +x /usr/local/bin/speedtest.sh

EXPOSE 443 8005 8006 8007 8880 8008 8009 8010 8443 8011 8012 8013 2053 8014 8080

CMD ["/usr/local/bin/xray", "run", "-c", "/etc/xray/config.json"]
