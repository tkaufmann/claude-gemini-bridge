# Claude-Gemini Bridge

🤖 **Intelligent integration between Claude Code and Google Gemini for large-scale code analysis**

The Claude-Gemini Bridge automatically delegates complex code analysis tasks from Claude Code to Google Gemini, combining Claude's reasoning capabilities with Gemini's large context processing power.

[![Tests](https://img.shields.io/badge/tests-passing-brightgreen)](#testing)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](#license)
[![Shell](https://img.shields.io/badge/shell-bash-orange.svg)](#requirements)

## 🚀 Quick Start

```bash
# Clone and install for all projects in one simple process
git clone https://github.com/your-username/claude-gemini-bridge.git
cd claude-gemini-bridge
./install.sh

# IMPORTANT: Restart Claude Code to load the new hooks
# (Hooks are only loaded once at startup)

# Test the installation
./test/test-runner.sh

# Use Claude Code normally - large analyses will automatically use Gemini!
claude "analyze all Python files in this project"
```

### Installation Details

The installer:
- ✅ Works in the current directory (no separate installation location)
- ✅ Automatically merges with existing Claude hooks in `~/.claude/settings.json`
- ✅ Creates backups before making changes
- ✅ Tests all components during installation
- ✅ Provides uninstallation via `./uninstall.sh`

## 📋 Table of Contents

- [Architecture](#-architecture)
- [How It Works](#-how-it-works)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [Usage Examples](#-usage-examples)
- [Testing](#-testing)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

## 🏗️ Architecture

```mermaid
graph TB
    subgraph "Claude Code"
        CC[Claude Code CLI]
        TC[Tool Call]
    end
    
    subgraph "Claude-Gemini Bridge"
        HS[Hook System]
        DE[Decision Engine]
        PC[Path Converter]
        CH[Cache Layer]
    end
    
    subgraph "External APIs"
        GC[Gemini CLI]
        GA[Gemini API]
    end
    
    CC -->|PreToolUse Hook| HS
    HS --> PC
    PC --> DE
    DE -->|Delegate?| CH
    CH -->|Yes| GC
    GC --> GA
    GA -->|Analysis| CH
    CH -->|Response| HS
    HS -->|Result| CC
    DE -->|No| CC
    
    style CC fill:#e1f5fe
    style HS fill:#f3e5f5
    style GC fill:#e8f5e8
    style DE fill:#fff3e0
```

## 🔄 How It Works

The bridge operates through Claude Code's hook system, intelligently deciding when to delegate tasks to Gemini:

```mermaid
sequenceDiagram
    participant User
    participant Claude as Claude Code
    participant Bridge as Gemini Bridge
    participant Gemini as Gemini API
    
    User->>Claude: "Analyze these 20 Python files"
    Claude->>Bridge: PreToolUse Hook (Glob *.py)
    
    Bridge->>Bridge: Convert @ paths to absolute
    Bridge->>Bridge: Count files (20 files)
    Bridge->>Bridge: Calculate total size (500KB)
    Bridge->>Bridge: Estimate tokens (~125k)
    
    alt Token limit exceeded (>50k)
        Bridge->>Bridge: Check if within Gemini limits (<800k)
        Bridge->>Gemini: Analyze 20 files with context
        Gemini->>Bridge: Structured analysis result
        Bridge->>Claude: Replace tool call with Gemini result
        Claude->>User: Comprehensive analysis from Gemini
    else Multi-file Task (≥3 files)
        Bridge->>Bridge: Check if Task operation
        Bridge->>Gemini: Delegate multi-file analysis
        Gemini->>Bridge: Analysis result
        Bridge->>Claude: Replace with Gemini result
        Claude->>User: Multi-file analysis from Gemini
    else Small content (<50k tokens, <3 files)
        Bridge->>Claude: Continue with normal execution
        Claude->>Claude: Process files normally
        Claude->>User: Standard Claude response
    end
```

### Delegation Criteria

The bridge delegates to Gemini when:

- **Token Limit**: Content exceeds ~50k tokens (~200KB, optimized for Claude's 200k context)
- **Multi-File Tasks**: ≥3 files for Task operations (configurable)
- **Safety Limits**: Content must be ≤10MB and ≤800k tokens for Gemini processing
- **File Exclusions**: Automatically excludes sensitive files (*.secret, *.key, *.env, etc.)

## 📦 Installation

### Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed and configured
- [Google Gemini CLI](https://github.com/google/generative-ai-cli) installed
- `jq` for JSON processing
- `bash` 4.0+

### Installation Options

The Claude-Gemini Bridge supports two deployment models:

#### 🌍 Global Installation (Recommended)

For system-wide use across all projects:

```bash
# Clone to a permanent location (one-time setup)
git clone https://github.com/your-username/claude-gemini-bridge.git ~/claude-gemini-bridge
cd ~/claude-gemini-bridge
./install.sh

# IMPORTANT: Restart Claude Code after installation!
```

**Benefits:**
- ✅ Works with all projects automatically
- ✅ Single bridge installation to maintain
- ✅ Easier updates via git pull
- ✅ Global hooks in `~/.claude/settings.json`

#### 📁 Project-Specific Configuration

For project-specific settings without separate installation:

```bash
# Use the same global bridge installation
# No additional cloning needed!

# Create project-specific Claude settings
mkdir -p .claude
cat > .claude/settings.json << 'EOF'
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Read|Grep|Glob|Task",
      "hooks": [{
        "type": "command", 
        "command": "/Users/yourname/claude-gemini-bridge/hooks/gemini-bridge.sh"
      }]
    }]
  }
}
EOF

# Ensure script is executable (usually not needed after git clone)
chmod +x /Users/yourname/claude-gemini-bridge/hooks/gemini-bridge.sh

# Create project-specific environment setup (optional)
cat > project-claude-setup.sh << 'EOF'
export DEBUG_LEVEL=1
export GEMINI_TIMEOUT=60
export DRY_RUN=false
EOF
chmod +x project-claude-setup.sh
```

**Benefits:**
- ✅ Project-specific settings via environment variables
- ✅ Different thresholds per project  
- ✅ Team-shareable setup scripts
- ✅ No duplicate bridge installations
- ✅ Project-local Claude settings override global ones

The installer automatically:
- ✅ Checks all prerequisites
- ✅ Tests Gemini connectivity  
- ✅ Backs up existing Claude settings
- ✅ Intelligently merges hooks into `~/.claude/settings.json`
- ✅ Sets up directory structure and permissions
- ✅ Runs validation tests

### Manual Installation

<details>
<summary>Click to expand manual installation steps</summary>

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/claude-gemini-bridge.git
   cd claude-gemini-bridge
   ```

2. **Set up directory structure:**
   ```bash
   # Files are already in the right place after git clone
   chmod +x hooks/*.sh
   mkdir -p cache/gemini logs/debug debug/captured
   ```

3. **Configure Claude Code hooks:**
   ```bash
   # Add to ~/.claude/settings.json
   {
     "hooks": {
       "PreToolUse": [{
         "matcher": "Read|Grep|Glob|Task",
         "hooks": [{
           "type": "command",
           "command": "/full/path/to/claude-gemini-bridge/hooks/gemini-bridge.sh"
         }]
       }]
     }
   }
   ```

</details>

## ⚙️ Configuration

### Configuration Reference

**Currently Configurable** (edit `hooks/config/debug.conf`):

```bash
# Debug configuration (WORKING)
DEBUG_LEVEL=2                    # 0=off, 1=basic, 2=verbose, 3=trace
CAPTURE_INPUTS=true              # Save hook inputs for analysis
MEASURE_PERFORMANCE=true         # Enable timing measurements
DRY_RUN=false                   # Test mode without Gemini calls

# Gemini API settings (WORKING)
GEMINI_CACHE_TTL=3600           # Cache responses for 1 hour
GEMINI_RATE_LIMIT=1             # 1 second between API calls
GEMINI_TIMEOUT=30               # 30 second API timeout
GEMINI_MAX_FILES=20             # Maximum files per Gemini call

# File security (WORKING)
GEMINI_EXCLUDE_PATTERNS="*.secret|*.key|*.env|*.password|*.token|*.pem|*.p12"

# Automatic maintenance (WORKING)
AUTO_CLEANUP_CACHE=true         # Enable cache cleanup
CACHE_MAX_AGE_HOURS=24          # Clean cache older than 24h
AUTO_CLEANUP_LOGS=true          # Enable log rotation
LOG_MAX_AGE_DAYS=7              # Keep logs for 7 days
```

**Currently Hardcoded** (not configurable):

```bash
# Delegation thresholds (HARDCODED in gemini-bridge.sh)
# Token limit: 50k tokens (~200KB)
# File count: 3 files for Task operations
# Max size: 10MB, 800k tokens for Gemini
```

### Advanced Configuration

**Current Implementation:**
- Single global configuration file: `hooks/config/debug.conf`
- Delegation thresholds are hardcoded in the bridge script
- No project-specific configuration (yet)

## 💡 Usage Examples

### Basic Usage

Simply use Claude Code normally - the bridge works transparently:

```bash
# These commands will automatically use Gemini for large analyses:
claude "analyze all TypeScript files and identify patterns"
claude "find security issues in @src/ directory" 
claude "summarize the architecture of this codebase"
```

### Project-Specific Configuration

#### Configuration Sources

The bridge currently uses a single configuration source:

- **Global Configuration**: `hooks/config/debug.conf` (in bridge installation directory)
- **Runtime Overrides**: Environment variables can override some config values

*Note: Core delegation thresholds are hardcoded and cannot be configured.*

#### Project-Specific Settings

Currently, delegation thresholds (file count, token limits) are hardcoded and cannot be overridden per project. 

**What you CAN configure per project:**

```bash
# project-claude-setup.sh
export DEBUG_LEVEL=3                 # Increase logging for this project
export DRY_RUN=true                  # Disable Gemini calls (testing)
export GEMINI_TIMEOUT=60             # Longer timeout for complex analysis
export CAPTURE_INPUTS=true           # Save inputs for debugging

# Source before using Claude
source ./project-claude-setup.sh
claude "analyze this project"
```

**What you CANNOT configure** (hardcoded):
- File count threshold (always 3 files)
- Token limit (always 50k tokens)
- File size limits (always 10MB max)

### Debug Mode

```bash
# Enable verbose debugging
echo "DEBUG_LEVEL=3" >> ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/config/debug.conf

# Test without calling Gemini
echo "DRY_RUN=true" >> ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/config/debug.conf

# View live logs
tail -f ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/logs/debug/$(date +%Y%m%d).log
```

## 🔍 Verifying Gemini Integration

### How to See if Gemini is Actually Called

#### 1. Real-time Log Monitoring

```bash
# Monitor live logs while using Claude Code
tail -f ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/logs/debug/$(date +%Y%m%d).log

# Filter for Gemini-specific entries
tail -f ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/logs/debug/$(date +%Y%m%d).log | grep -i gemini
```

#### 2. Enable Verbose Debug Output

```bash
# Set maximum debug level
echo "DEBUG_LEVEL=3" >> ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/config/debug.conf

# Now run a Claude command that should trigger Gemini
claude "analyze all Python files in @src/ directory"
```

#### 3. Look for These Log Indicators

**Gemini WILL be called when you see:**
```
[INFO] Processing tool: Task
[DEBUG] File count: 5 (minimum: 3)
[DEBUG] Total file size: 25KB (minimum: 10KB)
[INFO] Delegating to Gemini: files meet criteria
[INFO] Calling Gemini for tool: Task
[INFO] Gemini call successful (2.3s, 5 files)
```

**Gemini will NOT be called when you see:**
```
[INFO] Processing tool: Read
[DEBUG] File count: 1 (minimum: 3)
[DEBUG] Not enough files for Gemini delegation
[INFO] Continuing with normal tool execution
```

#### 4. Force Gemini Delegation for Testing

```bash
# Temporarily lower thresholds to force delegation
echo "MIN_FILES_FOR_GEMINI=1" >> hooks/config/debug.conf
echo "MIN_FILE_SIZE_FOR_GEMINI=1" >> hooks/config/debug.conf

# Test with a simple file
claude "analyze @README.md"

# Reset thresholds afterwards
echo "MIN_FILES_FOR_GEMINI=3" >> hooks/config/debug.conf
echo "MIN_FILE_SIZE_FOR_GEMINI=10240" >> hooks/config/debug.conf
```

#### 5. Check Cache for Gemini Responses

```bash
# List cached Gemini responses
ls -la cache/gemini/

# View a cached response
find cache/gemini/ -name "*" -type f -exec echo "=== {} ===" \; -exec cat {} \; -exec echo \;
```

#### 6. Performance Indicators

Gemini calls typically show:
- **Execution time**: 2-10 seconds (vs. <1s for Claude)
- **Rate limiting**: "Rate limiting: sleeping 1s" messages
- **Cache hits**: "Using cached result" for repeated queries

#### 7. Test with Interactive Tool

```bash
# Use the interactive tester to simulate Gemini calls
${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/test/manual-test.sh

# Choose option 3 (Multi-File Glob) or 2 (Task Search) to trigger Gemini
```

#### 8. Dry Run Mode for Debugging

```bash
# Enable dry run to see decision logic without calling Gemini
echo "DRY_RUN=true" >> ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/config/debug.conf

# Run Claude command - you'll see "DRY RUN: Would call Gemini" instead of actual calls
claude "analyze @src/ @docs/ @test/"

# Disable dry run
sed -i '' '/DRY_RUN=true/d' ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/config/debug.conf
```

## 🧪 Testing

### Automated Testing

```bash
# Run full test suite
${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/test/test-runner.sh

# Test individual components
${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/lib/path-converter.sh
${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/lib/json-parser.sh
${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/lib/gemini-wrapper.sh
```

### Interactive Testing

```bash
# Interactive test tool
${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/test/manual-test.sh
```

The interactive tester provides:
- 🔍 Mock tool call testing
- 📝 Custom JSON input testing  
- 🔄 Replay captured calls
- 📊 Log analysis
- 🧹 Cache management

### Test Architecture

```mermaid
graph TD
    subgraph "Test Suite"
        TR[Test Runner<br/>test-runner.sh]
        MT[Manual Tester<br/>manual-test.sh]
        
        subgraph "Component Tests"
            PC[Path Converter]
            JP[JSON Parser] 
            DH[Debug Helpers]
            GW[Gemini Wrapper]
        end
        
        subgraph "Integration Tests"
            HT[Hook Tests]
            ET[End-to-End]
            CT[Cache Tests]
        end
        
        subgraph "Mock Data"
            MTC[Mock Tool Calls]
            TF[Test Files]
        end
    end
    
    TR --> PC
    TR --> JP
    TR --> DH
    TR --> GW
    TR --> HT
    TR --> ET
    TR --> CT
    
    MT --> MTC
    MT --> TF
    
    style TR fill:#e1f5fe
    style MT fill:#f3e5f5
```

## 🐛 Troubleshooting

### Common Issues

<details>
<summary><strong>Hook not executing</strong></summary>

**Symptoms:** Claude behaves normally, Gemini never called

**Solutions:**
```bash
# Check hook configuration
cat ~/.claude/settings.local.json | jq '.hooks'

# Test hook manually
echo '{"tool":"Read","parameters":{"file_path":"test.txt"},"context":{}}' | \
  ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/gemini-bridge.sh

# Verify file permissions
ls -la ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/gemini-bridge.sh
```
</details>

<details>
<summary><strong>Gemini API errors</strong></summary>

**Symptoms:** "Gemini initialization failed" errors

**Solutions:**
```bash
# Test Gemini CLI directly
echo "test" | gemini -p "Say hello"

# Check API key
echo $GEMINI_API_KEY

# Verify rate limits
grep -i "rate limit" ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/logs/debug/*.log
```
</details>

<details>
<summary><strong>Cache issues</strong></summary>

**Symptoms:** Outdated responses, cache errors

**Solutions:**
```bash
# Clear cache
rm -rf ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/cache/gemini/*

# Check cache settings
grep CACHE ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/config/debug.conf

# Monitor cache usage
du -sh ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/cache/
```
</details>

### Debug Workflow

```mermaid
flowchart TD
    Start([Issue Reported]) --> Reproduce{Can Reproduce?}
    
    Reproduce -->|Yes| Logs[Check Logs]
    Reproduce -->|No| More[Request More Info]
    
    Logs --> Level{Debug Level}
    Level -->|Low| Increase[Set DEBUG_LEVEL=3]
    Level -->|High| Analyze[Analyze Logs]
    
    Increase --> Reproduce
    Analyze --> Component{Component Issue?}
    
    Component -->|Yes| Unit[Run Unit Tests]
    Component -->|No| Integration[Run Integration Tests]
    
    Unit --> Fix[Fix Component]
    Integration --> System[Check System State]
    
    Fix --> Test[Test Fix]
    System --> Config[Check Configuration]
    
    Test --> PR[Submit PR]
    Config --> Fix
    
    More --> Start
    
    style Start fill:#e8f5e8
    style PR fill:#e1f5fe
    style Fix fill:#fff3e0
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Setup

```bash
# Fork and clone
git clone https://github.com/your-username/claude-gemini-bridge.git
cd claude-gemini-bridge

# Run tests before committing
./test/test-runner.sh
```

### Code Standards

- **Shell Scripts**: Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- **Comments**: English only, include ABOUTME headers
- **Testing**: All functions must have unit tests
- **Documentation**: Update README for any API changes

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Inspired by**: Reddit user's implementation of Claude-Gemini integration
- **Claude Code Team**: For the excellent hook system
- **Google**: For the Gemini API and CLI tools
- **Community**: For testing and feedback

## 📊 Project Stats

```mermaid
pie title Component Distribution
    "Hook System" : 35
    "Path Processing" : 20
    "Caching" : 15
    "Debug/Logging" : 15
    "Testing" : 10
    "Documentation" : 5
```

---

<div align="center">

**Made with ❤️ for the Claude Code community**

[Report Bug](https://github.com/your-username/claude-gemini-bridge/issues) • 
[Request Feature](https://github.com/your-username/claude-gemini-bridge/issues) • 
[View Documentation](./docs/)

</div>