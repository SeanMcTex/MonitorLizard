# Troubleshooting

## App Immediately Exits at Launch (April 2026)

### Symptom
The app launches, the menu bar lizard icon appears briefly, then disappears. The process exits with code 0 (clean exit, not a crash). No crash reports are generated.

### Root Cause
During Sparkle update testing, two OS-level state changes were made that were **not reverted by git**:

1. **`SULastCheckTime` set to `2000-01-01`** in `UserDefaults` — This was done to force Sparkle to perform an immediate update check on next launch. With `automaticallyDownloadsUpdates = true`, Sparkle was finding the latest release on the appcast, downloading it, and calling `exit()` to apply the update. This started a loop: the "new" version also had `SULastCheckTime=2000-01-01` set, so it immediately tried to update again on next launch.

2. **Sandbox container created** at `~/Library/Containers/net.mcmains.MonitorLizard/` — The Sparkle testing included enabling `com.apple.security.app-sandbox = true` in entitlements. Although the code was reverted, the macOS container manager retained a sandbox policy for the bundle ID. On subsequent launches of the non-sandboxed build, `containermanagerd` detected the entitlement mismatch, and the OS workspace (`FBSWorkspaceScenesClient`) sent a terminate scene action to the app's `NSSceneStatusItem`.

### Diagnosis
The exit was traced using an `NSApplicationDelegateAdaptor` with `applicationShouldTerminate(_:)` logging a stack trace. The key frame was:
```
AppKit  -[NSSceneStatusItem scene:handleActions:]
        called from FBSWorkspaceScenesClient sceneID:sendActions:toExtension:
```
This confirmed the OS workspace (not the app code) was initiating the termination.

### Fix Applied
```bash
# 1. Delete the stale Sparkle update-check timestamp
defaults delete net.mcmains.MonitorLizard SULastCheckTime

# 2. Delete the stale sandbox container (created when app-sandbox=true was tested)
rm -rf ~/Library/Containers/net.mcmains.MonitorLizard

# 3. Clear stale Sparkle Updater.app launcher cache
rm -rf ~/Library/Caches/net.mcmains.MonitorLizard/org.sparkle-project.Sparkle/Launcher/

# 4. Restart WindowManager to clear stale in-memory scene registration (THE KEY FIX)
killall WindowManager
# WindowManager is managed by launchd and restarts automatically within ~1 second.
# This clears the cached scene policy that was sending terminate actions on launch.
```

### Prevention
When testing Sparkle update behavior:
- Use `SPUUpdater.resetUpdateCycle()` or similar API instead of manually setting `SULastCheckTime`
- If entitlements are temporarily changed (e.g., adding `app-sandbox`), delete `~/Library/Containers/<bundle-id>` before reverting
- Test automatic updates in a separate branch to make cleanup explicit

### Additional Findings During Investigation
- The app builds and initializes completely before the terminate is sent (`applicationDidFinishLaunching` fires, `body` is evaluated twice)
- Cancelling the termination in `applicationShouldTerminate:` allows the app to run normally
- The terminate is **not** triggered by Sparkle code itself — it persists even with `UpdateService` disabled
- The release binary from `build/release/MonitorLizard.xcarchive` was also affected (confirms it's OS state, not a build artifact)
- `codesign -vvv` showed valid signatures on all components including Sparkle XPC services
- Launch Services re-registration (`lsregister`) did not fix it alone — the container deletion was necessary
