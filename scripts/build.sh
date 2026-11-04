#!/usr/bin/env bash
# build.sh —— 构建 linglong builder 镜像（替代原先三份重复的 Dockerfile）。
#
#   ./scripts/build.sh <arch> <version> [--variant base|jenkins|multica] [--push]
#
# 例：
#   ./scripts/build.sh amd64 1.13.8                 # 构建 base + jenkins + multica
#   ./scripts/build.sh loong64 1.13.8 --variant base
#   ./scripts/build.sh arm64 1.13.8 --push          # 构建完推到镜像仓库
#
# 环境变量：REGISTRY / IMAGE / ENGINE（默认自动探测 podman、docker）。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REGISTRY=${REGISTRY:-registry.cn-hangzhou.aliyuncs.com/linyaps}
IMAGE=${IMAGE:-builder}
ENGINE=${ENGINE:-$(command -v podman || command -v docker || true)}

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

[ $# -ge 2 ] || usage
arch=$1
version=$2
shift 2

push=0
variants="base jenkins multica"
while [ $# -gt 0 ]; do
  case "$1" in
    --push)    push=1 ;;
    --variant) variants=${2:-}; shift ;;
    -h|--help) usage ;;
    *) echo "未知参数: $1" >&2; usage ;;
  esac
  shift
done

[ -n "$ENGINE" ] || { echo "未找到 podman 或 docker" >&2; exit 1; }

case "$arch" in
  amd64|arm64)
    base=hub.cicd.getdeepin.org/library/debian:trixie
    codename=trixie ;;
  loong64)
    base=ghcr.cicd.getdeepin.org/loong64/debian:sid
    codename=sid ;;
  *)
    echo "不支持的架构: $arch（可选 amd64 / arm64 / loong64）" >&2
    exit 2 ;;
esac

tags=()
for v in $variants; do
  tag="${version}_${arch}"
  [ "$v" != "base" ] && tag="${tag}_${v}"
  tags+=("$REGISTRY/$IMAGE:$tag")
  echo "==> 构建 $REGISTRY/$IMAGE:$tag（target=$v, base=$base）"
  "$ENGINE" build \
    --target "$v" \
    --platform "linux/$arch" \
    --build-arg BASE_IMAGE="$base" \
    --build-arg DEBIAN_CODENAME="$codename" \
    -t "$REGISTRY/$IMAGE:$tag" \
    "$ROOT"
done

if [ "$push" -eq 1 ]; then
  for t in "${tags[@]}"; do
    echo "==> 推送 $t"
    "$ENGINE" push "$t"
  done
fi
