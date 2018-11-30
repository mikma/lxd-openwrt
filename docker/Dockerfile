FROM debian:stable-slim as builder

WORKDIR /root/

RUN apt-get update
RUN apt-get -y --no-install-recommends install build-essential subversion fakeroot gawk gpg git wget ca-certificates

RUN git clone https://github.com/mikma/lxd-openwrt.git

RUN (cd lxd-openwrt && ./build.sh -v snapshot --type plain)
RUN mkdir rootfs
RUN tar xzf /root/lxd-openwrt/bin/openwrt-snapshot-x86-64-plain.tar.gz -C rootfs


FROM scratch

COPY --from=builder /root/rootfs /

COPY init.sh /

RUN mkdir -p /var/lock && opkg update && opkg install luci-ssl

ENTRYPOINT ["/init.sh"]
