# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Claude-Gemini Bridge repository.

## Project Overview

The Claude-Gemini Bridge is an intelligent hook system that seamlessly integrates Claude Code with Google Gemini for large-scale code analysis tasks. When Claude Code encounters complex analysis requests, the bridge automatically delegates appropriate tasks to Gemini while maintaining Claude's control over the conversation flow.

## Architecture

### Core Components

- **Hook System**: Uses Claude Code's PreToolUse hooks to intercept tool calls
- **Path Converter**: Translates Claude's `@` notation to absolute file paths
- **Decision Engine**: Intelligently determines when to delegate tasks to Gemini
- **Caching Layer**: Avoids redundant API calls with content-aware caching
- **Debug System**: Comprehensive logging and performance monitoring

### How It Works

1. **Interception**: Hook catches Claude's tool calls (Read, Glob, Grep, Task)
2. **Analysis**: Decision engine evaluates file count, size, and task complexity
3. **Delegation**: Large or complex tasks are sent to Gemini for processing
4. **Integration**: Gemini's analysis is seamlessly returned to Claude
5. **Fallback**: Failed delegations continue with normal Claude execution

## Usage Patterns

### Automatic Delegation Triggers

The bridge delegates to Gemini when:
- **Token Limit**: Content exceeds ~50k tokens (~200KB, optimized for Claude's 200k context)
- **Multi-File Tasks**: ≥3 files for Task operations (configurable)
- **Safety Limits**: Content must be ≤10MB and ≤800k tokens for Gemini processing
- **File Exclusions**: Automatically excludes sensitive files (*.secret, *.key, *.env, etc.)

### Configuration

Key settings in `hooks/config/debug.conf`:

```bash
# Delegation thresholds (optimized for Claude 200k context)
MIN_FILES_FOR_GEMINI=3          # Delegate Task operations with ≥3 files
MIN_FILE_SIZE_FOR_GEMINI=5120   # Minimum 5KB total size
MAX_TOTAL_SIZE_FOR_GEMINI=10485760  # Maximum 10MB total size

# Debug and performance
DEBUG_LEVEL=2                   # 0=off, 1=basic, 2=verbose, 3=trace
DRY_RUN=false                   # Test mode without Gemini calls
```

See README.md for complete configuration reference.

## Development Guidelines

### Code Style
- All shell scripts use bash and follow POSIX compliance where possible
- Comments are in English
- Functions include single-line ABOUTME comments explaining purpose
- Error handling with proper exit codes and logging

### Testing
- Use `test/test-runner.sh` for automated testing
- Use `test/manual-test.sh` for interactive debugging
- All library functions include self-tests

### Debugging
- Set `DEBUG_LEVEL=3` for maximum verbosity
- Enable `CAPTURE_INPUTS=true` to save tool calls for replay
- Use `DRY_RUN=true` to test delegation logic without calling Gemini

## Security Considerations

### File Exclusions
The bridge automatically excludes sensitive files:
- `*.secret`, `*.key`, `*.env`
- `*.password`, `*.token`, `*.pem`, `*.p12`

### Rate Limiting
- 1 second between Gemini API calls (configurable)
- 100 requests/day quota monitoring
- Automatic cache cleanup to prevent data accumulation

### Permissions
- Scripts run with user permissions only
- No elevated privileges required
- Logs stored in user directory

## Performance Optimization

### Delegation Strategy (Optimized 2024)
- **Early delegation**: Content >50k tokens (~200KB) goes to Gemini
- **Multi-file threshold**: Task operations with ≥3 files delegate automatically
- **Efficient context usage**: Claude reserves capacity for response generation
- **Gemini utilization**: Leverages 1M token capacity for large analysis tasks

### Caching Strategy
- Content-aware cache keys based on file contents and metadata
- 1-hour default TTL with automatic cleanup
- Cache invalidation on file modifications

### Resource Management
- Automatic memory cleanup after processing
- Background cache and log rotation
- Configurable file size limits

### Performance Impact (2024 Optimization)
- **Early delegation**: Content >50k tokens (~200KB) → Gemini
- **Multi-file threshold**: ≥3 files for Task operations → Gemini  
- **Better coverage**: Minimum size reduced to 5KB

## Integration Points

### Claude Code Integration
- Seamless hook integration via `settings.json`
- No modification of Claude Code required
- Preserves all existing Claude functionality

### Gemini API Integration
- Direct CLI integration (no custom API wrappers)
- Automatic error handling and fallbacks
- Structured prompt generation based on task type

## Troubleshooting

### Common Issues
- **Hook not executing**: Check `~/.claude/settings.json` configuration
- **Gemini not found**: Verify `gemini` CLI is in PATH
- **Cache issues**: Clear cache with `rm -rf cache/gemini/*`
- **Permission errors**: Ensure scripts are executable

### Debug Commands
```bash
# View recent logs
tail -f logs/debug/$(date +%Y%m%d).log

# Test individual components
hooks/lib/path-converter.sh
hooks/lib/json-parser.sh
hooks/lib/gemini-wrapper.sh

# Run full test suite
test/test-runner.sh

# Interactive testing
test/manual-test.sh
```

## Monitoring

### Performance Metrics
- Hook execution time
- Gemini processing duration
- Cache hit/miss ratios
- File processing statistics

### Health Checks
- Automated testing in CI/CD
- Component-level validation
- API connectivity verification
- Resource usage monitoring

## Contribution Guidelines

### Pull Requests
- Include test coverage for new features
- Update documentation for API changes
- Follow existing code style conventions
- Add debug logging for new components

### Issue Reporting
- Include debug logs and reproduction steps
- Specify Claude Code and Gemini CLI versions
- Provide sample inputs when possible
- Test with latest version before reporting