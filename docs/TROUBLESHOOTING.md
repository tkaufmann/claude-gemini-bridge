# Troubleshooting Guide for Claude-Gemini Bridge

## 🔧 Common Problems and Solutions

### Installation & Setup

#### Hook not executing
**Symptom:** Claude behaves normally, but Gemini is never called

**Solution steps:**
1. Check Claude Settings:
   ```bash
   cat ~/.claude/settings.json
   ```
   
2. Test hook manually:
   ```bash
   echo '{"tool_name":"Read","tool_input":{"file_path":"test.txt"},"session_id":"test"}' | ./hooks/gemini-bridge.sh
   ```

3. Check permissions:
   ```bash
   ls -la hooks/gemini-bridge.sh
   # Should be executable (x-flag)
   ```

4. Check hook configuration:
   ```bash
   jq '.hooks' ~/.claude/settings.json
   ```

**Solution:** Run re-installation:
```bash
./install.sh
```

---

#### "command not found: jq"
**Symptom:** Error when running scripts

**Solution:**
- **macOS:** `brew install jq`
- **Linux:** `sudo apt-get install jq`
- **Alternative:** Use the installer, which checks jq dependencies

---

#### "command not found: gemini"
**Symptom:** Bridge cannot find Gemini

**Solution steps:**
1. Check Gemini installation:
   ```bash
   which gemini
   gemini --version
   ```

2. Test Gemini manually:
   ```bash
   echo "Test" | gemini -p "Say hello"
   ```

3. Check PATH:
   ```bash
   echo $PATH
   ```

**Solution:** Install Gemini CLI or add to PATH

---

### Gemini Integration

#### Gemini not responding
**Symptom:** Hook runs, but Gemini doesn't return responses

**Debug steps:**
1. Enable verbose logging:
   ```bash
   # In hooks/config/debug.conf
   DEBUG_LEVEL=3
   ```

2. Check Gemini logs:
   ```bash
   tail -f logs/debug/$(date +%Y%m%d).log | grep -i gemini
   ```

3. Test Gemini API key:
   ```bash
   gemini "test" -p "Hello"
   ```

**Common causes:**
- Missing or invalid API key
- Rate limiting reached
- Network problems
- Gemini service unavailable

---

#### "Rate limiting: sleeping Xs"
**Symptom:** Bridge waits between calls

**Explanation:** Normal! Prevents API overload.

**Adjust:**
```bash
# In debug.conf
GEMINI_RATE_LIMIT=0.5  # Reduce to 0.5 seconds
```

---

#### Cache problems
**Symptom:** Outdated responses from Gemini

**Solution:**
```bash
# Clear cache completely
rm -rf cache/gemini/*

# Or reduce cache TTL (in debug.conf)
GEMINI_CACHE_TTL=1800  # 30 minutes instead of 1 hour
```

---

### Path Conversion

#### @ paths not converted
**Symptom:** Gemini cannot find files

**Debug:**
1. Test path conversion in isolation:
   ```bash
   cd hooks/lib
   source path-converter.sh
   convert_claude_paths "@src/main.py" "/Users/tim/project"
   ```

2. Check working directory in logs:
   ```bash
   grep "Working directory" logs/debug/$(date +%Y%m%d).log
   ```

**Common causes:**
- Missing working_directory in tool call
- Relative paths without @ prefix
- Incorrect directory structures

---

### Performance & Behavior

#### Gemini called too often
**Symptom:** Every small Read command goes to Gemini

**Adjustments in debug.conf:**
```bash
MIN_FILES_FOR_GEMINI=5        # Increase minimum file count
CLAUDE_TOKEN_LIMIT=100000     # Increase token threshold
```

---

#### Gemini never called
**Symptom:** Even large analyses don't go to Gemini

**Debug:**
1. Enable DRY_RUN mode:
   ```bash
   # In debug.conf
   DRY_RUN=true
   ```

2. Check decision logic:
   ```bash
   grep "should_delegate_to_gemini" logs/debug/$(date +%Y%m%d).log
   ```

**Adjustments:**
```bash
MIN_FILES_FOR_GEMINI=1        # Reduce thresholds
CLAUDE_TOKEN_LIMIT=10000      # Lower token limit
```

---

## 🔍 Debug Workflow

