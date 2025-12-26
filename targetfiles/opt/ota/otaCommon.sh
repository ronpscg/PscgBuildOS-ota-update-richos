# source this, do not execute
# This is tailored to a very specific kernel version, so of course it needs to be modified

: ${ota_base_dir=/mnt/ota} # Allow change for debug etc.

# Allow run in tmpfs logic for out-of-band command running via manifest file (dev feature)
: ${OTA_FIRST_TMP_DIR=/tmp/otadev} # Allow an easy way to start working completely in tmpfs. This can for example help with livepatching a ramdisk etc...
: ${OTA_FIRST_TMP_MANIFEST_FILE=$OTA_FIRST_TMP_DIR/downloads/manifests/last_manifest}

export ota_base_dir OTA_FIRST_TMP_DIR manifest_file

### OTA State management directories
OTA_STATE_BASE_DIR=$ota_base_dir/state
OTA_STATE_WIP_DIR=$OTA_STATE_BASE_DIR/wip/
OTA_STATE_DONE_DIR=$OTA_STATE_BASE_DIR/done/
OTA_STATE_EXCLUDED_DIR=$OTA_STATE_BASE_DIR/excluded/	# Failed and otherwise blacklisted images (could also be used for preventing rollbacks, etc...) won't do that on the simple versions

OTA_STATE_FILE=$OTA_STATE_BASE_DIR/current_state

NEW_WIP_MANIFEST_FILE=$OTA_STATE_WIP_DIR/last_manifest
NEW_WIP_MANIFEST_DIGEST=$OTA_STATE_WIP_DIR/last_manifest_digest # NOT IMPLEMENTED YET, see comments in other places in the code

OTA_SUCCESS_BOOT_COUNTER_FILE=$OTA_STATE_WIP_DIR/success_boot_counter
OTA_FAIL_BOOT_COUNTER_FILE=$OTA_STATE_WIP_DIR/fail_boot_counter
OTA_EXCLUDED_DIGESTS_FILE=$OTA_STATE_BASE_DIR/excluded/digests

### OTA Blob download and extraction directories
OTA_EXTRACT_BASE_DIR=$ota_base_dir/extract

# All of the OTA_BLOBS related directories are [onlyusedbyrichos]
: ${OTA_BLOBS_BASE_DIR=$ota_base_dir/downloads}
OTA_BLOBS_KEYS_DIR=$OTA_BLOBS_BASE_DIR/keys
OTA_BLOBS_MANIFESTS_DIR=$OTA_BLOBS_BASE_DIR/manifests
OTA_BLOBS_BLOBS_DIR=$OTA_BLOBS_BASE_DIR/blobs
OTA_BLOBS_WIP_DIR=$OTA_BLOBS_BLOBS_DIR/wip
OTA_BLOBS_DONE_DIR=$OTA_BLOBS_BLOBS_DIR/done
OTA_BLOBS_FAILED_DIR=$OTA_BLOBS_BLOBS_DIR/failed

: ${OTA_LOG_DIR=$OTA_EXTRACT_BASE_DIR/debug/}
: ${OTA_LOG_FILE=$OTA_LOG_DIR/ota-debug.log}

OTA_REFLASH_COUNTER_FILE=$OTA_STATE_WIP_DIR/reflash_counter
MAX_REFLASH_COUNTER=5

OTA_MAX_SUCCESS_BOOT_COUNTER=1
OTA_MAX_FAIL_BOOT_COUNTER=3


LAST_VALID_ACTIVE_SYSTEM_PARTITION_FILE=$OTA_STATE_DONE_DIR/last_active_system_partition
LAST_VALID_ACTIVE_BOOT_PARTITION_FILE=$OTA_STATE_DONE_DIR/last_active_boot_partition
LAST_VALID_ACTIVE_DIGEST_FILE=$OTA_STATE_DONE_DIR/last_active_digest
OTA_NEXT_BOOT_PARTITION_FILE=$OTA_STATE_WIP_DIR/next_boot_partition
OTA_NEXT_SYSTEM_PARTITION_FILE=$OTA_STATE_WIP_DIR/next_system_partition

