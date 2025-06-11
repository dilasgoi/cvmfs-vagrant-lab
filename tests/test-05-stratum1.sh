#!/bin/bash
# Test 05: Stratum-1 Replica Server

source $(dirname "$0")/test-common.sh || exit 1

start_test_suite "STRATUM-1 REPLICA SERVER"

# Test 1: Apache works
run_test "Apache HTTP server responds"
if curl -s -o /dev/null -w "%{http_code}" http://192.168.58.11/ | grep -q "200"; then
    pass_test
else
    fail_test
fi

# Test 2: Repository replica is accessible
run_test "Repository replica manifest accessible"
if curl -s http://192.168.58.11/cvmfs/software.lab.local/.cvmfspublished | head -1 | grep -q "^C"; then
    pass_test
else
    fail_test
fi

# Test 3: Replica has synced
run_test "Repository replica exists on server"
if vagrant ssh cvmfs-stratum1 -c "cvmfs_server list 2>/dev/null" 2>/dev/null | grep -q "software.lab.local"; then
    pass_test
else
    fail_test
fi

# Test 4: Can access repository content
run_test "Repository content accessible"
if curl -s http://192.168.58.11/cvmfs/software.lab.local/.cvmfswhitelist | grep -q "^N"; then
    pass_test
else
    fail_test
fi

end_test_suite
