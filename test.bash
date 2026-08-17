podman build -t builder ./amd64
podman run --privileged -ti --rm -v builder-home:/home/builder builder sh -c "ll-builder create a; cd a; ll-builder build --skip-run-container -- sh -c 'touch /tmp/testfile; chown root:adm /tmp/testfile'"
