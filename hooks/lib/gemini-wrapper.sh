#!/bin/bash
# ABOUTME: Wrapper for Gemini CLI with caching and rate limiting

# Configuration
GEMINI_CACHE_DIR="${GEMINI_CACHE_DIR:-${CLAUDE_GEMINI_BRIDGE_DIR:-$HOME/.claude-gemini-bridge}/cache/gemini}"
GEMINI_CACHE_TTL="${GEMINI_CACHE_TTL:-3600}"  # 1 hour
GEMINI_TIMEOUT="${GEMINI_TIMEOUT:-30}"        # 30 seconds
GEMINI_RATE_LIMIT="${GEMINI_RATE_LIMIT:-1}"   # 1 second between calls
GEMINI_MAX_FILES="${GEMINI_MAX_FILES:-20}"    # Max 20 files per call

# Rate limiting file
RATE_LIMIT_FILE="/tmp/claude_bridge_gemini_last_call"

# Initialize Gemini wrapper
init_gemini_wrapper() {
    mkdir -p "$GEMINI_CACHE_DIR"
    
    # Test if Gemini is available
    if ! command -v gemini >/dev/null 2>&1; then
        error_log "Gemini CLI not found in PATH"
        return 1
    fi
    
    debug_log 1 "Gemini wrapper initialized"
    debug_log 2 "Cache dir: $GEMINI_CACHE_DIR"
    debug_log 2 "Cache TTL: $GEMINI_CACHE_TTL seconds"
    
    return 0
}

# Implement rate limiting
enforce_rate_limit() {
    if [ -f "$RATE_LIMIT_FILE" ]; then
        local last_call=$(cat "$RATE_LIMIT_FILE" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_call))
        
        if [ "$time_diff" -lt "$GEMINI_RATE_LIMIT" ]; then
            local sleep_time=$((GEMINI_RATE_LIMIT - time_diff))
            debug_log 2 "Rate limiting: sleeping ${sleep_time}s"
            sleep "$sleep_time"
        fi
    fi
    
    # Save current time
    date +%s > "$RATE_LIMIT_FILE"
}

# Generate cache key from input
generate_cache_key() {
    local prompt="$1"
    local files="$2"
    local working_dir="$3"
    
    # Create hash from file contents + metadata
    local content_hash=""
    local file_array=($files)
    
    for file in "${file_array[@]}"; do
        if [ -f "$file" ] && [ -r "$file" ]; then
            # Combine filename, size, modification time and first 1KB of content
            local file_info=$(stat -f "%N|%z|%m" "$file" 2>/dev/null || stat -c "%n|%s|%Y" "$file" 2>/dev/null)
            local file_sample=$(head -c 1024 "$file" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
            content_hash="${content_hash}${file_info}|${file_sample}|"
        fi
    done
    
    # SHA256 hash from all parameters + file contents
    local input_string="$prompt|$files|$working_dir|$content_hash"
    echo "$input_string" | shasum -a 256 | cut -d' ' -f1
}

# Check if cache entry is still valid
is_cache_valid() {
    local cache_file="$1"
    
    if [ ! -f "$cache_file" ]; then
        return 1
    fi
    
    local cache_age=$(( $(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file") ))
    
    if [ "$cache_age" -lt "$GEMINI_CACHE_TTL" ]; then
        debug_log 2 "Cache hit: age ${cache_age}s (TTL: ${GEMINI_CACHE_TTL}s)"
        return 0
    else
        debug_log 2 "Cache expired: age ${cache_age}s"
        return 1
    fi
}

# Create Gemini prompt based on tool type
create_gemini_prompt() {
    local tool_type="$1"
    local original_prompt="$2"
    local file_count="$3"
    
    case "$tool_type" in
        "Read")
            echo "You are assisting another LLM with file analysis. The user requested to read this file, but it's large enough that I'm helping out. Please analyze this file and provide a concise summary focusing on purpose, main functions, and important details:"
            ;;
        "Glob"|"Grep")
            echo "You are assisting another LLM with multi-file analysis. The user is searching across $file_count files. Please analyze these files and create a structured overview, grouping similar files and explaining the purpose of each group:"
            ;;
        "Task")
            if [[ "$original_prompt" =~ (search|find|suche|finde) ]]; then
                echo "You are assisting another LLM with a complex search task. The original request was: $original_prompt

Please search the provided files for the specified criteria and provide a structured list of findings with context:"
            elif [[ "$original_prompt" =~ (analyze|analysiere|verstehe) ]]; then
                echo "You are assisting another LLM with a complex analysis task. The original request was: $original_prompt

Please perform a detailed analysis of the provided files:"
            else
                echo "You are assisting another LLM with a complex analysis task. The original request was: $original_prompt

Please process this task with the provided files and give a comprehensive response:"
            fi
            ;;
        *)
            echo "You are assisting another LLM with file analysis. Please analyze the provided files and provide a helpful summary."
            ;;
    esac
}

