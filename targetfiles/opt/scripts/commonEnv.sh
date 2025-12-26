#
# do not run this file. only source it. if you want to set your own debug file name - set the variables prior to sourcing this file
#
set -a

: ${DEBUGFILE=/dev/null}
: ${TEECMD=" tee -a $DEBUGFILE"}
DATECMD='date "+%y-%m-%d %H:%M:%S"'


# TODO revise comments
# copied from the ramdisk, minimal adjustments, todo maybe merge as I like this style better (except we don't need seconds as we have syslog)
# The style for the "hard functions" is then much more verbose
# Utility functions
error() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[31m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
info() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[32m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
warn() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[33m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
debug() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[34m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
verbose() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[35m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
fatalError() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[41m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
	exit 1
}
hardError() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[41m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
hardInfo() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[42m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
hardWarn() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[43m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
hardDebug() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[44m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
hardVerbose() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[45m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}

info_do() { info $@ ; $@ ; }
verbose_do() { verbose $@ ; $@ ; }
hard_info_do() { hardInfo $@ ; $@ ; }
hard_verbose_do() { hardVerbose $@ ; $@ ; }

# Note the syntax. In busybox sh, source <file> || <cmd> does not work, so we need to check the return value in another statement
info_do_or_die() { info $@ ;  $@ ; [ $? = 0 ] || fatalError $@ ; }
debug_do_or_die() { debug $@ ; $@ ; [ $? = 0 ] || fatalError $@ ; }
verbose_do_or_die() { verbose $@ ; $@ ; [ $? = 0 ] || fatalError $@ ; }
do_or_die() { $@ ; [ $? = 0 ] || fatalError $@ ; } 
dod() { do_or_die $@ ; }
debug_do() { debug $@ ; $@  ; }

call_if_exists() {
	type $1 &>/dev/null
	if [ $? = 0 ] ; then 
		$@
	fi
	# return non zero if the command does not exist
}

#
#
# The error return functions are very tricky, as there are no nested returns (as opposed to e.g. break <n>, which does not go out of the function scope)
# So two versions are presented: one that returns the error (and the error needs to be checked) and another that exits, meaning that the caller
# must be in subshell
#

#
# Important: put message in quotes, and either call with one parameter, or ensure the second parameter is an integer - we will not error check this for now!
#
errorReturn() {
	error $1
	if [ -n "$2" ] ; then
		return $2
	else
		return 1
	fi
}

#
# Important: put message in quotes, and either call with one parameter, or ensure the second parameter is an integer - we will not error check this for now!
#
warnReturn() {
	warn $1
	if [ -n "$2" ] ; then
		return $2
	else
		return 1
	fi
}

#
# Important: put message in quotes, and either call with one parameter, or ensure the second parameter is an integer - we will not error check this for now!
#
hardErrorReturn() {
	hardError $1
	if [ -n "$2" ] ; then
		return $2
	else
		return 1
	fi
}
#
# These should be started from a subshell. If called from within a function, make sure you define the function body within (...) and not with {...}
#
errorExitScope() {
	error $1
	if [ -n "$2" ] ; then
		exit $2
	else
		exit 1
	fi
}
warnExitScope() {
	warn $1
	if [ -n "$2" ] ; then
		exit $2
	else
		exit 1
	fi
}
hardErrorExitScope() {
	hardError $1
	if [ -n "$2" ] ; then
		exit $2
	else
		exit 1
	fi
}

set +a
