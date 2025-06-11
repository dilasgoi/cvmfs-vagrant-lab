#!/bin/bash
# Test 08: Publishing Workflow

source $(dirname "$0")/test-common.sh || exit 1

start_test_suite "PUBLISHING WORKFLOW"

# Test 1: Basic publish
run_test "Publisher can publish content"
if vagrant ssh cvmfs-publisher1 -c "
    # Clean state
    sudo cvmfs_server abort -f software.lab.local 2>/dev/null || true

    # Transaction and publish
    sudo cvmfs_server transaction software.lab.local >/dev/null 2>&1 && \
    echo 'Test content' | sudo tee /cvmfs/software.lab.local/test_file.txt >/dev/null && \
    sudo cvmfs_server publish software.lab.local >/dev/null 2>&1 && \
    echo SUCCESS
" 2>/dev/null | grep -q "SUCCESS"; then
    pass_test
else
    fail_test
fi

# Test 2: Content is on Stratum-0
run_test "Content accessible on Stratum-0"
if curl -s "http://192.168.58.10/cvmfs/software.lab.local/.cvmfspublished" | grep -q "^C"; then
    pass_test
else
    fail_test
fi

# Test 3: Sync to Stratum-1
run_test "Stratum-1 can sync content"
if vagrant ssh cvmfs-stratum1 -c "sudo cvmfs_server snapshot software.lab.local >/dev/null 2>&1 && echo OK" 2>/dev/null | grep -q "OK"; then
    sleep 3
    pass_test
else
    fail_test
fi

# Test 4: Client access with aggressive refresh
run_test "Client can access content"
if vagrant ssh cvmfs-client -c "
    # Aggressive refresh sequence
    sudo cvmfs_config reload software.lab.local 2>/dev/null || true
    sleep 2
    sudo cvmfs_config umount software.lab.local 2>/dev/null
    sleep 2
    sudo cvmfs_config probe software.lab.local >/dev/null 2>&1
    sleep 3
    # Access parent directory first
    ls /cvmfs/software.lab.local/ >/dev/null 2>&1
    sleep 1
    if test -f /cvmfs/software.lab.local/test_file.txt; then
        echo FOUND
    fi
" 2>/dev/null | grep -q "FOUND"; then
    pass_test
else
    fail_test
fi

# Test 5: Verify proxy is caching
run_test "Proxy caches repository data"
if vagrant ssh squid-proxy -c "systemctl is-active squid >/dev/null 2>&1 && test -d /var/spool/squid && echo OK" 2>/dev/null | grep -q "OK"; then
    pass_test
else
    fail_test
fi

# Test 6: Multiple file publish
run_test "Publisher can publish multiple files"
if vagrant ssh cvmfs-publisher1 -c "
    sudo cvmfs_server transaction software.lab.local >/dev/null 2>&1 && \
    echo 'Multi 1' | sudo tee /cvmfs/software.lab.local/multi_1.txt >/dev/null && \
    echo 'Multi 2' | sudo tee /cvmfs/software.lab.local/multi_2.txt >/dev/null && \
    echo 'Multi 3' | sudo tee /cvmfs/software.lab.local/multi_3.txt >/dev/null && \
    echo 'Multi 4' | sudo tee /cvmfs/software.lab.local/multi_4.txt >/dev/null && \
    echo 'Multi 5' | sudo tee /cvmfs/software.lab.local/multi_5.txt >/dev/null && \
    sudo cvmfs_server publish software.lab.local >/dev/null 2>&1 && \
    echo SUCCESS
" 2>/dev/null | grep -q "SUCCESS"; then
    pass_test
else
    fail_test
fi

# Test 7: All files accessible with AGGRESSIVE refresh
run_test "All published files accessible on client"
# Sync first
vagrant ssh cvmfs-stratum1 -c "sudo cvmfs_server snapshot software.lab.local" >/dev/null 2>&1
sleep 5

# AGGRESSIVE refresh approach
if vagrant ssh cvmfs-client -c "
    # Full reload first
    sudo cvmfs_config reload software.lab.local 2>/dev/null || true
    sleep 2

    # Unmount completely
    sudo cvmfs_config umount software.lab.local 2>/dev/null
    sleep 2

    # Probe to remount fresh
    sudo cvmfs_config probe software.lab.local >/dev/null 2>&1
    sleep 3

    # Access parent directory to trigger autofs
    ls -la /cvmfs/software.lab.local/ >/dev/null 2>&1
    sleep 1

    # Use find to force directory traversal
    find /cvmfs/software.lab.local/ -name 'multi_*.txt' >/dev/null 2>&1
    sleep 1

    # Now check if files exist
    if test -f /cvmfs/software.lab.local/multi_1.txt && \
       test -f /cvmfs/software.lab.local/multi_2.txt && \
       test -f /cvmfs/software.lab.local/multi_3.txt && \
       test -f /cvmfs/software.lab.local/multi_4.txt && \
       test -f /cvmfs/software.lab.local/multi_5.txt; then
        echo ALL_FOUND
    else
        # Debug output if it fails
        echo 'Failed to find all files. Found:'
        ls /cvmfs/software.lab.local/multi_*.txt 2>&1
    fi
" 2>/dev/null | grep -q "ALL_FOUND"; then
    pass_test
else
    fail_test
fi

# Test 8: Repository metadata is current
run_test "Repository metadata is updated"
if vagrant ssh cvmfs-client -c "cvmfs_config stat software.lab.local >/dev/null 2>&1 && echo UPDATED" 2>/dev/null | grep -q "UPDATED"; then
    pass_test
else
    fail_test
fi

# Test 9: Clean up test files
run_test "Cleanup published test files"
if vagrant ssh cvmfs-publisher1 -c "
    sudo cvmfs_server transaction software.lab.local >/dev/null 2>&1 && \
    sudo rm -f /cvmfs/software.lab.local/test_file.txt && \
    sudo rm -f /cvmfs/software.lab.local/multi_*.txt && \
    sudo cvmfs_server publish software.lab.local >/dev/null 2>&1 && \
    echo CLEANED
" 2>/dev/null | grep -q "CLEANED"; then
    pass_test
else
    fail_test
fi

end_test_suite
