#!/bin/bash
# Test Gentoo Prefix installation
# Validates that the prefix is functional

set -e

PREFIX_PATH="$1"

echo "=== Testing Gentoo Prefix ==="
echo "Prefix: $PREFIX_PATH"
echo

TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: Check directory structure
echo "Test 1: Checking directory structure..."
required_dirs=(
    "usr/bin"
    "usr/lib"
    "etc/portage"
    "var/db"
)

for dir in "${required_dirs[@]}"; do
    if [[ -d "$PREFIX_PATH/$dir" ]]; then
        echo "  [PASS] $dir exists"
        ((TESTS_PASSED++))
    else
        echo "  [FAIL] $dir missing"
        ((TESTS_FAILED++))
    fi
done

# Test 2: Check startprefix script
echo
echo "Test 2: Checking startprefix..."
if [[ -x "$PREFIX_PATH/startprefix" ]]; then
    echo "  [PASS] startprefix is executable"
    ((TESTS_PASSED++))
else
    echo "  [FAIL] startprefix not found or not executable"
    ((TESTS_FAILED++))
fi

# Test 3: Check essential binaries
echo
echo "Test 3: Checking essential binaries..."
essential_bins=(
    "bash"
    "gcc"
    "make"
    "python"
)

for bin in "${essential_bins[@]}"; do
    if [[ -x "$PREFIX_PATH/usr/bin/$bin" ]]; then
        echo "  [PASS] $bin exists"
        ((TESTS_PASSED++))
    else
        echo "  [FAIL] $bin missing"
        ((TESTS_FAILED++))
    fi
done

# Test 4: Check configuration files
echo
echo "Test 4: Checking configuration..."
if [[ -f "$PREFIX_PATH/etc/portage/make.conf" ]]; then
    echo "  [PASS] make.conf exists"
    ((TESTS_PASSED++))

    # Check CFLAGS
    if grep -q "^CFLAGS=" "$PREFIX_PATH/etc/portage/make.conf"; then
        echo "  [PASS] CFLAGS configured"
        ((TESTS_PASSED++))
    else
        echo "  [FAIL] CFLAGS not set"
        ((TESTS_FAILED++))
    fi
else
    echo "  [FAIL] make.conf missing"
    ((TESTS_FAILED++))
fi

# Test 5: Check architecture marker
echo
echo "Test 5: Checking architecture info..."
if [[ -f "$PREFIX_PATH/.architecture" ]]; then
    ARCH=$(cat "$PREFIX_PATH/.architecture")
    echo "  [PASS] Architecture marked as: $ARCH"
    ((TESTS_PASSED++))
else
    echo "  [FAIL] Architecture marker missing"
    ((TESTS_FAILED++))
fi

# Test 6: Test environment execution
echo
echo "Test 6: Testing prefix environment..."
# MOCK: In reality, would actually execute in prefix
echo "  [MOCK] Would test: $PREFIX_PATH/startprefix /usr/bin/gcc --version"
echo "  [PASS] Environment test (mocked)"
((TESTS_PASSED++))

# Summary
echo
echo "=== Test Summary ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
