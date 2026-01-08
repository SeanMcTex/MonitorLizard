# Quick Start Guide

## 🚀 Get MonitorLizard Running in 5 Minutes

### Prerequisites Checklist

- [ ] macOS 13.0 (Ventura) or later
- [ ] Xcode 15.0 or later installed
- [ ] GitHub CLI (`gh`) installed: `brew install gh`
- [ ] GitHub CLI authenticated: `gh auth login`

### Step 1: Verify GitHub CLI Setup

Run the test script to ensure gh CLI is working:

```bash
./test-gh-integration.sh
```

You should see: "✅ All GitHub CLI integration tests passed!"

### Step 2: Create Xcode Project

1. **Open Xcode**

2. **Create New Project**:
   - File > New > Project
   - Select: macOS > App
   - Click Next

3. **Configure Project**:
   - Product Name: `MonitorLizard`
   - Team: (Select your team)
   - Organization Identifier: `com.yourname.monitorlizard`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Click Next

4. **Save Location**:
   - Navigate to `/Users/seanmcmains/Developer/MonitorLizard`
   - **Important**: Save it in the MonitorLizard directory (not inside another folder)
   - Click Create

### Step 3: Remove Default Files

In Xcode Project Navigator:
- Delete `ContentView.swift` (Move to Trash)
- Delete `MonitorLizardApp.swift` (Move to Trash)

### Step 4: Add Source Files

1. **Add Files to Project**:
   - Right-click on `MonitorLizard` folder in Project Navigator
   - Select "Add Files to MonitorLizard..."
   - Navigate to `MonitorLizard/MonitorLizard` directory
   - Select ALL Swift files and folders (Models, Services, ViewModels, Views)
   - **Uncheck** "Copy items if needed"
   - Select "Create groups"
   - Ensure target "MonitorLizard" is checked
   - Click Add

2. Your project structure should look like:
   ```
   MonitorLizard/
   ├── Models/
   │   ├── BuildStatus.swift
   │   └── PullRequest.swift
   ├── Services/
   │   ├── GitHubService.swift
   │   ├── ShellExecutor.swift
   │   ├── NotificationService.swift
   │   └── WatchlistService.swift
   ├── ViewModels/
   │   └── PRMonitorViewModel.swift
   ├── Views/
   │   ├── MonitorLizardApp.swift
   │   ├── MenuBarView.swift
   │   ├── PRRowView.swift
   │   └── SettingsView.swift
   └── Info.plist
   ```

### Step 5: Configure Project Settings

1. **Select Project** in Navigator (top level)

2. **Select Target** "MonitorLizard"

3. **General Tab**:
   - Minimum Deployments: **macOS 13.0**

4. **Signing & Capabilities Tab**:
   - Select your Team
   - Add Capability: **Push Notifications**
     - Click "+ Capability"
     - Search for "Push Notifications"
     - Add it

5. **Info Tab**:
   - Locate the Info.plist file
   - Click "Choose Info.plist File..."
   - Select `MonitorLizard/MonitorLizard/Info.plist`

6. **Build Settings Tab**:
   - Search for: "Info.plist"
   - Set **Info.plist File** to: `MonitorLizard/MonitorLizard/Info.plist`

### Step 6: Build and Run

1. Select **My Mac** as the build target (top of Xcode window)

2. Click the **Run** button (▶️) or press **⌘R**

3. If build succeeds, look for the **lizard icon** 🦎 in your menu bar!

### Step 7: First Run

1. **Click the lizard icon** in your menu bar

2. You should see your open PRs with their build statuses!

3. **Watch a PR**:
   - Hover over any PR
   - Click the **eye icon** to watch it
   - You'll be notified when the build completes

4. **Configure Settings**:
   - Click "Settings" at the bottom
   - Adjust refresh interval (default: 30s)
   - Toggle sounds/notifications

## Troubleshooting

### Build Errors

**"Cannot find 'PRMonitorViewModel' in scope"**
- Ensure all Swift files are added to the target
- Project Navigator > Select each file > File Inspector > Target Membership: Check "MonitorLizard"

**"LSUIElement not found"**
- Info.plist not configured correctly
- Build Settings > Info.plist File > Set to `MonitorLizard/MonitorLizard/Info.plist`

**"Entitlements error"**
- Signing & Capabilities > Push Notifications must be added
- Ensure a valid Team is selected

### Runtime Issues

**"GitHub CLI is not installed"**
```bash
brew install gh
```

**"GitHub CLI is not authenticated"**
```bash
gh auth login
```

**"No PRs showing"**
- Verify you have open PRs: `gh pr list --author=@me --state=open`
- Click the refresh button
- Check error messages in the UI

**App doesn't appear in menu bar**
- Check Info.plist has `LSUIElement` set to `true`
- Restart Xcode and rebuild

## Success!

Once running, MonitorLizard will:
- 🔄 Auto-refresh every 30 seconds
- 📊 Show all your open PRs with build status
- 👀 Let you watch specific PRs
- 🔔 Notify you when watched builds complete
- 🔊 Play sounds and speak "Build ready for Q A"

Enjoy! 🦎
