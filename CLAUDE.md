# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MonitorLizard is a native macOS menu bar application (MenuBarExtra) that monitors GitHub pull requests using the `gh` CLI. It polls GitHub every 30 seconds, displays PR build statuses, and sends notifications when watched builds complete.

**Key Constraint**: The app runs as a menu bar-only application (`LSUIElement = true` in Info.plist), so it has no dock icon or traditional app window.

## Build Commands

### Building with Xcode
```bash
# Build from command line
xcodebuild -project MonitorLizard.xcodeproj -scheme MonitorLizard -configuration Debug build

# Run the app
open -a /Users/seanmcmains/Library/Developer/Xcode/DerivedData/MonitorLizard-*/Build/Products/Debug/MonitorLizard.app
```

### Testing GitHub CLI Integration
```bash
# Verify gh CLI is working
gh search prs --author=@me --state=open --json number,title,repository,url,author,updatedAt,labels --limit 3
gh pr view <NUMBER> --repo <OWNER>/<REPO> --json headRefName,statusCheckRollup
```

## Architecture

### MVVM Pattern
- **Models**: `BuildStatus`, `PullRequest` (domain models, no business logic)
- **Services**: `GitHubService`, `ShellExecutor`, `NotificationService`, `WatchlistService`, `WindowManager`, `PinnedPRsService`
- **ViewModels**: `PRMonitorViewModel` (single source of truth for PR state, polling logic)
- **Views**: `MonitorLizardApp`, `MenuBarView`, `PRRowView`, `SettingsView`, `PinPRView`

### Critical Architectural Details

#### 1. Shell Command Execution & PATH
`ShellExecutor` must set `PATH` environment variable to include Homebrew locations (`/opt/homebrew/bin`, `/usr/local/bin`) because apps launched from Finder don't inherit shell PATH from `.zshrc`:

```swift
var environment = ProcessInfo.processInfo.environment
let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin", ...]
environment["PATH"] = (homebrewPaths + [existingPath]).joined(separator: ":")
process.environment = environment
```

Without this, `gh` commands will fail with "No such file or directory" when launched normally.

#### 2. PR Sorting with State Preservation
The app maintains two arrays to enable instant re-sorting:
- `unsortedPullRequests`: Original GitHub order
- `pullRequests`: Displayed (possibly sorted) order

When the "Sort non-success PRs first" setting changes, `applySorting()` immediately re-sorts without waiting for the next poll. Both arrays must be kept in sync when toggling watch status.

#### 3. MenuBarExtra Label Rendering Limitations
MenuBarExtra labels have severe rendering constraints:
- **SwiftUI shapes (Circle, Rectangle) don't render** - only Images and Text work
- Menu bar icons are rendered as **template images** (system-colored, ignoring `.foregroundColor()`)
- Solution: Swap the entire icon (`Image(systemName:)`) rather than adding overlays

Current implementation: Dynamically changes icon from `"lizard"` to `"exclamationmark.triangle.fill"` when builds fail.

#### 4. Settings Window Management
MenuBarExtra sheets dismiss the entire menu when interacted with. Solution: `WindowManager` creates a standalone `NSWindow` with `.level = .floating` and dismisses the menu by closing `NSPanel` windows before showing settings:

```swift
NSApp.windows.forEach { window in
    if window is NSPanel {
        window.orderOut(nil)
    }
}
```

#### 5. State Observation Pattern
Uses Combine's `@Published` for reactive updates. For UserDefaults changes (like sorting preference), creates a publisher with `.dropFirst()` to skip initial value:

```swift
UserDefaults.standard
    .publisher(for: \.sortNonSuccessFirst)
    .dropFirst()
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in self?.applySorting() }
```

Requires an `@objc dynamic` extension on UserDefaults for KVO.

#### 6. Build Status Priority Logic
When a PR has multiple status checks, overall status is determined by priority:
```
failure > error > pending > success
```

This means one failing check marks the entire PR as failed, even if other checks passed.

## Common Development Tasks

### Adding New Settings
1. Add `@AppStorage` property in `SettingsView` and `PRMonitorViewModel`/service that needs it
2. Set default value in appropriate service's `init()` using `UserDefaults.standard.object(forKey:)`
3. Use `@AppStorage` for automatic persistence and reactivity

