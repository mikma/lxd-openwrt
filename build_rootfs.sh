#!/bin/sh

set -e

if [ $# -ne 2 ]; then
	echo "Usage: $0 <src tar> <dst file>"
	exit 1
fi

src_tar=$1
dst_file=$2
base=`basename $src_tar`
dir=/tmp/build.$$
export IPKG_INSTROOT=$dir

unpack() {
	mkdir $dir
	cat $src_tar | (cd $dir && tar -xz)
}

pack() {
	echo Pack rootfs
	(cd $dir && tar -cz *) > $dst_file
}

pack_squashfs() {
	echo Pack rootfs squashfs
	mksquashfs $dir $dst_file
}

add_files() {
	for f in $(cd files && find); do
		src=files/$f
		dst=$dir/$f
		if test -d $src; then
			test -d $dst || mkdir $dst
		elif test -f $src; then
			cp $src $dst
			foo=$(dirname $f)
			if [ "$foo" = "./etc/init.d" ]; then
				echo Enabling $f
				set +e
				sh $dir/etc/rc.common $src enable
				set -e
			fi
		fi
	done
}

unpack
add_files
#pack
pack_squashfs
