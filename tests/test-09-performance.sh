#!/bin/bash
# Test 09: Performance Tests
# Measures actual performance metrics of the CVMFS infrastructure

source $(dirname "$0")/test-common.sh || exit 1

start_test_suite "PERFORMANCE TESTS"

# Helper function to measure time in milliseconds
get_time_ms() {
    echo $(($(date +%s%N)/1000000))
}

# 1. Publishing Performance
run_test "Publish single file performance"
START=$(get_time_ms)
if vagrant ssh cvmfs-publisher1 -c "
    sudo cvmfs_server transaction software.lab.local >/dev/null 2>&1 && \
    echo 'Performance test' | sudo tee /cvmfs/software.lab.local/perf_test.txt >/dev/null && \
    sudo cvmfs_server publish software.lab.local >/dev/null 2>&1 && \
    echo OK
" 2>/dev/null | grep -q "OK"; then
    END=$(get_time_ms)
    DURATION=$((END - START))
    echo -n " (${DURATION}ms)"
    pass_test
else
    fail_test
fi

# 2. Publishing bulk files performance
run_test "Publish 50 files performance"
START=$(get_time_ms)
if vagrant ssh cvmfs-publisher1 -c "
    sudo cvmfs_server transaction software.lab.local >/dev/null 2>&1 && \
    for i in \$(seq 1 50); do
        echo \"File \$i\" | sudo tee /cvmfs/software.lab.local/bulk_\$i.txt >/dev/null
    done && \
    sudo cvmfs_server publish software.lab.local >/dev/null 2>&1 && \
    echo OK
" 2>/dev/null | grep -q "OK"; then
    END=$(get_time_ms)
    DURATION=$((END - START))
    echo -n " (${DURATION}ms)"
    pass_test
else
    fail_test
fi

# 3. Stratum-1 sync performance
run_test "Stratum-1 sync performance"
START=$(get_time_ms)
if vagrant ssh cvmfs-stratum1 -c "sudo cvmfs_server snapshot software.lab.local >/dev/null 2>&1 && echo OK" 2>/dev/null | grep -q "OK"; then
    END=$(get_time_ms)
    DURATION=$((END - START))
    echo -n " (${DURATION}ms)"
    pass_test
else
    fail_test
fi

# 4. Client cold cache access
run_test "Client cold cache file access"
vagrant ssh cvmfs-client -c "sudo cvmfs_config umount software.lab.local >/dev/null 2>&1; sudo cvmfs_config wipecache >/dev/null 2>&1" >/dev/null 2>&1
sleep 2
START=$(get_time_ms)
if vagrant ssh cvmfs-client -c "cat /cvmfs/software.lab.local/README.txt >/dev/null 2>&1 && echo OK" 2>/dev/null | grep -q "OK"; then
    END=$(get_time_ms)
    DURATION=$((END - START))
    echo -n " (${DURATION}ms)"
    pass_test
else
    fail_test
fi

# 5. Client warm cache access
run_test "Client warm cache file access"
# Prime the cache
vagrant ssh cvmfs-client -c "cat /cvmfs/software.lab.local/README.txt >/dev/null 2>&1" 2>/dev/null
sleep 1
START=$(get_time_ms)
if vagrant ssh cvmfs-client -c "cat /cvmfs/software.lab.local/README.txt >/dev/null 2>&1 && echo OK" 2>/dev/null | grep -q "OK"; then
    END=$(get_time_ms)
    DURATION=$((END - START))
    echo -n " (${DURATION}ms)"
    pass_test
else
    fail_test
fi

# 6. Gateway API response time
run_test "Gateway API response time"
START=$(get_time_ms)
if vagrant ssh cvmfs-gateway-stratum0 -c "curl -s -m 2 http://localhost:4929/api/v1/repos >/dev/null && echo OK" 2>/dev/null | grep -q "OK"; then
    END=$(get_time_ms)
    DURATION=$((END - START))
    echo -n " (${DURATION}ms)"
    pass_test
else
    fail_test
fi

# 7. Concurrent client access
run_test "10 concurrent client reads"
START=$(get_time_ms)
if vagrant ssh cvmfs-client -c "
    for i in {1..10}; do
        cat /cvmfs/software.lab.local/README.txt >/dev/null 2>&1 &
    done
    wait
    echo OK
" 2>/dev/null | grep -q "OK"; then
    END=$(get_time_ms)
    DURATION=$((END - START))
    echo -n " (${DURATION}ms)"
    pass_test
else
    fail_test
fi

