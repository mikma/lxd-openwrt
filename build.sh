#!/bin/sh

set -e

arch=x86
subarch=64
arch_lxd=${arch}_${subarch}
arch_dash=${arch}-${subarch}
ver=17.01.4
image=openwrt
name=openwrt
dist=lede

generic_rootfs_url=https://downloads.openwrt.org/releases/${ver}/targets/${arch}/${subarch}/${dist}-${ver}-${arch_dash}-generic-rootfs.tar.gz
generic_rootfs_sum=43886c6b4a555719603286ceb1733ea2386d43b095ab0da9be35816cd2ad8959
generic_rootfs=dl/$(basename $generic_rootfs_url)

lxc_tar=${dist}-${ver}-${arch_dash}-lxd.tar.gz
metadata=metadata.yaml

download_rootfs() {
	test -e dl || mkdir dl

	if ! test -e "$generic_rootfs" ; then
		echo Downloading $generic_rootfs_url
		wget -O $generic_rootfs "$generic_rootfs_url"
	fi
}

check_rootfs() {
	sum=$(sha256sum $generic_rootfs| cut -d ' ' -f1)
	if test $generic_rootfs_sum != $sum; then
		echo Bad checksum $sum of $generic_rootfs
		exit 1
	fi
}

build_tarball() {
	fakeroot ./build_rootfs.sh $generic_rootfs $metadata $lxc_tar
}

build_metadata() {
	stat=`stat -c %Y $generic_rootfs`
	date=`date -R -d "@${stat}"`

	cat > $metadata <<EOF
architecture: "$arch_lxd"
creation_date: $(date +%s)
properties:
 architecture: "$arch_lxd"
 description: "OpenWrt $ver $arch_lxd ($date)"
 os: "OpenWrt"
 release: "$ver"
templates:
EOF

## Add templates
#
# templates:
#   /etc/hostname:
#     when:
#       - start
#     template: hostname.tpl
}

build_image() {
	lxc image import $lxc_tar --alias $image
}

download_rootfs
check_rootfs
build_metadata
build_tarball
build_image

echo \# start
echo lxc launch --config "raw.lxc=lxc.aa_profile=lxc-container-default-without-dev-mounting" --profile openwrt $image $name
#lxc config
echo \# set root password
echo lxc exec $name passwd root
#echo 'echo "148.251.78.235 downloads.openwrt.org"
