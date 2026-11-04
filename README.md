# 在 docker / podman 中使用 ll-builder

1. 先安装 docker 或 podman
2. 用下面的命令进入容器，就可以在容器里使用 `ll-builder` 构建应用了

## rootful（root 或 docker 组用户）

```bash
docker run -ti --privileged -v ll-builder-cache:/home/builder \
  registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.13.8_amd64
```

## rootless（普通用户 + podman）

普通用户不需要 sudo，但宿主机要先做两件事。

### 1. 给当前用户足够的 subuid / subgid（一次性）

`/etc/subuid` 和 `/etc/subgid` 里当前用户的范围，**size 必须 ≥ 165536**：

```diff
-username:100000:65536
+username:100000:165536
```

基址随意，只要整段空闲、不和别人重叠即可（实测 `265536:165536` 同样可用）。

改完**必须**执行一次 `podman system migrate`，否则新范围不会生效——只改文件时 `podman info` 里仍然是旧的 65536，容器里继续报 EPERM：

```bash
podman system migrate
podman info --format '{{json .Host.IDMappings.uidmap}}'   # 应出现 165536
```

### 2. 起容器

```bash
podman run --rm -ti --privileged \
  --userns=keep-id:uid=1000,gid=1000 \
  -v "$PWD":/project -w /project \
  -v ll-builder-cache:/home/builder \
  registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.13.8_loong64
```

要点：

- **`--userns=keep-id:uid=1000,gid=1000`**：把容器里的 `builder(1000)` 映射成**你**。裸写 `--userns=keep-id` 只是“保留调用者 uid”，当宿主 uid 不是 1000 时（例如 1002），容器里的 `builder` 反而落到 subuid 上，工程目录读写不了，构建报 `Build failed: [code 1]: stage build error`（日志里往往只有一句误导性的 `unknown argument ignored: lazytime`）。
- **缓存卷必须在这个映射下新建**。换过映射的旧卷里文件属主对不上，会报 `failed to check build config … Permission denied`；`podman volume rm` 重建即可（纯缓存，删了只是下次要重新下载 base）。
- **`--privileged` 不能省**，原因见下文。
- SELinux 系统（Fedora / CentOS 等）上 bind mount 要加 `:z`，或直接 `--security-opt label=disable`，否则容器里可能读不到工程目录。
- 1.13.8 及更早的镜像还需要加 `--tmpfs /run/user/1000:rw,mode=1777,size=64m`：这些镜像把 `XDG_RUNTIME_DIR` 放在 root 所有的卷里，`builder` 写不进去会报 `stage runtime check error`。本仓库新构建的镜像已把 `XDG_RUNTIME_DIR` 改到 `/home/builder/.run`，不再需要这个参数。

## 为什么需要 165536 个 subuid

`ll-builder` 在构建时会再开一层用户命名空间（构建沙箱隔离，同时让 `build` 脚本以 root 运行——`buildext.apt` 里的 apt 就依赖这一点），它实际调用的是：

```text
newuidmap <pid> 0 <uid> 1 1 100000 65536
```

含义是「新命名空间的 1..65536 → 父命名空间的 100000..165535」，所以 rootless 容器所在的父命名空间必须能映射到 **165535**。两层命名空间下：

- 第一层（podman 容器）：容器 0 → 宿主 uid，容器 1..65536 → 宿主 subuid 段
- 第二层（ll-builder 再套一层）：1..65536 → 容器内 100000..165535 → 宿主 subuid 段内的对应偏移

宿主默认的 `username:100000:65536` 只有 65536 个 id，装不下第二层要的 100000..165535，于是 `newuidmap: write to uid_map failed: Operation not permitted`。

> 注意：**不是只有 `buildext` 才需要**。rootless 下只要跑构建（哪怕最普通的 `kind: app`），ll-builder 都会建这层命名空间，所以 rootless 场景一律要 165536。

## 为什么 --privileged 不能省

