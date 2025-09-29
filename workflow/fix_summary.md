# Sed Error Fix Summary

## Problem
During installation (`sudo bash scripts/install.sh`), the script failed with:
```
sed: -e expression #1, char 78: unterminated `s' command
```

## Root Cause
The error occurred in `/scripts/lib/config.sh` at line 167-168 in the `apply_template()` function.
The original code used a complex sed command with semicolons to chain multiple substitutions:
```bash
value=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/\//\\\//g; s/&/\\&/g')
```

This caused parsing issues with the sed command when special characters were present in the values being substituted.

## Solution Applied
Fixed by splitting the complex sed command into separate pipeline commands:
```bash
value=$(printf '%s' "$value" | sed 's/\\/\\\\/g' | sed 's/\//\\\//g' | sed 's/&/\\&/g')
```

Each sed command now runs separately in a pipeline, avoiding parsing issues with semicolons.

## Files Modified
- `/scripts/lib/config.sh` - Line 167: Split sed command into pipeline

## Testing
- Validated syntax of both `config.sh` and `install.sh`
- Tested `apply_template` function with various special characters including `/`, `&`, and `\`
- All tests passed successfully

## Impact
The installation script should now work correctly when creating configuration files with REALITY domains containing colons and other special characters.