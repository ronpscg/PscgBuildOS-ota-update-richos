#
# This file is expected to be sourced
# It is relevant only for the rich/operational rootfs
#

initialize_update_manifest_url() {
	if [ -z "$URL_OTA_MANIFEST" ] ; then
		if [ -n "$URL_OTA_SERVER_BASE" ] ; then
			: ${URL_OTA_MANIFEST:="$URL_OTA_SERVER_BASE/otafiles/ota-manifest"}
			return
		fi
		
		warn "Your OTA update URLs are not set yet, either because you did not provide URL_OTA_SERVER_BASE, or because the network is not up yet and it could not be set for you"
		check_network_interface_is_up_for_development
		# This also sets the URL_OTA_MANIFEST. In development (QEMU) mode, if there is no network, it will wait
		# rather then just failing and waiting for the next respawn of the service (which is fine)
	fi
}

#
# Set the base URL for a server. This allows to easily quick in trivially networked emulators or docker instances
# The URL is set *only* if it was not set prior to that, so an operational system can set it
# prior to sourcing this file and everything will work as expected by  it.
#
# In the future, in systems that allow this, we will also include some chain of trust. This 
# can be implemented without any change to the mechanism by using https and having trusted
# certificates (if the richofs is debos, it's alreday there, otherwise, it will need to be set up)
#
set_url_ota_server_base_for_development() {
	if ip a | grep -q 10.0.2.15 ; then	
		: ${URL_OTA_SERVER_BASE="http://10.0.2.2:8000"}
	elif [ -f /.dockerenv ] ; then
		: ${URL_OTA_SERVER_BASE="http://172.17.0.1:8000"}
	else
		: ${URL_OTA_SERVER_BASE="http://localhost:8000"}
	fi
}

# 
# This is meant to be called during each wake up of the service, because the network may be up only after the first check, and we
# have a development heuristic which sets URL_OTA_SERVER_BASE to allow someone to mock a local server
# We opt to wait for an active connection, before we consider to autoset the variable
#
check_network_interface_is_up_for_development() {
	if [ -n "$URL_OTA_MANIFEST" ] ; then 
		return
	fi

	while [ $(ip route show default | wc -l) = 0 ] ; do
		local NETWORK_WAIT_SLEEP_TIME=10 # you will be able to see the status in the log / journalctrl at this time, and if you use QEMU or Docker, any network resolving will be very fast
		warn "Network is not up yet."
		sleep $NETWORK_WAIT_SLEEP_TIME
	done

	set_url_ota_server_base_for_development
	: ${URL_OTA_MANIFEST="$URL_OTA_SERVER_BASE/otafiles/ota-manifest"}
}


#
# A simple placeholder for notifying your servers, or whatever you wish of interesting events.
#
notify_server_placeholder() {	
	# busybox ash does not support the debugging arrays. it does support LINENO and FUNCNAME but only for the current function, which is useless for a traceback function
	# 
	hardInfo "HEY SERVER! $@"
}

init_env_rich_rootfs() {
	# Allow the build system to provide a configuration file when packing the product
	# this is mostly useful for setting URL_OTA_SERVER_BASE to a desired IP, regardless
	# of the network status (otherwise a development heuristic is used)
	: ${OPTIONAL_OPERATIONAL_CONFIG_FILE=/opt/ota/ota.config}
	[ -f "$OPTIONAL_OPERATIONAL_CONFIG_FILE" ] && source $OPTIONAL_OPERATIONAL_CONFIG_FILE
	set -a
	# Allow a developer to set a config file and source it
	[ -n "$OTA_DEV_CONFIG_FILE" ] && source $OTA_DEV_CONFIG_FILE

	: ${OTA_UPDATE_CHECK_INTERVAL_SEC=60}

	: ${MANIFESTCMD_AUTO_REBOOT_AFTER_FLASHING=do_auto_reboot_after_flashing}
	set +a
}

# The file is sourced, but we do want it to be as simple as a configuration file, so just execute a "main" function
init_env_rich_rootfs
