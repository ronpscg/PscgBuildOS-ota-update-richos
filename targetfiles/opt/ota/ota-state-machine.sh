#
# This method essentially runs exec $0, taking into consideration systems that have bash, but /bin/sh does not point to them (e.g. all Debian/Ubuntu's by default)
# This solves some dash disagreements with bash and busybox that supports source (not POSIX compliant, but very common and we like it better)
#
restart_process_using_bash_if_exists() {
	if [ -n "$BASH" ] ; then
		exec $BASH $0
	else
		exec $0
	fi
}

#
# Reads variables from a file (specified by the environment variable $manifest_path), and does some validity checks.
# Note the reading from file - it is of course better to read it once and cache it, however as there are no arrays in ash, that would make an ugly code.
# No harm done if you decide to save the temporary files in a tmpfs - but this kind of constructs and designs are what we discuss as parts of the trade offs, when we
# go over the code and potential design criteria
#
# If $blob_download_path or $blob_extract_path are not empty we will assume that the manifest author knew what they were doing,
#	and in particular, DID NOT mean to put them under a mountpoint. In this case, There will be an attempt to create the directories
#	but without crazy validation, and ONLY in the case where the manifest is read before anything else [to simplify the logic]. That would
#	be checked for explicitly outside of this function, and this comment is presented here only because this use case complicates things
#	and for no good reason (usually)
#
# The read_update_manifest_contents function is used in several places, to gather information about the update:
# 	- If manifest file does not exist - there is no update
# 	-If manifest file exists - check versions and "update instructions" / "update types"
#
# Note the comments about the manifest digest - in an OTA solution you MUST have a root of trust if you want to update securely.
# "Enrolling" that is out of the scope of this version, which aims to be both minimal "busyboxfs" like and "debos" like compatible
#
read_update_manifest_contents() {
	local manifest_file_path=$manifest_file
	blob_url=$(get_value_by_key_file $manifest_file_path blob_url)
	blob_digest=$(get_value_by_key_file $manifest_file_path blob_digest)
	blob_size=$(get_value_by_key_file $manifest_file_path blob_size)
	digest_type=$(get_value_by_key_file $manifest_file_path digest_type)
	compression_type=$(get_value_by_key_file $manifest_file_path compression_type)
	encrpytion_type=$(get_value_by_key_file $manifest_file_path encryption_type)
	misc_commands=$(get_value_by_key_file $manifest_file_path misc_commands)
	on_done_commands=$(get_value_by_key_file $manifest_file_path on_done_commands)
	blob_download_path=$(get_value_by_key_file $manifest_file_path blob_download_path)
	blob_extract_path=$(get_value_by_key_file $manifest_file_path blob_extract_path)
	update_type=$(get_value_by_key_file $manifest_file_path update_type)


	if [ -z "$blob_url" -o -z "$blob_digest" -o -z "$digest_type" ] ; then
		fatalError "Manifest does not have all the required information: \necho_vars blob_url blob_digest blob_size digest_type compression_type encryption_type misc_commands\
		blob_signature signature_type encryption_type signer_public_key"
	fi

	if echo $blob_url | grep -q \$URL_OTA_SERVER_BASE ; then
		blob_url=$(eval echo $blob_url)
	fi

	case $digest_type in
		md5)
			cmd_calc_digest=md5sum ;;
		sha1) cmd_calc_digest=sha1sum ;;
		sha256) cmd_calc_digest=sha256sum ;;
		sha512) cmd_calc_digest=sha512sum ;;
		*) fatalError "Unexpected digest_type $digest_type" ;;
	esac

	which $cmd_calc_digest &>/dev/null || fatalError "Cannot find $cmd_calc_digest on your machine"

	if [ -n "$blob_download_path" ] ; then
		# assume that if the path did not exist, the manifest maintainer would create in the misc_commands
		ota_blob_downloaded_file=$blob_download_path
	else
		# this is the expected default behavior, and the containing folder had already been setup
		ota_blob_downloaded_file=$OTA_BLOBS_BASE_DIR/blobs/wip/blob.$compression_type
	fi

	if [ -n "$blob_extract_path" ] ; then
		# assume that if the path did not exist, the manifest maintainer would create in the misc_commands
		# also assume that they put the file name that would match the compressing algorithm etc.
		ota_blob_extract_path=$blob_extract_path
	else
		# this is the expected default behavior, and the containing folder had already been setup
		ota_blob_extract_path=$OTA_EXTRACT_BASE_DIR
	fi

	case $compression_type in
		tar|tar.*) cmd_extract_blob="tar -C $ota_blob_extract_path -xvf $ota_blob_downloaded_file " ;; # can make it parallel and can do other things, but will keep it like this
		*) fatalError "Unexpected compression_type $compression_type" ;;
	esac

	export ota_blob_downloaded_file ota_blob_extract_path
	export cmd_calc_digest cmd_extract_blob
}

