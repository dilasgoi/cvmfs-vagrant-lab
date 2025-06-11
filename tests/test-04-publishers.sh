#!/bin/bash
# Test 04: Publisher Nodes

source $(dirname "$0")/test-common.sh || exit 1

start_test_suite "PUBLISHER NODES"

# Test Publisher 1
echo -e "\n  Testing Publisher 1:"

run_test "  Can reach gateway API"
if vagrant ssh cvmfs-publisher1 -c "curl -s http://192.168.58.10:4929/api/v1/repos 2>/dev/null" 2>/dev/null | grep -q "software.lab.local"; then
    pass_test
else
    fail_test
fi

run_test "  Repository configured"
if vagrant ssh cvmfs-publisher1 -c "cvmfs_server list 2>/dev/null" 2>/dev/null | grep -q "software.lab.local"; then
    pass_test
else
    fail_test
fi

run_test "  Can publish content"
TIMESTAMP=$(date +%s)
# Don't start a new transaction if one is already open - just publish
if vagrant ssh cvmfs-publisher1 -c "
    # Check if transaction is already open
    if cvmfs_server list | grep -q 'in transaction'; then
        echo 'Transaction already open, just adding content...'
    else
        sudo cvmfs_server transaction software.lab.local/test/pub1 >/dev/null 2>&1
    fi

    # Create content
    sudo mkdir -p /cvmfs/software.lab.local/test/pub1
    echo 'Test from publisher1 at ${TIMESTAMP}' | sudo tee /cvmfs/software.lab.local/test/pub1/test_${TIMESTAMP}.txt >/dev/null

    # Publish
    sudo cvmfs_server publish software.lab.local >/dev/null 2>&1 && echo SUCCESS
" 2>/dev/null | grep -q "SUCCESS"; then
    pass_test
else
    fail_test
fi

# Test Publisher 2
echo -e "\n  Testing Publisher 2:"

run_test "  Can reach gateway API"
if vagrant ssh cvmfs-publisher2 -c "curl -s http://192.168.58.10:4929/api/v1/repos 2>/dev/null" 2>/dev/null | grep -q "software.lab.local"; then
    pass_test
else
    fail_test
fi

run_test "  Repository configured"
if vagrant ssh cvmfs-publisher2 -c "cvmfs_server list 2>/dev/null" 2>/dev/null | grep -q "software.lab.local"; then
    pass_test
else
    fail_test
fi

run_test "  Can publish content"
TIMESTAMP2=$(date +%s)
# Don't start a new transaction if one is already open - just publish
if vagrant ssh cvmfs-publisher2 -c "
    # Check if transaction is already open
    if cvmfs_server list | grep -q 'in transaction'; then
        echo 'Transaction already open, just adding content...'
    else
        sudo cvmfs_server transaction software.lab.local/test/pub2 >/dev/null 2>&1
    fi

    # Create content
    sudo mkdir -p /cvmfs/software.lab.local/test/pub2
    echo 'Test from publisher2 at ${TIMESTAMP2}' | sudo tee /cvmfs/software.lab.local/test/pub2/test_${TIMESTAMP2}.txt >/dev/null

    # Publish
    sudo cvmfs_server publish software.lab.local >/dev/null 2>&1 && echo SUCCESS
" 2>/dev/null | grep -q "SUCCESS"; then
    pass_test
else
    fail_test
fi

end_test_suite
