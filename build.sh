#!/bin/sh

set -e

arch_lxd=x86_64
ver=18.06.1
dist=openwrt
type=lxd

# Workaround for Debian/Ubuntu systems which use C.UTF-8 which is unsupported by OpenWrt
export LC_ALL=C

usage() {
	echo "Usage: $0 [-a|--arch <x86_64|i686>] [-v|--version <version>] [-p|--packages <packages>] [-f|--files] [-t|--type lxd|plain] [--help]"
	exit 1
}

temp=$(getopt -o "a:v:p:f:t:" -l "arch:,version:,packages:,files:,type:,help" -- "$@")
eval set -- "$temp"
while true; do
	case "$1" in
	-a|--arch)
		arch_lxd="$2"; shift 2;;
	-v|--version)
		ver="$2"; shift 2
		if test ver=snapshot; then
			dist=openwrt
		else
			dist=lede
		fi;;
	-p|--packages)
		packages="$2"; shift 2;;
	-f|--files)
		files="$2"; shift 2;;
	-t|--type)
		type="$2"
		shift 2

		case "$type" in
		lxd|plain)
			;;
		*)
			usage;;
		esac;;
	--help)
		usage;;
	--)
		shift; break;;
	esac
done

if [ $# -ne 0 ]; then
        usage
fi

case "$arch_lxd" in
	i686)
		arch=x86
		subarch=generic
		;;
	x86_64)
		arch=x86
		subarch=64
		;;
	*)
		usage
		;;
esac

branch_ver=$(echo "${ver}"|cut -d- -f1|cut -d. -f1,2)

if test $ver = snapshot; then
	openwrt_branch=snapshot
	procd_url=https://github.com/openwrt/openwrt/trunk/package/system/procd
else
	openwrt_branch=${dist}-${branch_ver}
	procd_url=https://github.com/openwrt/openwrt/branches/${openwrt_branch}/package/system/procd
fi

procd_extra_ver=lxd-3

tarball=bin/${dist}-${ver}-${arch}-${subarch}-${type}.tar.gz
metadata=bin/metadata.yaml
pkgdir=bin/${ver}/packages/${arch}/${subarch}

download_rootfs() {
	if test $ver = snapshot; then
		local rootfs_url=https://downloads.openwrt.org/snapshots/targets/${arch}/${subarch}/${dist}-${arch}-${subarch}-generic-rootfs.tar.gz
	else
		local rootfs_url=https://downloads.openwrt.org/releases/${ver}/targets/${arch}/${subarch}/${dist}-${ver}-${arch}-${subarch}-generic-rootfs.tar.gz
	fi

	# global $rootfs
	rootfs=dl/$(basename $rootfs_url)

	download $rootfs_url $rootfs
	check $rootfs $rootfs_url
}

