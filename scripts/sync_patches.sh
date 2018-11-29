#!/bin/sh

set -e

usage() {
	echo "Usage: $0 <procd git repository>"
	exit 1
}

if [ $# -ne 1 ]; then
        usage
fi

repo=$1
tmpdir=/tmp/procd.$$

git clone $repo $tmpdir

for ver in openwrt-18.06 master; do
	outdir=$(pwd)/patches/procd-$ver
	git rm $outdir/00*
	(cd $tmpdir && git format-patch --output-directory $outdir origin/$ver...origin/lxd/$ver)
	git add $outdir/00*
done
