# OTA for the RichOS part of PscgBuildOS

**Oneliner**: The source code tells everything, and is meant to be used as a part of an OTA update mechanism workshop or conference talks.

Some things that are not obvious or worth noting if you want to test it by yourself are presented below.

## Testing theory and practice
The easiest way to test (except for, of course, setting an operational server with a certificate and https, etc.) would be to:
- Use http in your localhost and serve files statically. For example:
    - Create a directory called `test-host/ota-files`, and either copy output links to your OTA tarballs (may it be a full image, or a partial update), and put the manifest file, `ota-manifest`, in it.
    - Run a simple server. This one will listen on your localhost on port 8000:
        ```
        python3 -m http.server -d test-host/
        ```
    - If not running qemu with network mode, ensure you update the server address.
    - Otherwise see in the next section

In this scenario, an example of *test-host* tree would look something like this:
```bash
$ tree test-host/
test-host/
└── otafiles
    ├── build-image-version-riscv.tar.xz
    └── ota-manifest
```

An example concise, quick and working server script is provided in `hostfiles/test/ota-server.sh` . It requires python3, and does, among other things what is describe above.
To run it:
```bash
manifest=<path-to-reference-manifest> blob=<path-to-served-blob> ./ota-server.sh <fullota|livepatch>
```

## Getting the OTA tarball and the respective manifest file
- *fullota*: Consult the PscgBuildOS code and video tutorials on my Youtube channel for more information.
- *livepatch*: Read some of the examples below. I think there are also videos for this there as well

## Testing Examples

###  Testing example: Updating the OTA code via a livepatch
To do this example, you don't need to do anything else other than run the following command:
```bash
./hostfiles/test/ota-server.sh  livepatch updateota
```

This takes care of everything.

### Testing under user mode network in QEMU 
- Get dhcp address before running the `/opt/ota/ota-update.sh` script
- Then, when you run the script, it will identify the QEMU NAT networking and access your localhost via 10.0.0.2. 


## Preparing partial livepatches yourselves - theory and practice
A nice thing you can do is to update the ota code via a livepatch mechanism. For that, you can just serve the tarball in the manifest and set `update_type=livepatch` in it.

If you want to add some commands to a livepatch you create, to be automatically executed (regardless of the instructions in the manifest, which you can also do, but may be harder to write or debug if you are not experienced with it) it you can have a `run-commands.sh` file in your livepatch. It must return 0 upon success, or the patching will consider it as failure.

### A "run-commands.sh example" 
The following is an example that creates a tarball for such a live patch, and populates it with a run-commands.sh that is "hooked into the system". 
It doesn't do much, but it explains enough to be useful, and you can use it to do some more useful things:

```bash
mkdir wip-example
echo '
#!/bin/sh
echo blob_extract_path is $blob_extract_path
printenv > /tmp/run-commands-printenv

# If the shell is bash - you will be able to use the exported functions as well

if [ -f $BASE_DIR/opt/scripts/commonEnv.sh ] ; then	
	. $BASE_DIR/opt/scripts/commonEnv.sh # I prefer to write "source" but if the shell is dash - it does not exist in it
fi

hardWarn "run-commands says: OK, looks OK. But if you are in dash, it will not look nice and colorful. That is just fine and do not worry about it"

exit 0
' >  wip-example/run-commands.sh
chmod +x wip-example/run-commands.sh

tar -C wip-example -cf livepatch-example.tar . # you can use other compressing methods if you want
```


