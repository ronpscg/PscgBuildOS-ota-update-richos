#!/bin/sh
: ${BASE_DIR=$(readlink -f $(dirname $(readlink -f $0))/../../..)}

source $BASE_DIR/opt/scripts/commonEnv.sh || { echo "Can't source common environment definitio files" ; exit 1 ; }
do_or_die source $BASE_DIR/opt/ota/otaCommon.sh
do_or_die source $BASE_DIR/opt/ota/ota-richos-defs.sh

state=${1-idle}
echo "resetting state to $state"
set_state $state
echo 0 > $OTA_REFLASH_COUNTER_FILE