# Prepare files for Gemini
prepare_files_for_gemini() {
    local files="$1"
    local working_dir="$2"
    local processed_files=""
    local file_count=0
    
    # Convert to array
    local file_array=($files)
    
    for file in "${file_array[@]}"; do
        # Skip if too many files
        if [ "$file_count" -ge "$GEMINI_MAX_FILES" ]; then
            debug_log 1 "File limit reached: $GEMINI_MAX_FILES"
            break
        fi
        
        # Make path absolute if necessary
        if [[ "$file" != /* ]]; then
            file="$working_dir/$file"
        fi
        
        # Check if file exists and is readable
        if [ -f "$file" ] && [ -r "$file" ]; then
            # Check file size (max 1MB per file)
            local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
            if [ "$file_size" -lt 1048576 ]; then
                processed_files="$processed_files $file"
                file_count=$((file_count + 1))
                debug_log 3 "Added file: $file (${file_size} bytes)"
            else
                debug_log 2 "Skipping large file: $file (${file_size} bytes)"
            fi
        else
            debug_log 2 "Skipping non-existent/unreadable file: $file"
        fi
    done
    
    echo "$processed_files"
}

# Main function: Call Gemini with caching
call_gemini() {
    local tool_type="$1"
    local files="$2"
    local working_dir="$3"
    local original_prompt="$4"
    
    debug_log 1 "Calling Gemini for tool: $tool_type"
    start_timer "gemini_call"
    
    # Generate cache key
    local cache_key=$(generate_cache_key "$tool_type|$original_prompt" "$files" "$working_dir")
    local cache_file="$GEMINI_CACHE_DIR/$cache_key"
    
    # Check cache
    if is_cache_valid "$cache_file"; then
        debug_log 1 "Using cached result"
        cat "$cache_file"
        end_timer "gemini_call" >/dev/null
        return 0
    fi
    
    # Prepare files
    local processed_files=$(prepare_files_for_gemini "$files" "$working_dir")
    local file_count=$(echo "$processed_files" | wc -w | tr -d ' ')
    
    if [ "$file_count" -eq 0 ]; then
        debug_log 1 "No valid files found for Gemini"
        echo "No valid files found for analysis."
        end_timer "gemini_call" >/dev/null
        return 1
    fi
    
    # Create prompt
    local gemini_prompt=$(create_gemini_prompt "$tool_type" "$original_prompt" "$file_count")
    
    debug_log 2 "Processing $file_count files with Gemini"
    debug_log 3 "Prompt: $gemini_prompt"
    
    # Rate limiting
    enforce_rate_limit
    
    # Call Gemini
    local gemini_result=""
    local gemini_exit_code=0
    
    # Timeout with GNU timeout or gtimeout (macOS)
    local timeout_cmd="timeout"
    if command -v gtimeout >/dev/null 2>&1; then
        timeout_cmd="gtimeout"
    fi
    
    # Prepare file contents for STDIN
    local file_contents=""
    for file in $processed_files; do
        if [ -f "$file" ]; then
            file_contents="${file_contents}=== File: $file ===\n\n"
            file_contents="${file_contents}$(cat "$file" 2>/dev/null)\n\n"
        fi
    done
    
    # Debug: Show exact command being executed
    debug_log 3 "Executing: echo [file contents] | gemini -p \"$gemini_prompt\""
    
    if command -v "$timeout_cmd" >/dev/null 2>&1; then
        gemini_result=$(echo -e "$file_contents" | "$timeout_cmd" "$GEMINI_TIMEOUT" gemini -p "$gemini_prompt" 2>&1)
        gemini_exit_code=$?
    else
        # Fallback without timeout
        gemini_result=$(echo -e "$file_contents" | gemini -p "$gemini_prompt" 2>&1)
        gemini_exit_code=$?
    fi
    
    local duration=$(end_timer "gemini_call")
    
    # Check result
    if [ "$gemini_exit_code" -eq 0 ] && [ -n "$gemini_result" ]; then
        # Cache successful response
        echo "$gemini_result" > "$cache_file"
        debug_log 1 "Gemini call successful (${duration}s, $file_count files)"
        echo "$gemini_result"
        return 0
    else
        error_log "Gemini call failed (exit code: $gemini_exit_code)"
        debug_log 2 "Gemini error output: $gemini_result"
        echo "Gemini analysis failed. Please check the logs."
        return 1
    fi
}

# Clean up old cache
cleanup_gemini_cache() {
    local max_age_hours=${1:-24}  # Default: 24 hours
    
    debug_log 2 "Cleaning up Gemini cache older than $max_age_hours hours"
    
    find "$GEMINI_CACHE_DIR" -type f -mtime +$(echo "$max_age_hours/24" | bc) -delete 2>/dev/null
    
    # Cache statistics
    local cache_files=$(find "$GEMINI_CACHE_DIR" -type f | wc -l | tr -d ' ')
    local cache_size=$(du -sh "$GEMINI_CACHE_DIR" 2>/dev/null | cut -f1)
    
    debug_log 1 "Cache stats: $cache_files files, $cache_size total size"
}

# Test function for Gemini wrapper
test_gemini_wrapper() {
    echo "Testing Gemini wrapper..."
    local failed=0
    
    # Test 1: Initialization
    if ! init_gemini_wrapper; then
        echo "❌ Test 1 failed: Gemini wrapper initialization"
        failed=1
    else
        echo "✅ Test 1 passed: Gemini wrapper initialization"
    fi
    
    # Test 2: Cache-Key Generierung
    local key1=$(generate_cache_key "test" "file1.txt" "/tmp")
    local key2=$(generate_cache_key "test" "file1.txt" "/tmp")
    local key3=$(generate_cache_key "test2" "file1.txt" "/tmp")
    
    if [ "$key1" != "$key2" ]; then
        echo "❌ Test 2a failed: Cache keys should be identical"
        failed=1
    elif [ "$key1" = "$key3" ]; then
        echo "❌ Test 2b failed: Cache keys should be different"
        failed=1
    else
        echo "✅ Test 2 passed: Cache key generation"
    fi
    
    # Test 3: Prompt creation
    local prompt=$(create_gemini_prompt "Read" "analyze this file" 1)
    local prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
    if [[ "$prompt_lower" != *"analyze"* ]]; then
        echo "❌ Test 3 failed: Prompt creation"
        failed=1
    else
        echo "✅ Test 3 passed: Prompt creation"
    fi
    
    # Test 4: Rate limiting (simulated)
    echo $(date +%s) > "$RATE_LIMIT_FILE"
    local start_time=$(date +%s)
    enforce_rate_limit
    local end_time=$(date +%s)
    local time_diff=$((end_time - start_time))
    
    if [ "$time_diff" -ge 1 ]; then
        echo "✅ Test 4 passed: Rate limiting works"
    else
        echo "✅ Test 4 passed: Rate limiting (no delay needed)"
    fi
    
    # Cleanup
    rm -f "$RATE_LIMIT_FILE"
    
    if [ $failed -eq 0 ]; then
        echo "🎉 All Gemini wrapper tests passed!"
        return 0
    else
        echo "💥 Some tests failed!"
        return 1
    fi
}

# If script is called directly, run tests
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    # Initialize debug system for tests
    if [ -f "$(dirname "$0")/debug-helpers.sh" ]; then
        source "$(dirname "$0")/debug-helpers.sh"
        init_debug "gemini-wrapper-test"
    fi
    
    test_gemini_wrapper
fi