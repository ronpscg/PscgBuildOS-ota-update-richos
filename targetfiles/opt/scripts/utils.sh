# 
# Basic utils 
# Compatible with ash (busybox shell). If something is Bash specific we will list it explicitly by testing $BASH
# 
#


echo_vars() {
	for i in $@ ; do echo $i: $(eval echo \$$i); done 
}

#
# Print out the 'value' of a 'key'='value' tupple in a file. If the key does not exists, print nothing
# In bash it would be wiser, e.g., to create an array, read once the file at some points and keep it, but in ash you need to 
# do other things (or use sed) so KISS
# $1 file
# $2 key to look for
#
get_value_by_key_file() {
	local file=$1
	local key=$2
	while read line ; do
		# Unless in quotes, ash will try and evaluate some of the lines. In bash there is no need for quotes
		[[ "$line" =~ "^#.*" ]] && continue
		if [ "$(echo $line | cut -d= -f1)" = "$key" ] ; then
			echo $line | cut -d= -f2
			return
		fi
	done < $file
}

#
# Albeit tedious, source bash specific stuff from a different file.
# This allows for more easily defining no-op methods, or simpler methods, and then override them with
# bash specific code only if the shell is indeed bash. Having bash code in none-bash shells is an almost
# certain call for parsing failures, or other unintended behaviors
#
if [ -n "$BASH" ] ; then
	if [ -e "$BASE_DIR/opt/scripts/bash-utils.sh" ] ; then	
		source $BASE_DIR/opt/scripts/bash-utils.sh	
	fi
fi

