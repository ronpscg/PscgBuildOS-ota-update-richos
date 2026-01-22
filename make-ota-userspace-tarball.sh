#!/bin/bash

: ${workdir=/tmp/ota-packed-files}
: ${targetarchive=$PWD/ota-richos-targetfiles.tar.xz}
: ${OPTIONAL_OPERATIONAL_CONFIG_FILE_SOURCE=""}
: ${OPTIONAL_OPERATIONAL_CONFIG_FILE_TARGET=/opt/ota/ota.config}
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
	
	if [ -n "$OPTIONAL_OPERATIONAL_CONFIG_FILE_SOURCE" ] ; then
		cp $OPTIONAL_OPERATIONAL_CONFIG_FILE_SOURCE $workdir/$OPTIONAL_OPERATIONAL_CONFIG_FILE_TARGET || { echo "Failed to copy optional operational config file"  ; exit 1; }
	fi
		# can be extended to put more files, or provide a configuration file - we won't do it now
	tar -C $workdir -cJf $targetarchive .
	sha256sum $targetarchive | cut -d ' ' -f 1
}
main $@
