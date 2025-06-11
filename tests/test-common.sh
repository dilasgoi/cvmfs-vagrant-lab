#!/bin/bash
# Common functions and variables for CVMFS tests
# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m'
# Global counters
export TOTAL_TESTS=0
export PASSED_TESTS=0
export FAILED_TESTS=0
# Helper function to run commands on VMs without "Connection closed" messages
run_on_vm() {
    vagrant ssh $1 -c "$2" 2>&1 | grep -v "Connection to .* closed"
}
# Test tracking functions
run_test() {
    echo -n "   $1: "
    ((TOTAL_TESTS++))
}
pass_test() {
    echo -e "${GREEN}✓${NC}"
    ((PASSED_TESTS++))
}
fail_test() {
    echo -e "${RED}✗${NC}"
    ((FAILED_TESTS++))
}
# Test suite management
start_test_suite() {
    local suite_name="$1"
    echo -e "\n${YELLOW}═══ $suite_name ═══${NC}"
    if [ -n "$2" ]; then
        echo -e "${PURPLE}$2${NC}"
    fi
    echo
}
end_test_suite() {
    echo -e "\n${CYAN}Subtotal: $PASSED_TESTS passed, $FAILED_TESTS failed out of $TOTAL_TESTS tests${NC}"
    # Export results for master script
    echo "$TOTAL_TESTS $PASSED_TESTS $FAILED_TESTS" >> "/tmp/cvmfs_test_results_master"
}
# Utility functions
check_vm_running() {
    local vm=$1
    vagrant status $vm 2>/dev/null | grep -q "running"
}
wait_for_service() {
    local vm=$1
    local service=$2
    local max_attempts=${3:-30}
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if run_on_vm $vm "systemctl is-active $service" | grep -q "active"; then
            return 0
        fi
        sleep 1
        ((attempt++))
    done
    return 1
}
# Export functions
export -f run_on_vm
export -f run_test
export -f pass_test
export -f fail_test
export -f start_test_suite
export -f end_test_suite
export -f check_vm_running
export -f wait_for_service
