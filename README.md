# 在 docker 中使用 ll-builder

1. 先安装 docker 或 podman
2. 使用 `docker run -ti --privileged -v ll-builder-cache:/home/builder registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.8.1` 进入 docker 容器，就可以在容器里使用 ll-builder 构建应用了。