docker / podman 默认给容器设 `no_new_privs=1`。镜像里的 `newuidmap` 是 setuid root 的，而 `no_new_privs` 会让 setuid 失效，`newuidmap` 拿不到权限，结果还是同一个 EPERM。`--privileged` 会关掉 `no_new_privs`，同时提供 `/dev/fuse` 与内层命名空间所需的能力。

实测更小的组合（`--security-opt no-new-privileges=false --device /dev/fuse --cap-add SYS_ADMIN`）能通过 uid 映射，但到 `buildext.apt` 阶段仍然 `stage build error`，所以目前只能 `--privileged`。

## 自检脚本

进容器前先跑一遍，可以提前发现上面这些问题：

```bash
./scripts/doctor.sh                 # 检查 subuid、映射是否生效、/dev/fuse、podman 版本
./scripts/doctor.sh --smoke <镜像>  # 额外在容器里跑一次 ll-builder --version
```

## 镜像列表

除了基础的镜像，还提供了包含 jenkins agent 和 multica runtime（内置 codex）的镜像，可自行选用

```txt
registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.13.8_amd64
registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.13.8_amd64_jenkins
registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.13.8_amd64_multica

registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.13.8_arm64
registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.13.8_arm64_jenkins
registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.13.8_arm64_multica

registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.13.8_loong64
registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.13.8_loong64_jenkins
```

## 构建镜像

仓库根目录的 `Dockerfile` 是多架构统一入口，架构差异全部通过 `--build-arg` 表达（`BASE_IMAGE` / `DEBIAN_CODENAME`），不再维护三份重复的 Dockerfile。用脚本构建：

```bash
./scripts/build.sh amd64 1.13.8                  # base + jenkins + multica 三个变体
./scripts/build.sh loong64 1.13.8 --variant base # 只构建 base
./scripts/build.sh arm64 1.13.8 --push           # 构建完推送
```

构建完用 smoke 脚本验证一下（在容器里跑一次最小构建，覆盖 uid 映射、fuse、内层沙箱、`buildext.apt`）：

```bash
./scripts/smoke.sh registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.13.8_amd64
```

> 各架构的 base 镜像不同：amd64 / arm64 用 `hub.cicd.getdeepin.org/library/debian:trixie`，loong64 用 `ghcr.cicd.getdeepin.org/loong64/debian:sid`（龙芯移植版）。两个 registry 仅内网可达，所以镜像构建要在内网机器上做。

## jenkins 使用案例

普通用户（rootless）跑 agent，直接用 keep-id，缓存卷挂在 `/home/builder`：

```bash
podman run -d --name builder --privileged \
  --userns=keep-id:uid=1000,gid=1000 \
  -v builder-home:/home/builder \
  registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.13.8_amd64_jenkins \
  java -jar /agent.jar -url https://jenkins.linyaps.org.cn/ -secret xxx -name "builder-amd64" -webSocket -workDir "./jenkins-agent"
```

构建阶段直接复用同一个容器即可（`podman exec` 或 `podman run` 都行），不需要再用 `--user 0`：`build` 脚本在 ll-builder 的沙箱里本身就是 root，`buildext.apt` 也能正常装包。

## 常见报错对照

| 报错 | 原因 | 处理 |
|---|---|---|
| `newuidmap: write to uid_map failed: Operation not permitted` / `failed to mapping uid` | subuid/subgid size 不足，或改了没执行 migrate | size 改到 ≥165536 后 `podman system migrate` |
| `Build failed: [code 1]: stage build error` | 工程目录属主和容器内 `builder` 对不上 | 用 `--userns=keep-id:uid=1000,gid=1000` |
| `failed to check build config … Permission denied` | 复用了别的映射下建的旧卷 | `podman volume rm` 重建 |
| `stage runtime check error` | `XDG_RUNTIME_DIR`（`/run/user/1000`）不可写 | 新镜像已修；旧镜像加 `--tmpfs /run/user/1000:rw,mode=1777,size=64m` |
| `failed to create the repository of builder: [code 13]: Permission denied` | 只挂了 `$HOME/.cache/linglong` 这类子目录，父目录在容器里属 root | 用 `-v <卷>:/home/builder` 挂整个 HOME |
