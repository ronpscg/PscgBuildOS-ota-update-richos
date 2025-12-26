#!/bin/bash
#
# This script gets a blob, reference manifest file, and a workdir and:
# - Creates from scratch the workdir
# - links the blob to a file in it
# - copies the reference manifest into it
# - updates the copy of the manifest to serve the ota client, taking into consideration some command files"
# 
# Then, it runs a static http server under the default port of 8000
#
# By default, unless blob and manifest are provided, we will build the ota tarball and serve it as a livepatch
# This is obviously not how you would want to test your own design, so be sure to provide these environment variables
#

usage() {
	echo "usage: $0 <livepatch|fullota> [updateota]"
	echo "Must also provide valid manifest, blob, and workdir environment variables"
	exit 1
}

do_or_die() { $@ || { echo "$@ failed" ; exit 1 ; } ; }
info_do_or_die() { echo $@ ; $@ || { echo "$@ failed" ; exit 1 ; } ; }

check_usage() {
	echo $1
	case $1 in
		fullota|livepatch)
			;;
		*)
			usage
			;;
	esac

	[ -f "$manifest" ] || usage
	[ -f "$blob" ] || usage
	[ -n "$workdir" ] || usage
	[ -e "$workdir" ] && { rm -r $workdir || usage ; } # Careful to not give the wrong workdir...
	if [ "$manifest" = "$LOCAL_DIR/ota-manifest.example" -a ! "$2" = "updateota" ] ; then
		echo "You did not provide the manifest, and probably also did not provide the other variables. Do not rely on automatic code unless you are trying the OTA code!"
		usage
	fi
	mkdir -p $workdir || usage
}

rebuild_and_serve_ota_code() {
	ota_tarball_builder=$(readlink -f $LOCAL_DIR/../../make-ota-userspace-tarball.sh)
	local wd=/tmp/ota-src
	local ta=$blob
	workdir=$wd targetarchive=$ta $ota_tarball_builder
}

run_server() {
	python3 -m http.server -d $workdir/..
}


update_manifest_fields() {
	do_or_die sed -i "s/blob_url=.*/blob_url=\$URL_OTA_SERVER_BASE\/otafiles\/$origname/" $manifest_file
	do_or_die sed -i "s/original_blob_filename=.*/original_blob_filename=$origname/" $manifest_file
	do_or_die sed -i "s/blob_digest=.*/blob_digest=$digest/" $manifest_file
	do_or_die sed -i "s/digest_type=.*/digest_type=sha256/" $manifest_file
	do_or_die sed -i "s/update_type=.*/update_type=$update_type/" $manifest_file
	do_or_die sed -i "s/blob_size=.*/blob_size=$size/" $manifest_file
	do_or_die sed -i "s/blob_extract_path=.*/blob_extract_path=$sed_style_extract_path/" $manifest_file
	sed -i "s/blob_creation_date=.*/blob_creation_date=$(date)-filled-by-tester/" $manifest_file || exit 1 # expression is with spaces don't bother fighting with macros

	# These can get dangerous, so don't change anything unless being told to very explicitly
	if [ -n "$on_done_commands" ] ; then
		sed -i "s/on_done_commands=.*/on_done_commands=${on_done_commands}/" $manifest_file || exit 1
	fi
	if [ -n "$misc_commands" ] ; then
		sed -i "s/misc_commands=.*/misc_commands=${misc_commands}/" $manifest_file || exit 1
	fi
}

main() {
	LOCAL_DIR=$(readlink -f $(dirname ${BASH_SOURCE[0]}))
	: ${blob=$(readlink -f $LOCAL_DIR/../../ota-targetfiles-tarball.tar.xz)}
	: ${manifest=$LOCAL_DIR/ota-manifest.example} # The disadvantage here is that we will need to synchronize code
	: ${workdir=/tmp/test-ota-server/otafiles}
	: ${update_type=""}
	
	# in a live patch, you want to either populate a run-commands.sh file, or if you want to extract it 
	# directly on top of a folder - specify it!. Empty means default path
	: ${extract_path=""} 

	if [ "$1" = "livepatch" -a "$2" = "updateota" ] ; then
		rebuild_and_serve_ota_code
		# Note: if you want to patch the mechanism and *persist* in the presence of overlays, you need to add command instructions, either in misc_commands or run-commands.sh
		# You want to escape slashes, and make sed happy (!)
		sed_style_extract_path='\/'
		misc_commands="echo -e \x1b[45mHello from livepatch tester updating your ota\x1b[0m"
		on_done_commands='echo -e "\x1b[45mUpdated your OTA - reloading \$0 ;\x1b[0m" ; restart_process_using_bash_if_exists'
	fi


	check_usage $@

	origname=$(basename $blob)
	manifest_file=$workdir/ota-manifest
	update_type=$1
		

	echo "Serving (a 'copy' of): $manifest, $blob, under $workdir"
	echo "[+] populating directory"
	do_or_die cp $manifest  $manifest_file
	do_or_die ln -s $blob $workdir
	echo "[+] sha256 digest"
	digest=$(sha256sum $blob | tr -s " " | cut -f 1 -d" ")
	echo "[+] size"
	size=$(du -Db $blob | cut -f 1)
	do_or_die update_manifest_fields

	cat $manifest_file
	echo "OTA server: starting to serve $update_type/$origname/$digest"
	notify-send "$update_type/$digest/$origname" # easier to see the digest first and the rest are cut as the digest is long


	run_server
}

main $@
