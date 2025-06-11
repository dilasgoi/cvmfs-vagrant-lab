#!/bin/bash
# Test 06: Squid Proxy

source $(dirname "$0")/test-common.sh || exit 1

start_test_suite "SQUID PROXY"

# Test 1: Proxy port is open - simpler test
run_test "Proxy responds on port 3128"
if curl -s -x http://192.168.58.14:3128 -o /dev/null -w "%{http_code}" http://example.com 2>/dev/null | grep -q "200"; then
    pass_test
else
    fail_test
fi

# Test 2: Proxy can fetch external content
run_test "Proxy can fetch external URLs"
if curl -s -x http://192.168.58.14:3128 -o /dev/null -w "%{http_code}" http://example.com | grep -q "200"; then
    pass_test
else
    fail_test
fi

# Test 3: Proxy can fetch from Stratum-1
run_test "Proxy can access Stratum-1"
if curl -s -x http://192.168.58.14:3128 http://192.168.58.11/cvmfs/software.lab.local/.cvmfspublished | head -1 | grep -q "^C"; then
    pass_test
else
    fail_test
fi

end_test_suite
