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

---

## App Immediately Exits — Recurrence (April 2026, session 2)

### Symptom
After the fixes above resolved the issue in session 1, the app started exiting immediately again in session 2. This time:
- **Zero output** when running the binary directly from the terminal — not even a print from `@main`
- Exit code 0 (clean, not a crash)
- `open MonitorLizard.app` fails with LaunchServices error -600
- No `FBSceneErrorDomain` or similar error in the log

### Observations So Far
- `~/Library/Containers/net.mcmains.MonitorLizard/` does **not** exist (container was previously deleted, not recreated)
- `SULastCheckTime` is set to today's date (not 2000-01-01 — the Sparkle loop trigger is gone)
- `SUAutomaticallyUpdate = 1` is set in UserDefaults, and `automaticallyDownloadsUpdates = true` in code — Sparkle will silently install any available update on launch
- Sparkle cache dirs (`PersistentDownloads`, `Installation`) are empty
- A stale MonitorLizard process (pid 50396, from the previous working session) was being held **suspended** by a stale Xcode `debugserver` process; `kill -9` had no effect until the `debugserver` was killed
- After clearing the stale process + `killall WindowManager`, `open` still returns error -600 and the binary still exits immediately with no output

### Root Cause (Resolved)

The key was `"NSStatusItem VisibleCC Item-0" = 0` in `defaults read net.mcmains.MonitorLizard`. This preference is written by macOS when a status item is "removed from menu bar" (e.g. via right-click menu or state corruption). On launch, FrontBoard reads this cached value, sends a "disconnect scene" action to the `NSSceneStatusItem`, which calls `NSApplication.terminate:`. Cancelling the terminate in `applicationShouldTerminate:` keeps the process alive but the scene is already deactivated — so the icon never appears.

Two stale MonitorLizard processes and a stale `debugserver` were also present, potentially blocking clean NSStatusItem registration.

### Fix Applied

```bash
# 1. Kill stale processes (pids were 41617, 85994 for MonitorLizard; 41747 for debugserver)
kill -9 <stale-pids>

# 2. Delete the hidden status item preference (THE KEY FIX)
defaults delete net.mcmains.MonitorLizard "NSStatusItem VisibleCC Item-0"

# 3. Restart WindowManager to clear cached scene policy
killall WindowManager
```

### Prevention

The `NSStatusItem VisibleCC Item-0` key can be written by:
- Right-clicking the menu bar item and choosing "Remove from Menu Bar" (if macOS surfaces that option)
- State corruption during crash/force-kill of the app while the status item is being manipulated
- WindowManager state getting out of sync during aggressive restart testing

When diagnosing future recurrences, check `defaults read net.mcmains.MonitorLizard` for this key first.
