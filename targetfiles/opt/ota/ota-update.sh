#!/bin/sh
#
# NOTE: On rich systems, use bash, or make /bin/sh point to bash. The interpreter here is /bin/sh to prove that
#       it works on busybox as well. Debian's default shell is usually dash, it sucks, and we'd rather support
#		either bash or busybox
#
# OTA update service entry point script
# Since this is done for educational purposes, we are providing a developer mode for you to be able to check how this code works also from your systems, without deploying more things
#
: ${ota_nomounts=false}		# If true, will not mount partitions, but rather make up a folder hierarchy
: ${strict_debugging=false}
export strict_debugging


set_strict_debugging() {
	if [ -n "$BASH" ] ; then
		trap bash_backtrace_trap ERR
		set -eo pipefail
		strict_debugging=true
	fi
}

#
# the exact oposite of the the previous function
#
unset_strict_debugging() {
	if [ -n "$BASH" ] ; then
		trap "" ERR
		set +eo pipefail
		strict_debugging=false
	fi
}

#
# To allow some development options (e.g. "playing" with the system on your development host), and to allow
# running some things from tmpfs (e.g ramdisk systems for very first deployments etc, with a "command script" (@see livepatch)
# We will organize some invariant checking in this function.
#
# Side-effect: setting of:
# $BASE_DIR - the base dir of the scripts (i.e. containing /opt), or the root dir in operational systems
# $ota_base_dir - where the state, extract and logs will reside (unless logs are redirected elsewhere)
#
init_script_directories() { # TODO rename, rename comments etc.
	export BASE_DIR
	# We assume an hierarchy where the relevant scripts are under /opt
	: ${BASE_DIR=$(readlink -f $(dirname $(readlink -f $0))/../..)}


	#init_ota_dev_directories_if_needed - now doing the contents in main
}

#
# Creates the directory structure on a host, without having to mount any other storage. Used for development purposes
#
init_ota_dev_directories_if_needed() {
	if [ "$ota_nomounts" = "true" ] ; then
		: ${ota_base_dir=/tmp/otadev}
		mkdir -p $ota_base_dir || { echo "Failed to create $ota_base_dir" ; exit 1 ; }
		echo "Doing OTA DEBUGGING FLOW --> $ota_base_dir"
		for i in state extract logs ; do
			mkdir -p $ota_base_dir/$i || { echo "Failed to create $ota_base_dir/$i" ; exit 1 ; }
		done

		echo "OTA dev folders are available."
		export ota_base_dir # affect subsequent scripts
		return 0
	fi
	return 1
}

# We can use /etc/fstab - but we want this to support file systems without fstab
init_ota_mounts() {
	# We need to mount and initialize once. No need to check it every time
	info "Mounting the OTA directories..." | $TEECMD
	if mount_ota_partitions ; then
		verbose "OTA partitions are available."
	else
		error "No OTA partitions, OTA is not supported. Trying to see if it they were already mounted, and retry"
		unmount_ota_partitions
		mount_ota_partitions || fatalError "Can't mount OTA partitions even after retrying. Giving up"
		info "Seems like we were able to remount the partitions. Hooray."
	fi
}

