# syntax=docker/dockerfile:1
#
# 多架构统一构建入口（替代原先 amd64/arm64/loong64 三份重复的 Dockerfile）。
#
#   # amd64 / arm64（base 是同一份多架构 debian:trixie 清单）
#   podman build --target base --build-arg BASE_IMAGE=hub.cicd.getdeepin.org/library/debian:trixie \
#                -t registry.cn-hangzhou.aliyuncs.com/linyaps/builder:dev_amd64 .
#
#   # loong64（debian sid 的龙芯移植）
#   podman build --target base \
#                --build-arg BASE_IMAGE=ghcr.cicd.getdeepin.org/loong64/debian:sid \
#                --build-arg DEBIAN_CODENAME=sid \
#                -t registry.cn-hangzhou.aliyuncs.com/linyaps/builder:dev_loong64 .
#
#   # jenkins / multica 变体：加 --target jenkins 或 --target multica
#   # 多架构：交给 buildx / GitHub Actions（见 .github/workflows/build.yml），会自动注入 TARGETARCH
#
# 版本号写进 TAG：<linglong 版本>_<arch>，例如 1.13.8_loong64。

ARG BASE_IMAGE=hub.cicd.getdeepin.org/library/debian:trixie
# debian 的 codename，用于给 InRelease 预取路径拼 URL（trixie / sid）
ARG DEBIAN_CODENAME=trixie

FROM ${BASE_IMAGE} AS base
ARG DEBIAN_CODENAME

# 基础镜像默认走公网 debian 源，这里换成内网镜像；InRelease 预取一次，
# 让 DNS / 证书问题在构建早期就暴露，而不是卡在 apt-get update 里
RUN sed -i 's/deb.debian.org/mirrors.cicd.getdeepin.org/g' /etc/apt/sources.list.d/debian.sources
ADD https://mirrors.cicd.getdeepin.org/debian/dists/${DEBIAN_CODENAME}/InRelease /tmp/InRelease

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates

RUN echo "deb [trusted=yes] https://ci.deepin.com/repo/obs/linglong:/CI:/release/Debian_13/ ./" \
      > /etc/apt/sources.list.d/linglong.list

# wget 是 linglong-builder 的运行期依赖，装在同一层里避免重复 update
RUN apt-get update \
 && apt-get install -y --no-install-recommends linglong-bin linglong-builder wget \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/ll-box && chmod 777 /run/ll-box

RUN useradd --create-home --no-log-init --shell /bin/bash builder

# XDG_RUNTIME_DIR 放在 /home/builder 卷内，属主跟着 builder 走。
# 原先用 /run/user/1000 + VOLUME，rootless（--userns=keep-id）时这个匿名卷属主是容器 root
# （映射到宿主机 subuid），builder 写不进去，构建会报 "stage runtime check error"。
ENV XDG_RUNTIME_DIR /home/builder/.run
RUN mkdir -p /home/builder/.run && chown -R builder:builder /home/builder/.run

WORKDIR /home/builder
VOLUME ["/home/builder"]
USER builder

# jenkins agent 镜像
FROM base AS jenkins
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-21-jre \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*
ADD https://jenkins.linyaps.org.cn/jnlpJars/agent.jar /agent.jar
RUN chmod 444 /agent.jar
USER builder

# multica CLI 镜像（内置 codex）
FROM base AS multica
USER root
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) CODEX_ARCH=x86_64;  MULTICA_ARCH=amd64 ;; \
      arm64) CODEX_ARCH=aarch64; MULTICA_ARCH=arm64 ;; \
      *) echo "multica 变体暂不支持 ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    wget --progress=dot:mega -O /tmp/codex.tar.gz \
      "https://gh-proxy.com/https://github.com/openai/codex/releases/download/rust-v0.153.0/codex-${CODEX_ARCH}-unknown-linux-musl.tar.gz"; \
    tar -xzf /tmp/codex.tar.gz -C /tmp; \
    install -m 0755 "/tmp/codex-${CODEX_ARCH}-unknown-linux-musl" /usr/local/bin/codex; \
    wget --progress=dot:mega -O /tmp/multica.tar.gz \
      "https://gh-proxy.com/https://github.com/multica-ai/multica/releases/download/v0.4.38/multica-cli-0.4.38-linux-${MULTICA_ARCH}.tar.gz"; \
    tar -xzf /tmp/multica.tar.gz -C /tmp multica; \
    install -m 0755 /tmp/multica /usr/local/bin/multica; \
    rm -f /tmp/codex.tar.gz /tmp/multica.tar.gz /tmp/codex-* /tmp/multica
RUN apt-get update \
 && apt-get install -y --no-install-recommends sudo curl \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*
RUN echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder \
 && chmod 440 /etc/sudoers.d/builder
USER builder
