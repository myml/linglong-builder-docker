#!/usr/bin/env bash
# smoke.sh —— 在容器里跑一次最小构建，验证 ll-builder 全链路。
#
#   ./scripts/smoke.sh <镜像> [--repo-url URL] [--repo-name NAME] [--base BASE] [--keep]
#
# 覆盖到的链路：rootless 用户命名空间（keep-id）→ /dev/fuse → ll-builder 内层沙箱
# → buildext.apt 装包 → build → export 检查点。首次运行要下载 base 包（数百 MB），
# 缓存卷可复用。
#
# 退出码：0 通过，1 失败。
set -uo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
ok()  { printf '%s[ OK ]%s %s\n' "$GREEN" "$RESET" "$*"; }
bad() { printf '%s[FAIL]%s %s\n' "$RED" "$RESET" "$*"; }

IMAGE=${1:-}
[ -n "$IMAGE" ] || { echo "用法: $0 <镜像> [--repo-url URL] [--repo-name NAME] [--base BASE] [--keep]" >&2; exit 2; }
shift

REPO_NAME=stable
REPO_URL=https://mirror-repo-linglong.deepin.com
BASE=org.deepin.base/25.2.2
KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-name) REPO_NAME=${2:-}; shift ;;
    --repo-url)  REPO_URL=${2:-}; shift ;;
    --base)      BASE=${2:-}; shift ;;
    --keep)      KEEP=1 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
  shift
done

ENGINE=$(command -v podman || command -v docker || true)
[ -n "$ENGINE" ] || { bad "未找到 podman 或 docker"; exit 1; }

WORK=$(mktemp -d)
CACHE_VOL="ll-builder-smoke-cache"
cleanup() {
  if [ "$KEEP" -eq 1 ]; then
    echo "工作目录保留: $WORK"
    return
  fi
  rm -rf "$WORK" 2>/dev/null
  if [ -d "$WORK" ]; then
    # 构建会在工程目录里留下属主是 subuid 的 overlay 缓存，普通 rm 删不掉
    "$ENGINE" unshare rm -rf "$WORK" 2>/dev/null || true
  fi
  [ -d "$WORK" ] && echo "提示: 残留目录 $WORK 属主是 subuid，可执行: podman unshare rm -rf $WORK"
}
trap cleanup EXIT

cat > "$WORK/linglong.yaml" <<YAML
version: "1"
package:
  id: com.example.smoketest
  name: smoketest
  version: 0.0.0.1
  kind: app
  description: ll-builder smoke test
command: [echo, ok]
base: ${BASE}
buildext:
  apt:
    build_depends:
      - cmake
build: |
  echo "build 脚本身份: \$(id)"
  cmake --version | head -1
YAML

# rootless 下必须 keep-id:uid=1000,gid=1000，否则容器里的 builder 对不上宿主机用户
RUN_ARGS=(--rm --privileged --userns=keep-id:uid=1000,gid=1000
          -v "$WORK":/project -w /project
          -v "$CACHE_VOL":/home/builder)

echo "==> 镜像: $IMAGE"
echo "==> 仓库: $REPO_NAME ($REPO_URL)，base: $BASE"
log=$("$ENGINE" run "${RUN_ARGS[@]}" "$IMAGE" sh -c "
  ll-builder repo add '$REPO_NAME' '$REPO_URL' >/dev/null 2>&1 \
    || ll-builder repo update '$REPO_NAME' '$REPO_URL' >/dev/null 2>&1
  ll-builder repo set-default '$REPO_NAME' >/dev/null 2>&1
  ll-builder build -f linglong.yaml 2>&1
" 2>&1)
rc=$?

echo "$log" | grep -E 'build 脚本身份|cmake version|Successfully build|Build failed|stage .* error' | sed 's/^/    /'

if [ "$rc" -ne 0 ] || ! printf '%s' "$log" | grep -q 'Successfully build'; then
  bad "smoke test 失败（退出码 $rc）"
  printf '%s' "$log" | grep -q 'pull dependency error' \
    && echo "    提示: 拉取 base 失败，多为仓库/网络瞬时问题，重跑一次通常即可" >&2
  echo "$log" | tail -15 | sed 's/^/    /'
  exit 1
fi
ok "构建成功：uid 映射、fuse、内层沙箱、buildext.apt 全链路正常"
