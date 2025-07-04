#!/bin/bash
# ABOUTME: Simplified installer for Claude-Gemini Bridge that works in current directory

echo "🚀 Claude-Gemini Bridge Installer"
echo "=================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SETTINGS_FILE="$HOME/.claude/settings.json"
BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)

# Log function
log() {
    local level="$1"
    local message="$2"
    
    case $level in
        "info") echo -e "${GREEN}✅${NC} $message" ;;
        "warn") echo -e "${YELLOW}⚠️${NC}  $message" ;;
        "error") echo -e "${RED}❌${NC} $message" ;;
        "debug") echo -e "${BLUE}🔍${NC} $message" ;;
    esac
}

# Error handling
error_exit() {
    log "error" "$1"
    echo ""
    echo "💥 Installation aborted!"
    echo "For help see: $SCRIPT_DIR/docs/TROUBLESHOOTING.md"
    exit 1
}

# Check prerequisites
check_requirements() {
    log "info" "Checking prerequisites..."
    
    # Claude CLI - check multiple ways
    local claude_found=false
    local claude_location=""
    
    # First check if claude command exists (handles PATH and aliases)
    if which claude &> /dev/null; then
        claude_found=true
        claude_location=$(which claude)
    # Check common installation locations
    elif [ -x "$HOME/.claude/local/claude" ]; then
        claude_found=true
        claude_location="$HOME/.claude/local/claude"
    elif [ -x "/usr/local/bin/claude" ]; then
        claude_found=true
        claude_location="/usr/local/bin/claude"
    elif [ -x "/opt/homebrew/bin/claude" ]; then
        claude_found=true
        claude_location="/opt/homebrew/bin/claude"
    fi
    
    if [ "$claude_found" = false ]; then
        error_exit "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
    fi
    log "debug" "Claude CLI found: $claude_location"
    
    # Gemini CLI
    if ! command -v gemini &> /dev/null; then
        error_exit "Gemini CLI not found. Visit: https://github.com/google-gemini/gemini-cli"
    fi
    log "debug" "Gemini CLI found: $(which gemini)"
    
    # jq for JSON processing
    if ! command -v jq &> /dev/null; then
        log "warn" "jq not found. Install with:"
        echo "  macOS: brew install jq"
        echo "  Linux: sudo apt-get install jq"
        error_exit "jq is required for JSON processing"
    fi
    log "debug" "jq found: $(which jq)"
    
    log "info" "All prerequisites met"
}

# Create directory structure if needed
create_directories() {
    log "info" "Creating directory structure..."
    
    mkdir -p "$SCRIPT_DIR"/{cache/gemini,logs/debug,debug/captured}
    
    if [ $? -eq 0 ]; then
        log "info" "Directory structure ready"
    else
        error_exit "Error creating directory structure"
    fi
}