#
# Placeholder for verifying the manifest file (i.e. that it is authentic and not been compromised, etc.)
#
verify_manifest() {
	# TODO: manifest signature validation here or just getting it with https (and not really working with a file)
	return 0
}

#
# In real systems, working against a real server, you would most likely want to have a secure channel with the update server, where you would provide it with
# some identity information, and in response will get an HTTP code specifying whether there is information for you (and the manifest) and some JSON (instead of a file), to parse
# To be extremely simple, and allow static serving of files, we provide here a manifest. It is just as powerful, if getting it is secure
#
check_update_manifest() (
	: ${URL_OTA_MANIFEST_DIGEST=""}	# NOT IMPLEMENTED AT THIS POINT. THIS IS WHERE YOU WOULD NEED TO HAVE A CHAIN OF TRUST (gpg, trusted certificates, etc.)
					# This is kept as a comment here, because it makes it easier to discuss it. At this point, I deliberately don't add the URL
					# to the definitions.
					# Read the comments of the function. A real system can also get along without it, if the server is set up properly
	if [ -z "$URL_OTA_MANIFEST" ] ; then
		warn "Your OTA update URLs are not set yet, either because you did not provide URL_OTA_SERVER_BASE, or because the network is not up yet and it could not be set for you"
		# I don't think it is needed check_network_interface_is_up_for_development	# This also sets the URL_OTA_MANIFEST. In development (QEMU) mode, if there is no network, it will wait
								# rather then just failing and waiting for the next respawn of the service (which is fine)

	fi	
	info_do_or_die wget $URL_OTA_MANIFEST -q -O $manifest_file

	if ! verify_manifest ; then
		errorExitScope "Could not verify the manifest"
	fi
)

#
# If here, it is assumed that the manifest is trusted, and for the sake of simplicity, and that the algorithms mentioned in the manifest are the same algorithms
# We also assume that the reported size is the size of the download, and if we don't have enough disk space for it, will fail the download.
# To be really rigorous you would most likely want to provide the size installed as well, but hey, we are not going to plan another .deb or .rpm here!
#
# Note that some servers can tell you a file size if they support wget's --spider option. Just for your information.
# For the sake of simplicity, we do not support resuming of updates, and we could, e.g. with wget's --continue option. It is not
# such a hard problem, so there is no interest for us in implementing a more capable "download manager".
#
download_update() {
	local free_space_download	# will just show a slight calculation. extra margins should always be taken into consideration
	local free_space_extract 	# won't support for now. could be taken care of directly via a manifest command. leaving it here for reference in case we want to implement it in here as well

	free_space_download=$(df -B 1 $OTA_BLOBS_BASE_DIR | tail -1 | tr -s " " | cut -d " " -f 4)


	if [ $free_space_download -lt $blob_size ] ; then
		error "Not enough free space. Needs at least $blob_size, but the free space (before extracting!) is $free_space_download"
		return 1
	fi

	info "Downloading the software update file... $blob_url --> $ota_blob_downloaded_file... "
	if wget $blob_url -q -O $ota_blob_downloaded_file ; then
		set_state "downloaded"
		info "Download completed. Your blob is in $ota_blob_downloaded_file"
	else
		set_state downloadFailed
		return 1
	fi
}


