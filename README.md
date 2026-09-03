# 在 docker 中使用 ll-builder

1. 先安装 docker 或 podman
2. 使用 `docker run -ti --privileged -v ll-builder-cache:/home/builder registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.10.3_amd64` 进入 docker 容器，就可以在容器里使用 ll-builder 构建应用了。

从1.13.8版本开始，需要修改宿主机的 /etc/subuid 才能正常使用buildext.apt功能
```diff
-username:100000:65536
+username:100000:165536
```

因为有些deb包会使用chown更改文件权限。

一层容器：1:65535(podman) -> 100000:1065535(host)
两层容器：1:65535(ll-builder) -> 100000:1065535(podman) -> 199999:265534(host)

host默认的subuid 1000:100000:65536，最大的uid是1065535无法满足条件

## 镜像列表

除了基础的镜像，还提供了包含jenkins agent和multica runtime（内置codex）的镜像，可自行选用
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
jenkins使用案例

```bash
podman run -d --name builder --privileged -v builder-home:/home/builder \
  registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.13.8_amd64_jenkins \
  java -jar /agent.jar -url https://jenkins.linyaps.org.cn/ -secret xxx -name "builder-amd64" -webSocket -workDir "./jenkins-agent"
```
