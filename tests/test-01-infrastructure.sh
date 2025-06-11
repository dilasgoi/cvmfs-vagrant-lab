
#!/bin/bash
# Test 01: Virtual Machine Infrastructure
# Verifies all VMs are running and accessible

source $(dirname "$0")/test-common.sh || exit 1

start_test_suite "VIRTUAL MACHINE INFRASTRUCTURE"

# Test each VM
for vm in cvmfs-gateway-stratum0 cvmfs-publisher1 cvmfs-publisher2 cvmfs-stratum1 squid-proxy cvmfs-client; do
    run_test "$vm is running"
    if vagrant status $vm 2>/dev/null | grep -q "running"; then
        pass_test
    else
        fail_test
    fi
done

# Test VM connectivity
for vm in cvmfs-gateway-stratum0 cvmfs-publisher1 cvmfs-publisher2 cvmfs-stratum1 squid-proxy cvmfs-client; do
    run_test "$vm SSH accessible"
    if run_on_vm $vm "echo ok" | grep -q "ok"; then
        pass_test
    else
        fail_test
    fi
done

end_test_suite