#
# Check for software updates, and populate some control variables from the downloaded manifest
# In a proper implementation, either the downloaded manifest would be signed and validated, or the connection would be over TLS/SSL with a trusted certificate etc.
#
# returns:
# 	0 if there is update
#	1 if there is no update/if cannot get update details from server
#
check_for_updates() {
	if check_update_manifest ; then
		# Note we don't check for return code for the next statement. It is intended, as if there is a fatal error,
		# there is no point in continuing the process as it means the provided manifest is broken
		read_update_manifest_contents

		last_installed_digest=$(get_last_valid_active_digest)
		[ -n "$last_installed_digest" ] || warn "There is no previous valid active digest file."

		if [ "$last_installed_digest" = "$blob_digest" ] ; then
			verbose "No need for update. Same $digest_type digest: $blob_digest"
			return 1
		else
			info "Update available! Will update $last_installed_digest --> $blob_digest. This is where you may want to ask a (human) user whether they want to download an update..."
			return 0
		fi
	else
		return $?
	fi
}

#
# Verify the digest matches. In a full solution, a signature should also be verified
# This function expects blob_digest, cmd_calc_digest, and ota_blob_downloaded_file to be set prior to calling it
#
verify_update() {
	info "Verifying downloaded update file..."
	actual_digest=$($cmd_calc_digest $ota_blob_downloaded_file | tr -s ' ' | cut -d ' ' -f 1)
	if [ "$blob_digest" = "$actual_digest" ] ; then
		set_state verified
		info "Actual and expected $digest_type match"
		return 0
	else
		# after several attempts, one may decide to blacklist this digest
		error "Actual and expected $digest_type do not match (actual: $actual_digest ; expected: $blob_digest). Need to redownload"
		notify_server_placeholder "Actual and expected $digest_type do not match (actual: $actual_digest ; expected: $blob_digest). Need to redownload"
		set_state verifyFailed
		return 1
	fi
}

#
# Run $cmd_extract_blob to unpack the blob
#
unpack_update() {
	verbose "Unpacking update file..."
	set_state "unpacking"

	if ! info_do $cmd_extract_blob ; then
		set_state unpackFailed
		fatalError "Failed to extract the partitions"
	fi

	set_state "unpacked"
	info "Done extracting tarball"
}

#
# Do an entire software update sequence flow on the rich OS side. If this works well, the system will reboot (if allowed),
# the flasher OS (ramdisk, or bootloader code) will take care of flashing, and after a successful flashing, image verification
# will take place in the rich OS, aiming to declare the new image as the stable image, declaring the update as successful
#
do_it_all() {
	do_check_for_updates $@
	do_download $@
	do_verify $@
	do_unpack $@
	do_post_unpack $@
	ota_state_machine_main $@
}

#
# Checks whether there are updates. This accesses the network. If there is no network, the entire process will exit.
# The reason for full exits, are because the process is mostly intended to be run within the context of a daemon,
# and on an init framework, dependencies can be handled there
#
do_check_for_updates() {
	check_for_updates $@
	case $? in
		0)
			return 0
			;;
		1)
			exit 0
			;;
		*)
			exit $?
			;;
	esac
}

#
# Reads the manifest and downloads the update
#
do_download() {
	read_update_manifest_contents
	download_update $@ || exit 2
}

#
# Reads the manifest and verifies the blob digest matches. Then, if there are special instructions, can execute them
#
do_verify() {
	read_update_manifest_contents
	verify_update $@ || exit 2
	do_post_verify_pre_unpack $@ || exit 2
}

