#!/bin/bash
# ABOUTME: Main hook script for Claude-Gemini Bridge - intercepts tool calls and delegates to Gemini when appropriate

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/config/debug.conf"
source "$SCRIPT_DIR/lib/debug-helpers.sh"
source "$SCRIPT_DIR/lib/path-converter.sh"
source "$SCRIPT_DIR/lib/json-parser.sh"
source "$SCRIPT_DIR/lib/gemini-wrapper.sh"

# Initialize debug system
init_debug "gemini-bridge" "$SCRIPT_DIR/../logs/debug"

# Start performance measurement
start_timer "hook_execution"

debug_log 1 "Hook execution started"
debug_system_info

# Read tool call JSON from stdin
TOOL_CALL_JSON=$(cat)

# Check for empty input
if [ -z "$TOOL_CALL_JSON" ]; then
    debug_log 1 "Empty input received, continuing with normal execution"
    create_hook_response "continue" "" "Empty input"
    exit 0
fi

debug_log 2 "Received tool call of size: $(echo "$TOOL_CALL_JSON" | wc -c) bytes"

# Save input for later analysis
if [ "$CAPTURE_INPUTS" = "true" ]; then
    CAPTURE_FILE=$(capture_input "$TOOL_CALL_JSON" "$CAPTURE_DIR")
    debug_log 1 "Input captured to: $CAPTURE_FILE"
fi

# Validate JSON
if ! validate_json "$TOOL_CALL_JSON"; then
    error_log "Invalid JSON received from Claude"
    create_hook_response "continue" "" "Invalid JSON input"
    exit 1
fi

# Determine working directory
WORKING_DIR=$(extract_working_directory "$TOOL_CALL_JSON")
if [ -z "$WORKING_DIR" ]; then
    WORKING_DIR=$(pwd)
    debug_log 1 "No working_directory in context, using: $WORKING_DIR"
else
    debug_log 2 "Working directory from context: $WORKING_DIR"
fi

# Extract tool type and parameters
TOOL_NAME=$(extract_tool_name "$TOOL_CALL_JSON")
TOOL_PARAMS=$(extract_parameters "$TOOL_CALL_JSON")

debug_log 1 "Processing tool: $TOOL_NAME"
debug_json "Tool parameters" "$TOOL_PARAMS"

# Extract file paths based on tool type
case "$TOOL_NAME" in
    "Read")
        FILE_PATH_RAW=$(extract_file_paths "$TOOL_PARAMS" "$TOOL_NAME")
        ABSOLUTE_PATH=$(convert_claude_paths "$FILE_PATH_RAW" "$WORKING_DIR")
        FILES="$ABSOLUTE_PATH"
        ORIGINAL_PROMPT="Read file: $FILE_PATH_RAW"
        ;;
    "Glob")
        PATTERN_RAW=$(extract_file_paths "$TOOL_PARAMS" "$TOOL_NAME")
        ABSOLUTE_PATTERN=$(convert_claude_paths "$PATTERN_RAW" "$WORKING_DIR")
        # Expand glob pattern
        cd "$WORKING_DIR" 2>/dev/null || cd /tmp
        FILES=$(eval "ls $ABSOLUTE_PATTERN" 2>/dev/null | head -$GEMINI_MAX_FILES)
        ORIGINAL_PROMPT="Find files matching: $PATTERN_RAW"
        ;;
    "Grep")
        GREP_INFO=$(extract_file_paths "$TOOL_PARAMS" "$TOOL_NAME")
        GREP_PATH=$(echo "$GREP_INFO" | cut -d' ' -f1)
        ABSOLUTE_GREP_PATH=$(convert_claude_paths "$GREP_PATH" "$WORKING_DIR")
        # For Grep we use the search path as basis
        FILES="$ABSOLUTE_GREP_PATH"
        ORIGINAL_PROMPT="Search in: $GREP_INFO"
        ;;
    "Task")
        TASK_PROMPT=$(extract_task_prompt "$TOOL_PARAMS")
        CONVERTED_PROMPT=$(convert_claude_paths "$TASK_PROMPT" "$WORKING_DIR")
        # Extract file paths from prompt
        FILES=$(extract_files_from_text "$CONVERTED_PROMPT")
        ORIGINAL_PROMPT="$TASK_PROMPT"
        ;;
    *)
        debug_log 1 "Unknown tool type: $TOOL_NAME, continuing normally"
        create_hook_response "continue"
        exit 0
        ;;
esac

debug_vars "extracted" TOOL_NAME FILES WORKING_DIR ORIGINAL_PROMPT

