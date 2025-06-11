#!/bin/bash
# Master Test Script - Runs all CVMFS infrastructure tests

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if we're in the right directory
if [ ! -f "../Vagrantfile" ]; then
    echo -e "${RED}ERROR: This script should be run from the tests directory${NC}"
    echo "Please cd to the tests directory first"
    exit 1
fi

# Change to project root for vagrant commands
cd ..

# Check if test scripts exist
if [ ! -f "$SCRIPT_DIR/test-common.sh" ]; then
    echo -e "${RED}ERROR: test-common.sh not found${NC}"
    exit 1
fi

# Make all test scripts executable
chmod +x "$SCRIPT_DIR"/test-*.sh

# Clear any old results filed
RESULTS_FILE="/tmp/cvmfs_test_results_master"
rm -f "$RESULTS_FILE"

# Header
clear
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    CVMFS Infrastructure Test Suite                           ║${NC}"
echo -e "${BLUE}║                          Master Test Runner                                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo
echo "Date: $(date)"
echo "Directory: $(pwd)"
echo "Test Scripts: $SCRIPT_DIR"
echo

# Global counters
GLOBAL_TOTAL=0
GLOBAL_PASSED=0
GLOBAL_FAILED=0

# Function to run a test script and collect results
run_test_script() {
    local script_name=$1
    local script_path="$SCRIPT_DIR/$script_name"

    if [ ! -f "$script_path" ]; then
        echo -e "${RED}WARNING: $script_name not found, skipping${NC}"
        return
    fi

    echo -e "\n${BLUE}Running $script_name...${NC}"

    # Export the results file path so child scripts can use it
    export RESULTS_FILE

    # Run the test script
    bash "$script_path"
}

# Option parsing
RUN_ALL=true
SELECTED_TESTS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 [options] [test-numbers]"
            echo "Options:"
            echo "  -h, --help     Show this help message"
            echo "  -l, --list     List all available tests"
            echo "  -q, --quick    Run only essential tests (1,2,7,8)"
            echo ""
            echo "Examples:"
            echo "  $0              # Run all tests"
            echo "  $0 1 2 3        # Run only tests 1, 2, and 3"
            echo "  $0 --quick      # Run quick essential tests"
            exit 0
            ;;
        -l|--list)
            echo "Available tests:"
            echo "  1  - Infrastructure (VMs running)"
            echo "  2  - Gateway + Stratum0"
            echo "  3  - Security and Keys"
            echo "  4  - Publishers"
            echo "  5  - Stratum1 Replica"
            echo "  6  - Squid Proxy"
            echo "  7  - Client Access"
            echo "  8  - Publishing Workflow"
            echo "  9  - Performance Tests"
            exit 0
            ;;
        -q|--quick)
            SELECTED_TESTS=(1 2 7 8)
            RUN_ALL=false
            ;;
        [0-9]|10)
            SELECTED_TESTS+=($1)
            RUN_ALL=false
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
    shift
done

# Define test scripts in order
declare -A TEST_SCRIPTS=(
    [1]="test-01-infrastructure.sh"
    [2]="test-02-gateway-stratum0.sh"
    [3]="test-03-security.sh"
    [4]="test-04-publishers.sh"
    [5]="test-05-stratum1.sh"
    [6]="test-06-proxy.sh"
    [7]="test-07-client.sh"
    [8]="test-08-publishing.sh"
    [9]="test-09-performance.sh"
)

# Check which test scripts actually exist
echo -e "${CYAN}Checking available test scripts...${NC}"
AVAILABLE_TESTS=()
for i in {1..9}; do
    if [ -f "$SCRIPT_DIR/${TEST_SCRIPTS[$i]}" ]; then
        AVAILABLE_TESTS+=($i)
        echo -e "  ${GREEN}✓${NC} Test $i: ${TEST_SCRIPTS[$i]}"
    else
        echo -e "  ${YELLOW}⚠${NC}  Test $i: ${TEST_SCRIPTS[$i]} (not found)"
    fi
done

if [ ${#AVAILABLE_TESTS[@]} -eq 0 ]; then
    echo -e "\n${RED}ERROR: No test scripts found!${NC}"
    echo "Please ensure test scripts are in: $SCRIPT_DIR"
    exit 1
fi

# Run tests
START_TIME=$(date +%s)

if [ "$RUN_ALL" = true ]; then
    echo -e "\n${CYAN}Running all available tests...${NC}"
    for test_num in "${AVAILABLE_TESTS[@]}"; do
        run_test_script "${TEST_SCRIPTS[$test_num]}"
    done
else
    echo -e "\n${CYAN}Running selected tests: ${SELECTED_TESTS[@]}${NC}"
    for test_num in "${SELECTED_TESTS[@]}"; do
        if [[ " ${AVAILABLE_TESTS[@]} " =~ " $test_num " ]]; then
            run_test_script "${TEST_SCRIPTS[$test_num]}"
        else
            echo -e "${YELLOW}Test $test_num not available, skipping${NC}"
        fi
    done
fi

# Read all results
if [ -f "$RESULTS_FILE" ]; then
    while read total passed failed; do
        GLOBAL_TOTAL=$((GLOBAL_TOTAL + total))
        GLOBAL_PASSED=$((GLOBAL_PASSED + passed))
        GLOBAL_FAILED=$((GLOBAL_FAILED + failed))
    done < "$RESULTS_FILE"
    rm -f "$RESULTS_FILE"
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Final summary
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                              FINAL TEST SUMMARY                               ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo
echo "Total Tests Run: $GLOBAL_TOTAL"
echo -e "Tests Passed: ${GREEN}$GLOBAL_PASSED${NC}"
echo -e "Tests Failed: ${RED}$GLOBAL_FAILED${NC}"
echo "Success Rate: $([ $GLOBAL_TOTAL -gt 0 ] && echo "$(( GLOBAL_PASSED * 100 / GLOBAL_TOTAL ))%" || echo "N/A")"
echo "Duration: ${DURATION} seconds"
echo

if [ $GLOBAL_FAILED -eq 0 ] && [ $GLOBAL_TOTAL -gt 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED!${NC}"
    echo "Your CVMFS infrastructure is working correctly."
    EXIT_CODE=0
else
    echo -e "${RED}✗ Some tests failed.${NC}"
    echo "Please review the individual test outputs above for details."
    EXIT_CODE=1
fi

echo -e "\n${YELLOW}Quick Commands:${NC}"
echo "  Run specific test:  $0 <test-number>"
echo "  Quick test:         $0 --quick"
echo "  View help:          $0 --help"
echo
echo -e "${YELLOW}Key Endpoints:${NC}"
echo "  Gateway API: http://192.168.58.10:4929/api/v1"
echo "  Stratum-0:   http://192.168.58.10/cvmfs/software.lab.local"
echo "  Stratum-1:   http://192.168.58.11/cvmfs/software.lab.local"
echo "  Proxy:       http://192.168.58.14:3128"

exit $EXIT_CODE
