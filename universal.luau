--[[
    xanhub | Universal

    Orchestrates feature modules loaded from universal/modules/.
    Runs through loader.luau or standalone.
]]

local runtime = ...
local env = (type(getgenv) == "function" and getgenv()) or _G

if type(runtime) ~= "table" then
	runtime = env.XANHUB_RUNTIME
end

local REPOSITORY_ROOT = (type(runtime) == "table" and runtime.repositoryRoot)
	or "https://raw.githubusercontent.com/PPainez/idk/main"

local function bootstrapModule(path)
	local source, loadError

	local ok, result = pcall(function()
		return game:HttpGet(REPOSITORY_ROOT .. "/" .. path, true)
	end)

	if ok and type(result) == "string" and #result > 20 then
		source = result
	else
		loadError = tostring(result or "request failed")
	end

	assert(source, "[xanhub universal] bootstrap failed for " .. path .. ": " .. tostring(loadError))

	local chunk, compileError = loadstring(source)
	assert(chunk, "[xanhub universal] compile failed for " .. path .. ": " .. tostring(compileError))

	return chunk()
end

local Http = bootstrapModule("shared/http.luau")
local Constants = bootstrapModule("shared/constants.luau")
local Connection = bootstrapModule("shared/connection.luau")
local ModuleLoader = bootstrapModule("shared/module_loader.luau")
local createContext = bootstrapModule("universal/lib/context.luau")

Http.setUserAgent(Constants.UNIVERSAL_USER_AGENT)

local moduleLoader = ModuleLoader.new(Http, function(path)
	return Constants.repositoryUrls(path)
end)

local UI_URL = (type(runtime) == "table" and runtime.uiUrl) or Constants.uiUrl()

local function acquireLibrary()
	if type(runtime) == "table"
		and type(runtime.library) == "table"
		and not runtime.library.unloaded then
		return runtime.library
	end

	local source, fetchError = Http.fetchSource(UI_URL)
	assert(source, "[xanhub universal] UI request failed: " .. tostring(fetchError))

	local chunk, compileError = Http.compileSource(source)
	assert(chunk, "[xanhub universal] UI compile failed: " .. tostring(compileError))

	local loaded = chunk()
	assert(type(loaded) == "table", "[xanhub universal] UI library returned an invalid value")

	runtime = type(runtime) == "table" and runtime or {}
	runtime.library = loaded
	runtime.uiUrl = UI_URL
	runtime.repositoryRoot = REPOSITORY_ROOT
	runtime.placeId = game.PlaceId
	runtime.universeId = game.GameId
	env.XANHUB_RUNTIME = runtime
	return loaded
end

local library = acquireLibrary()
library:SetTitle("xanhub | Universal")
library:SetAccent(Color3.fromRGB(0, 170, 255))
library:SetTweening(false)

local services = {
	Players = game:GetService("Players"),
	RunService = game:GetService("RunService"),
	UserInputService = game:GetService("UserInputService"),
	Lighting = game:GetService("Lighting"),
	TweenService = game:GetService("TweenService"),
	TeleportService = game:GetService("TeleportService"),
	VirtualUser = game:GetService("VirtualUser"),
	StarterGui = game:GetService("StarterGui"),
	Workspace = game:GetService("Workspace"),
}

local state = {
	unloading = false,
	reloading = false,
	connections = {},
	original = {},
	esp = {},
	overlays = {},
	fly = {},
	noclipOriginal = setmetatable({}, { __mode = "k" }),
	movementOriginal = setmetatable({}, { __mode = "k" }),
	effectOriginal = setmetatable({}, { __mode = "k" }),
}

local connections = Connection.new(library, state.connections)

local ctx = createContext({
	library = library,
	runtime = runtime,
	state = state,
	env = env,
	connections = connections,
	services = services,
	columns = nil,
	tabs = nil,
	refs = {},
})

ctx.shared = {
	Http = Http,
	Constants = Constants,
}

local uiResult = moduleLoader.load("universal/modules/ui.luau")(ctx)
ctx.columns = uiResult.columns
ctx.tabs = uiResult.tabs

local updateController = moduleLoader.load("universal/modules/updates.luau")(ctx)

local featureSetups = {}
for _, modulePath in ipairs({
	"universal/modules/movement.luau",
	"universal/modules/esp.luau",
	"universal/modules/overlay.luau",
	"universal/modules/world.luau",
	"universal/modules/utility.luau",
}) do
	local feature = moduleLoader.load(modulePath)(ctx)
	if feature and type(feature.setup) == "function" then
		table.insert(featureSetups, feature.setup)
	end
end

moduleLoader.load("universal/modules/keybinds.luau")(ctx)

local initialized, initError = library:Init()
assert(initialized, "[xanhub universal] initialization failed: " .. tostring(initError))

task.defer(function()
	updateController.check(false)
end)

state.original.cameraFov = services.Workspace.CurrentCamera
	and services.Workspace.CurrentCamera.FieldOfView
	or 70

ctx.createOverlayRoot()
for _, setup in ipairs(featureSetups) do
	setup()
end

library:AddCleanup(function()
	state.unloading = true
	updateController.cancel()

	if type(runtime) == "table" then
		runtime.unloading = true
	end

	for flag, value in pairs(library.flags or {}) do
		if type(flag) == "string"
			and string.sub(flag, 1, 10) == "Universal "
			and type(value) == "boolean" then
			library.flags[flag] = false
		end
	end
	state.aimTarget = nil

	local camera = services.Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = state.original.cameraFov or 70
	end

	connections:disconnectAll()

	if state.overlays.root then
		pcall(function()
			state.overlays.root:Destroy()
		end)
		state.overlays.root = nil
	end
end)

library:SetOpen(true)
library:selectTab(ctx.tabs.home)
if ctx.refs.runtimeStatus then
	ctx.refs.runtimeStatus.Text = "Status: ready | Universal"
end
ctx.notify("Universal menu loaded", 3)
print("[xanhub] Universal loaded for place", game.PlaceId)

return {
	library = library,
	runtime = runtime,
	state = state,
}
