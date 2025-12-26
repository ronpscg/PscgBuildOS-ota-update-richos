#
# Some debug traps - to use in bash only. Read comments about why you should not use such things...
#

#
# It is NOT recommended to work in bash with set -e et. al unless you really know what you are doing, or just trying your luck
# The reason is that some commands trigger some errors on some circumstances, and some not (e.g. subshells within if commands, etc.)
# You can go ahead and modify "eo" to "euo" to fail on undefined variables as well
#
bash_backtrace_trap() {	
	local maxdepth=${#FUNCNAME[@]}
	local msg=""
	
	for ((i=1; i<$maxdepth;++i)) ; do		
		msg="$msg\t$(basename ${BASH_SOURCE[$(($i-1))]}) +${BASH_LINENO[$(($i-1))]}  ${FUNCNAME[$i]}\n"
	done
	
	if type fatalError &>/dev/null ; then
		fatalError "\n$msg"
	else
		echo "$msg"
	fi
	exit 1
}