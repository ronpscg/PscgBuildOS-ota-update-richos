### The sanity_check_test* and build_test_list would be implemented in every project as per the relevant requirements
sanity_check_test1() {
	echo "Hello Wisconsin!"
}

sanity_check_test2() {
	cat /etc/thepscgos-release
}

sanity_check_test3() {
	uname -a
}

#
# Build a list of tests
# You would want to modify this function, and the other functions defined above
#
build_test_list() {
        local tests=""
        # an example of test list population
        for test in $(seq 1 10) ; do
	        tests="$tests sanity_check_test$test"
        done
        echo $tests
}


### The code below can be ported to your systems

#
# Build a list of tests, and run every test in it.
# returns 0 if all tests succeed, and 1 otherwise
#
run_sanity_checks_on_system() {
        local tests=$(build_test_list)
        # now run the tests (this is something you would do regardless of the test building)
        for test in $tests ;  do
		if ! call_if_exists $test ; then
                        error "Failed to run $test"
			return 1			
		fi
	done
        info "All tests passed successfully!"	
}