download_sdk() {
	if test $ver = snapshot; then
		local sdk_url=https://downloads.openwrt.org/snapshots/targets/${arch}/${subarch}/${dist}-sdk-${arch}-${subarch}_gcc-7.3.0_musl.Linux-x86_64.tar.xz
	elif test $ver \< 18; then
		local sdk_url=https://downloads.openwrt.org/releases/${ver}/targets/${arch}/${subarch}/${dist}-sdk-${ver}-${arch}-${subarch}_gcc-5.4.0_musl-1.1.16.Linux-x86_64.tar.xz
	else
		local sdk_url=https://downloads.openwrt.org/releases/${ver}/targets/${arch}/${subarch}/${dist}-sdk-${ver}-${arch}-${subarch}_gcc-7.3.0_musl.Linux-x86_64.tar.xz
	fi
	local sdk_tar=dl/$(basename $sdk_url)

	download $sdk_url $sdk_tar
	check $sdk_tar $sdk_url

	# global $sdk
	sdk="build_dir/$(tar tf $sdk_tar|head -1)"

	if ! test -e $sdk; then
		test -e build_dir || mkdir build_dir
		tar xvf $sdk_tar -C build_dir
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

download_sums() {
	local url=$1

	local sums_url="$(dirname $url)/sha256sums"
	local sums_file="dl/sha256sums_$(echo $sums_url|md5sum|cut -d ' ' -f 1)"

	if ! test -e $sums_file; then
		wget -O $sums_file $sums_url
	fi

	return=$sums_file
}

check() {
	local dst=$1
	local dst_url=$2

	download_sums $dst_url
	local sums=$return

	local dst_sum="$(grep $(basename $dst_url) $sums|cut -d ' ' -f 1)"

	sum=$(sha256sum $dst| cut -d ' ' -f1)
	if test -z "$dst_sum" -o $dst_sum != $sum; then
		echo Bad checksum $sum of $dst
		exit 1
	fi
}

download_procd() {
	if ! test -e dl/procd-${openwrt_branch}; then
		svn export $procd_url dl/procd-${openwrt_branch}
		sed -i -e "s/PKG_RELEASE:=\(\S\+\)/PKG_RELEASE:=\1-${procd_extra_ver}/" dl/procd-${openwrt_branch}/Makefile
	fi

	test -e dl/procd-${openwrt_branch}/patches || mkdir dl/procd-${openwrt_branch}/patches
	cp -a patches/procd-${openwrt_branch}/* dl/procd-${openwrt_branch}/patches
}

build_procd() {
	rm $sdk/package/lxd-procd||true
	ln -sfT $(pwd)/dl/procd-${openwrt_branch} $sdk/package/lxd-procd

	local date=$(grep PKG_SOURCE_DATE:= dl/procd-${openwrt_branch}/Makefile | cut -d '=' -f 2)
	local version=$(grep PKG_SOURCE_VERSION:= dl/procd-${openwrt_branch}/Makefile | cut -d '=' -f 2 | cut -b '1-8')
	local release=$(grep PKG_RELEASE:= dl/procd-${openwrt_branch}/Makefile | cut -d '=' -f 2)
	local ipk_old=$sdk/bin/targets/${arch}/${subarch}/packages/procd_${date}-${version}-${release}_*.ipk
	local ipk_new=$sdk/bin/packages/${arch_lxd}/base/procd_${date}-${version}-${release}_*.ipk

	if test $ver \< 18; then
		local ipk=$ipk_old
	else
		local ipk=$ipk_new
	fi

	if ! test -s $ipk; then
	(cd $sdk &&
	./scripts/feeds update base &&
	./scripts/feeds install libubox && test -d package/feeds/base/libubox &&
	./scripts/feeds install ubus && test -d package/feeds/base/ubus &&
	make defconfig &&
	make package/lxd-procd/compile
	)
	fi
	test -e ${pkgdir} || mkdir -p ${pkgdir}
	(cd ${pkgdir} && ln -sf ../../../../../$ipk .)
}

build_tarball() {
	export SDK="$(pwd)/${sdk}"
	local opts=""
	if test ${type} = lxd; then
		opts="$opts -m $metadata"
	fi
	if test ${ver} != snapshot; then
		opts="$opts --upgrade"
	fi
	local allpkgs="${packages}"
	for pkg in $pkgdir/*.ipk; do
		allpkgs=" $pkg"
	done
	fakeroot scripts/build_rootfs.sh $rootfs $opts -o $tarball --arch=${arch} --subarch=${subarch} --packages="${allpkgs}" --files="${files}"
}

build_metadata() {
	local stat=`stat -c %Y $rootfs`
	local date="`date -d \"@${stat}\" +%F`"
	local desc="$(tar xf $rootfs ./etc/openwrt_release -O|grep DISTRIB_DESCRIPTION|sed -e "s/.*='\(.*\)'/\1/")"

	cat > $metadata <<EOF
architecture: "$arch_lxd"
creation_date: $(date +%s)
properties:
 architecture: "$arch_lxd"
 description: "$desc"
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

download_rootfs
download_sdk
download_procd
build_procd
build_metadata
build_tarball

echo "Tarball built: $tarball"
