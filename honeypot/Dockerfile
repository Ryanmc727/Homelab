FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpcap-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir opencanary requests

COPY opencanary.conf /etc/opencanaryd/opencanary.conf
COPY notifier.py     /usr/local/bin/notifier.py
COPY start.sh        /start.sh
RUN chmod +x /start.sh

VOLUME ["/var/log/opencanary"]

CMD ["/start.sh"]
