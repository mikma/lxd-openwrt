#!/bin/sh

set -e

arch=x86
subarch=64
arch_dash=${arch}-${subarch}
ver=17.01.4
image=openwrt
name=openwrt
dist=lede

rootfs_url=https://downloads.openwrt.org/releases/${ver}/targets/${arch}/${subarch}/${dist}-${ver}-${arch_dash}-generic-rootfs.tar.gz
rootfs_sum=43886c6b4a555719603286ceb1733ea2386d43b095ab0da9be35816cd2ad8959
rootfs=dl/$(basename $rootfs_url)

sdk_url=https://downloads.openwrt.org/releases/${ver}/targets/${arch}/${subarch}/${dist}-sdk-${ver}-${arch}-${subarch}_gcc-5.4.0_musl-1.1.16.Linux-x86_64.tar.xz
sdk_sum=ef8b801f756cf2aa354198df0790ab6858b3d70b97cc3c00613fd6e5d5bb100c
sdk_tar=dl/$(basename $sdk_url)
sdk_name=sdk-${ver}-${arch}-${subarch}
sdk=build_dir/${sdk_name}

procd_url=https://github.com/openwrt/openwrt/branches/lede-17.01/package/system/procd
procd_extra_ver=lxd-3

lxc_tar=bin/${dist}-${ver}-${arch_dash}-lxd.tar.gz
metadata=bin/metadata.yaml

download_rootfs() {
	download $rootfs_url $rootfs
	check $rootfs $rootfs_sum
}

download_sdk() {
	download $sdk_url $sdk_tar
	check $sdk_tar $sdk_sum
	if ! test -e $sdk; then
		test -e build_dir || mkdir build_dir
		tar xvpf $sdk_tar -C build_dir
		(cd build_dir && ln -sfT ${dist}-sdk-${ver}-${arch}-${subarch}* $sdk_name)
	fi
}

download() {
	url=$1
	dst=$2
	dir=$(dirname $dst)

	if ! test -e "$dst" ; then
		echo Downloading $url
		test -e $dir || mkdir $dir

		wget -O $dst "$url"
	fi
}

check() {
	dst=$1
	dst_sum=$2

	sum=$(sha256sum $dst| cut -d ' ' -f1)
	if test -n "$dst_sum" -a $dst_sum != $sum; then
		echo Bad checksum $sum of $dst
		exit 1
	fi
}

download_procd() {
	if ! test -e dl/procd; then
		svn co $procd_url dl/procd
		sed -i -e "s/PKG_RELEASE:=\(\S\+\)/PKG_RELEASE:=\1-${procd_extra_ver}/" dl/procd/Makefile
	fi

	test -e dl/procd/patches || mkdir dl/procd/patches
	cp -a patches/procd/* dl/procd/patches
}

build_procd() {
	if ! test -e $sdk/package/lxd-procd; then
		ln -sfT $(pwd)/dl/procd $sdk/package/lxd-procd
	fi
	(cd $sdk
	./scripts/feeds update base
	./scripts/feeds install libubox
	./scripts/feeds install ubus
	make defconfig
	make package/lxd-procd/compile
	)
	local date=$(grep PKG_SOURCE_DATE:= dl/procd/Makefile | cut -d '=' -f 2)
	local version=$(grep PKG_SOURCE_VERSION:= dl/procd/Makefile | cut -d '=' -f 2 | cut -b '1-8')
	local release=$(grep PKG_RELEASE:= dl/procd/Makefile | cut -d '=' -f 2)
	test -e bin/packages/${arch}/${subarch} || mkdir -p bin/packages/${arch}/${subarch}
	(cd bin/packages/${arch}/${subarch} && ln -sf ../../../../$sdk/bin/targets/${arch}/${subarch}/packages/procd_${date}-${version}-${release}_*.ipk .)
}

build_tarball() {
	export SDK="$(pwd)/${sdk}"
	export ARCH=${arch}
	export SUBARCH=${subarch}
	fakeroot ./build_rootfs.sh $rootfs $metadata $lxc_tar
}

build_metadata() {
	local stat=`stat -c %Y $rootfs`
	local date="`date -R -d "@${stat}"`"

	if test ${subarch} = generic; then
		local arch_lxd=${arch}
	else
		local arch_lxd=${arch}_${subarch}
	fi

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
download_sdk
download_procd
build_procd
build_metadata
build_tarball
build_image

echo \# start
echo lxc launch --config "raw.lxc=lxc.aa_profile=lxc-container-default-without-dev-mounting" --profile openwrt $image $name
#lxc config
echo \# set root password
echo lxc exec $name passwd root
#echo 'echo "148.251.78.235 downloads.openwrt.org"
