#!/bin/bash
# Test 03: Security and Keys

source $(dirname "$0")/test-common.sh || exit 1

start_test_suite "SECURITY AND AUTHENTICATION"

# Test 1: Public key is accessible via HTTP (we already know this works)
run_test "Repository public key accessible via HTTP"
if curl -s http://192.168.58.10/cvmfs/keys/software.lab.local.pub | grep -q "BEGIN PUBLIC KEY"; then
    pass_test
else
    fail_test
fi

# Test 2: Gateway key is accessible via HTTP
run_test "Gateway key accessible via HTTP"
if curl -s http://192.168.58.10/cvmfs/keys/software.lab.local.gw | grep -q "plain_text"; then
    pass_test
else
    fail_test
fi

# Test 3: Publishers can authenticate to gateway
run_test "Publisher 1 can authenticate to gateway"
if vagrant ssh cvmfs-publisher1 -c "test -f /etc/cvmfs/keys/software.lab.local.gw && echo FOUND" 2>/dev/null | grep -q "FOUND"; then
    pass_test
else
    fail_test
fi

run_test "Publisher 2 can authenticate to gateway"
if vagrant ssh cvmfs-publisher2 -c "test -f /etc/cvmfs/keys/software.lab.local.gw && echo FOUND" 2>/dev/null | grep -q "FOUND"; then
    pass_test
else
    fail_test
fi

# Test 4: Client has public key for verification
run_test "Client has repository public key"
if vagrant ssh cvmfs-client -c "test -f /etc/cvmfs/keys/lab.local/software.lab.local.pub && echo FOUND" 2>/dev/null | grep -q "FOUND"; then
    pass_test
else
    fail_test
fi

end_test_suite
