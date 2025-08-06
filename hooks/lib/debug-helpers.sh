#!/bin/bash
# ABOUTME: Debug helper functions for Claude-Gemini Bridge

# Global variables
DEBUG_LOG_DIR=""
DEBUG_LEVEL=${DEBUG_LEVEL:-1}
DEBUG_COMPONENT=""

# Helper to get bridge directory
get_bridge_dir() {
    echo "${CLAUDE_GEMINI_BRIDGE_DIR:-$HOME/.claude-gemini-bridge}"
}

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Initializes the debug system
init_debug() {
    DEBUG_COMPONENT="$1"
    DEBUG_LOG_DIR="$2"
    
    # Fallback to default directory
    if [ -z "$DEBUG_LOG_DIR" ]; then
        DEBUG_LOG_DIR="${CLAUDE_GEMINI_BRIDGE_DIR:-$HOME/.claude-gemini-bridge}/logs/debug"
    fi
    
    # Create log directory
    mkdir -p "$DEBUG_LOG_DIR"
    
    debug_log 1 "Debug system initialized for component: $DEBUG_COMPONENT"
}

# Main function for debug logging
debug_log() {
    local level=$1
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    local component_prefix=""
    
    # Add component prefix
    if [ -n "$DEBUG_COMPONENT" ]; then
        component_prefix="[$DEBUG_COMPONENT] "
    fi
    
    # Only log if level is activated
    if [ "$level" -le "$DEBUG_LEVEL" ]; then
        local log_entry="[$timestamp] $component_prefix$message"
        
        # Level-specific handling
        case $level in
            1) 
                prefix="${GREEN}[INFO]${NC}"
                log_file="$DEBUG_LOG_DIR/$(date +%Y%m%d).log"
                ;;
            2) 
                prefix="${YELLOW}[DEBUG]${NC}"
                log_file="$DEBUG_LOG_DIR/$(date +%Y%m%d).log"
                ;;
            3) 
                prefix="${BLUE}[TRACE]${NC}"
                log_file="$DEBUG_LOG_DIR/$(date +%Y%m%d)_trace.log"
                ;;
        esac
        
        # Write to file
        echo "$log_entry" >> "$log_file"
        
        # Also output to stderr for higher debug levels
        if [ "$DEBUG_LEVEL" -ge 2 ]; then
            echo -e "$prefix $log_entry" >&2
        fi
    fi
}

# Error logging (always active)
error_log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local component_prefix=""
    
    if [ -n "$DEBUG_COMPONENT" ]; then
        component_prefix="[$DEBUG_COMPONENT] "
    fi
    
    local log_entry="[$timestamp] $component_prefix$message"
    
    # Both stderr and error log
    echo -e "${RED}[ERROR]${NC} $log_entry" >&2
    echo "$log_entry" >> "$DEBUG_LOG_DIR/errors.log"
}

# Start performance measurement
start_timer() {
    local timer_name="$1"
    local start_time=$(date +%s.%N)
    echo "$start_time" > "/tmp/claude_bridge_timer_$timer_name"
    debug_log 3 "Timer started: $timer_name"
}

# End performance measurement
end_timer() {
    local timer_name="$1"
    local timer_file="/tmp/claude_bridge_timer_$timer_name"
    
    if [ -f "$timer_file" ]; then
        local start_time=$(cat "$timer_file")
        local end_time=$(date +%s.%N)
        # Use awk instead of bc for better portability
        local duration=$(awk -v e="$end_time" -v s="$start_time" 'BEGIN {printf "%.3f", e-s}' 2>/dev/null || echo "0")
        
        debug_log 2 "Timer finished: $timer_name took ${duration}s"
        rm -f "$timer_file"
        echo "$duration"
    else
        debug_log 1 "Timer not found: $timer_name"
        echo "0"
    fi
}

# Pretty-print for JSON with syntax highlighting
debug_json() {
    local label="$1"
    local json="$2"
    
    debug_log 3 "$label:"
    
    if [ "$DEBUG_LEVEL" -ge 3 ]; then
        if command -v jq >/dev/null 2>&1; then
            echo -e "${CYAN}JSON:${NC}" >&2
            echo "$json" | jq '.' 2>/dev/null >&2 || echo "$json" >&2
        else
            echo -e "${CYAN}JSON (raw):${NC}" >&2
            echo "$json" >&2
        fi
    fi
}