#
# Give a chance to execute custom misc_commands before unpacking. This may be useful for hacking a first time solution/
# updating a basic OTA code before doing some more serious OTA updates (e.g. in case you have e.g. a Debian/Redhat/Suse/etc. based system)
# This is different from the "first time" tmpfs check, because there we allow for complete arbitrary stuff.
# Here, we follow the state machine.
#
# For example, the misc commands can be some preparation for hotpatching.
#
#
do_post_verify_pre_unpack() {
	if [ -n "$misc_commands" ] ; then
		notify_server_placeholder "$FUNCNAME: Will run $misc_commands"
		# Note for students: don't use eval unless you know what you're doing...
		# Another note for students: eval is used here to enable running compound commands
		eval $misc_commands
		# Note: the misc_commands, if they exist are usually expected to be a "one timer".
		# If they are not, the logic will continue, and it will tell your there is an update etc.
		# So if the misc commands already do something like downloading/verifying/etc. - the prints will be misleading
		# That is OK, because you are not supposed to use them unless you know what you are doing anyway :-)
	fi
}

#
# Reads the manifest and unpacks the downloaded blob
#
do_unpack() {
	read_update_manifest_contents
	do_or_die unpack_update
	notify_server_placeholder "$FUNCNAME done!"
}

#
# Allow doing some extra commands if the ota update package requires so, e.g. in the case of a live patch, or in case
# of updating early boot code or setting early boot states
#
do_post_unpack() {
	local cmdfile=$ota_blob_extract_path/run-commands.sh
	if [ -x $cmdfile ] ; then
		hardInfo "Will run the commands in $cmdfile"
		if [ -n "$BASH" ] ; then
			bash $cmdfile || fatalError "Failed to run to completion the commands in $cmdfile"
		else
			$cmdfile || fatalError "Failed to run to completion the commands in $cmdfile"
		fi
	fi

	case $update_type in
		fullota|"")
			set_state "awaitingReboot"
			if [ "$on_done_commands" = "$MANIFESTCMD_AUTO_REBOOT_AFTER_FLASHING" ] ; then
				info "Rebooting to apply the software update..."
				notify_server_placeholder "Rebooting to apply the software update"
				do_reboot_to_state pendingReflash
			fi
			;;
		livepatch)
			set_state livepatchCompletedSuccessfully
			notify_server_placeholder "Done applying livepatch"
			;;
		*)
			fatalError "invalid update type"
			;;
	esac

}

#
# Called when testing seems to be successful
#
on_boot_candidate_success() {
	local counter=$(get_success_boot_counter)
	counter=$(($counter+1))
	set_success_boot_counter $counter
	if [ "$counter" -ge "$OTA_MAX_SUCCESS_BOOT_COUNTER" ] ; then
		info "System has been booted and verified successfully $counter times and is now declared stable"
		set_state otaCompletedSuccessfully
	else
		info "System has been booted and verified $counter/$OTA_MAX_SUCCESS_BOOT_COUNTER times. Rebooting and trying to test again"
		do_reboot_to_state # keep the same state
	fi
}

#
# Called when testing seems to have failed
#
on_boot_candidate_fail() {
	local counter=$(get_fail_boot_counter)
	counter=$(($counter+1))
	set_fail_boot_counter $counter
	if [ "$counter" -ge "$OTA_MAX_FAIL_BOOT_COUNTER" ] ; then
		error "System has failed to boot (from richos system verification perspective) $counter times and is now declared unstable. You should revert to a better working image if you can"
		set_state reflashFailed
		do_reboot_to_state reflashFailed
	else
		error "System verification failed $counter/$OTA_MAX_FAIL_BOOT_COUNTER times. Rebooting, and trying to test again"
		do_reboot_to_state # keep the same state
	fi
}

