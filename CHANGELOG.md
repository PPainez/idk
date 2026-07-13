# Changelog

## 1.3.0 — Full build reliability pass

### Runtime and loading

- Added generated `build.luau` metadata with a repository-wide source revision.
- Added revision-based cache busting for UI, Universal, game, shared, and developer modules.
- Rebuilt shared HTTP handling with executor fallbacks, marker validation, short error bodies, request metadata, and safer compilation.
- Added cached module loading, recursion protection, invalidation, source statistics, and isolated optional-module failures.
- Updated the Volt-compatible loader to resolve build metadata before loading feature sources.
- Added safe traceback fallbacks for executors without a complete `debug` library.

### Updates

- Replaced expensive source-by-source checks with a fast `build.luau` check.
- Kept an all-or-nothing fallback manifest when build metadata is unreachable.
- Fixed false update prompts when the current loader already started the newest revision.
- Compile-checks the replacement Universal script before unloading the active build.
- Reloads with a fresh runtime and revision so no stale shared/module cache is reused.

### Module lifecycle

- Universal and Gakuran now track module load/setup status and isolate optional module errors.
- Fixed duplicate notification setup when the Developer tab was enabled after startup.
- Added complete rendering-quality, lighting-effect, particle, FOV, CoreGui, and connection restoration.
- Fixed a Universal update prompt typo that could stop the confirmation from appearing.

### Developer tools

- Added Runtime Diagnostics with build, module, source-cache, connection, UI-root, notification, FPS, frame-time, memory, and ping information.
- Integrated the advanced stacked Notification Center into runtime startup and module notices.
- Kept Remote Spy limited to inbound observation and explicit wrapper calls; it does not hook unrelated game scripts or provide replay controls.

### Release tooling

- Added `tools/update-build.ps1`.
- Added `tools/verify-build.ps1`.
- Updated `push.bat` to regenerate and verify the build manifest before staging.