#
# Create all the relevant directories at once, even if not needed.
# This must be done after having the base folders mounted (if using an operational mountpoint solution),
# or just created (otherwise)
#
init_ota_directories_local() {
	: ${OTA_FIRST_TMP_DIR=/tmp/otadev}
	### Basics - state, extract
	if [ ! "$ota_nomounts" = "true" ] ; then
		: ${ota_base_dir=/mnt/ota}	# This would be the operational anyway - and mount points would be under it
		source_ota_defs
		init_ota_mounts
	else
		: ${ota_base_dir=/tmp/otadev}	# This is for debugging mode
		source_ota_defs
		for dir in $OTA_STATE_BASE_DIR $OTA_EXTRACT_BASE_DIR ; do
			debug_do mkdir -p $dir || fatalError "Can't create $dir"
		done
	fi

	for dir in $OTA_STATE_WIP_DIR $OTA_STATE_DONE_DIR $OTA_STATE_EXCLUDED_DIR ; do
		debug_do mkdir -p $dir || fatalError "Can't create $dir"
	done

	for dir in $OTA_LOG_DIR ; do
		debug_do mkdir -p $dir || fatalError "Can't create $dir"
	done

	### Initialize Downloads. The important thing is blobs, but you may also want to store security keys/certificates there,
	### (and later move to a "state/done" dir etc.)
	if [ ! -d "$OTA_BLOBS_BASE_DIR" ] ; then
			info "Creating $OTA_BLOBS_BASE_DIR for the first time"
			info_do_or_die mkdir -p $OTA_BLOBS_BASE_DIR
	fi

	# Most of the folders related to the downloads/blobs are preperation for future features or discussions. We made a simple system, and we will
	# focus on the simple operation
	for dir in $OTA_BLOBS_KEYS_DIR $OTA_BLOBS_MANIFESTS_DIR $OTA_BLOBS_BLOBS_DIR $OTA_BLOBS_WIP_DIR $OTA_BLOBS_DONE_DIR $OTA_BLOBS_FAILED_DIR ; do
		debug_do mkdir -p $dir || fatalError "Can't create $dir"
	done

	### Manifest download
	if [ -w $OTA_FIRST_TMP_DIR ] && [ ! -e $OTA_FIRST_TMP_MANIFEST_FILE -o -w $OTA_FIRST_TMP_MANIFEST_FILE ] ; then
		manifest_file=$OTA_FIRST_TMP_MANIFEST_FILE		# goes into somewhere volatile, allowing to download even before starting anything else
														# this allows to do complete different logic by getting the manifest commands
														# including livepatching the OTA code itself [mostly intended for that]
	else
		manifest_file=$NEW_WIP_MANIFEST_FILE			# goes into the state/wip directory
	fi

	if [ ! -d $(readlink -f $(dirname $manifest_file)) ] ; then
		do_or_die mkdir $(readlink -f $(dirname $manifest_file))
	fi
}


#
# Decide log sinks. stdout would usually be one of them
# We can debug to multiple sinks, but we'll chose one. Other a file on a persistent storage, file on volatile storage, /dev/kmsg or /dev/null
#
init_ota_debug_files() {
	: ${logTag=otasvc}	# emphasize in the common log file that everything here comes from userspace (the "richos")

	if [ ! -d $OTA_LOG_DIR ] ; then
		: ${DEBUGFILENAME=ota-debug.log}
		DEBUGFILE=/tmp/$DEBUGFILENAME
	else
		DEBUGFILE=$OTA_LOG_FILE
	fi

	if ! touch $DEBUGFILE ; then
		echo "Cannot write to $DEBUGFILE"
		if [ -w /dev/kmsg ] ; then
			echo "Will log to the kernel log buffer, and not to a file"
			DEBUGFILE=/dev/kmsg
		else
			echo "Will log to standard output, and not to a file"
			DEBUGFILE=/dev/null
		fi
	fi

	# can also select a multiple TEECMD and export it - e.g.: TEECMD=" tee -a your file | tee /dev/kmsg" - in this format (does not start with pipe)
	TEECMD=" tee -a $DEBUGFILE"
	export DEBUGFILE TEECMD # for the subsequent scripts to enjoy
}


sigusr1() {
        debug $FUNCNAME $(get_state)
}

sigusr2() {
        # Could restart the service in systemd - but keeping it independent
        warn "$FUNCNAME --> restarting $0"
        exec $(readlink -f $0)
}


#
# Just a wrapper to source some common definition files
#
source_ota_defs() {
	source $BASE_DIR/opt/ota/otaCommon.sh || fatalError "Cannot source the ota common file"
	source $BASE_DIR/opt/ota/ota-richos-defs.sh || fatalError "Cannot source the rich operating system ota definitions"
}