# Test Gemini connection
test_gemini_connection() {
    log "info" "Testing Gemini connection..."
    
    # Simple test call - just check if Gemini CLI works at all
    local test_result=$(echo "1+1" | gemini -p "What is the result?" 2>&1)
    local exit_code=$?
    
    # Only check exit code and that we got SOME response
    if [ $exit_code -eq 0 ] && [ -n "$test_result" ] && [ ${#test_result} -gt 0 ]; then
        log "info" "Gemini connection tested successfully"
        log "debug" "Gemini CLI is working and responding"
    else
        log "warn" "Gemini test failed. API key configured?"
        log "debug" "Gemini exit code: $exit_code"
        log "debug" "Gemini output: $test_result"
        echo ""
        echo "Common issues:"
        echo "  - Missing API key: export GEMINI_API_KEY=your_key"
        echo "  - Authentication problem with Gemini CLI"
        echo "  - Network connectivity issues"
        echo ""
        read -p "Continue anyway? (y/N): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            error_exit "Gemini configuration required. See Gemini CLI documentation."
        fi
    fi
}

# Intelligent hook merging for settings.json
configure_claude_hooks() {
    log "info" "Configuring Claude Code Hooks..."
    
    # Create .claude directory if not exists
    mkdir -p "$(dirname "$CLAUDE_SETTINGS_FILE")"
    
    # Backup existing settings
    if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
        cp "$CLAUDE_SETTINGS_FILE" "${CLAUDE_SETTINGS_FILE}.backup.${BACKUP_SUFFIX}"
        log "info" "Backup created: ${CLAUDE_SETTINGS_FILE}.backup.${BACKUP_SUFFIX}"
    fi
    
    # Our hook configuration
    local hook_command="$SCRIPT_DIR/hooks/gemini-bridge.sh"
    local hook_matcher="Read|Grep|Glob|Task"
    
    # Check for any existing Claude-Gemini Bridge installation
    if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
        if grep -q "gemini-bridge.sh" "$CLAUDE_SETTINGS_FILE" 2>/dev/null; then
            log "warn" "Existing Claude-Gemini Bridge installation detected!"
            
            # Show current hook path
            local current_path=$(grep -o '[^"]*gemini-bridge.sh' "$CLAUDE_SETTINGS_FILE" 2>/dev/null | head -1)
            if [ -n "$current_path" ]; then
                log "debug" "Current hook path: $current_path"
                log "debug" "New hook path: $hook_command"
            fi
            
            # Ask user what to do
            echo ""
            echo "Options:"
            echo "1) Update hook path to current location (recommended)"
            echo "2) Remove old hook and add new one"
            echo "3) Cancel installation"
            echo ""
            read -p "Choose option (1-3): " update_choice
            
            case $update_choice in
                1)
                    log "info" "Updating hook path to current location..."
                    update_existing_hook "$hook_command" "$hook_matcher"
                    return 0
                    ;;
                2)
                    log "info" "Removing old hook and installing new one..."
                    remove_existing_hooks
                    # Continue with normal installation below
                    ;;
                3|*)
                    log "info" "Installation cancelled"
                    exit 0
                    ;;
            esac
        fi
    fi
    
    # Merge with existing configuration or create new
    if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
        log "debug" "Merging with existing settings..."
        
        # Add our hook to existing PreToolUse array
        local merged_config=$(jq --arg cmd "$hook_command" --arg matcher "$hook_matcher" '
            .hooks.PreToolUse = (.hooks.PreToolUse // []) + [{
                "matcher": $matcher,
                "hooks": [{
                    "type": "command",
                    "command": $cmd
                }]
            }]' "$CLAUDE_SETTINGS_FILE" 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$merged_config" ]; then
            echo "$merged_config" > "$CLAUDE_SETTINGS_FILE"
            log "info" "Hook added to existing settings"
        else
            log "warn" "Error merging configuration. Creating new settings file."
            create_new_settings_file "$hook_command" "$hook_matcher"
        fi
    else
        log "debug" "Creating new settings file..."
        create_new_settings_file "$hook_command" "$hook_matcher"
    fi
    
    log "debug" "Hook configured: $hook_command"
}

# Update existing hook path
update_existing_hook() {
    local hook_command="$1"
    local hook_matcher="$2"
    
    local updated_config=$(jq --arg cmd "$hook_command" --arg matcher "$hook_matcher" '
        .hooks.PreToolUse = (.hooks.PreToolUse // []) | 
        .hooks.PreToolUse |= map(
            if .hooks[]?.command? and (.hooks[]?.command | contains("gemini-bridge.sh"))
            then (.hooks[0].command = $cmd | .matcher = $matcher)
            else . end
        )' "$CLAUDE_SETTINGS_FILE" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$updated_config" ]; then
        echo "$updated_config" > "$CLAUDE_SETTINGS_FILE"
        log "info" "Hook path updated successfully"
    else
        log "error" "Failed to update hook path"
        exit 1
    fi
}

# Remove existing gemini-bridge hooks
remove_existing_hooks() {
    log "debug" "Removing existing Claude-Gemini Bridge hooks..."
    
    local cleaned_config=$(jq '
        .hooks.PreToolUse = (.hooks.PreToolUse // []) | 
        .hooks.PreToolUse |= map(
            select(.hooks[]?.command? and (.hooks[]?.command | contains("gemini-bridge.sh")) | not)
        ) |
        if (.hooks.PreToolUse | length) == 0 then 
            del(.hooks.PreToolUse) 
        else . end |
        if (.hooks | length) == 0 then 
            del(.hooks) 
        else . end
    ' "$CLAUDE_SETTINGS_FILE" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$cleaned_config" ]; then
        echo "$cleaned_config" > "$CLAUDE_SETTINGS_FILE"
        log "info" "Existing hooks removed"
    else
        log "warn" "Could not remove existing hooks automatically"
    fi
}

# Create new settings file
create_new_settings_file() {
    local hook_command="$1"
    local hook_matcher="$2"
    
    cat > "$CLAUDE_SETTINGS_FILE" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "$hook_matcher",
        "hooks": [
          {
            "type": "command",
            "command": "$hook_command"
          }
        ]
      }
    ]
  }
}
EOF
    log "info" "New Claude settings created"
}

