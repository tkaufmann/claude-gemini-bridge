#!/bin/bash
# ABOUTME: Converts Claude's @ notation to absolute paths for Gemini integration

# Main function for path conversion with security validation
convert_claude_paths() {
    local input="$1"
    local base_dir="$2"
    
    # Input validation
    if [ -z "$input" ]; then
        echo ""
        return 0
    fi
    
    if [ -z "$base_dir" ]; then
        base_dir="$(pwd)"
    fi
    
    # Security: Block path traversal attempts  
    if [[ "$input" =~ \.\./|\.\.\\ ]]; then
        echo "" # Return empty on path traversal attempt
        return 1
    fi
    
    # Security: Validate base_dir is safe
    case "$base_dir" in
        /etc/*|/usr/*|/bin/*|/sbin/*|/root/*|/home/*/\.ssh/*)
            echo "" # Block access to system directories
            return 1
            ;;
    esac
    
    # Remove trailing slash from base_dir
    base_dir="${base_dir%/}"
    
    # Perform conversions
    # @./ -> empty string (current directory)
    input="${input//@\.\//}"
    
    # @/ -> project root (base_dir)
    input="${input//@\//$base_dir/}"
    
    # @filename or @folder/ -> absolute path
    # Use sed for @ followed by file/folder name
    input=$(echo "$input" | sed -E "s|@([^/[:space:]]+)|$base_dir/\\1|g")
    
    # Clean up double slashes
    input=$(echo "$input" | sed 's|//|/|g')
    
    echo "$input"
}

# Extracts file paths from text with security validation
extract_files_from_text() {
    local text="$1"
    
    # Security: Block path traversal attempts
    if [[ "$text" =~ \.\./|\.\.\\ ]]; then
        echo "" # Return empty on path traversal attempt
        return 1
    fi
    
    # Security: Block absolute paths outside working directory
    if [[ "$text" =~ /etc/|/usr/|/bin/|/sbin/|/root/|/home/ ]]; then
        echo "" # Return empty on system path access
        return 1
    fi
    
    # Finds all file paths with extensions
    echo "$text" | grep -oE '(/[^[:space:]]+|[^[:space:]]+/[^[:space:]]+)\.[a-zA-Z0-9]+' | sort -u
}

# Advanced path conversion for complex patterns
convert_advanced_paths() {
    local input="$1"
    local base_dir="$2"
    
    # Basic conversion
    local result=$(convert_claude_paths "$input" "$base_dir")
    
    # Glob pattern support
    # **/*.py -> all Python files recursively
    if [[ "$result" == *"**/"* ]]; then
        result=$(echo "$result" | sed "s|\\*\\*/|**/|g")
    fi
    
    echo "$result"
}

# Test function for path conversion
test_path_conversion() {
    local wd="/Users/tim/Code/project"
    local failed=0
    
    echo "Testing path conversion..."
    
    # Test 1: @./ -> empty string
    local result1=$(convert_claude_paths '@./' "$wd")
    if [ "$result1" != "" ]; then
        echo "❌ Test 1 failed: '@./' -> '$result1' (expected: '')"
        failed=1
    else
        echo "✅ Test 1 passed: '@./' -> ''"
    fi
    
    # Test 2: @src/main.py -> absolute path
    local result2=$(convert_claude_paths '@src/main.py' "$wd")
    local expected2="$wd/src/main.py"
    if [ "$result2" != "$expected2" ]; then
        echo "❌ Test 2 failed: '@src/main.py' -> '$result2' (expected: '$expected2')"
        failed=1
    else
        echo "✅ Test 2 passed: '@src/main.py' -> '$expected2'"
    fi
    
    # Test 3: Multiple @ paths
    local input3="Check @README.md and @src/*.py files"
    local result3=$(convert_claude_paths "$input3" "$wd")
    local expected3="Check $wd/README.md and $wd/src/*.py files"
    if [ "$result3" != "$expected3" ]; then
        echo "❌ Test 3 failed: '$input3' -> '$result3' (expected: '$expected3')"
        failed=1
    else
        echo "✅ Test 3 passed: Multiple @ paths"
    fi
    
    # Test 4: @/ -> base_dir
    local result4=$(convert_claude_paths '@/' "$wd")
    local expected4="$wd/"
    if [ "$result4" != "$expected4" ]; then
        echo "❌ Test 4 failed: '@/' -> '$result4' (expected: '$expected4')"
        failed=1
    else
        echo "✅ Test 4 passed: '@/' -> '$expected4'"
    fi
    
    if [ $failed -eq 0 ]; then
        echo "🎉 All path conversion tests passed!"
        return 0
    else
        echo "💥 Some tests failed!"
        return 1
    fi
}

# If the script is called directly, run tests
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    test_path_conversion
fi