OTA_ACTIVE_SYSTEM_PARTITION_LABEL=system
OTA_STANDBY_SYSTEM_PARTITION_LABEL=retired-system
OTA_TESTED_CANDIDATE_SYSTEM_PARTITION_LABEL=system-pscg-can
# better label with upercase, for legacy support, lowercase labels for fat fs do work in practice
OTA_ACTIVE_BOOT_PARTITION_LABEL=BOOTFS
OTA_STANDBY_BOOT_PARTITION_LABEL=RETIREDBOOT # fat label can have 11 characters

# The following is intended for populating a manifest upon installation, hence avoiding unnecessary downloads
# of the same image
# This also allows for testing scenarios while avoiding downloading and extracting again
LAST_VALID_OTA_MANIFEST_FILE=$OTA_STATE_DONE_DIR/manifest

#
# The objective of this function is to check that OTA is mounted properly
#
check_ota_partitions_mounted() {
	if mountpoint $OTA_STATE_BASE_DIR && mountpoint $OTA_EXTRACT_BASE_DIR ; then
		debug "OTA directories are already mounted"
		return 0
	else
		return 1
	fi
}

#
# Under some circumstances, we would like to bind mount folders that were, well, bind mounted with docker
# mountpoint will fail to declare them as mountpoints, so we want another mechanism to identify it
# it is done in a separate function to not contaminate the operational logic
#
docker_mount_ota_partitions_logic() {
	: # not needed if we mount them from docker - BUT - they will not find themselves updated in the iso...
	# this is really needed only for the very first setup AFAIK
	verbose "This was already taken care of way before trying to mount the ota partitions, so not doing anything"
}

#
# The objective of this function is to mount the OTA directories.
# If the OTA directories are already mounted, it is assumed that it is for a reason. At first, this was considered an error,
# to 7x check that the caller knows what they are doing. While it is a good practice, it limits all kinds of emulations, so we now allow
# another type of mounting (e.g. if we do other namespaces, use containers, etc.), and if the directories are already mounted, we assume
# it was intentional
#
mount_ota_partitions() (
	mkdir -p $OTA_STATE_BASE_DIR || errorExitScope "Failed to create ota state dir" 2
	mkdir -p $OTA_EXTRACT_BASE_DIR || errorExitScope "Failed to create ota extract dir" 2

	if [ "$docker" = "true" -a "$docker_use_bindmount_ota_partitions" = "true" ] ; then
		warn "DOING THE DOCKER LOGIC for mountOtaPartitions"
		docker_mount_ota_partitions_logic
		return $?
	fi

	if mountpoint $OTA_STATE_BASE_DIR ; then
		warn "$OTA_STATE_BASE_DIR was already mounted."
	else
		mount LABEL=otastate $OTA_STATE_BASE_DIR || errorExitScope "Cannot mount ota state dir" 3
	fi

	if mountpoint $OTA_EXTRACT_BASE_DIR ; then
		warn "$OTA_EXTRACT_BASE_DIR was already mounted."
	else
		mount LABEL=otaextract $OTA_EXTRACT_BASE_DIR || errorExitScope "Cannot mount ota extract dir" 3
	fi

	return 0
)


unmount_ota_partitions() (
	mountpoint $OTA_STATE_BASE_DIR && { umount $OTA_STATE_BASE_DIR || errorExitScope "Failed to unmount state" ; }
	mountpoint $OTA_EXTRACT_BASE_DIR && { umount $OTA_EXTRACT_BASE_DIR || errorExitScope "Failed to unmount extract" ; }
	return 0
)

