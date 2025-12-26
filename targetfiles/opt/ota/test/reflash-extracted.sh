#!/bin/sh
#
# Testing script: Sets the state to pending reflashing relying on the availablilty of a previously extracted blob
#
: ${BASE_DIR=$(readlink -f $(dirname $(readlink -f $0))/../../..)}
. $BASE_DIR/opt/ota/ota-richos-defs.sh
. $BASE_DIR/opt/ota/otaCommon.sh

type fatalError &> /dev/null || . $BASE_DIR/opt/scripts/commonEnv.sh

: ${manifest_file=$NEW_WIP_MANIFEST_FILE} # change it via environment variable if you want to use another directory

if [ ! -d $OTA_STATE_WIP_DIR ] ; then
	info "Recreating $OTA_STATE_WIP_DIR and copying files - this is for testing only and we don't check mounts or anything, you're on your own if you're unwise"
	info_do_or_die mkdir $OTA_STATE_WIP_DIR	
	info_do_or_die copy_to_last_valid_manifest_file $manifest_file
fi

if [ ! -f $manifest_file ] ; then
	info_do_or_die cp $(get_last_valid_manifest_file_path) $manifest_file
fi
	
/opt/ota/test/reset-state.sh pendingReflash

if [ "$1" = "reboot" ] ; then
	cd /
	sync
	umount -a
	reboot
fi

