#!/bin/sh

set -e

arch=x86_64
arch_dash=`echo $arch | tr _ -`
ver=17.01.4
image=openwrt
name=openwrt

generic_rootfs=lede-${ver}-${arch_dash}-generic-rootfs.tar.gz
lxc_rootfs=lede-${ver}-${arch_dash}-lxc-rootfs.tar.gz

build_rootfs() {
	fakeroot ./build_rootfs.sh $generic_rootfs $lxc_rootfs
}

build_metadata() {
	stat=`stat -c %Y $lxc_rootfs`
	date=`date -R -d "@${stat}"`

	cat > metadata.yaml <<EOF
architecture: "$arch"
creation_date: $(date +%s)
properties:
 architecture: "$arch"
 description: "OpenWrt $ver $arch ($date)"
 os: "OpenWrt"
 release: "$ver"
templates:
EOF
}

build_image() {
	tar czf metadata.tar.gz metadata.yaml
	lxc image import metadata.tar.gz $lxc_rootfs --alias $image
}

build_rootfs
build_metadata
build_image

echo \# start
echo lxc launch --config "raw.lxc=lxc.aa_profile=lxc-container-default-without-dev-mounting" --profile openwrt $image $name
#lxc config
echo \# set root password
echo lxc exec $name passwd root
#echo 'echo "148.251.78.235 downloads.openwrt.org"
