#!/bin/bash
# ABOUTME: Interactive test tool for Claude-Gemini Bridge

echo "🧪 Claude-Gemini Bridge Test Tool"
echo "=================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use current directory structure (git repo = installation)
BRIDGE_DIR="$SCRIPT_DIR/.."
echo "🔧 Running from: $BRIDGE_DIR"

BRIDGE_SCRIPT="$BRIDGE_DIR/hooks/gemini-bridge.sh"

# Check if bridge script exists
if [ ! -f "$BRIDGE_SCRIPT" ]; then
    echo "❌ Bridge script not found: $BRIDGE_SCRIPT"
    exit 1
fi

# Test scenarios
run_test() {
    local test_name="$1"
    local json_file="$2"
    
    echo "🔍 Running test: $test_name"
    echo "JSON file: $json_file"
    echo ""
    
    if [ ! -f "$json_file" ]; then
        echo "❌ Test file not found: $json_file"
        return 1
    fi
    
    echo "📋 Input JSON:"
    cat "$json_file" | jq '.' 2>/dev/null || cat "$json_file"
    echo ""
    
    echo "⚡ Bridge Response:"
    cat "$json_file" | "$BRIDGE_SCRIPT" | jq '.' 2>/dev/null || cat "$json_file" | "$BRIDGE_SCRIPT"
    echo ""
    
    echo "📊 Check logs for details:"
    echo "   Debug: tail -f $BRIDGE_DIR/logs/debug/$(date +%Y%m%d).log"
    echo "   Errors: tail -f $BRIDGE_DIR/logs/debug/errors.log"
    echo ""
}

# Interactive menu
while true; do
    echo "Choose a test:"
    echo "1) Simple Read (@src/main.py)"
    echo "2) Task with Search (config analysis)"
    echo "3) Multi-File Glob (@**/*.php)"
    echo "4) Grep Search (function.*config)"
    echo "5) Custom JSON Input"
    echo "6) Replay Captured Call"
    echo "7) Test All Library Functions"
    echo "8) View Recent Logs"
    echo "9) Clear Cache and Logs"
    echo "0) Exit"
    echo ""
    read -p "Selection (0-9): " choice
    
    case $choice in
        1)
            run_test "Simple Read" "$SCRIPT_DIR/mock-tool-calls/simple-read.json"
            ;;
        2)
            run_test "Task Search" "$SCRIPT_DIR/mock-tool-calls/task-search.json"
            ;;
        3)
            run_test "Multi-File Glob" "$SCRIPT_DIR/mock-tool-calls/multi-file-glob.json"
            ;;
        4)
            run_test "Grep Search" "$SCRIPT_DIR/mock-tool-calls/grep-search.json"
            ;;
        5)
            echo "Enter your JSON (Ctrl+D to finish):"
            echo "Example:"
            echo '{"tool":"Read","parameters":{"file_path":"@test.txt"},"context":{}}'
            echo ""
            CUSTOM_JSON=$(cat)
            echo "$CUSTOM_JSON" | "$BRIDGE_SCRIPT" | jq '.' 2>/dev/null || echo "$CUSTOM_JSON" | "$BRIDGE_SCRIPT"
            echo ""
            ;;
        6)
            CAPTURE_DIR="$BRIDGE_DIR/debug/captured"
            if [ -d "$CAPTURE_DIR" ] && [ "$(ls -A "$CAPTURE_DIR" 2>/dev/null)" ]; then
                echo "Available captures:"
                ls -la "$CAPTURE_DIR/"
                echo ""
                read -p "Enter filename: " filename
                if [ -f "$CAPTURE_DIR/$filename" ]; then
                    run_test "Replay: $filename" "$CAPTURE_DIR/$filename"
                else
                    echo "❌ File not found: $filename"
                fi
            else
                echo "❌ No captures available in: $CAPTURE_DIR"
            fi
            echo ""
            ;;
        7)
            echo "🧪 Testing all library functions..."
            echo ""
            echo "Path Converter:"
            "$BRIDGE_DIR/hooks/lib/path-converter.sh"
            echo ""
            echo "JSON Parser:"
            "$BRIDGE_DIR/hooks/lib/json-parser.sh"
            echo ""
            echo "Debug Helpers:"
            "$BRIDGE_DIR/hooks/lib/debug-helpers.sh"
            echo ""
            echo "Gemini Wrapper:"
            "$BRIDGE_DIR/hooks/lib/gemini-wrapper.sh"
            echo ""
            ;;
        8)
            echo "📋 Recent Debug Logs (last 20 lines):"
            LOG_FILE="$BRIDGE_DIR/logs/debug/$(date +%Y%m%d).log"
            if [ -f "$LOG_FILE" ]; then
                tail -20 "$LOG_FILE"
            else
                echo "No logs found for today"
            fi
            echo ""
            
            echo "📋 Recent Error Logs:"
            ERROR_FILE="$BRIDGE_DIR/logs/debug/errors.log"
            if [ -f "$ERROR_FILE" ]; then
                tail -10 "$ERROR_FILE"
            else
                echo "No errors logged"
            fi
            echo ""
            ;;
        9)
            echo "🧹 Clearing cache and logs..."
            rm -rf "$BRIDGE_DIR/cache/gemini/"*
            rm -rf "$BRIDGE_DIR/logs/debug/"*
            rm -rf "$BRIDGE_DIR/debug/captured/"*
            mkdir -p "$BRIDGE_DIR/cache/gemini"
            mkdir -p "$BRIDGE_DIR/logs/debug"
            mkdir -p "$BRIDGE_DIR/debug/captured"
            echo "✅ Cache and logs cleared"
            echo ""
            ;;
        0)
            echo "👋 Goodbye!"
            break
            ;;
        *)
            echo "❌ Invalid selection"
            echo ""
            ;;
    esac
    
    read -p "Press Enter to continue..." dummy
    echo ""
done