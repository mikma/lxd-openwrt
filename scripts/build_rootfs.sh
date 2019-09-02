#!/bin/sh

set -e

usage() {
	echo "Usage: $0 [-a|--arch <arch>] [-d|--disable-services <services>] [-s|--subarch <subarch>] [-o|--output <dst file>] [-p|--packages <packages>] [-f|--files <files>] [-m|--metadata <metadata.yaml>] [-u|--upgrade] <src tar>"
	exit 1
}

arch=x86
subarch=64
packages=
dst_file=/dev/stdout
files=
services=
metadata=
metadata_dir=
upgrade=

temp=$(getopt -o "a:d:o:p:s:f:m:u:" -l "arch:,disable-services:,output:,packages:,subarch:,files:,metadata:,upgrade,help" -- "$@")
eval set -- "$temp"
while true; do
	case "$1" in
		-a|--arch)
			arch="$2"; shift 2;;
		-d|--disable-services)
            services="$2"; shift 2;;
		-s|--subarch)
			subarch="$2"; shift 2;;
		-p|--packages)
			packages="$2"; shift 2;;
		-o|--output)
			dst_file="$2"; shift 2;;
		-f|--files)
			files="$2"; shift 2;;
		-m|--metadata)
			metadata=`basename $2`
			metadata_dir=`dirname $2`
			shift 2;;
		-u|--upgrade)
			upgrade=1; shift 1;;
		--help)
			usage;;
		--)
			shift; break;;
	esac
done

if [ $# -ne 1 ]; then
	usage
fi

src_tar=$1
base=`basename $src_tar`
dir=/tmp/build.$$
files_dir=files/
instroot=$dir/rootfs
cache=dl/packages/$arch/$subarch

test -e $cache || mkdir -p $cache
OPKG="env LD_PRELOAD= IPKG_NO_SCRIPT=1 IPKG_INSTROOT=$instroot $SDK/staging_dir/host/bin/opkg -o $instroot --cache $cache"

unpack() {
	mkdir -p $instroot
	cat $src_tar | (cd $instroot && tar -xz)
}

pack() {
	echo Pack rootfs
	if test -n "$metadata"; then
		(cd $dir && tar -cz *) > $dst_file
	else
		(cd $dir/rootfs && tar -cz *) > $dst_file
	fi
}

pack_squashfs() {
	echo Pack rootfs squashfs
	mksquashfs $dir $dst_file
}

disable_root() {
	sed -i -e 's/^root::/root:*:/' $instroot/etc/shadow
}

add_file() {
    file=$1
    src_dir=$2
    dst_dir=$3

    src=$src_dir/$file
    dst=$dst_dir/$file

    if test -d $src; then
	test -d $dst || mkdir -p $dst
    elif test -f $src; then
	cp $src $dst
	foo=$(dirname $file)
	if [ "$foo" = "./etc/init.d" ]; then
	    echo Enabling $file
	    set +e
	    env IPKG_INSTROOT=$instroot sh $instroot/etc/rc.common $dst enable
	    set -e
	fi
    fi
}

add_files() {
	src_dir=$1
	dst_dir=$2

	for f in $(cd $src_dir && find); do
		add_file $f $src_dir $dst_dir
	done
}

add_package() {
	local ipkg=$1
	$OPKG install --force-downgrade $ipkg
}

add_packages() {
	local dir=$1
	for f in $dir/*.ipk; do
		add_package $f
	done
}

opkg_update() {
	$OPKG update
}

update_packages() {
	local upgradable="$($OPKG list-upgradable|grep -e '^.* - .* - .*'|cut -d ' ' -f 1)"
	for pkg in $upgradable; do
		echo Upgrading $pkg
		$OPKG upgrade $pkg
	done
}

install_packages() {
	local packages="$1"
	for pkg in $packages; do
		echo Install $pkg
		$OPKG install --force-downgrade $pkg
	done
}

disable_services() {
    local services="$1"
    for service in $services; do
        echo Disabling $service
        env IPKG_INSTROOT=$instroot sh $instroot/etc/rc.common $instroot/etc/init.d/$service disable
    done
}

create_manifest() {
    $OPKG list-installed > $instroot/etc/openwrt_manifest
}

unpack
disable_root
if test -n "$metadata"; then
	add_file $metadata $metadata_dir $dir
fi
add_files templates/ $dir/templates/
opkg_update
if test -n "$upgrade"; then
	update_packages
fi
install_packages "$packages"
disable_services "$services"
add_files $files_dir $instroot
if test -n "$files"; then
	add_files $files $instroot
fi
create_manifest
pack
#pack_squashfs
