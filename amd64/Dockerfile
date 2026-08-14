FROM hub.cicd.getdeepin.org/library/debian:trixie
RUN sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/debian.sources
RUN apt update && apt-get install -y ca-certificates
RUN echo "deb [trusted=yes] https://ci.deepin.com/repo/obs/linglong:/CI:/release/Debian_13/ ./" | tee /etc/apt/sources.list.d/linglong.list
RUN apt update
RUN apt-get install -y --no-install-recommends linglong-bin
RUN apt-get install -y --no-install-recommends linglong-builder
# Fix Error: linglong-builder depend wget
RUN apt-get install -y wget

RUN mkdir /run/ll-box && chmod 777 /run/ll-box
# fix Error: filesystem error: cannot create directories: Permission denied [/run/user/0/linglong/box]
RUN mkdir -m 700 -p /run/user/1000 && chown 1000:1000 /run/user/1000
RUN useradd --create-home --no-log-init --shell /bin/bash builder

# fix Error: newuidmap: write to uid_map failed: Operation not permitted
RUN echo 0 0 65535 > /etc/subuid
RUN echo 0 0 65535 > /etc/subgid

ENV XDG_RUNTIME_DIR /run/user/1000
USER builder
WORKDIR /home/builder