#
# [onlyusedbyflasher]
# TODO perahps merge with the temporary dirs and other code in the richos. - although only the mounts matter for the ramdisk
init_ota_directories() {
	local curdir
	curdir=$PWD

	mountpoint $OTA_STATE_BASE_DIR	|| fatalError "$OTA_STATE_BASE_DIR is not a mountpoint. OTA is not supported"
	mountpoint $OTA_EXTRACT_BASE_DIR || fatalError "$OTA_EXTRACT_BASE_DIR is not a mount point. OTA is not supported"
	cd $OTA_STATE_BASE_DIR || fatalError "$OTA_STATE_BASE_DIR does not exist."

	[ -d $OTA_STATE_DONE_DIR ] || { warn "Creating the state/done directory for the first time - this should have been populated on first installation and on every update"; mkdir $OTA_STATE_DONE_DIR || fatalError "Could not create the done dir" ; }
	[ -d $OTA_STATE_WIP_DIR ] || { warn "Creating the state/wip directory for the first time. This is where work in progress update is happening"; mkdir $OTA_STATE_WIP_DIR || fatalError "Could not create the wip dir" ; }
	[ -d $OTA_STATE_EXCLUDED_DIR ] || { warn "Creating the state/excluded directory for the first time. This is where work in progress update is happening"; mkdir $OTA_STATE_EXCLUDED_DIR || fatalError "Could not create the excluded dir" ; }

	cd $curdir
}

#
# This function is meant to be called ONLY after first flashing from a removable media installer
# It is assumed that the following variables are set prior to calling it:
#	last_active_boot_partition - the boot partition the image is first installed onto
#	last_active_system_partition - the system partition the image is first installed onto
#	installer_digest - If the installer provides digest file, put its contents
#	installer_manifest_file - If the installer provides a manifest file, copies its contents
#
#[onlyusedbyflasher]
#
set_ota_done_states_after_first_installation() (
	check_ota_partitions_mounted || { mount_ota_partitions || errorExitScope "Failed to mount the ota partitions" ; }
	init_ota_directories || errorExitScope "Failed to set and initialize the OTA directories"
	set_state idle
	debug "First time flashing: lab=$last_active_boot_partition las=$last_active_system_partition installer_digest=$installer_digest manifest_file=$installer_manifest_file"
	[ ! -z $last_active_boot_partition ] && set_last_valid_active_boot_partition $last_active_boot_partition
	[ ! -z $last_active_system_partition ] && set_last_valid_active_system_partition $last_active_system_partition
	[ ! -z $installer_digest ] && set_last_valid_active_digest $installer_digest
	[ -f "$installer_manifest_file" ] && copy_to_last_valid_manifest_file $installer_manifest_file
	sync
)

set_state() {
	local current_state=$1
	verbose "Setting state to $current_state"
	echo $current_state > $OTA_STATE_FILE || fatalError "Failed to set state to $current_state"
	sync # ensure the state gets sync to the file system
}

get_state() {
	local current_state=""
	current_state=$(cat $OTA_STATE_FILE) || current_state=""
	echo $current_state
}

set_last_valid_active_digest() {
	local digest
	digest=$1
	if [ ! -z "$digest" ] ; then
		verbose "Setting last valid active digest to $digest"
		echo $digest > $LAST_VALID_ACTIVE_DIGEST_FILE || fatalError "Failed to set last valid active digest to $digest"
	else
		error "empty last valid digest"
	fi
}

get_last_valid_active_digest() {
	local digest
	digest=$(cat $LAST_VALID_ACTIVE_DIGEST_FILE 2>/dev/null) || digest=""
	echo $digest
}

#
# The objective of this function is to copy $1 to the last valid manifest file, so that the system maintainer
# would be able to know more details about the flashed image, and not only the digest.
#
copy_to_last_valid_manifest_file() {
	local manifest
	manifest=$1
	if [ ! -z "$manifest" ] ; then
		verbose "Copying last valid manifest file from $manifest"
		cp $manifest $LAST_VALID_OTA_MANIFEST_FILE || fatalError "Failed to copy last valid manifest file from $manifest"
	else
		error "empty last valid manifest"
	fi
}