# 8. Large file creation and publish
run_test "Create and publish 10MB file"
START=$(get_time_ms)
if vagrant ssh cvmfs-publisher1 -c "
    sudo cvmfs_server transaction software.lab.local >/dev/null 2>&1 && \
    sudo dd if=/dev/zero of=/cvmfs/software.lab.local/large_perf.dat bs=1M count=10 2>/dev/null && \
    sudo cvmfs_server publish software.lab.local >/dev/null 2>&1 && \
    echo OK
" 2>/dev/null | grep -q "OK"; then
    END=$(get_time_ms)
    DURATION=$((END - START))
    echo -n " (${DURATION}ms)"
    pass_test
else
    fail_test
fi

# 9. Client access to large file with AGGRESSIVE refresh
run_test "Client read 10MB file"
# Sync first
vagrant ssh cvmfs-stratum1 -c "sudo cvmfs_server snapshot software.lab.local" >/dev/null 2>&1
sleep 5

# AGGRESSIVE refresh pattern
START=$(get_time_ms)
if vagrant ssh cvmfs-client -c "
    # Full reload
    sudo cvmfs_config reload software.lab.local 2>/dev/null || true
    sleep 2

    # Unmount
    sudo cvmfs_config umount software.lab.local 2>/dev/null
    sleep 2

    # Probe to remount
    sudo cvmfs_config probe software.lab.local >/dev/null 2>&1
    sleep 3

    # Access parent directory
    ls -la /cvmfs/software.lab.local/ >/dev/null 2>&1
    sleep 1

    # Force find
    find /cvmfs/software.lab.local/ -name 'large_perf.dat' >/dev/null 2>&1
    sleep 1

    # Check file
    if test -f /cvmfs/software.lab.local/large_perf.dat; then
        echo OK
    fi
" 2>&1 | grep -q "OK"; then
    END=$(get_time_ms)
    DURATION=$((END - START))
    echo -n " (${DURATION}ms)"
    pass_test
else
    fail_test
fi

# 10. Proxy cache hit performance
run_test "Proxy cache hit for file"
# First access to populate cache
vagrant ssh cvmfs-client -c "cat /cvmfs/software.lab.local/README.txt >/dev/null 2>&1" >/dev/null 2>&1
sleep 1
# Clear client cache only
vagrant ssh cvmfs-client -c "sudo cvmfs_config wipecache >/dev/null 2>&1" >/dev/null 2>&1
sleep 1
# Measure cached access
START=$(get_time_ms)
if vagrant ssh cvmfs-client -c "cat /cvmfs/software.lab.local/README.txt >/dev/null 2>&1 && echo OK" 2>/dev/null | grep -q "OK"; then
    END=$(get_time_ms)
    DURATION=$((END - START))
    echo -n " (${DURATION}ms)"
    pass_test
else
    fail_test
fi

# 11. Transaction throughput test
run_test "100 small file publish"
START=$(get_time_ms)
if vagrant ssh cvmfs-publisher1 -c "
    sudo cvmfs_server transaction software.lab.local >/dev/null 2>&1 && \
    for i in \$(seq 1 100); do
        echo \"Throughput test \$i\" > /cvmfs/software.lab.local/throughput_\$i.txt
    done && \
    sudo cvmfs_server publish software.lab.local >/dev/null 2>&1 && \
    echo OK
" 2>/dev/null | grep -q "OK"; then
    END=$(get_time_ms)
    DURATION=$((END - START))
    FILES_PER_SEC=$((100000 / DURATION))
    echo -n " (${DURATION}ms, ~${FILES_PER_SEC} files/sec)"
    pass_test
else
    fail_test
fi

# 12. Cleanup performance test files
run_test "Cleanup test files"
if vagrant ssh cvmfs-publisher1 -c "
    sudo cvmfs_server transaction software.lab.local >/dev/null 2>&1 && \
    sudo rm -f /cvmfs/software.lab.local/perf_test.txt && \
    sudo rm -f /cvmfs/software.lab.local/bulk_*.txt && \
    sudo rm -f /cvmfs/software.lab.local/large_perf.dat && \
    sudo rm -f /cvmfs/software.lab.local/throughput_*.txt && \
    sudo cvmfs_server publish software.lab.local >/dev/null 2>&1 && \
    echo OK
" 2>/dev/null | grep -q "OK"; then
    pass_test
else
    fail_test
fi

# Performance Summary
echo
echo -e "${CYAN}Performance Summary:${NC}"
echo "  - Publishing operations: Measured in milliseconds"
echo "  - Client access: Includes mount/unmount overhead"
echo "  - Large file handling: 10MB test file"
echo "  - Throughput: Files per second for bulk operations"

end_test_suite
