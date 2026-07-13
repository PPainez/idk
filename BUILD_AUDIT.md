# Build Audit

## Scope

The repository was scanned as a complete build, including the loader, UI library, shared runtime, Universal modules, Gakuran host/modules, developer modules, release scripts, and documentation.

## Corrected during this pass

- Raw GitHub cache inconsistencies and stale-module loading.
- Loader errors that could include the entire downloaded source body.
- Optional module failures taking down the full menu.
- Duplicate developer-notification lifecycle setup.
- Update checks comparing against saved history rather than the build actually running.
- Update confirmation path using an invalid scheduler name.
- Rendering quality being restored to `Automatic` rather than its original value.
- Post effects and Atmosphere objects added after startup not being tracked.
- Particle/effect writes failing the entire update loop when an Instance disappears.
- Universal Anti-AFK bypassing the shared connection tracker.
- Gakuran custom FOV not restoring when disabled.
- Gakuran effects, particles, FOV, and rendering quality not being fully restored on unload.

## Validation performed

- Every repository `.luau` file was parsed after normalizing Luau-only compound assignments for the parser.
- Every module path in runtime manifests was checked against the repository tree.
- The generated build manifest records SHA-256 hashes for every Luau source.
- The release verifier independently recomputes every file hash and the aggregate build revision.

## Runtime note

Static validation cannot reproduce every Roblox game, executor, permission, API, or UI-parent combination. The build still requires a live Volt/Roblox smoke test for executor-specific behavior. Runtime Diagnostics is included to make any remaining module or environment failure visible without crashing the rest of the hub.
