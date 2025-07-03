#!/bin/bash
# ABOUTME: Uninstaller for Claude-Gemini Bridge - removes hooks and optionally cleans up data

echo "🗑️  Claude-Gemini Bridge Uninstaller"
echo "===================================="
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
    echo "💥 Uninstallation failed!"
    exit 1
}

# Check if jq is available
check_jq() {
    if ! command -v jq &> /dev/null; then
        log "warn" "jq not found - will use fallback method for settings removal"
        return 1
    fi
    return 0
}

# Remove hook from Claude settings
remove_claude_hooks() {
    log "info" "Removing Claude Code Hooks..."
    
    if [ ! -f "$CLAUDE_SETTINGS_FILE" ]; then
        log "info" "No Claude settings file found - nothing to remove"
        return 0
    fi
    
    # Backup existing settings
    cp "$CLAUDE_SETTINGS_FILE" "${CLAUDE_SETTINGS_FILE}.backup.${BACKUP_SUFFIX}"
    log "info" "Backup created: ${CLAUDE_SETTINGS_FILE}.backup.${BACKUP_SUFFIX}"
    
    # Check if our hook exists
    local hook_command="$SCRIPT_DIR/hooks/gemini-bridge.sh"
    if ! grep -q "gemini-bridge.sh" "$CLAUDE_SETTINGS_FILE" 2>/dev/null; then
        log "info" "No Claude-Gemini Bridge hooks found in settings"
        return 0
    fi
    
    if check_jq; then
        # Use jq to remove our hook
        local updated_config=$(jq '
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
        
        if [ $? -eq 0 ] && [ -n "$updated_config" ]; then
            echo "$updated_config" > "$CLAUDE_SETTINGS_FILE"
            log "info" "Hook removed from Claude settings"
        else
            log "warn" "Could not remove hook with jq - using fallback method"
            remove_hook_fallback
        fi
    else
        remove_hook_fallback
    fi
}

# Fallback method to remove hook (without jq)
remove_hook_fallback() {
    log "debug" "Using fallback method to remove hook..."
    
    # Create a temporary file without our hook
    local temp_file=$(mktemp)
    local in_our_hook=false
    local brace_count=0
    
    while IFS= read -r line; do
        # Check if we're entering our hook section
        if [[ "$line" =~ gemini-bridge\.sh ]]; then
            in_our_hook=true
            # Skip this entire hook object
            continue
        fi
        
        # If we're in our hook, count braces to know when we're out
        if [ "$in_our_hook" = true ]; then
            # Count opening and closing braces
            local open_braces=$(echo "$line" | tr -cd '{' | wc -c)
            local close_braces=$(echo "$line" | tr -cd '}' | wc -c)
            brace_count=$((brace_count + open_braces - close_braces))
            
            # If brace count is back to 0, we're out of our hook
            if [ $brace_count -le 0 ]; then
                in_our_hook=false
            fi
            continue
        fi
        
        # If we're not in our hook, keep the line
        echo "$line" >> "$temp_file"
    done < "$CLAUDE_SETTINGS_FILE"
    
    # Replace the original file
    mv "$temp_file" "$CLAUDE_SETTINGS_FILE"
    log "info" "Hook removed using fallback method"
}

# Clean up data
cleanup_data() {
    local cleanup_choice="$1"
    
    case $cleanup_choice in
        "all")
            log "info" "Removing all data (cache, logs, captured inputs)..."
            rm -rf "$SCRIPT_DIR/cache" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/debug" 2>/dev/null
            log "info" "All data removed"
            ;;
        "cache")
            log "info" "Removing cache only..."
            rm -rf "$SCRIPT_DIR/cache" 2>/dev/null
            log "info" "Cache removed"
            ;;
        "logs")
            log "info" "Removing logs only..."
            rm -rf "$SCRIPT_DIR/logs" "$SCRIPT_DIR/debug" 2>/dev/null
            log "info" "Logs removed"
            ;;
        "none")
            log "info" "Keeping all data files"
            ;;
    esac
}

# Show uninstallation summary
show_summary() {
    echo ""
    echo "🎉 Uninstallation completed!"
    echo "============================"
    echo ""
    echo "✅ Claude-Gemini Bridge hooks removed from: $CLAUDE_SETTINGS_FILE"
    echo "📁 Bridge directory remains: $SCRIPT_DIR"
    echo ""
    echo "📚 Next steps:"
    echo ""
    echo "   1. **RESTART Claude Code** to apply hook changes"
    echo ""
    echo "   2. Optional: Remove the bridge directory manually:"
    echo "      rm -rf $SCRIPT_DIR"
    echo ""
    echo "   3. If needed, restore settings backup:"
    echo "      cp ${CLAUDE_SETTINGS_FILE}.backup.${BACKUP_SUFFIX} $CLAUDE_SETTINGS_FILE"
    echo ""
    echo "💡 The Claude-Gemini Bridge can be reinstalled anytime by running:"
    echo "    git clone [repository] && cd claude-gemini-bridge && ./install.sh"
}

# Main uninstallation
main() {
    echo "This script removes Claude-Gemini Bridge hooks from Claude Code settings."
    echo "Bridge directory: $SCRIPT_DIR"
    echo ""
    
    # Ask what to clean up
    echo "What would you like to clean up?"
    echo ""
    echo "1) Remove hooks only (keep cache and logs)"
    echo "2) Remove hooks + cache (keep logs)"
    echo "3) Remove hooks + logs (keep cache)"
    echo "4) Remove hooks + all data (cache, logs, captured inputs)"
    echo "5) Cancel"
    echo ""
    read -p "Choose option (1-5): " choice
    
    case $choice in
        1)
            cleanup_option="none"
            ;;
        2)
            cleanup_option="cache"
            ;;
        3)
            cleanup_option="logs"
            ;;
        4)
            cleanup_option="all"
            ;;
        5)
            log "info" "Uninstallation cancelled"
            exit 0
            ;;
        *)
            log "warn" "Invalid choice. Using option 1 (hooks only)"
            cleanup_option="none"
            ;;
    esac
    
    echo ""
    read -p "Continue with uninstallation? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "info" "Uninstallation cancelled"
        exit 0
    fi
    
    echo ""
    
    # Uninstallation steps
    remove_claude_hooks
    cleanup_data "$cleanup_option"
    
    show_summary
}

# Execute script
main "$@"