# VS Code Desktop (stable) under Xvfb, for running a development extension headlessly.
FROM debian:12-slim
ARG CODE_DEB_URL=https://update.code.visualstudio.com/latest/linux-deb-x64/stable
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates xvfb xauth procps libasound2 libgbm1 libgtk-3-0 libnss3 libxss1 \
      libsecret-1-0 libxkbfile1 xdg-utils \
    && curl -fsSL "$CODE_DEB_URL" -o /tmp/code.deb \
    && apt-get install -y --no-install-recommends /tmp/code.deb \
    && rm -f /tmp/code.deb && rm -rf /var/lib/apt/lists/*
RUN useradd -m tester && mkdir -p /ws && chown tester /ws
USER tester
ENV REPRO_LOG=/tmp/repro-task-events.log
COPY run.sh /run.sh
ENTRYPOINT ["/run.sh"]
