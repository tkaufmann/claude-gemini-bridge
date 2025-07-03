#!/bin/bash
# ABOUTME: Automated test suite for Claude-Gemini Bridge

echo "🚀 Claude-Gemini Bridge Test Suite"
echo "==================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use current directory structure (git repo = installation)
BRIDGE_DIR="$SCRIPT_DIR/.."
echo "🔧 Running from: $BRIDGE_DIR"

BRIDGE_SCRIPT="$BRIDGE_DIR/hooks/gemini-bridge.sh"
MOCK_DIR="$SCRIPT_DIR/mock-tool-calls"

# Statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test function
run_test() {
    local test_name="$1"
    local json_file="$2"
    local expected_action="$3"  # "continue" or "replace"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo "🧪 Test $TOTAL_TESTS: $test_name"
    
    if [ ! -f "$json_file" ]; then
        echo "❌ FAILED: Test file not found: $json_file"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    
    # Execute test
    local result=$(cat "$json_file" | "$BRIDGE_SCRIPT" 2>/dev/null)
    local exit_code=$?
    
    # Check exit code
    if [ $exit_code -ne 0 ]; then
        echo "❌ FAILED: Bridge script exit code: $exit_code"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    
    # Check JSON validity
    if ! echo "$result" | jq empty 2>/dev/null; then
        echo "❌ FAILED: Invalid JSON response"
        echo "   Response: $result"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    
    # Check decision (new Claude Code hook format)
    local decision=$(echo "$result" | jq -r '.decision // empty')
    
    # Map expected actions to decisions
    local expected_decision
    case "$expected_action" in
        "continue") expected_decision="approve" ;;
        "replace") expected_decision="block" ;;
        *) expected_decision="$expected_action" ;;
    esac
    
    if [ "$decision" != "$expected_decision" ]; then
        echo "❌ FAILED: Expected decision '$expected_decision', got '$decision'"
        echo "   Response: $result"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    
    # Additional validation for "block" decision (delegation to Gemini)
    if [ "$decision" = "block" ]; then
        local has_result=$(echo "$result" | jq -r '.result // empty')
        if [ -z "$has_result" ]; then
            echo "❌ FAILED: Block decision without result"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    fi
    
    echo "✅ PASSED: $test_name"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    return 0
}

# Test preparation
echo "📋 Preparing test environment..."

# Create test files if they don't exist
mkdir -p /tmp/test-project/src
echo "print('Hello World')" > /tmp/test-project/src/main.py
echo "# Test config file" > /tmp/test-project/config.txt

echo "✅ Test environment ready"
echo ""

# Execute tests
echo "🏃 Running tests..."
echo ""

# Test 1: Simple Read (should be "continue" since only 1 file)
run_test "Simple Read (continue)" "$MOCK_DIR/simple-read.json" "continue"

# Test 2: Task with Search (could be "replace" depending on files)
run_test "Task Search" "$MOCK_DIR/task-search.json" "continue"

# Test 3: Multi-File Glob (could be "replace" with many files)
run_test "Multi-File Glob" "$MOCK_DIR/multi-file-glob.json" "continue"

# Test 4: Grep Search
run_test "Grep Search" "$MOCK_DIR/grep-search.json" "continue"

# Test 5: Invalid JSON
echo "🧪 Test $((TOTAL_TESTS + 1)): Invalid JSON"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
INVALID_RESULT=$(echo '{"invalid": json}' | "$BRIDGE_SCRIPT" 2>/dev/null)
INVALID_EXIT=$?
if [ $INVALID_EXIT -eq 1 ]; then
    echo "✅ PASSED: Invalid JSON handled correctly"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "❌ FAILED: Invalid JSON not handled properly"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 6: Empty Input
echo "🧪 Test $((TOTAL_TESTS + 1)): Empty Input"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
EMPTY_RESULT=$(echo '' | "$BRIDGE_SCRIPT" 2>/dev/null)
EMPTY_EXIT=$?
if [ $EMPTY_EXIT -eq 0 ] && [[ "$EMPTY_RESULT" == *"approve"* ]]; then
    echo "✅ PASSED: Empty input handled correctly"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "❌ FAILED: Empty input not handled properly (exit: $EMPTY_EXIT, result: $EMPTY_RESULT)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Library tests
echo ""
echo "📚 Testing library functions..."

# Path Converter Test
echo "🧪 Testing path-converter.sh..."
if "$BRIDGE_DIR/hooks/lib/path-converter.sh" >/dev/null 2>&1; then
    echo "✅ PASSED: Path converter"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "❌ FAILED: Path converter"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# JSON Parser Test
echo "🧪 Testing json-parser.sh..."
if "$BRIDGE_DIR/hooks/lib/json-parser.sh" >/dev/null 2>&1; then
    echo "✅ PASSED: JSON parser"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "❌ FAILED: JSON parser"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Debug Helpers Test
echo "🧪 Testing debug-helpers.sh..."
if "$BRIDGE_DIR/hooks/lib/debug-helpers.sh" >/dev/null 2>&1; then
    echo "✅ PASSED: Debug helpers"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "❌ FAILED: Debug helpers"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Gemini Wrapper Test
echo "🧪 Testing gemini-wrapper.sh..."
if "$BRIDGE_DIR/hooks/lib/gemini-wrapper.sh" >/dev/null 2>&1; then
    echo "✅ PASSED: Gemini wrapper"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "❌ FAILED: Gemini wrapper"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test summary
echo ""
echo "📊 Test Summary"
echo "==============="
echo "Total Tests:  $TOTAL_TESTS"
echo "Passed:       $PASSED_TESTS"
echo "Failed:       $FAILED_TESTS"
echo "Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo "🎉 All tests passed! Bridge is ready for use."
    exit 0
else
    echo "💥 Some tests failed. Check the logs for details:"
    echo "   Debug: $BRIDGE_DIR/logs/debug/$(date +%Y%m%d).log"
    echo "   Errors: $BRIDGE_DIR/logs/debug/errors.log"
    echo ""
    echo "Run manual tests for more details:"
    echo "   $SCRIPT_DIR/manual-test.sh"
    exit 1
fi