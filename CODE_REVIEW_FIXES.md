# MonitorLizard Code Review & Fixes

## Summary

I conducted a comprehensive code review before sharing with colleagues and addressed the most important issues. The code quality is good overall (7/10), with clean MVVM architecture and proper use of Swift concurrency. The main areas for improvement were memory management, code organization, and eliminating magic numbers.

## Critical Issues Fixed

### 1. Memory Leak - Timer Not Cancelled ✅ FIXED
**File:** `PRMonitorViewModel.swift`
**Issue:** The refresh timer was never cleaned up when the ViewModel was deallocated
**Fix:** Added `deinit` block to properly invalidate the timer and cancel the Combine observer

```swift
deinit {
    stopPolling()
    sortSettingObserver?.cancel()
}
```

### 2. Magic Numbers Eliminated ✅ FIXED
**Files:** Multiple files throughout the codebase
**Issue:** Hardcoded values scattered throughout the code made maintenance difficult
**Fix:** Created `Constants.swift` with centralized constants:

```swift
enum Constants {
    // Time intervals
    static let secondsPerDay: TimeInterval = 24 * 60 * 60
    static let defaultRefreshInterval = 30
    static let defaultShellTimeout: TimeInterval = 30

    // Settings defaults
    static let defaultInactiveBranchThreshold = 3
    static let minRefreshInterval = 10
    static let maxRefreshInterval = 300
    static let refreshIntervalStep = 10
    static let minInactiveBranchThreshold = 1
    static let maxInactiveBranchThreshold = 90

    // UI constants
    static let menuMaxHeightMultiplier = 0.7
    static let settingsWindowWidth = 450.0
    static let settingsWindowHeight = 500.0

    // Voice announcement
    static let defaultVoiceAnnouncementText = "Build ready for Q A"
}
```

**Updated files:**
- `PRRowView.swift` - Days calculation
- `GitHubService.swift` - Inactive detection calculation
- `SettingsView.swift` - All default values and slider bounds
- `PRMonitorViewModel.swift` - Default settings values
- `NotificationService.swift` - Default voice announcement text
- `MenuBarView.swift` - Screen height multiplier
- `ShellExecutor.swift` - Default timeout

## Known Issues (Not Critical for Initial Sharing)

### Security Observations

1. **Command Injection (Low Risk)**
   - **Location:** `NotificationService.swift`, line 111-123
   - **Status:** Actually safe - `Process.arguments` array prevents shell interpretation
   - **Note:** Voice announcement text goes through `say` command, but arguments are properly isolated

2. **URL Validation**
   - **Location:** `PRRowView.swift`, lines 123-125, 143-147
   - **Issue:** PR URLs from GitHub opened without domain validation
   - **Risk:** Low - URLs come from authenticated GitHub API
   - **Future improvement:** Validate URLs are HTTPS and contain github.com domain

3. **Information Leakage in Errors**
   - **Location:** `GitHubService.swift`, `ShellExecutor.swift`
   - **Issue:** Shell command errors displayed directly to users
   - **Risk:** Low for single-user app
   - **Future improvement:** Sanitize error messages before showing to users

### Code Quality Issues (Minor)

4. **Duplicate Date Formatting Logic**
   - **Location:** `GitHubService.swift`, lines 49-60 and 236-247
   - **Future improvement:** Extract into dedicated `createDateFormatters()` method

5. **Inconsistent Error Handling**
   - **Location:** Multiple files use `print()` statements
   - **Future improvement:** Implement centralized logging system

6. **Unsafe Hex Color Parsing**
   - **Location:** `PRRowView.swift`, lines 152-174
   - **Issue:** Invalid label colors fail silently (become black)
   - **Risk:** Low - only affects visual display
   - **Future improvement:** Log warnings for invalid colors

## Architecture Notes

### Singletons
- `WatchlistService.shared` and `NotificationService.shared` use singleton pattern
- **Trade-off:** Practical for this app, but makes unit testing harder
- **Future improvement:** Consider dependency injection for testability

### Shell Command Security
- All shell commands go through `ShellExecutor` actor (thread-safe)
- Commands use `/usr/bin/env` with argument arrays (not shell strings)
- PATH is explicitly set to include Homebrew locations
- **Security:** Generally safe approach, minimizes command injection risks

## Testing Recommendations

Before sharing, manually test:

1. **Memory:** Open Settings, close it, repeat 10 times - should not leak
2. **Inactive Detection:** Enable with 1-day threshold, verify calculations are correct
3. **Error Handling:** Disconnect network, verify app handles gracefully
4. **Settings Persistence:** Change settings, quit app, relaunch - verify settings saved
5. **Timer Cleanup:** Use Instruments to verify no timer leaks

## Next Steps (Post-Sharing Improvements)

### High Priority
1. Add unit tests for date calculations and status priority logic
2. Implement proper logging system to replace print statements
3. Add URL validation for PR links

### Medium Priority
1. Refactor date formatter duplication
2. Consider dependency injection for better testability
3. Add retry logic for network failures

### Low Priority
1. Improve hex color parsing with warnings
2. Add more detailed error messages
3. Consider extracting UserDefaults into PreferencesService protocol

## Build Instructions

**IMPORTANT:** After pulling these changes, you must manually add `Constants.swift` to the Xcode project:

1. Open `MonitorLizard.xcodeproj` in Xcode
2. Right-click on the "MonitorLizard" folder in the Project Navigator
3. Select "Add Files to MonitorLizard..."
4. Navigate to and select `Constants.swift`
5. Ensure "Copy items if needed" is UNchecked (file is already in correct location)
6. Ensure "MonitorLizard" target is checked
7. Click "Add"
8. Build the project (Cmd+B)

The file is already in the correct location (`MonitorLizard/Constants.swift`) and has been added to git, but Xcode needs to know about it.

## Conclusion

The code is in good shape for sharing with colleagues. The critical memory leak has been fixed, and magic numbers have been centralized. The app follows good architecture patterns and uses modern Swift concurrency properly.

The remaining issues are minor and don't need to be addressed before initial sharing. They're documented here for future reference and can be addressed iteratively based on feedback from your colleagues.

**Overall Assessment:** ✅ Ready to share after adding Constants.swift to Xcode project
