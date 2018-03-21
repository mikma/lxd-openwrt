#!/bin/sh

set -e

usage() {
	echo "Usage: $0 [-a|--arch <arch>] [-s|--subarch <subarch>] [-o|--output <dst file>] [-p|--packages <packages>] [-f|--files <files>] [-m|--metadata <metadata.yaml>] <src tar>"
	exit 1
}

arch=x86
subarch=64
packages=
dst_file=/dev/stdout
files=
metadata=
metadata_dir=

temp=$(getopt -o "a:o:p:s:f:m:" -l "arch:,output:,packages:,subarch:,files:,metadata:,help" -- "$@")
eval set -- "$temp"
while true; do
	case "$1" in
		-a|--arch)
			arch="$2"; shift 2;;
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
	$OPKG install $ipkg
}

add_packages() {
	local dir=$1
	for f in $dir/*.ipk; do
		add_package $f
	done
}

update_packages() {
	$OPKG update
	local upgradable="$($OPKG list-upgradable|cut -d ' ' -f 1)"
	for pkg in $upgradable; do
		echo Upgrading $pkg
		$OPKG upgrade $pkg
	done
}

install_packages() {
	local packages="$1"
	for pkg in $packages; do
		echo Install $pkg
		$OPKG install $pkg
	done
}

unpack
disable_root
if test -n "$metadata"; then
	add_file $metadata $metadata_dir $dir
fi
add_files templates/ $dir/templates/
add_packages bin/packages/${arch}/${subarch}
update_packages
install_packages "$packages"
add_files $files_dir $instroot
if test -n "$files"; then
	add_files $files $instroot
fi
pack
#pack_squashfs
