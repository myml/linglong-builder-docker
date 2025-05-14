FROM hub.deepin.com/library/debian:bookworm
RUN sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources
RUN apt update && apt-get install -y ca-certificates
RUN echo "deb [trusted=yes] https://ci.deepin.com/repo/obs/linglong:/CI:/release/Debian_12/ ./" | tee /etc/apt/sources.list.d/linglong.list
RUN apt update
RUN apt-get install -y --no-install-recommends linglong-bin
RUN apt-get install -y --no-install-recommends linglong-builder
RUN mkdir /run/ll-box && chmod 777 /run/ll-box
RUN useradd --create-home --no-log-init --shell /bin/bash builder
USER builder
VOLUME /home/builder/.cache/linglong-builder