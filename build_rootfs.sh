#!/bin/sh

set -e

if [ $# -ne 3 ]; then
	echo "Usage: $0 <src tar> <metadata.yaml> <dst file>"
	exit 1
fi

src_tar=$1
metadata_dir=`dirname $2`
metadata=`basename $2`
dst_file=$3
base=`basename $src_tar`
dir=/tmp/build.$$
files_dir=files/
instroot=$dir/rootfs

OPKG=$SDK/staging_dir/host/bin/opkg
export IPKG_INSTROOT=$instroot

unpack() {
	mkdir -p $instroot
	cat $src_tar | (cd $instroot && tar -xz)
}

pack() {
	echo Pack rootfs
	(cd $dir && tar -cz *) > $dst_file
}

pack_squashfs() {
	echo Pack rootfs squashfs
	mksquashfs $dir $dst_file
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
	    sh $instroot/etc/rc.common $src enable
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
	$OPKG -o $instroot install $ipkg
}

add_packages() {
	local dir=$1
	for f in $dir/*.ipk; do
		add_package $f
	done
}

unpack
add_files $files_dir $instroot
add_file $metadata $metadata_dir $dir
add_files templates/ $dir/templates/
add_packages bin/packages/${ARCH}/${SUBARCH}
pack
#pack_squashfs
