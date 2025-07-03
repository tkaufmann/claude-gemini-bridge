#!/bin/bash
# ABOUTME: Fully automated installer for Claude-Gemini Bridge

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
INSTALL_DIR="${CLAUDE_GEMINI_BRIDGE_DIR:-$HOME/.claude-gemini-bridge}"
CLAUDE_SETTINGS_FILE="$HOME/.claude/settings.local.json"
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
    echo "For help see: $INSTALL_DIR/docs/TROUBLESHOOTING.md"
    exit 1
}

# Check prerequisites
check_requirements() {
    log "info" "Checking prerequisites..."
    
    # Claude CLI
    if ! command -v claude &> /dev/null; then
        error_exit "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
    fi
    log "debug" "Claude CLI found: $(which claude)"
    
    # Gemini CLI
    if ! command -v gemini &> /dev/null; then
        error_exit "Gemini CLI not found. Visit: https://github.com/google/generative-ai-cli"
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
    
    # bc for calculations (optional)
    if ! command -v bc &> /dev/null; then
        log "warn" "bc not found (optional). Performance measurements might not work."
    fi
    
    log "info" "All prerequisites met"
}

# Check if already installed
check_existing_installation() {
    if [ -d "$INSTALL_DIR" ]; then
        log "warn" "Existing installation found in: $INSTALL_DIR"
        echo ""
        read -p "Do you want to overwrite the existing installation? (y/N): " overwrite
        
        if [[ "$overwrite" =~ ^[Yy]$ ]]; then
            log "info" "Creating backup of existing installation..."
            mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.${BACKUP_SUFFIX}"
            log "info" "Backup created: ${INSTALL_DIR}.backup.${BACKUP_SUFFIX}"
        else
            log "info" "Installation cancelled. Use existing installation or remove it manually."
            exit 0
        fi
    fi
}

# Create directory structure
create_directories() {
    log "info" "Creating directory structure..."
    
    mkdir -p "$INSTALL_DIR"/{hooks/{lib,config},cache/gemini,logs/debug,test/mock-tool-calls,debug/captured,docs}
    
    if [ $? -eq 0 ]; then
        log "info" "Directory structure created"
    else
        error_exit "Error creating directory structure"
    fi
}