#
# If the flashing operation succeeded, run some code in the currently tested system to assure
# that it is functioning well/behaving sanely. While some tests can be done on the flasher, even in a chroot,
# you also want to make sure that the system itself works.
#
# The success/fail boot counters will be modified depending on the outcome of these tests.
# Obviously, the contents of the testing themselves are project dependent
#
do_test_reflashed_images_on_current_boot() {
	info "Testing the reflashed software update from within rich OS."
	notify_server_placeholder "Testing the reflashed software update "
	if call_if_exists run_sanity_checks_on_system ; then
		on_boot_candidate_success
	else
		on_boot_candidate_fail
	fi
	#
	# If the tests fail we will stay in the same state, and retry to validate so the failBootCounter will increase
	# until we will declare the image failure
	#
	# if we succeed, we will stay in this state until the boot counter increases
	state=$(get_state)
	if [ "$state" = "otaCompletedSuccessfully" ] ; then
		info "OTA has completed successfully. Setting state to idle"
		restart_process_using_bash_if_exists
	fi
}

#
# Reboot system as cleanly, and init system independently as possible
# $1: if exists, set the state to it prior to rebooting
#
do_reboot_to_state() {
	local state
	if [ -n "$1" ] ; then
		state=$1
		set_state "$state"
	else
		state=$(get_state)
	fi
	warn "Rebooting to state ($state)" | tee /dev/kmsg
	notify_server_placeholder "$logTag Rebooting to state ($state)"
	wall "$logTag Rebooting to state ($state)"
	sync
	cd /
	umount -a
	reboot
}

#
# This function takes care of relabling the current system partition under test to be the operational system partition
#
relabel_system_partitions_upon_successful_update() {
	las=$(get_last_valid_active_system_partition)
	nas=$(get_next_system_partition)
	if [ -z "$nas" ] ; then
		fatalError "Failed to set the next system partition"
	fi

	info "Relabling your system partitions: $las --> $nas "
	tune2fs -L $OTA_ACTIVE_SYSTEM_PARTITION_LABEL $nas || fatalError "Failed to relabel the partition  $nas to $OTA_ACTIVE_SYSTEM_PARTITION_LABEL"
	tune2fs -L $OTA_STANDBY_SYSTEM_PARTITION_LABEL $las || fatalError "Failed to relabel the partition  $las to $OTA_STANDBY_SYSTEM_PARTITION_LABEL"

	set_last_valid_active_system_partition $nas || fatalError "Failed to update the active system partition to $nas"
}

#
# This is mostly for reference. See comments in the calling function (under OTA_AB_UPDATE_ON_FAT_BOOT which is never set to true at the moment)
#
relabel_boot_partitions_upon_successful_update() {
	lab=$(get_last_valid_active_boot_partition)
	nab=$(get_next_boot_partition)

	info "Relabling your boot partitions if your distro supports that: $lab --> $nab "
	if [ -z "$nab" ] ; then
		fatalError "Failed to set the next boot partition"
		if [ -z "$lab" ] ; then
			fatalError "last valid active boot partition is unset. it is very likely you are trying to upgrade from a system not prepared by this project"
		fi
		nab=$lab
	fi

	if ! which fatlabel &> /dev/null ; then
		warn "fatlabel does not exist --> will not replace your boot partition"
		return 0 # deliberate - we don't really want to support this anyway, it's just a demonstration. for "live demonstration" of failure just change warn to fatalError
	fi

	fatlabel $nab $OTA_ACTIVE_BOOT_PARTITION_LABEL || fatalError "Failed to relabel the partition $nab to $OTA_ACTIVE_BOOT_PARTITION_LABEL"
	fatlabel $lab $STANDBY_BOOT_PARTITION_LABEL || fatalError "Failed to relabel the partition  $lab to $STANDBY_BOOT_PARTITION_LABEL"

	set_last_valid_active_boot_partition $nab || fatalError "Failed to update the active boot partition to $nab"
}