# Variable dump for debugging
debug_vars() {
    local prefix="$1"
    shift
    
    debug_log 3 "Variables dump ($prefix):"
    
    if [ "$DEBUG_LEVEL" -ge 3 ]; then
        for var in "$@"; do
            if [ -n "${!var}" ]; then
                echo -e "${PURPLE}  $var=${NC}${!var}" >&2
            else
                echo -e "${PURPLE}  $var=${NC}(empty)" >&2
            fi
        done
    fi
}

# System info for debug context
debug_system_info() {
    debug_log 3 "System info:"
    if [ "$DEBUG_LEVEL" -ge 3 ]; then
        echo -e "${CYAN}System Information:${NC}" >&2
        echo "  OS: $(uname -s)" >&2
        echo "  PWD: $(pwd)" >&2
        echo "  USER: ${USER:-unknown}" >&2
        echo "  PID: $$" >&2
        echo "  Bash version: $BASH_VERSION" >&2
    fi
}

# File size for debug output
debug_file_size() {
    local file="$1"
    if [ -f "$file" ]; then
        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "unknown")
        debug_log 3 "File size: $file = $size bytes"
        echo "$size"
    else
        debug_log 3 "File not found: $file"
        echo "0"
    fi
}

# Capture input for later analysis
capture_input() {
    local input="$1"
    local capture_dir="$2"
    
    if [ -z "$capture_dir" ]; then
        capture_dir="$(get_bridge_dir)/debug/captured"
    fi
    
    mkdir -p "$capture_dir"
    
    local capture_file="$capture_dir/$(date +%Y%m%d_%H%M%S)_$(uuidgen 2>/dev/null || echo $$).json"
    echo "$input" > "$capture_file"
    
    debug_log 2 "Input captured to: $capture_file"
    echo "$capture_file"
}

# Clean up old debug files
cleanup_debug_files() {
    local days_to_keep=${1:-7}
    
    debug_log 2 "Cleaning up debug files older than $days_to_keep days"
    
    # Delete old log files
    find "$DEBUG_LOG_DIR" -name "*.log" -mtime +$days_to_keep -delete 2>/dev/null
    
    # Delete old capture files
    find "$(get_bridge_dir)/debug/captured" -name "*.json" -mtime +$days_to_keep -delete 2>/dev/null
    
    # Delete old timer files
    find "/tmp" -name "claude_bridge_timer_*" -mtime +1 -delete 2>/dev/null
}

# Test function for debug helpers
test_debug_helpers() {
    echo "Testing debug helpers..."
    local failed=0
    
    # Test directory
    local test_dir="/tmp/claude_bridge_debug_test"
    mkdir -p "$test_dir"
    
    # Test 1: Initialization
    init_debug "test_component" "$test_dir"
    if [ ! -d "$test_dir" ]; then
        echo "❌ Test 1 failed: Debug directory not created"
        failed=1
    else
        echo "✅ Test 1 passed: Debug initialization"
    fi
    
    # Test 2: Logging
    debug_log 1 "Test message"
    local log_file="$test_dir/$(date +%Y%m%d).log"
    if [ ! -f "$log_file" ]; then
        echo "❌ Test 2 failed: Log file not created"
        failed=1
    else
        echo "✅ Test 2 passed: Debug logging"
    fi
    
    # Test 3: Timer
    start_timer "test_timer"
    sleep 0.1
    local duration=$(end_timer "test_timer")
    if [ "$duration" = "0" ]; then
        echo "❌ Test 3 failed: Timer not working"
        failed=1
    else
        echo "✅ Test 3 passed: Timer functionality"
    fi
    
    # Test 4: JSON Debug
    local test_json='{"test": "value"}'
    debug_json "Test JSON" "$test_json"
    echo "✅ Test 4 passed: JSON debug (check manually)"
    
    # Cleanup
    rm -rf "$test_dir"
    
    if [ $failed -eq 0 ]; then
        echo "🎉 All debug helper tests passed!"
        return 0
    else
        echo "💥 Some tests failed!"
        return 1
    fi
}

# If script is called directly, run tests
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    test_debug_helpers
fi