### Modifying PR Data Fetching
1. Update `gh` command arguments in `GitHubService.fetchAllOpenPRs()`
2. Add corresponding fields to `GHPRSearchResponse` struct
3. Map new fields in PR construction (around line 89-105 in GitHubService)

### Handling New Build Statuses
1. Add case to `BuildStatus` enum
2. Update `icon`, `color`, and `displayName` computed properties
3. Modify `parseOverallStatus()` priority logic if needed

### Customizing Notifications
- Sounds: Change `soundName` in `NotificationService.playSound()` (uses `/System/Library/Sounds/`)
- Voice: Modify `voiceAnnouncementText` UserDefaults key
- Notification content: Update `UNMutableNotificationContent` in `showNotification()`

## Key Files

### Service Layer Dependencies
- `GitHubService` depends on `ShellExecutor` (actor for thread safety)
- `PRMonitorViewModel` orchestrates: `GitHubService`, `WatchlistService`, `NotificationService`, `PinnedPRsService`
- `WatchlistService` is a singleton storing watched PR state in UserDefaults (manual dictionary serialization, not Codable)
- `PinnedPRsService` stores `[PinnedPRIdentifier]` in UserDefaults as JSON (Codable); injectable `UserDefaults` for testability

### View Hierarchy
```
MonitorLizardApp (App)
├─ MenuBarExtra with MenuBarLabel (dynamic icon)
│  └─ MenuBarView (main content)
│     ├─ Header (title + refresh button)
│     ├─ ScrollView
│     │  └─ LazyVStack of PRRowView (3 sections: Awaiting My Review, Other PRs, My PRs)
│     └─ Footer (Commands menu: Add PR…, Settings, Check for Updates | Quit)
└─ WindowManager (singleton for Settings + Add PR NSWindows)
```

### Data Flow
1. Timer in `PRMonitorViewModel.startPolling()` triggers refresh every N seconds
2. `refresh()` concurrently fetches authored/review PRs and Other PRs (pinned), deduplicates, updates `pullRequests` and `pinnedPullRequests` arrays
3. SwiftUI automatically re-renders when `@Published pullRequests` / `@Published pinnedPullRequests` changes
4. `applySorting()` can be called independently to re-sort without re-fetching

## Gotchas & Known Issues

### MenuBarExtra Behavior
- Using `.sheet()` or `.popover()` modifiers causes the entire menu to dismiss when interacted with
- Must use standalone `NSWindow` for persistent dialogs (see `WindowManager`)
- SwiftUI `@State` in menu bar views is **not reset** when the panel dismisses — views are kept alive in memory. Use imperative AppKit APIs (e.g. `NSAlert.runModal()`) for confirmations instead of SwiftUI `confirmationDialog`, which would re-appear on the next menu open.

### LazyVStack Section Header Identity
Section headers in a `LazyVStack` must have **stable, unique `.id()` values** (e.g. `"header-review"`, `"header-pinned"`, `"header-authored"`). If the same `.id()` (like `"top"`) is reassigned between different views as sections appear/disappear, SwiftUI recycles the wrong view and displays stale content (e.g. the wrong section title). Use a separate zero-height `Color.clear.id("top")` as the scroll anchor.

### ProgressView in Menu Bar Icons
- Animated spinners work in PR rows but not in the MenuBarExtra label itself
- For pending builds, use `ProgressView()` in `PRRowView`, but only static icons in menu bar

### Color Contrast on Labels
PR labels use `contrastingTextColor` computed property that calculates luminance using WCAG formula to determine white or black text. GitHub label colors come as hex strings.

### Build Status Emoji vs Spinner
The `BuildStatus.pending` case shows an animated `ProgressView()` spinner in PR rows, not the 🔄 emoji. This is done by checking `if pr.buildStatus == .pending` in `PRRowView.body`.

## External Dependencies

- **GitHub CLI (`gh`)**: Must be installed and authenticated. Check with `gh auth status`.
- **macOS 13.0+**: Required for `MenuBarExtra` API
- **UserNotifications framework**: For native macOS notifications
- **Combine framework**: For `@Published` and reactive patterns


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