#
# Common activities for fullota and livepatch at the end of the update. Includes setting the state back to idle
#
common_on_update_completed_activities() {
	local release_file=/etc/thepscgos-release
	local version=$(grep VERSION $release_file | tr -d \")

	info "You can now use $update_type image  as the new image. Finalizing state..."
	verbose_do_or_die set_last_valid_active_digest $blob_digest
	verbose_do_or_die copy_to_last_valid_manifest_file $manifest_file
	set_state idle  # Set state as soon as possible, before further cleanups

	notify_server_placeholder "Running the $update_type image ($version / $(get_last_valid_active_digest))"
	echo 0 > $OTA_REFLASH_COUNTER_FILE || fatalError "Failed to reset the reflash counter file"
	rm -r $OTA_STATE_WIP_DIR/* || fatalError "Failed to remove the wip state directory"
	sync

	info "The updated image is the new stable $update_type image ($blob_digest)"

	# Done!!! If you wish to check for a new software version immediately after checking an update you may uncomment the next line
	# restart_process_using_bash_if_exists
}

#
# Update state files upon successful livepatch completion
# In addition, since a livepatch may want to update the ota code update itself, or perhaps even reboot,
# it is more valuable to do commands after the update
#
on_livepatch_completed() {
	common_on_update_completed_activities
	if [ -n "$on_done_commands" ] ; then
		notify_server_placeholder "$FUNCNAME: Will run $on_done_commands"
		eval $on_done_commands # same usage notes as per the misc_commands
	fi
}

#
# Update state files upon successful software update completion
# In a more complex design, one could prepare a partition manifest as part of the flashing mechanism, which is something
#
# Note about boot A/B: this must be taken care of by the bootloader. We put the kernel and ramdisk where we put
# Just to show the separation. In general, if the bootloader can work a Linux filesystem, then the kernel and ramdisk can
# easily be on that partition, and A/B update becomes updating of a single partition, for example.
# Having said so, we provide a reference that is not used in practice under the OTA_AB_UPDATE_ON_FAT_BOOT switch
#
# Since in our reference design the ramdisk code is actually the flasher code, and we do "bootloader stuff" on it
# (to more easily separate between, e.g. U-Boot, QEMU bios, GRUB, EFI, etc.), we will do bootloader A/B scheme
# (i.e. relabling, in our simple design), only if fatlabel is available on the target device.
# Otherwise, we won't do it, in order to not add more unnecessary stuff to a busybox based OS (we added e2fstools to allow fsck etc.)
#
# Perhaps this will change in the future
#
# Note about labeling: using LABEL= is simpler. It is not better. We keep it this way so it would easier to explain and maintain.
# However, you must be careful about the order:
#	- if we first label the second partition as system - then the higher number will be the default if there is a
#	  a crash between the two labeling (which may result in both partitions having the same label for some time)
# 	- Otherwise, you have to do state keeping when the system comes up.
#	  Such state keeping can (and actually should, along with other things) be implemented in the bootloader before loading the Linux kernel
#
on_ota_completed() {
	verbose "Software update is almost done. Doing final activities before declaring the new stable image current_state=$(get_state)"
	# While not doing it is not the end of the universe, we do want to store the digest to prevent subsequent updates,
	# so failing to retrieve it would result in a failed state
	if [ -z "$blob_digest" ] ; then
		if ! read_update_manifest_contents ; then
				fatalError "Cannot read the manifest file. Your OTA state is corrupted"
		fi
	fi

	relabel_system_partitions_upon_successful_update
	if [ "$OTA_AB_UPDATE_ON_FAT_BOOT" = "true" ] ; then
		# Not supported at the moment, for reasons explained mostly in the flasher code, but adding it in the richos is trivial.
		relabel_boot_partitions_upon_successful_update
	fi

	common_on_update_completed_activities
}

#
# Called after failing to flash or verify the correctness of the running systems more than a threshold of times
#
on_reflash_failed_max_counter_times() {
	# Deciding what to do with a failing image, is a per project decision design
	# so we are not implementing something here. In class, we discuss several options
	error "Reflashing failed $MAX_REFLASH_COUNTER times"
	notify_server_placeholder "Reflashing failed $MAX_REFLASH_COUNTER times"
	exit 1
}

#
# Called when a golde-image recovery attempt fails to succeed on the rich OS side
#
on_recovery_failed() {
	warn "Recovery/golden image failed. Restarting in idle mode, hoping that an OTA update will fix it"
	notify_server_placeholder "Recovery to golden image failed"
	set_state idle
	restart_process_using_bash_if_exists
}


#
# This is the main state machine function. It handles all elements of the update within the rich OS
#
ota_state_machine_main() {
	do_or_die source $BASE_DIR/opt/ota/otaCommon.sh
	do_or_die source $BASE_DIR/opt/ota/ota-test-reflashed-images-on-system.sh
	export blob_url blob_digest blob_size digest_type compression_type encryption_type misc_commands on_done_commands blob_signature signature_type encryption_type signer_public_key

	if [ ! -f $OTA_STATE_FILE ] ; then
		warn "Creating $OTA_STATE_FILE for the first time, assuming a first installation, and setting the state to idle"
		do_or_die set_state idle
	fi

	# Main state machine
	case "$(get_state)" in
	""|idle)
		hard_verbose_do do_it_all
		;;
	downloading)
		hard_verbose_do do_download
		hard_verbose_do do_verify
		hard_verbose_do do_unpack
		hard_verbose_do do_post_unpack
		ota_state_machine_main $@
		;;
	downloaded|verifying)
		hard_verbose_do do_verify
		hard_verbose_do do_unpack
		hard_verbose_do do_post_unpack
		ota_state_machine_main $@
		;;
	verified|unpacking)
		hard_verbose_do do_unpack
		;;
	unpacked)
		# This can be an interim state of done unpacking the blob, but post unpack instructions not executed yet.
		# Therefore, we give the post unpacking flow an opportunity to run.
		# If this happens, and there are complex unpacked post-unpack-commands (e.g., not just reboot), it might be better to cleanup
		# the unpacking and redo the process. Since this would not be a common scenario, and it would take quite some time to test, it's not being done for now.
		do_post_unpack
		;;
	downloadFailed)
		warn "Previous software update blob failed. Redoing the entire sequence"
		hard_verbose_do do_it_all
		;;
	verifyFailed)
		warn "Previous software update blob verification attempt failed. Redoing the entire sequence"
		hard_verbose_do do_it_all
		;;
	unpackFailed)
		warn "Previous software update blob unpacking failed.  Redoing the entire sequence"
		hard_verbose_do do_it_all
		;;
	awaitingReboot|pendingReflash)
		# We can be in this state only if the user did not opt for an automatic reboot,
		# This can be a good place to probe some flag that could be, e.g., set by an end-user agreeing
		# to reboot when an update is done or something - but in this case, it really means that whatever interacts
		# with it, can just call reboot directly and it would be safe.
		warn "Pending reboot in $(get_state)"
		notify_server_placeholder "Pending reboot in $(get_state)"
		;;
	pendingReflash|reflashing)
		# These are done at the flasher
		error "Impossible state at $FUNCNAME/$LINENO: $(get_state)" # it is expected in the ramdisk or bootloader code implementing the flashing part
		;;
	pendingReflashVerification)
		# This stands for the first reflash verification which is done at the flasher
		error "Impossible state at $FUNCNAME/$LINENO: $(get_state)" # it is expected in the ramdisk or bootloader code implementing the flashing part
		;;
	livepatchCompletedSuccessfully)
		info_do on_livepatch_completed
		;;
	otaCompletedSuccessfully)
		info_do on_ota_completed
		;;
	reflashFailed)
		error "Reflashing failed!"
		notify_server_placeholder "Reflashing failed!"
		;;
	reflashOK)
		info "Reflashing succeeded and verified. Will test the running image and complete the update process"
		set_state testingReflashedImages
		ota_state_machine_main $@
		;;
	testingReflashedImages)
		do_test_reflashed_images_on_current_boot
		;;
	reflashFailedMaxCounter)
		on_reflash_failed_max_counter_times
		;;
	recoveryFailed)
		on_recovery_failed
		;;
	*)
		warn "Illegal case $(get_state)"
		;;
	esac
}


