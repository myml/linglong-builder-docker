#!/usr/bin/env bash
# doctor.sh —— 在宿主机上自检 ll-builder 容器的运行环境。
#
#   ./scripts/doctor.sh                 只做环境检查
#   ./scripts/doctor.sh --smoke <镜像>  检查后再启动一次容器，验证 ll-builder 可执行
#
# 检查项对应 README「常见报错对照」里的每一条，rootless 用户建议进容器前先跑一次。
set -u

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
FAIL=0
ok()   { printf '%s[ OK ]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*"; }
bad()  { printf '%s[FAIL]%s %s\n' "$RED" "$RESET" "$*"; FAIL=1; }
have() { command -v "$1" >/dev/null 2>&1; }

SMOKE_IMAGE=""
if [ "${1:-}" = "--smoke" ]; then
  SMOKE_IMAGE="${2:-}"
  if [ -z "$SMOKE_IMAGE" ]; then
    printf '用法: %s --smoke <镜像>\n' "$0" >&2
    exit 2
  fi
fi

echo "== 1. 容器引擎 =="
if have podman; then
  ok "podman $(podman --version 2>/dev/null | awk '{print $NF}')"
elif have docker; then
  warn "只找到 docker：下面的 subuid / keep-id 检查项不适用，rootful 用法可忽略"
else
  bad "未找到 podman 或 docker"
fi

ROOTLESS=1
[ "$(id -u)" -eq 0 ] && ROOTLESS=0

echo
echo "== 2. subuid / subgid（rootless 必需，size ≥ 165536）=="
if [ "$ROOTLESS" -eq 0 ]; then
  ok "当前是 root，跳过 subuid 检查"
else
  U=$(id -un)
  for f in /etc/subuid /etc/subgid; do
    line=$(awk -F: -v u="$U" '$1==u {print $2":"$3; exit}' "$f" 2>/dev/null)
    if [ -z "$line" ]; then
      bad "$f 里没有 $U 的条目 —— 追加一行: $U:100000:165536"
      continue
    fi
    start=${line%%:*}
    size=${line##*:}
    if [ "$size" -ge 165536 ]; then
      ok "$f: $U:$start:$size"
    else
      bad "$f: $U:$start:$size 不够用 —— 改成 $U:$start:165536，然后执行 podman system migrate"
    fi
  done

  echo
  echo "== 3. 映射是否已生效（改完 subuid 后必须 migrate）=="
  if have podman; then
    map=$(podman info --format '{{json .Host.IDMappings}}' 2>/dev/null)
    [ -z "$map" ] && map=$(podman unshare cat /proc/self/uid_map 2>/dev/null | tr -s ' ' ' ')
    if printf '%s' "$map" | grep -q '165536'; then
      ok "rootless 映射里已包含 165536"
    elif [ -n "$map" ]; then
      bad "映射仍是旧的（不含 165536）: $(printf '%s' "$map" | tr '\n' ' ' | cut -c1-160)"
      echo "         只改 /etc/subuid 不生效，需要执行: podman system migrate"
    else
      warn "读不到映射，请手动确认: podman unshare cat /proc/self/uid_map"
    fi
  fi
fi

echo
echo "== 4. /dev/fuse（ll-builder 挂 overlay 用）=="
if [ -e /dev/fuse ]; then
  ok "/dev/fuse 存在"
else
  bad "/dev/fuse 不存在 —— 安装 fuse3 或加载 fuse 内核模块"
fi

echo
echo "== 5. 宿主机 uid（决定 --userns=keep-id 的写法）=="
uid_now=$(id -u)
if [ "$uid_now" -ne 1000 ]; then
  warn "当前 uid=$uid_now（不是 1000）"
  echo "         请用 --userns=keep-id:uid=1000,gid=1000；裸写 --userns=keep-id 会让容器里的 builder 落到 subuid 上"
else
  ok "当前 uid=1000，--userns=keep-id 与 --userns=keep-id:uid=1000,gid=1000 等价"
fi

if [ -n "$SMOKE_IMAGE" ]; then
  echo
  echo "== 6. smoke test: $SMOKE_IMAGE =="
  out=$(podman run --rm --privileged \
          --userns=keep-id:uid=1000,gid=1000 \
          --tmpfs /run/user/1000:rw,mode=1777,size=64m \
          "$SMOKE_IMAGE" sh -c 'echo "容器内 uid=$(id -u)"; ll-builder --version' 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%s\n' "$out" | grep -E '容器内 uid|ll-builder|linyaps build tool' | sed 's/^/         /'
    ok "容器可启动，ll-builder 可执行"
  else
    printf '%s\n' "$out" | tail -5 | sed 's/^/         /'
    bad "smoke test 失败（退出码 $rc）"
  fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
  printf '%s全部检查通过%s\n' "$GREEN" "$RESET"
else
  printf '%s存在未通过项，按上面提示处理后重跑%s\n' "$RED" "$RESET"
fi
exit "$FAIL"
