# MonitorLizard 🦎

A native macOS menu bar application that monitors your GitHub pull requests and notifies you when builds complete.

## Features

- **Live PR Monitoring**: Displays all your open pull requests with real-time build status
- **Auto-Refresh**: Polls GitHub every 30 seconds (configurable 10-300s)
- **Watch PRs**: Mark specific PRs to get notified when their builds finish
- **Native Notifications**: macOS notifications with sound and voice announcements
- **Multi-Repository**: Monitors PRs across all repositories you have access to
- **Build Status Icons**:
  - ✅ Success
  - ❌ Failure
  - ⚠️ Error
  - 🔄 Pending
  - ❓ Unknown

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

### 3. Build the Application

Since the Swift source files are already created, you need to create an Xcode project:

#### Option A: Create Xcode Project (Recommended)

1. Open Xcode
2. Select **File > New > Project**
3. Choose **macOS > App**
4. Configure project:
   - **Product Name**: MonitorLizard
   - **Team**: Select your team
   - **Organization Identifier**: com.yourname.monitorlizard
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: None
5. **Save** the project to `/Users/seanmcmains/Developer/MonitorLizard`
6. **Delete** the default `ContentView.swift` and `MonitorLizardApp.swift` files Xcode created
7. In Xcode, **File > Add Files to "MonitorLizard"**
8. Select the `MonitorLizard/MonitorLizard` directory containing all the Swift files
9. Ensure "Copy items if needed" is **unchecked** and "Create groups" is selected
10. Click **Add**

#### Configure Project Settings

1. Select the project in the navigator
2. Under **Signing & Capabilities**:
   - Enable **Hardened Runtime**
   - Under **Resource Access**, enable:
     - **User Selected Files** (Read/Write)
   - Add capability **Push Notifications**
3. Under **Info**:
   - Set **Minimum Deployments** to macOS 13.0
   - Add `Info.plist` from `MonitorLizard/MonitorLizard/Info.plist`
4. Under **Build Settings**:
   - Search for "Info.plist File"
   - Set to `MonitorLizard/MonitorLizard/Info.plist`

#### Build and Run

1. Select **Product > Run** (⌘R)
2. The app will appear in your menu bar with a lizard icon 🦎

#### Option B: Use Swift Package Manager (Advanced)

If you prefer command-line building, you can create a Package.swift:

```bash
cd /Users/seanmcmains/Developer/MonitorLizard
swift build
swift run MonitorLizard
```

However, note that MenuBarExtra requires a proper app bundle, so you'll need to create a `.app` bundle manually.

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

- **Refresh Interval**: 10-300 seconds (default: 30s)
- **Show Notifications**: Enable/disable macOS notifications
- **Play Sounds**: Enable/disable sound effects
- **Voice Announcements**: Enable/disable text-to-speech

## Architecture

The app follows MVVM architecture with SwiftUI:

```
MonitorLizard/
├── Models/              # Data models
│   ├── BuildStatus.swift
│   └── PullRequest.swift
├── Services/            # Business logic
│   ├── GitHubService.swift      # gh CLI wrapper
│   ├── ShellExecutor.swift      # Process execution
│   ├── NotificationService.swift # Notifications
│   └── WatchlistService.swift   # Persistent storage
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
2. **Fetch PRs**: Executes `gh search prs --author=@me --state=open`
3. **Fetch Status**: For each PR, executes `gh pr view N --json statusCheckRollup`
4. **Parse Status**: Determines overall status from individual checks
   - Priority: failure > error > pending > success
5. **Check Completions**: Compares with previous status for watched PRs
6. **Notify**: Sends notifications for completed builds

### GitHub CLI Commands

```bash
# Fetch all open PRs
gh search prs --author=@me --state=open --json number,title,repository,url,author,updatedAt

# Fetch PR details with status
gh pr view 123 --repo owner/repo --json headRefName,statusCheckRollup
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
- **New status types**: Extend `BuildStatus` enum

## Credits

Inspired by the original `watch-ci-build` bash script that watched CircleCI builds via GitHub API.

## License

MIT License - feel free to modify and distribute.
