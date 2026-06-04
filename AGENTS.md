# Agent Instructions

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

## Running Tests

```bash
xcodebuild test -project MonitorLizard/MonitorLizard.xcodeproj -scheme MonitorLizard -destination 'platform=macOS' -only-testing:MonitorLizardTests
```

**Important:** Tests that use `UserDefaults.standard` cannot run in parallel without state leakage between processes. Test structs that share this state are marked `@Suite(.serialized)`. If adding new tests that modify `UserDefaults.standard`, either:

1. Add `@Suite(.serialized)` to the test struct, or
2. Use isolated UserDefaults suites (`UserDefaults(suiteName:)`) for test isolation, or  
3. Always set and tear down all relevant UserDefaults keys with `defer { ... removeObject(forKey:) }`

When running a single test in isolation, it will likely pass even without these precautions. Bulk test failures are usually a sign of UserDefaults cross-contamination.

## Session Completion

**When ending a work session**, push your changes to remote:

```bash
git pull --rebase
git push
git status  # MUST show "up to date with origin"
```