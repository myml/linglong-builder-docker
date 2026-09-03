FROM ghcr.cicd.getdeepin.org/loong64/debian:sid AS base
RUN sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/debian.sources
ADD https://mirrors.tuna.tsinghua.edu.cn/debian/dists/sid/InRelease /tmp/InRelease
RUN apt update && apt-get install -y ca-certificates
RUN echo "deb [trusted=yes] https://ci.deepin.com/repo/obs/linglong:/CI:/release/Debian_13/ ./" | tee /etc/apt/sources.list.d/linglong.list
RUN apt update
RUN apt-get install -y --no-install-recommends linglong-bin
RUN apt-get install -y --no-install-recommends linglong-builder
# Fix Error: linglong-builder depend wget
RUN apt-get install -y wget

RUN mkdir /run/ll-box && chmod 777 /run/ll-box
RUN useradd --create-home --no-log-init --shell /bin/bash builder

# fix Error: OverlayFS mount failed at /run/user/1000
ENV XDG_RUNTIME_DIR /run/user/1000
RUN mkdir -p /run/user/1000
RUN chown builder:builder /run/user/1000
VOLUME ["/run/user/1000"]

WORKDIR /home/builder
VOLUME ["/home/builder"]
USER builder

# jenkins agent image
FROM base AS jenkins
USER root
RUN apt-get install -y openjdk-21-jre
ADD https://jenkins.linyaps.org.cn/jnlpJars/agent.jar /
RUN chmod 444 /agent.jar
USER builder