### 1. Reproduce problem
```bash
# Enable input capturing
# In debug.conf: CAPTURE_INPUTS=true

# Run problematic Claude command
# Input will be automatically saved
```

### 2. Analyze logs
```bash
# Current debug logs
tail -f logs/debug/$(date +%Y%m%d).log

# Error logs
tail -f logs/debug/errors.log

# All logs of the day
less logs/debug/$(date +%Y%m%d).log
```

### 3. Test in isolation
```bash
# Interactive tests
./test/manual-test.sh

# Automated tests
./test/test-runner.sh

# Replay saved inputs
ls debug/captured/
cat debug/captured/FILENAME.json | ./hooks/gemini-bridge.sh
```

### 4. Step-by-step debugging
```bash
# Highest debug level
# In debug.conf: DEBUG_LEVEL=3

# Dry-run mode (no actual Gemini call)
# In debug.conf: DRY_RUN=true

# Test individual library functions
./hooks/lib/path-converter.sh
./hooks/lib/json-parser.sh
./hooks/lib/gemini-wrapper.sh
```

---

## ⚙️ Configuration

### Debug levels
```bash
# In hooks/config/debug.conf

DEBUG_LEVEL=0  # No debug output
DEBUG_LEVEL=1  # Basic information (default)
DEBUG_LEVEL=2  # Detailed information
DEBUG_LEVEL=3  # Complete tracing
```

### Gemini settings
```bash
GEMINI_CACHE_TTL=3600      # Cache time in seconds
GEMINI_TIMEOUT=30          # Timeout per call
GEMINI_RATE_LIMIT=1        # Seconds between calls
GEMINI_MAX_FILES=20        # Max files per call
```

### Decision criteria
```bash
MIN_FILES_FOR_GEMINI=3           # Minimum file count
CLAUDE_TOKEN_LIMIT=50000         # Token threshold (~200KB)
GEMINI_TOKEN_LIMIT=800000        # Max tokens for Gemini
MAX_TOTAL_SIZE_FOR_GEMINI=10485760  # Max total size (10MB)

# Excluded files
GEMINI_EXCLUDE_PATTERNS="*.secret|*.key|*.env|*.password"
```

---

## 🧹 Maintenance

### Clear cache
```bash
# Manually
rm -rf cache/gemini/*

# Automatically (via debug.conf)
AUTO_CLEANUP_CACHE=true
CACHE_MAX_AGE_HOURS=24
```

### Clear logs
```bash
# Manually
rm -rf logs/debug/*

# Automatically (via debug.conf)
AUTO_CLEANUP_LOGS=true
LOG_MAX_AGE_DAYS=7
```

### Clear captured inputs
```bash
rm -rf debug/captured/*
```

---

## 🆘 Emergency Deactivation

### Temporarily disable hook
```bash
# Backup settings
cp ~/.claude/settings.json ~/.claude/settings.json.backup

# Remove hook
jq 'del(.hooks)' ~/.claude/settings.json > /tmp/claude_settings
mv /tmp/claude_settings ~/.claude/settings.json
```

### Re-enable hook
```bash
# Restore settings
cp ~/.claude/settings.json.backup ~/.claude/settings.json

# Or reinstall
./install.sh
```

### Complete uninstallation
```bash
# Remove hook
jq 'del(.hooks)' ~/.claude/settings.json > /tmp/claude_settings
mv /tmp/claude_settings ~/.claude/settings.json

# Remove bridge
rm -rf ~/claude-gemini-bridge
```

---

## 📞 Support & Reporting

### Collect logs for support
```bash
# Create debug package
tar -czf claude-gemini-debug-$(date +%Y%m%d).tar.gz \
  ~/.claude/settings.json \
  logs/debug/ \
  hooks/config/debug.conf
```

### Helpful information
- Claude Version: `claude --version`
- Gemini Version: `gemini --version`
- Operating System: `uname -a`
- Shell: `echo $SHELL`
- PATH: `echo $PATH`

### Common error messages
- **"Invalid JSON received"**: Input validation failed
- **"Gemini initialization failed"**: Gemini CLI not available
- **"Files too large/small"**: Thresholds not met
- **"Rate limiting"**: Normal, shows correct function
- **"Cache expired"**: Normal, cache being renewed