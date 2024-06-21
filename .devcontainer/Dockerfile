FROM ubuntu:24.04

LABEL maintainer="Matheus C. França <matheus-catarino@hotmail.com>"
LABEL version="1.0"
LABEL description="This is a devcontainer image for zig and flang toolchains"

# Ubuntu:Noble have flang-18/flang-new

ENV ZIG_VERSION=0.13.0
ENV ZIG_PATH=/zig/${ZIG_VERSION}/files

RUN apt update && apt install -y --no-install-recommends \
	flang \
    wget \
    ca-certificates \
    xz-utils

RUN dpkgArch="$(dpkg --print-architecture)"; \
    case "${dpkgArch##*-}" in \
        amd64) zigupURL='https://github.com/marler8997/zigup/releases/download/v2024_05_05/zigup-x86_64-linux.tar.gz' ;; \
        riscv64) zigupURL='https://github.com/marler8997/zigup/releases/download/v2024_05_05/zigup-riscv64-linux.tar.gz' ;; \
        ppc64) zigupURL='https://github.com/marler8997/zigup/releases/download/v2024_05_05/zigup-powerpc-linux.tar.gz' ;; \
        ppc64el) zigupURL='https://github.com/marler8997/zigup/releases/download/v2024_05_05/zigup-powerpc64le-linux.tar.gz' ;; \
        *) echo >&2 "unsupported architecture: ${dpkgArch}"; exit 1 ;; \
    esac; \
    wget -q "$zigupURL" && \
    tar -xzf "$(basename $zigupURL)" -C /usr/bin && \
    chmod +x /usr/bin/zigup && \
    zigup --install-dir /zig ${ZIG_VERSION}

RUN chmod +x ${ZIG_PATH}/zig

RUN apt autoclean \
    && apt remove -y --auto-remove \
        wget \
        ca-certificates \     
        xz-utils \
        ; \
    rm /*.tar.gz \
    /usr/bin/zigup; \
    rm -rf /var/lib/apt/lists/*;

WORKDIR /app

ENV CC=zcc \
    CXX=zcxx \
    LD=ld \
    FC=flang-new

RUN cat <<EOF > /usr/bin/zcc
#!/usr/bin/env bash
`which zig` cc -lunwind -fno-sanitize=all -s "\$@"
EOF
RUN cat <<EOF > /usr/bin/zcxx
#!/usr/bin/env bash
`which zig` c++ -fno-sanitize=all -s "\$@"
EOF
RUN cat <<EOF > /usr/bin/ld
#!/usr/bin/env bash
`which zig` ld.lld "\$@"
EOF

RUN chmod +x /usr/bin/zcc; \
    chmod +x /usr/bin/zcxx; \
    chmod +x /usr/bin/ld

ARG UNAME=flang
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID -o $UNAME
RUN useradd -m -u $UID -g $GID -o -s /bin/bash $UNAME

RUN chown -R $UNAME:$UNAME /app

USER $UNAME
