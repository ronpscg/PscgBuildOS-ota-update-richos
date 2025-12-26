#!/bin/bash

: ${workdir=/tmp/ota-packed-files}
: ${targetarchive=$PWD/ota-richos-targetfiles.tar.xz}

main() {
	set -euo pipefail
	LOCAL_DIR=$(dirname ${BASH_SOURCE[0]})
	rm -rf $workdir
	mkdir -p $workdir/etc/
	mkdir -p $workdir/opt/

	cd $LOCAL_DIR/targetfiles
	cp -a  etc/ $workdir/
	cp -a  opt/ $workdir/
	cp -a overlay-install-instructions.sh $workdir/ # if the file doesn't exist it's fine, this error would be OK
	tar -C $workdir -cJf $targetarchive .
	sha256sum $targetarchive | cut -d ' ' -f 1
}
main $@
