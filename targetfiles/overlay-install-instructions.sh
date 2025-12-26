#!/bin/sh


echo "Hello from $0" | tee /dev/console

dstdir=$instruction_file_folder_location
if [[ "$dstdir" =~ fsmaterials/upper ]] ; then 
	# this assumes our quite consistent format
	mergeddir=$dstdir/../merged
	echo "Demonstrating an overlay chroot trick (could just create a symlink instead...)" | tee /dev/console
	if [ -d $mergeddir/etc/systemd/system/multi-user.target.wants/ ] ; then	
		chroot $dstdir/../merged sh -c "systemctl enable ota" || { echo "Failed to enable the OTA service" | tee /dev/console ; exit 1; }
	else
		echo "Not a systemd based distro. OTA is already enabled, and if it's not, you may want to edit this line..." | tee /dev/console
	fi
fi