#
# Parse command line arguments. In an operational system that is fully tested, you are expected to have none
# otherwise, the parameters arae quite self explanatory
#
parse_args() {
	oneshot=false
	startwithmanifestdownloading=false
	for i in $@ ; do
		case $i in
			oneshot)
				oneshot=true
				;;
			startwithmanifestdownloading)
				startwithmanifestdownloading=true
				;;
			ota_nomounts)
				ota_nomounts=true;
				;;
			*)

				;;
		esac
	done
}

#
# Just show a welcome banner
#
ota_welcome_banner() {
	local release_file=/etc/thepscgos-release
	local state_file=$OTA_STATE_FILE
	local msg_release msg_state

	if [ -f $release_file ] ; then
		msg_release="Your currently installed version is: $(grep VERSION $release_file | tr -d \")"
	else
		msg_release="(No release file)"
	fi

	if [ -f $state_file ] ; then
		msg_state="The current update state is: $(get_state)"
	else
		msg_state="(No state file)"
	fi

	if [ ! -f $release_file -o ! -f $state_file ] ; then
		warn "Software updater is up and it seems like your system is trying this mechanism for the first time, or someone tampered with your state: \n$msg_release \n$msg_state"
	else
		info "Software updater is up. \n$msg_release \n$msg_state"
	fi
}

#
# The idea here is to enable doing commands that are out of the OTA logic. For example, enabling to completely hotpatch
# the ota mechanism before starting
#
# More details:
# Get the first manifest
# Have no dependencies whatsoever (sorry folks, no logging) so that it can be called as early as possible
#
# Remember that we are using a manifest file and parse it. We could or could not use a file and save it in a temporary location, if there is justification for it, meaning:
# - Network access
# - We want to support development or volatile memory work
# - The manifest file can then "give instructions"
#
# This leads to being able to use a generic framework before we actually mount anything on rely on any knowledge of the partition structure, or even any previous support
# of OTA. In other words, it enables to deploy an OTA framework while still developing an OTA framework (you should plan everything before, but hey, education fellows!)
#
#
# Note: this design is a bit wasteful, as it assumes the mounting of the partitions (if they need to be mounted) before using them.
#       this can lead to an irresponsible security design that would allow for TOCTOU attacks, which would be more easily mitigated by checking at every step of the process for validity of files used in the process
#
do_first_tmpfs_manifest_check_and_processing() {
	echo $manifest_file
	if check_for_updates ; then
		if [ -n "$misc_commands" ] ; then
			hardInfo "Will run $misc_commands"
			# Note for students: don't use eval unless you know what you're doing...
			# Another note for students: eval is used here to enable running compound commands
			eval $misc_commands
			# Note: the misc_commands, if they exist are usually expected to be a "one timer".
			# If they are not, the logic will continue, and it will tell your there is an update etc.
			# So if the misc commands already do something like downloading/verifying/etc. - the prints will be misleading
			# That is OK, because you are not supposed to use them unless you know what you are doing anyway :-)
		else
			warn "no misc commands"
		fi
	else
		verbose "No updates or no valid manifest. Nothing will be done on early start"
		return 2
	fi
}

#
# clean up log files, clean previous sta
# this is of course a suggestion, and in a real system you would define thresholds etc.
# There is no point in keeping the downloaded files and previous logs on the idle state, and in some of the failure
# states. However, it makes it easier to change the state and redo tests with large blobs on a real system, without
# having to redownload them, and same for archive extraction times etc.
#
do_cleanups() {
	local log_size=$(du -b $DEBUGFILE | cut -f 1)
	local log_size_threshold=$((1024*100))
	if [[ $log_size -ge $log_size_threshold ]] ; then
		# This logic is fine for /dev/null and /dev/kmsg again as for these files the size is always 0 so we won't get here
		hardWarn "\x1b[43m]Rotating log\x1b[0m]"
		mv $DEBUGFILE $DEBUGFILE.1
		touch $DEBUGFILE
		hardInfo rotated logfile
	fi

	if [ "$(get_state)" = "idle" ] ; then
		warn "Cleaning up previous downloads"
		# Well, don't do that, because it serves us now for speedups ;-)
	fi
}

