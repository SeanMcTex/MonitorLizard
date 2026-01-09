# MonitorLizard 🦎

A native macOS menu bar application that monitors your GitHub pull requests and notifies you when builds complete.

## Features

- **Live PR Monitoring**: Displays all your open pull requests with real-time build status
- **Auto-Refresh**: Polls GitHub every 30 seconds (configurable 10-300s)
- **Watch PRs**: Mark specific PRs to get notified when their builds finish
- **Inactive Branch Detection**: Highlights PRs that haven't been updated in N days (configurable)
- **Smart Sorting**: Optionally sort non-success PRs to the top of the list
- **Age Indicators**: Shows how long ago each PR was last updated
- **Native Notifications**: macOS notifications with sound and voice announcements
- **Multi-Repository**: Monitors PRs across all repositories you have access to
- **Build Status Icons**:
  - ❗ Merge Conflict (purple)
  - ❌ Failure (red)
  - ⚠️ Error (orange)
  - 🔄 Pending (blue)
  - ⏳ Inactive (orange)
  - ✅ Success (green)
  - ❓ Unknown (gray)

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- [GitHub CLI (gh)](https://cli.github.com) installed and authenticated

## Setup

### 1. Install GitHub CLI

```bash
brew install gh
```

### 2. Authenticate GitHub CLI

```bash
gh auth login
```

Follow the prompts to authenticate with your GitHub account.

### 3. Build and Run

1. Open `MonitorLizard/MonitorLizard.xcodeproj` in Xcode
2. Select your development team under **Signing & Capabilities** if needed
3. Press **⌘R** to build and run
4. The app will appear in your menu bar with a lizard icon 🦎
5. Grant notification permissions when prompted

**Note:** The app runs as a menu bar-only application (no Dock icon). Look for the lizard icon in your menu bar.

## Usage

### Basic Operation

1. **Launch**: Click the lizard icon in your menu bar
2. **View PRs**: See all your open pull requests with their build statuses
3. **Refresh**: Click the refresh button or wait for auto-refresh
4. **Open PR**: Click any PR to open it in your browser

### Watching PRs

1. **Start Watching**: Click the eye icon on any PR
2. **Get Notified**: When the build completes, you'll receive:
   - A macOS notification
   - A sound effect (Glass.aiff for success, Basso for failure)
   - Voice announcement: "Build ready for Q A" (for successful builds)
3. **Stop Watching**: Click the eye icon again to unwatch

### Settings

Click **Settings** to configure:

**General:**
- **Refresh Interval**: 10-300 seconds (default: 30s)
- **Sort non-success PRs first**: Show failing/pending/inactive PRs at the top
- **Inactive Branch Detection**: Enable detection and set threshold (1-90 days)

**Notifications:**
- **Show Notifications**: Enable/disable macOS notifications
- **Play Sounds**: Enable/disable sound effects
- **Voice Announcements**: Enable/disable and customize text-to-speech message

## Architecture

The app follows MVVM architecture with SwiftUI:

```
MonitorLizard/
├── Constants.swift      # Centralized constants
├── Models/              # Data models
│   ├── BuildStatus.swift
│   └── PullRequest.swift
├── Services/            # Business logic
│   ├── GitHubService.swift       # gh CLI wrapper
│   ├── ShellExecutor.swift       # Process execution
│   ├── NotificationService.swift # Notifications
│   ├── WatchlistService.swift    # Persistent storage
│   └── WindowManager.swift       # Settings window
├── ViewModels/          # State management
│   └── PRMonitorViewModel.swift
└── Views/               # UI components
    ├── MonitorLizardApp.swift
    ├── MenuBarView.swift
    ├── PRRowView.swift
    └── SettingsView.swift
```

### How It Works

1. **Polling**: Timer fires every N seconds (configurable)
2. **Fetch PRs**: Executes `gh search prs --author=@me --state=open --json number,title,repository,url,author,updatedAt,labels`
3. **Fetch Status**: For each PR, executes `gh pr view N --json headRefName,statusCheckRollup,mergeable,mergeStateStatus`
4. **Parse Status**: Determines overall status from individual checks
   - **Priority**: conflict > failure > error > pending > inactive > success > unknown
   - **Inactive Detection**: If enabled, marks PRs as inactive when `updatedAt` exceeds threshold
5. **Display**: Shows PRs with status icons, age indicators, and labels
6. **Check Completions**: Compares with previous status for watched PRs
7. **Notify**: Sends notifications for completed builds

### GitHub CLI Commands

```bash
# Fetch all open PRs
gh search prs --author=@me --state=open --json number,title,repository,url,author,updatedAt,labels --limit 100

# Fetch PR details with status and merge state
gh pr view 123 --repo owner/repo --json headRefName,statusCheckRollup,mergeable,mergeStateStatus

# Check gh CLI authentication
gh auth status
```

## Troubleshooting

### "GitHub CLI is not installed"

Install gh CLI:
```bash
brew install gh
```

### "GitHub CLI is not authenticated"

Authenticate:
```bash
gh auth login
```

### PRs not showing

1. Ensure you have open PRs: `gh pr list --author=@me --state=open`
2. Check gh CLI version: `gh --version` (should be 2.0+)
3. Try manual refresh

### Notifications not appearing

1. Check System Settings > Notifications > MonitorLizard
2. Ensure notifications are enabled in Settings
3. Grant notification permissions when prompted

### Build errors in Xcode

1. Ensure macOS deployment target is 13.0+
2. Check that all Swift files are added to the target
3. Verify Info.plist is configured correctly
4. Clean build folder: **Product > Clean Build Folder** (⇧⌘K)

## Development

### Running Tests

```bash
swift test
```

### Adding Features

The codebase is structured for easy extension:

- **New PR filters**: Modify `GitHubService.fetchAllOpenPRs()`
- **Custom notifications**: Extend `NotificationService`
- **Additional UI**: Add views to `Views/` directory
- **New status types**: Extend `BuildStatus` enum and update priority logic in `GitHubService.parseOverallStatus()`
- **New settings**: Add to `Constants.swift`, create `@AppStorage` properties in `SettingsView`, and wire through to services
- **Time-based features**: Use `Constants.secondsPerDay` for date calculations

## Distribution & Notarization

To distribute MonitorLizard outside of the App Store, you'll need to notarize it with Apple.

### Prerequisites

- Apple Developer account
- Valid Developer ID Application certificate
- App-specific password for notarization

### Build Archive

1. In Xcode, select **Product > Archive**
2. Select your development team in **Signing & Capabilities**
3. Wait for the archive to complete
4. In the Organizer window, select the archive and click **Distribute App**

### Export for Distribution

1. Choose **Developer ID** distribution method
2. Select **Upload** or **Export** based on your workflow
3. Xcode will automatically code sign with Hardened Runtime enabled
4. Export the .app bundle

### Notarization

Apple requires notarization for apps distributed outside the App Store on macOS 10.15+.

**Using Xcode (Automatic):**
1. During export, choose **Upload** to automatically submit for notarization
2. Xcode will handle the notarization process
3. Once complete, download the notarized app

**Using Command Line:**
```bash
# Create a zip of the app
cd /path/to/exported/app
ditto -c -k --keepParent MonitorLizard.app MonitorLizard.zip

# Submit for notarization (requires app-specific password)
xcrun notarytool submit MonitorLizard.zip \
  --apple-id "your-apple-id@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "your-app-specific-password" \
  --wait

# Check status
xcrun notarytool log <submission-id> \
  --apple-id "your-apple-id@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "your-app-specific-password"

# Staple the notarization ticket (optional but recommended)
xcrun stapler staple MonitorLizard.app
```

**Creating an App-Specific Password:**
1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in with your Apple ID
3. In the Security section, select **App-Specific Passwords**
4. Click **+** to generate a new password
5. Use this password for notarization (not your Apple ID password)

### Hardened Runtime

The project is configured with Hardened Runtime enabled, which is required for notarization. The entitlements file (`MonitorLizard.entitlements`) includes:

- App Sandbox disabled (required for shell command execution)
- Get Task Allow enabled (for debugging)

If you need additional entitlements, edit `MonitorLizard/MonitorLizard.entitlements`.

### Distribution Checklist

- [ ] Valid Developer ID certificate installed
- [ ] Hardened Runtime enabled (already configured)
- [ ] App signed with Developer ID
- [ ] App notarized by Apple
- [ ] Notarization ticket stapled to app (optional)
- [ ] Test on a different Mac to verify Gatekeeper acceptance

## Credits

Inspired by the original `watch-ci-build` bash script that watched CircleCI builds via GitHub API.

## License

MIT License - feel free to modify and distribute.
