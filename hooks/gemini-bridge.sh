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

# Decision: Should Gemini be used?
should_delegate_to_gemini() {
    local tool="$1"
    local files="$2"
    local prompt="$3"
    
    # Dry-run mode - always delegate for tests
    if [ "$DRY_RUN" = "true" ]; then
        debug_log 1 "DRY_RUN mode: would delegate to Gemini"
        return 0
    fi
    
    # Task tool with search/analysis tasks
    if [[ "$tool" == "Task" ]]; then
        if [[ "$prompt" =~ (search|find|analyze|summarize|suche|finde|analysiere|zusammenfasse) ]]; then
            debug_log 2 "Task with search/analysis keywords detected"
            return 0
        fi
    fi
    
    # Count available files
    local file_count=0
    if [ -n "$files" ]; then
        file_count=$(count_files "$files")
    fi
    
    debug_log 2 "File count: $file_count (minimum: $MIN_FILES_FOR_GEMINI)"
    
    # Check minimum file count
    if [ "$file_count" -lt "$MIN_FILES_FOR_GEMINI" ]; then
        debug_log 2 "Not enough files for Gemini delegation"
        return 1
    fi
    
    # Check total file size
    local total_size=0
    for file in $files; do
        if [ -f "$file" ]; then
            local file_size=$(debug_file_size "$file")
            total_size=$((total_size + file_size))
        fi
    done
    
    debug_log 2 "Total file size: $total_size bytes (min: $MIN_FILE_SIZE_FOR_GEMINI, max: $MAX_TOTAL_SIZE_FOR_GEMINI)"
    
    # Size checks
    if [ "$total_size" -lt "$MIN_FILE_SIZE_FOR_GEMINI" ]; then
        debug_log 2 "Files too small for Gemini delegation"
        return 1
    fi
    
    if [ "$total_size" -gt "$MAX_TOTAL_SIZE_FOR_GEMINI" ]; then
        debug_log 2 "Files too large for Gemini delegation"
        return 1
    fi
    
    # Check for excluded file patterns
    for file in $files; do
        local filename=$(basename "$file")
        if [[ "$filename" =~ $GEMINI_EXCLUDE_PATTERNS ]]; then
            debug_log 2 "Excluded file pattern detected: $filename"
            return 1
        fi
    done
    
    debug_log 1 "All criteria met - delegating to Gemini"
    return 0
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