# Run in background and wait to allow trap handling. Otherwise signals are handled only after the command (i.e. sleep) returns.
# Use this kind of constructs only if you don't have set -e (e.g. unset_strict_debugging if it was previously set)
#
# Bash note: while harmful, if you do something like "verbose_do" before the line, you would see that another
# process is started, and on ps you will see to copies. This is because the function would be running in the background.
# So if you want to wait for a process - just run a command in the background, and not the function in the background
# I find this comment easier to explain than having a designated "run and wait" for something that is not
# really needed for the mechanism, so I keep it here
# verbose sleep $OTA_UPDATE_CHECK_INTERVAL_SEC # uncomment if you want to print and see what is going on in logs...
#
wait_for_next_iteration() {
	if [ -n "$BASH" ] ; then
		sleep $OTA_UPDATE_CHECK_INTERVAL_SEC &
		wait $!
	else
		# forget about the traps, signals etc. they work, but then you need to know whether the signals are passed
		# to the subprocesses, or you'll have hanging processes. Fixable, but we do not wish to address it in this context
		sleep $OTA_UPDATE_CHECK_INTERVAL_SEC
	fi
}

#
# Check indefinitely every $OTA_UPDATE_CHECK_INTERVAL_SEC if there are new updates
#
main_loop() {
	while true ; do
		do_cleanups
		( info_do ota_state_machine_main $@ ) || error "Software updater failed"
		if [ "$oneshot" = "true" ] ; then
			info "Exiting software update check loop due to a oneshot flag"
			break
		fi

		wait_for_next_iteration
	done
}

#
# main function
# source one order:
#	parse_args
# 	decide what the ota_base_dir is
#   decide whether we run on tmpfs or not, and whether to start by downloading the manifest immediately and then checking the rest
#   	it complicates the logic (or just makes more code) but it's fine
#   create the folders if necessary
#		either under the mount dir
#		or the tmp dir
#		or another dir
#   OTA_BLOBS_BASE_DIR - if provided - fine - otherwise, under the base dir
#
#   So three options:
#		Everything under the tmp dir - and start from downloading
#		set ota_base_dir to whatever and work there - creating the first structure if necessary
#		mount the partitions (and fail otherwise), set the ota_base_dir and then create the directories if necessary
#
# To make things EASIER and not rely on any other partitions or storage (e.g. some read only config partition, nvram storage, UEFI variables, etc. ),
# or unpacking the system image after installation (e.g. modifying /etc/... files), we will assume a partition (or folder, in some development scenarios) that is dedicated
# to If ng the state of the update. If it does not exist, and cannot be created (or mounted) - we will not recreate it.
# If startwithmanifestdownloading is true, then we will first download the manifest into a tmpfs, and start working from there,
# and even if nothing exists, will give a shot to live patching. This would allow the live patcher to do their own logic,
# in case a remote system is far from the design of this OTA mechanism.
# Obviously, it is not recommended, but it is a part of the things you may find yourself doing in real life!
#
main() {
	if [ -z "$BASH" ] && which bash &> /dev/null ; then
		echo "Please run $0 explicitly with bash"
		exit 1
	fi
	[ "$strict_debugging" = "true" ] && set_strict_debugging
	parse_args $@
	echo "Software updater is starting..."
	init_script_directories # Set the script execution base directory (BASE_DIR)
	source $BASE_DIR/opt/scripts/commonEnv.sh
	source $BASE_DIR/opt/scripts/utils.sh

	init_ota_directories_local  # TODO: there is another function in otaCommmon.sh - and it is used by the ramdisk so will need to sync everything (!)
	init_ota_debug_files

	trap sigusr1 SIGUSR1
	trap sigusr2 SIGUSR2

	source $BASE_DIR/opt/ota/ota-state-machine.sh

	if [ "$startwithmanifestdownloading" = "true" ] ; then
		do_first_tmpfs_manifest_check_and_processing
	fi

	ota_welcome_banner

	main_loop
}

main $@
