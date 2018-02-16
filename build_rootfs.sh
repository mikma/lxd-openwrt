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
export IPKG_INSTROOT=$dir/rootfs

unpack() {
	mkdir -p $dir/rootfs
	cat $src_tar | (cd $dir/rootfs && tar -xz)
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
	test -d $dst || mkdir $dst
    elif test -f $src; then
	cp $src $dst
	foo=$(dirname $file)
	if [ "$foo" = "./etc/init.d" ]; then
	    echo Enabling $file
	    set +e
	    sh $dir/rootfs/etc/rc.common $src enable
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

unpack
add_files $files_dir $dir/rootfs/
add_file $metadata $metadata_dir $dir
pack
#pack_squashfs