# Decision: Should Gemini be used? Based on Claude's 200k vs Gemini's 1M token limit
should_delegate_to_gemini() {
    local tool="$1"
    local files="$2"
    local prompt="$3"
    
    # Dry-run mode - always delegate for tests
    if [ "$DRY_RUN" = "true" ]; then
        debug_log 1 "DRY_RUN mode: would delegate to Gemini"
        return 0
    fi
    
    # Calculate estimated token count (rough estimate: 4 chars = 1 token)
    local total_size=0
    local file_count=0
    
    if [ -n "$files" ]; then
        file_count=$(count_files "$files")
        for file in $files; do
            if [ -f "$file" ]; then
                local file_size=$(debug_file_size "$file")
                total_size=$((total_size + file_size))
            fi
        done
    fi
    
    # Rough token estimation: 4 characters ≈ 1 token
    local estimated_tokens=$((total_size / 4))
    
    debug_log 2 "File count: $file_count, Total size: $total_size bytes, Estimated tokens: $estimated_tokens"
    
    # Claude's practical limit: ~150k tokens (leaving room for response)
    local claude_token_limit=150000
    # Gemini's practical limit: ~800k tokens (leaving room for response)  
    local gemini_token_limit=800000
    
    # If estimated tokens exceed Claude's comfortable limit, use Gemini
    if [ "$estimated_tokens" -gt "$claude_token_limit" ]; then
        if [ "$estimated_tokens" -le "$gemini_token_limit" ]; then
            debug_log 1 "Large content ($estimated_tokens tokens) - delegating to Gemini"
            return 0
        else
            debug_log 1 "Content too large even for Gemini ($estimated_tokens tokens) - splitting needed"
            return 1
        fi
    fi
    
    # For smaller content, check if it's a multi-file analysis task that benefits from Gemini
    if [ "$file_count" -ge 5 ] && [[ "$tool" == "Task" ]]; then
        debug_log 1 "Multi-file Task ($file_count files) - delegating to Gemini for better analysis"
        return 0
    fi
    
    # Check for excluded file patterns
    for file in $files; do
        local filename=$(basename "$file")
        if [[ "$filename" =~ $GEMINI_EXCLUDE_PATTERNS ]]; then
            debug_log 2 "Excluded file pattern detected: $filename"
            return 1
        fi
    done
    
    debug_log 2 "Content size manageable for Claude - no delegation needed"
    return 1
}

# Main decision
if should_delegate_to_gemini "$TOOL_NAME" "$FILES" "$ORIGINAL_PROMPT"; then
    debug_log 1 "Delegating to Gemini for tool: $TOOL_NAME"
    
    # Initialize Gemini wrapper
    if ! init_gemini_wrapper; then
        error_log "Failed to initialize Gemini wrapper"
        create_hook_response "continue" "" "Gemini initialization failed"
        exit 1
    fi
    
    # Call Gemini
    start_timer "gemini_processing"
    GEMINI_RESULT=$(call_gemini "$TOOL_NAME" "$FILES" "$WORKING_DIR" "$ORIGINAL_PROMPT")
    GEMINI_EXIT_CODE=$?
    GEMINI_DURATION=$(end_timer "gemini_processing")
    
    if [ "$GEMINI_EXIT_CODE" -eq 0 ] && [ -n "$GEMINI_RESULT" ]; then
        # Successful Gemini response
        debug_log 1 "Gemini processing successful (${GEMINI_DURATION}s)"
        
        # Create structured response
        FILE_COUNT=$(count_files "$FILES")
        STRUCTURED_RESPONSE=$(create_gemini_response "$GEMINI_RESULT" "$TOOL_NAME" "$FILE_COUNT" "$GEMINI_DURATION")
        
        # Hook response with Gemini result
        create_hook_response "replace" "$STRUCTURED_RESPONSE"
    else
        # Gemini error - continue normally
        error_log "Gemini processing failed, continuing with normal tool execution"
        create_hook_response "continue" "" "Gemini processing failed"
    fi
else
    # Continue normally without Gemini
    debug_log 1 "Continuing with normal tool execution"
    create_hook_response "continue"
fi

# End performance measurement
TOTAL_DURATION=$(end_timer "hook_execution")
debug_log 1 "Hook execution completed in ${TOTAL_DURATION}s"

# Automatic cleanup
if [ "$AUTO_CLEANUP_CACHE" = "true" ]; then
    # Only clean occasionally (about 1 in 10 times)
    if [ $((RANDOM % 10)) -eq 0 ]; then
        cleanup_gemini_cache "$CACHE_MAX_AGE_HOURS" &
    fi
fi

if [ "$AUTO_CLEANUP_LOGS" = "true" ]; then
    # Only clean occasionally (about 1 in 20 times)
    if [ $((RANDOM % 20)) -eq 0 ]; then
        cleanup_debug_files "$LOG_MAX_AGE_DAYS" &
    fi
fi

exit 0