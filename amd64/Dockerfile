FROM hub.cicd.getdeepin.org/library/debian:trixie AS base
RUN sed -i 's/deb.debian.org/mirrors.cicd.getdeepin.org/g' /etc/apt/sources.list.d/debian.sources
ADD https://mirrors.cicd.getdeepin.org/debian/dists/trixie/InRelease /tmp/InRelease
RUN apt update && apt-get install -y ca-certificates
RUN echo "deb [trusted=yes] https://ci.deepin.com/repo/obs/linglong:/CI:/release/Debian_13/ ./" | tee /etc/apt/sources.list.d/linglong.list
RUN apt update
RUN apt-get install -y --no-install-recommends linglong-bin
RUN apt-get install -y --no-install-recommends linglong-builder
# Fix Error: linglong-builder depend wget
RUN apt-get install -y wget

RUN mkdir /run/ll-box && chmod 777 /run/ll-box
RUN useradd --create-home --no-log-init --shell /bin/bash builder

# XDG_RUNTIME_DIR 放在 /home/builder 卷内，属主跟着 builder 走。
# 原先用 /run/user/1000 + VOLUME，rootless（--userns=keep-id）时这个匿名卷属主是容器 root
# （映射到宿主机 subuid），builder 写不进去，构建会报 "stage runtime check error"。
ENV XDG_RUNTIME_DIR /home/builder/.run
RUN mkdir -p /home/builder/.run && chown -R builder:builder /home/builder/.run

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

# multica CLI image
FROM base AS multica
USER root
RUN wget --progress=dot:mega -O /tmp/codex.tar.gz \
      "https://gh-proxy.com/https://github.com/openai/codex/releases/download/rust-v0.153.0/codex-x86_64-unknown-linux-musl.tar.gz" \
    && tar -xzf /tmp/codex.tar.gz -C /tmp \
    && install -m 0755 /tmp/codex-x86_64-unknown-linux-musl /usr/local/bin/codex \
    && rm -f /tmp/codex.tar.gz
RUN wget --progress=dot:mega -O /tmp/multica.tar.gz \
      "https://gh-proxy.com/https://github.com/multica-ai/multica/releases/download/v0.4.38/multica-cli-0.4.38-linux-amd64.tar.gz" \
    && tar -xzf /tmp/multica.tar.gz -C /tmp multica \
    && install -m 0755 /tmp/multica /usr/local/bin/multica \
    && rm -f /tmp/multica.tar.gz
RUN apt-get install -y --no-install-recommends sudo curl 
RUN echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder \
 && chmod 440 /etc/sudoers.d/builder
USER builder