# Set permissions
set_permissions() {
    log "info" "Setting file permissions..."
    
    # Make all shell scripts executable
    find "$SCRIPT_DIR" -name "*.sh" -exec chmod +x {} \;
    
    log "info" "Permissions set"
}

# Run basic tests
run_basic_tests() {
    log "info" "Running basic tests..."
    
    # Test library functions
    local lib_tests=("path-converter.sh" "json-parser.sh" "debug-helpers.sh" "gemini-wrapper.sh")
    local test_failures=0
    
    for test in "${lib_tests[@]}"; do
        if [ -f "$SCRIPT_DIR/hooks/lib/$test" ]; then
            if "$SCRIPT_DIR/hooks/lib/$test" >/dev/null 2>&1; then
                log "debug" "$test: OK"
            else
                log "warn" "$test: Tests failed"
                test_failures=$((test_failures + 1))
            fi
        else
            log "warn" "File not found: $SCRIPT_DIR/hooks/lib/$test"
            test_failures=$((test_failures + 1))
        fi
    done
    
    # Test hook script with mock input
    local test_json='{"tool_name":"Read","tool_input":{"file_path":"test.txt"},"session_id":"test","transcript_path":"/tmp/test"}'
    local hook_result=$(echo "$test_json" | "$SCRIPT_DIR/hooks/gemini-bridge.sh" 2>/dev/null)
    
    if echo "$hook_result" | jq empty 2>/dev/null; then
        log "info" "Hook script test successful"
    else
        log "warn" "Hook script test failed, but installation continued"
        log "debug" "Hook output: $hook_result"
        test_failures=$((test_failures + 1))
    fi
    
    if [ $test_failures -eq 0 ]; then
        log "info" "All tests passed"
    else
        log "warn" "$test_failures test(s) failed - installation may need troubleshooting"
    fi
}

# Show installation summary
show_summary() {
    echo ""
    echo "🎉 Installation completed successfully!"
    echo "======================================="
    echo ""
    echo "📁 Installation Directory: $SCRIPT_DIR"
    echo "⚙️  Claude Settings: $CLAUDE_SETTINGS_FILE"
    echo ""
    echo "🧪 Next steps:"
    echo ""
    echo "   1. **RESTART Claude Code** (hooks are loaded at startup)"
    echo "      Exit Claude Code completely and restart it"
    echo ""
    echo "   2. Test the installation:"
    echo "      $SCRIPT_DIR/test/test-runner.sh"
    echo ""
    echo "   3. Use Claude Code normally:"
    echo "      Large file analyses will automatically use Gemini!"
    echo ""
    echo "📚 Documentation:"
    echo "   - README: $SCRIPT_DIR/README.md"
    echo "   - Troubleshooting: $SCRIPT_DIR/docs/TROUBLESHOOTING.md"
    echo ""
    echo "🔧 Configuration:"
    echo "   - Debug level: $SCRIPT_DIR/hooks/config/debug.conf"
    echo "   - Logs: $SCRIPT_DIR/logs/debug/"
    echo ""
    echo "💡 Debug commands:"
    echo "   - View logs: tail -f $SCRIPT_DIR/logs/debug/\$(date +%Y%m%d).log"
    echo "   - Clear cache: rm -rf $SCRIPT_DIR/cache/gemini/*"
    echo "   - Uninstall: $SCRIPT_DIR/uninstall.sh"
    echo ""
    echo "🚨 IMPORTANT: You must restart Claude Code for the hooks to take effect!"
}

# Main installation
main() {
    echo "This script configures the Claude-Gemini Bridge in the current directory."
    echo "Installation directory: $SCRIPT_DIR"
    echo ""
    read -p "Continue with installation? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "info" "Installation cancelled"
        exit 0
    fi
    
    echo ""
    
    # Installation steps
    check_requirements
    create_directories
    test_gemini_connection
    configure_claude_hooks
    set_permissions
    run_basic_tests
    
    show_summary
}

# Execute script
main "$@"
