# xanhub Developer Modules

Drop this entire `devmodules` folder in the repository root:

```text
/idk
  /devmodules
    init.luau
    dev_shared.luau
    animation_viewer.luau
    animation_logger.luau
    remote_spy.luau
    console_logger.luau
    performance_profiler.luau
    instance_inspector.luau
    manifest.luau
    module_template.luau
```

## Included modules


### Notification Center

A theme-matched stacked notification service for debug messages, moderation notices, progress jobs, warnings, errors, and module status. It supports priorities, sticky notices, dedupe keys, grouped duplicate counts, action buttons, hover pause, configurable corners, overflow queues, searchable history, JSON export, and complete unload cleanup.

```lua
local notices = ctx.devtools.apis.notifications
notices:Debug("Animator scan started", {channel = "animation"})
notices:Mod("Moderator present", {sticky = true, key = "staff-present"})

local progress = notices:Progress({title = "Scan", message = "Starting..."})
progress:SetProgress(0.5, "Halfway done")
progress:Complete("Finished")
```

### Runtime Diagnostics

Summarizes build metadata, uptime, executor, FPS, worst frame, memory, ping, UI-root count, tracked connections, ESP entries, notification counts, source-cache statistics, slow modules, and isolated startup errors. It provides a copyable health report and can refresh automatically.

### Animation Logger

Captures `Animator.AnimationPlayed` from self, players, and NPCs. It supports capture range, source filtering, deduplication, blacklist persistence, searchable history, JSON export, source-path copying, track metadata, and direct Animation Viewer integration.

### Animation Viewer

A separate draggable `ViewportFrame` player. It supports source/local/R6/R15 rigs, play and pause, frame stepping, ±0.10-second stepping, timeline scrubbing, speed, looping, camera orbit and zoom, keyframe/marker discovery, copying IDs, and a callback for using the current preview time.

### Remote Spy / Monitor

Discovers remotes, logs inbound `OnClientEvent` traffic, and logs outbound calls made through its wrapper API. It includes safe argument serialization, search, direction filtering, call-site metadata where available, return timing, copy/export, and Instance Inspector integration.

It does **not** hook `__namecall`, replace game callbacks, intercept unrelated scripts, replay calls, or provide a remote-firing UI.

Wrapper API:

```lua
local spy = ctx.devtools.apis.remoteSpy
spy:FireServer(remoteEvent, arg1, arg2)
local result = spy:InvokeServer(remoteFunction, arg1)
spy:Log(remote, "CUSTOM", anyValue)
```

### Console Logger

Searchable `LogService.MessageOut` and `ScriptContext.Error` capture with filters, stack traces, copying, and export.

### Performance Profiler

FPS, frame-time average/p95/p99/worst, memory, ping, instances, player count, spike history, compact overlay, graph, and copyable snapshots.

### Instance Inspector

Read-only path resolver, common-property viewer, attributes, child navigation, property watches, copyable paths, and APIs other modules can use to select an Instance.

## Integration

The initializer must run **before** `library:Init()` so it can create the Developer tab and sections. Call every returned module's `setup` function **after** `library:Init()`.

```lua
local DEV_INIT_URL = "https://raw.githubusercontent.com/PPainez/idk/main/devmodules/init.luau"
local source = game:HttpGet(DEV_INIT_URL, false)
local chunk, compileError = loadstring(source)
assert(chunk, "devmodules init compile failed: " .. tostring(compileError))

local createDevModules = chunk()
local devModules = createDevModules(ctx)

-- Existing menu initialization
local initialized, initError = library:Init()
assert(initialized, tostring(initError))

for _, module in ipairs(devModules) do
    if type(module.setup) == "function" then
        local ok, err = pcall(module.setup)
        if not ok then
            warn("[xanhub dev] " .. tostring(module.name) .. " setup failed: " .. tostring(err))
        end
    end
end
```

Your `ctx` should expose the same common fields used by the modular ESP:

```lua
ctx.library
ctx.runtime
ctx.Players
ctx.LocalPlayer
ctx.RunService
ctx.Workspace
ctx.getRoot(character?)
ctx.getHumanoid(character?)
ctx.addConnection(signal, callback)
ctx.createOverlayRoot()
ctx.createRounded(instance, radius)
ctx.notify(message, duration)
```

`dev_shared.luau` creates `ctx.devtools`, the Developer tab, shared windows, and these registries:

```lua
ctx.devtools.modules
ctx.devtools.apis
ctx.devtools.windows
ctx.devtools.shared
```

## Animation Viewer API

```lua
local viewer = ctx.devtools.apis.animationViewer
viewer:Open("123456789")
viewer:Open(loggerEntry)
viewer:SetTime(0.35)
print(viewer:GetTime())
viewer:SetUseTimeCallback(function(time, entry)
    print("selected time", time, entry and entry.id)
end)
```

## Animation Logger API

```lua
local logger = ctx.devtools.apis.animationLogger
logger:Open()
logger:OnEntry(function(entry)
    print(entry.id, entry.sourceName, entry.sourceType)
end)
logger:Blacklist("123456789", true)
```

All modules register cleanup through the xanhub library and remove their windows, connections, cloned rigs, event objects, and overlays during unload.

## Notification API

```lua
local notices = ctx.devtools.apis.notifications
notices:Info("Ready")
notices:Success("Saved", {channel = "config", key = "save-status"})
notices:Warning("High frame time", {duration = 6})
notices:Error("Module failed", {sticky = true})
notices:Open()
```

## Runtime Diagnostics API

```lua
local diagnostics = ctx.devtools.apis.runtimeDiagnostics
local snapshot = diagnostics:Snapshot()
print(diagnostics:Format(snapshot))
diagnostics:Copy()
diagnostics:Open()
```