# Copy files to installation directory
copy_files() {
    log "info" "Copying files to installation directory..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Copy all files except .git and temporary files
    cp -r "$script_dir"/* "$INSTALL_DIR/" 2>/dev/null || true
    
    # Ensure we don't copy .git directory
    rm -rf "$INSTALL_DIR/.git" 2>/dev/null || true
    
    # Verify critical files were copied
    if [ ! -f "$INSTALL_DIR/hooks/gemini-bridge.sh" ]; then
        error_exit "Failed to copy main hook script"
    fi
    
    if [ ! -d "$INSTALL_DIR/hooks/lib" ]; then
        error_exit "Failed to copy library files"
    fi
    
    log "info" "Files copied successfully"
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

# Configure Claude Code Hooks
configure_claude_hooks() {
    log "info" "Configuring Claude Code Hooks..."
    
    # Create .claude directory if not exists
    mkdir -p "$(dirname "$CLAUDE_SETTINGS_FILE")"
    
    # Backup existing settings
    if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
        cp "$CLAUDE_SETTINGS_FILE" "${CLAUDE_SETTINGS_FILE}.backup.${BACKUP_SUFFIX}"
        log "info" "Backup created: ${CLAUDE_SETTINGS_FILE}.backup.${BACKUP_SUFFIX}"
    fi
    
    # Hook configuration
    local hook_config='{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Grep|Glob|Task",
        "hooks": [
          {
            "type": "command",
            "command": "'$INSTALL_DIR'/hooks/gemini-bridge.sh"
          }
        ]
      }
    ]
  }
}'
    
    # Merge with existing settings or create new
    if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
        # Merge with existing configuration
        local merged_config=$(jq -s '.[0] * .[1]' "$CLAUDE_SETTINGS_FILE" <(echo "$hook_config") 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$merged_config" ]; then
            echo "$merged_config" > "$CLAUDE_SETTINGS_FILE"
            log "info" "Hook configuration added to existing settings"
        else
            log "warn" "Error merging configuration. Creating new settings file."
            echo "$hook_config" > "$CLAUDE_SETTINGS_FILE"
        fi
    else
        # Create new settings file
        echo "$hook_config" > "$CLAUDE_SETTINGS_FILE"
        log "info" "New Claude settings created"
    fi
    
    log "debug" "Hook configured for: $INSTALL_DIR/hooks/gemini-bridge.sh"
}

# Set permissions
set_permissions() {
    log "info" "Setting file permissions..."
    
    # Make all shell scripts executable
    find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
    
    # Special permissions for hook script
    chmod +x "$INSTALL_DIR/hooks/gemini-bridge.sh"
    
    log "info" "Permissions set"
}

# Run basic tests
run_basic_tests() {
    log "info" "Running basic tests..."
    
    # Test library functions
    local lib_tests=("path-converter.sh" "json-parser.sh" "debug-helpers.sh" "gemini-wrapper.sh")
    
    for test in "${lib_tests[@]}"; do
        if [ -f "$INSTALL_DIR/hooks/lib/$test" ]; then
            if "$INSTALL_DIR/hooks/lib/$test" >/dev/null 2>&1; then
                log "debug" "$test: OK"
            else
                log "warn" "$test: Tests failed"
            fi
        else
            error_exit "File not found: $INSTALL_DIR/hooks/lib/$test"
        fi
    done
    
    # Test hook script with mock input
    local test_json='{"tool":"Read","parameters":{"file_path":"test.txt"},"context":{}}'
    local hook_result=$(echo "$test_json" | "$INSTALL_DIR/hooks/gemini-bridge.sh" 2>/dev/null)
    
    if echo "$hook_result" | jq empty 2>/dev/null; then
        log "info" "Hook script test successful"
    else
        log "warn" "Hook script test failed, but installation continued"
        log "debug" "Hook output: $hook_result"
    fi
}

# Create documentation
create_documentation() {
    log "info" "Creating documentation..."
    
    # Create README
    cat > "$INSTALL_DIR/README.md" << 'EOF'
# Claude-Gemini Bridge

Automatische Integration zwischen Claude Code und Google Gemini für große Code-Analysen.

## Quick Start

1. **Teste die Installation:**
   ```bash
   $INSTALL_DIR/test/test-runner.sh
   ```

2. **Interaktive Tests:**
   ```bash
   $INSTALL_DIR/test/manual-test.sh
   ```

3. **Nutze Claude Code normal** - große Analysen werden automatisch an Gemini delegiert!

## Konfiguration

- **Debug-Level ändern:** Editiere `hooks/config/debug.conf`
- **Schwellwerte anpassen:** Editiere `MIN_FILES_FOR_GEMINI` in `debug.conf`
- **Cache leeren:** `rm -rf cache/gemini/*`

## Logs

- **Debug:** `tail -f logs/debug/$(date +%Y%m%d).log`
- **Errors:** `tail -f logs/debug/errors.log`
- **Captured Inputs:** `ls debug/captured/`

## Deinstallation

```bash
# Hook entfernen
jq 'del(.hooks)' ~/.claude/settings.local.json > /tmp/claude_settings && mv /tmp/claude_settings ~/.claude/settings.local.json

# Bridge entfernen
rm -rf $INSTALL_DIR
```

## Support

- **Troubleshooting:** `docs/TROUBLESHOOTING.md`
- **Manuelle Tests:** `test/manual-test.sh`
- **Logs prüfen:** `test/manual-test.sh` → Option 8
EOF

    log "info" "README.md created"
}

# Show installation summary
show_summary() {
    echo ""
    echo "🎉 Installation completed successfully!"
    echo "======================================="
    echo ""
    echo "📁 Installation Directory: $INSTALL_DIR"
    echo "⚙️  Claude Settings: $CLAUDE_SETTINGS_FILE"
    echo ""
    echo "🧪 Next steps:"
    echo "   1. Test the installation:"
    echo "      $INSTALL_DIR/test/test-runner.sh"
    echo ""
    echo "   2. Interactive tests:"
    echo "      $INSTALL_DIR/test/manual-test.sh"
    echo ""
    echo "   3. Use Claude Code normally - large analyses will be automatically delegated to Gemini!"
    echo ""
    echo "📚 Documentation:"
    echo "   - README: $INSTALL_DIR/README.md"
    echo "   - Troubleshooting: $INSTALL_DIR/docs/TROUBLESHOOTING.md"
    echo ""
    echo "🔧 Configuration:"
    echo "   - Debug level: $INSTALL_DIR/hooks/config/debug.conf"
    echo "   - Logs: $INSTALL_DIR/logs/debug/"
    echo ""
    echo "💡 Debug commands:"
    echo "   - View logs: tail -f $INSTALL_DIR/logs/debug/\$(date +%Y%m%d).log"
    echo "   - Clear cache: rm -rf $INSTALL_DIR/cache/gemini/*"
    echo "   - Run tests: $INSTALL_DIR/test/test-runner.sh"
}

# Main installation
main() {
    echo "This script installs the Claude-Gemini Bridge globally for all Claude Code projects."
    echo "Installation directory: $INSTALL_DIR"
    echo ""
    echo "To install to a different location, set CLAUDE_GEMINI_BRIDGE_DIR:"
    echo "  export CLAUDE_GEMINI_BRIDGE_DIR=/path/to/your/directory"
    echo ""
    read -p "Continue with installation? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "info" "Installation cancelled"
        exit 0
    fi
    
    echo ""
    
    # Installation steps
    check_requirements
    check_existing_installation
    create_directories
    copy_files
    test_gemini_connection
    configure_claude_hooks
    set_permissions
    run_basic_tests
    create_documentation
    
    show_summary
}

# Execute script
main "$@"