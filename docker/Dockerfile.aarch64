FROM multiarch/debian-debootstrap:arm64-stretch-slim as builder

WORKDIR /root/

RUN apt-get update
RUN apt-get -y --no-install-recommends install build-essential subversion fakeroot gawk gpg git wget ca-certificates

RUN git clone https://github.com/mikma/lxd-openwrt.git

RUN (cd lxd-openwrt && ./build.sh -v snapshot -a aarch64 --type plain)
RUN mkdir rootfs
RUN tar xzf /root/lxd-openwrt/bin/openwrt-snapshot-armvirt-64-plain.tar.gz -C rootfs

ENV ROOTFS /root/rootfs
ENV LD_LIBRARY_PATH=$ROOTFS/lib
RUN mkdir -p $ROOTFS/var/lock
RUN ln -s $ROOTFS/lib/ld-musl-aarch64.so.1 /lib
RUN $ROOTFS/bin/opkg -o $ROOTFS update
RUN $ROOTFS/bin/opkg -o $ROOTFS install luci-ssl

FROM scratch

COPY --from=builder /root/rootfs /
#COPY --from=builder /usr/bin/qemu-aarch64-static /usr/bin

COPY init.sh /

ENTRYPOINT ["/init.sh"]