#
# Just prints the path of the last manifest file name if it exists.
# The file can be long, so the set/get is different (see copy_to... ..._file_path) instead of set/get in other functions
#
# returns "" if the manifest file does not exist, and the path if it exists (just $LAST_VALID_OTA_MANIFEST_FILE)
#
get_last_valid_manifest_file_path() {
	if [ -f "$LAST_VALID_OTA_MANIFEST_FILE" ] ; then
		echo $LAST_VALID_OTA_MANIFEST_FILE
	fi
}

#
# You are unlikely to use this function. Perhaps if you want to grep in the file etc or just debug
#
print_last_valid_manifest_file() {
	if [ -f "$LAST_VALID_OTA_MANIFEST_FILE" ] ; then
		cat $LAST_VALID_OTA_MANIFEST_FILE
	fi
}

exclude_digest() {
	warn "Blacklisting $1 from being reflashed in the future" # TODO this feature is not implemented yet
	echo $1 >> $OTA_EXCLUDED_DIGESTS_FILE
	sync
}

is_digest_excluded() {
	debug "Checking $1 for previous (blacklist) failures"
	grep -q "$1" $OTA_EXCLUDED_DIGESTS_FILE
	return $?
}

# This kind of things should be the responsibility of the bootloader really

set_last_valid_active_boot_partition() {
	local partition=$1
	verbose "Setting active boot partition to $partition"
	echo $partition > $LAST_VALID_ACTIVE_BOOT_PARTITION_FILE || fatalError "Failed to set active boot partition to $partition"
	sync
}

set_last_valid_active_system_partition() {
	local partition=$1
	verbose "Setting active system partition to $partition"
	echo $partition > $LAST_VALID_ACTIVE_SYSTEM_PARTITION_FILE || fatalError "Failed to set active system partition to $partition"
	sync
}

get_last_valid_active_boot_partition() {
	local partition=""
	partition=$(cat $LAST_VALID_ACTIVE_BOOT_PARTITION_FILE) || partition=""
	echo $partition
}

get_last_valid_active_system_partition() {
	local partition=""
	partition=$(cat $LAST_VALID_ACTIVE_SYSTEM_PARTITION_FILE) || partition=""
	echo $partition
}

#
# $1: full path of the partition (e.g. /dev/mmcblk0p1,  /dev/vda1, etc.)
#
set_next_boot_partition() {
	local partition=$1
	verbose "Setting the next boot partition to $partition"
	echo $partition > $OTA_NEXT_BOOT_PARTITION_FILE || fatalError "Failed to set the next boot partition to $partition"
	sync
}

#
# $1: full path of the partition (e.g. /dev/mmcblk0p12,  /dev/vda5, etc.)
#
set_next_system_partition() {
	local partition=$1
	verbose "Setting the next system partition to $partition"
	echo $partition > $OTA_NEXT_SYSTEM_PARTITION_FILE || fatalError "Failed to set the next system partition to $partition"
	sync
}

get_next_boot_partition() {
	local partition
	partition=$(cat $OTA_NEXT_BOOT_PARTITION_FILE) || partition=""
	echo $partition
}

get_next_system_partition() {
	local partition
	partition=$(cat $OTA_NEXT_SYSTEM_PARTITION_FILE) || partition=""
	echo $partition
}

get_success_boot_counter() {
	local current_success_boot_counter
	if [ -f $OTA_SUCCESS_BOOT_COUNTER_FILE ] ; then
		current_success_boot_counter=$(cat $OTA_SUCCESS_BOOT_COUNTER_FILE)
	else
		current_success_boot_counter=0
	fi
	echo $current_success_boot_counter
}

set_success_boot_counter() {
        local counter=$1
        echo $counter > $OTA_SUCCESS_BOOT_COUNTER_FILE || fatalError "Could not update successful boot counter to $counter"
}

