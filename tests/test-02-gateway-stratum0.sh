#!/bin/bash
# Test 02: Gateway + Stratum0

source $(dirname "$0")/test-common.sh || exit 1

start_test_suite "GATEWAY + STRATUM0"

# Test 1: Apache works
run_test "Apache HTTP server responds"
if curl -s -o /dev/null -w "%{http_code}" http://192.168.58.10/ | grep -q "200"; then
    pass_test
else
    fail_test
fi

# Test 2: Gateway API works
run_test "Gateway API responds"
if curl -s http://192.168.58.10:4929/api/v1/repos | grep -q "software.lab.local"; then
    pass_test
else
    fail_test
fi

# Test 3: Repository is accessible
run_test "Repository manifest accessible"
if curl -s http://192.168.58.10/cvmfs/software.lab.local/.cvmfspublished | head -1 | grep -q "^C"; then
    pass_test
else
    fail_test
fi

# Test 4: Public key is accessible
run_test "Repository public key accessible"
if curl -s http://192.168.58.10/cvmfs/keys/software.lab.local.pub | grep -q "BEGIN PUBLIC KEY"; then
    pass_test
else
    fail_test
fi

# Test 5: Repository exists on server
run_test "Repository exists on server"
if vagrant ssh cvmfs-gateway-stratum0 -c "cvmfs_server list 2>/dev/null" 2>/dev/null | grep -q "software.lab.local"; then
    pass_test
else
    fail_test
fi

end_test_suite
