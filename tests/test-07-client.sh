#!/bin/bash
# Test 07: CVMFS Client

source $(dirname "$0")/test-common.sh || exit 1

start_test_suite "CVMFS CLIENT"

# Test 1: Client can probe repository
run_test "Client can probe repository"
if vagrant ssh cvmfs-client -c "cvmfs_config probe software.lab.local 2>&1" 2>/dev/null | grep -q "OK"; then
    pass_test
else
    fail_test
fi

# Test 2: Repository is mounted
run_test "Repository is mounted"
if vagrant ssh cvmfs-client -c "ls /cvmfs/software.lab.local 2>/dev/null" 2>/dev/null | grep -q "README.txt"; then
    pass_test
else
    fail_test
fi

# Test 3: Can read repository content
run_test "Can read repository files"
if vagrant ssh cvmfs-client -c "cat /cvmfs/software.lab.local/README.txt 2>/dev/null" 2>/dev/null | grep -q "Welcome"; then
    pass_test
else
    fail_test
fi

# Test 4: Test script is executable
run_test "Can execute test script"
if vagrant ssh cvmfs-client -c "/cvmfs/software.lab.local/test/hello.sh 2>/dev/null" 2>/dev/null | grep -q "Hello from CVMFS"; then
    pass_test
else
    fail_test
fi

end_test_suite
