FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

COPY apt-packages.txt /tmp/apt-packages.txt

RUN apt-get update \
 && xargs -a /tmp/apt-packages.txt apt-get install -y --no-install-recommends \
 && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 120 \
 && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 120 \
 && rm -rf /var/lib/apt/lists/*

ARG BUILD_UID=1000
ARG BUILD_GID=1000

RUN groupadd -g "$BUILD_GID" builder \
 && useradd -m -u "$BUILD_UID" -g "$BUILD_GID" -s /bin/bash builder

USER builder
WORKDIR /workspace
CMD ["/bin/bash"]
