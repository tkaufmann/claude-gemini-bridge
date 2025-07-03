#!/bin/bash
# ABOUTME: JSON parsing functions for Claude-Gemini Bridge

# Extracts tool name from JSON
extract_tool_name() {
    local json="$1"
    echo "$json" | jq -r '.tool // empty'
}

# Extracts parameters as JSON object
extract_parameters() {
    local json="$1"
    echo "$json" | jq -r '.parameters // {}'
}

# Extracts working directory from context
extract_working_directory() {
    local json="$1"
    echo "$json" | jq -r '.context.working_directory // empty'
}

# Extracts file paths based on tool type
extract_file_paths() {
    local params="$1"
    local tool="$2"
    
    case "$tool" in
        "Read")
            echo "$params" | jq -r '.file_path // empty'
            ;;
        "Glob")
            echo "$params" | jq -r '.pattern // empty'
            ;;
        "Grep")
            local path=$(echo "$params" | jq -r '.path // "."')
            local pattern=$(echo "$params" | jq -r '.pattern // empty')
            echo "$path (pattern: $pattern)"
            ;;
        "Task")
            # Search task prompts for file paths
            local prompt=$(echo "$params" | jq -r '.prompt // empty')
            echo "$prompt" | grep -oE '(@[^[:space:]]+|/[^[:space:]]+|[^[:space:]]+\.[a-zA-Z0-9]+)' | head -20
            ;;
        *)
            echo ""
            ;;
    esac
}

# Extracts prompt from task parameters
extract_task_prompt() {
    local params="$1"
    echo "$params" | jq -r '.prompt // empty'
}

# Extracts description from task parameters
extract_task_description() {
    local params="$1"
    echo "$params" | jq -r '.description // empty'
}

# Validates if JSON is valid
validate_json() {
    local json="$1"
    if echo "$json" | jq empty 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Creates JSON response for hook response
create_hook_response() {
    local action="$1"
    local result="$2"
    local error="$3"
    
    case "$action" in
        "continue")
            echo '{"action": "continue"}'
            ;;
        "replace")
            if [ -n "$result" ]; then
                jq -n --arg result "$result" '{"action": "replace", "result": $result}'
            else
                echo '{"action": "continue", "error": "No result provided"}'
            fi
            ;;
        "block")
            if [ -n "$error" ]; then
                jq -n --arg error "$error" '{"action": "block", "error": $error}'
            else
                echo '{"action": "block", "error": "Blocked by hook"}'
            fi
            ;;
        *)
            echo '{"action": "continue", "error": "Unknown action"}'
            ;;
    esac
}

# Creates structured Gemini response
create_gemini_response() {
    local content="$1"
    local original_tool="$2"
    local file_count="$3"
    local processing_time="$4"
    
    jq -n \
        --arg content "$content" \
        --arg original_tool "$original_tool" \
        --arg file_count "$file_count" \
        --arg processing_time "$processing_time" \
        '{
            type: "gemini_analysis",
            content: $content,
            metadata: {
                original_tool: $original_tool,
                file_count: ($file_count | tonumber),
                processing_time: $processing_time,
                timestamp: now
            }
        }'
}

# Counts number of files in a string
count_files() {
    local files="$1"
    if [ -z "$files" ]; then
        echo "0"
    else
        echo "$files" | wc -w | tr -d ' '
    fi
}

# Test function for JSON parser
test_json_parser() {
    echo "Testing JSON parser..."
    local failed=0
    
    # Test JSON
    local test_json='{
        "tool": "Read",
        "parameters": {
            "file_path": "@src/main.py"
        },
        "context": {
            "working_directory": "/Users/tim/Code/project"
        }
    }'
    
    # Test 1: Tool-Name extrahieren
    local tool_name=$(extract_tool_name "$test_json")
    if [ "$tool_name" != "Read" ]; then
        echo "❌ Test 1 failed: Tool name '$tool_name' != 'Read'"
        failed=1
    else
        echo "✅ Test 1 passed: Tool name extraction"
    fi
    
    # Test 2: Working Directory extrahieren
    local wd=$(extract_working_directory "$test_json")
    if [ "$wd" != "/Users/tim/Code/project" ]; then
        echo "❌ Test 2 failed: Working directory '$wd' != '/Users/tim/Code/project'"
        failed=1
    else
        echo "✅ Test 2 passed: Working directory extraction"
    fi
    
    # Test 3: Dateipfade extrahieren
    local params=$(extract_parameters "$test_json")
    local file_path=$(extract_file_paths "$params" "Read")
    if [ "$file_path" != "@src/main.py" ]; then
        echo "❌ Test 3 failed: File path '$file_path' != '@src/main.py'"
        failed=1
    else
        echo "✅ Test 3 passed: File path extraction"
    fi
    
    # Test 4: Hook-Response erstellen
    local response=$(create_hook_response "continue")
    if ! echo "$response" | jq empty 2>/dev/null; then
        echo "❌ Test 4 failed: Invalid JSON response"
        failed=1
    else
        echo "✅ Test 4 passed: Hook response creation"
    fi
    
    # Test 5: Task-JSON
    local task_json='{
        "tool": "Task",
        "parameters": {
            "prompt": "Search for config files in @src/ and @config/",
            "description": "Config search"
        },
        "context": {}
    }'
    
    local task_params=$(extract_parameters "$task_json")
    local task_prompt=$(extract_task_prompt "$task_params")
    if [[ "$task_prompt" != *"@src/"* ]]; then
        echo "❌ Test 5 failed: Task prompt extraction"
        failed=1
    else
        echo "✅ Test 5 passed: Task prompt extraction"
    fi
    
    if [ $failed -eq 0 ]; then
        echo "🎉 All JSON parser tests passed!"
        return 0
    else
        echo "💥 Some tests failed!"
        return 1
    fi
}

# Wenn das Script direkt aufgerufen wird, führe Tests aus
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    test_json_parser
fi