get_fail_boot_counter() {
	local current_fail_boot_counter
	if [ -f $OTA_FAIL_BOOT_COUNTER_FILE ] ; then
		current_fail_boot_counter=$(cat $OTA_FAIL_BOOT_COUNTER_FILE)
	else
		current_fail_boot_counter=0
	fi
	echo $current_fail_boot_counter
}

set_fail_boot_counter() {
        local counter=$1
        echo $counter > $OTA_FAIL_BOOT_COUNTER_FILE || fatalError "Could not update failed boot counter to $counter"
}


### Definitions only used by the flasher (preparation for refactoring)
OTA_WIP_EXTRACT_WORKING_DIR_FILE=$OTA_STATE_WIP_DIR/extract_working_dir	# Allow multiple flows for the same design - i.e. OTA, A/B installer and recovery can tell via this file to extract to a particular directory, or use a default #[onlyusedbyflasher]

#
# get the extract working dir. unless it was explicitly set by set_wip_extract_Working_dir, the default directory would be $OTA_EXTRACT_BASE_DIR
#[onlyusedbyflasher]
#
get_wip_extract_working_dir() {
	local workingdir=$OTA_EXTRACT_BASE_DIR
	if [ -f $OTA_WIP_EXTRACT_WORKING_DIR_FILE ] ; then
		workingdir=$(cat $OTA_WIP_EXTRACT_WORKING_DIR_FILE)
	fi
	echo $workingdir
}
#
# Set the extract working dir - and expect the logic to associate it with the right mounts/devices (e.g. otaextract, removable etc.)
#[onlyusedbyflasher]
#
set_wip_extract_working_dir() {
	workingdir=$1
	verbose "Setting the wip extract working dir $workingdir. This allows for using a single update (We call it OTA) mechanism for OTA, A/B installer and recovery"
	echo $workingdir > $OTA_WIP_EXTRACT_WORKING_DIR_FILE || fatalError "Failed to set the extract working dir to $workingdir"
	sync
}

#
# Clean up the ota extract partition
# $1: if set to cleandebug or cleanlogs, clean the debug and log files. Otherwise, keep them
#
cleanup_ota_extract() {
	info "Cleaning up $OTA_EXTRACT_BASE_DIR"
	for i in $(ls -A $OTA_EXTRACT_BASE_DIR) ; do
		if [ "$i" = "debug" ] ; then
			if [ ! "$1" = "cleandebug" -a ! "$1" = "cleanlogs" ] ; then
				rm -rf $OTA_EXTRACT_BASE_DIR/$i || error "Failed to remove $i"
			fi
		else
			rm -rf $OTA_EXTRACT_BASE_DIR/$i || error "Failed to remove $i"
		fi
	done
}

#
# can be also used by the richos
# redirects some of the logs to a persistent storagae in a dedicated partition (otaextract by default)
#
redirect_logs_to_ota_extract_partition() {
	local common_env_file=/commonEnv.sh
	if [ ! -f /commonEnv.sh ] ; then
		# this means we are running in a richos
		common_env_file=/opt/scripts/commonEnv.sh
	fi
	source $common_env_file || { echo "No logger file, skipping redirection" ; return ; }

	#
	# TODO (very, very low priority): unify for when allowing a *different* log partition
	# this should also work for the rich os but I wrote it separately and changing might be a little delicate for a use case
	# that is for debugging only:
	#	it is not important, and it needs some thought in case we do an OTA in the richos (I sometimes call it userspace,
	#	although the initramfs is also userspace...) without mounting any other partition
	if mountpoint "$(dirname $OTA_LOG_DIR)" &> /dev/null ; then
		if [ ! -d $OTA_LOG_DIR ] ; then
			do_or_die mkdir $OTA_LOG_DIR
		fi
	fi

	do_or_die touch $OTA_LOG_FILE
	export logFile2=$OTA_LOG_FILE
	source $common_env_file
}
