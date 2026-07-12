--[[
    xanhub | Gakuran

    Game-specific edition for (学乱) Gakuran.
    Menu outline only — feature logic wired later.
]]

local GAKURAN_PLACE_ID = 128736949265057

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

	assert(source, "[xanhub gakuran] bootstrap failed for " .. path .. ": " .. tostring(loadError))

	local chunk, compileError = loadstring(source)
	assert(chunk, "[xanhub gakuran] compile failed for " .. path .. ": " .. tostring(compileError))

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

if type(runtime) == "table" and runtime.forceFreshModules == true then
	moduleLoader.clear()
end

local UI_URL = (type(runtime) == "table" and runtime.uiUrl) or Constants.uiUrl()

local function acquireLibrary()
	if type(runtime) == "table" and runtime.reloadedFromUpdate == true then
		runtime.library = nil
	end

	if type(runtime) == "table"
		and type(runtime.library) == "table"
		and not runtime.library.unloaded then
		return runtime.library
	end

	local source, fetchError = Http.fetchSource(UI_URL)
	assert(source, "[xanhub gakuran] UI request failed: " .. tostring(fetchError))

	local chunk, compileError = Http.compileSource(source)
	assert(chunk, "[xanhub gakuran] UI compile failed: " .. tostring(compileError))

	local loaded = chunk()
	assert(type(loaded) == "table", "[xanhub gakuran] UI library returned an invalid value")

	runtime = type(runtime) == "table" and runtime or {}
	runtime.library = loaded
	runtime.uiUrl = UI_URL
	runtime.repositoryRoot = REPOSITORY_ROOT
	runtime.placeId = game.PlaceId
	runtime.universeId = game.GameId
	runtime.edition = "gakuran"
	env.XANHUB_RUNTIME = runtime
	return loaded
end

local library = acquireLibrary()
library:SetTitle("xanhub | Gakuran")
library:SetAccent(Color3.fromRGB(255, 168, 64))
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
	parry = {
		profiles = {},
		selected = nil,
	},
	rhythm = {},
	basketball = {},
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
ctx.moduleLoader = moduleLoader
ctx.gakuran = {
	placeId = GAKURAN_PLACE_ID,
	name = "Gakuran",
}

local uiResult = moduleLoader.load("games/gakuran/modules/ui.luau")(ctx)
ctx.columns = uiResult.columns
ctx.tabs = uiResult.tabs

local devtoolsController = moduleLoader.load("universal/modules/devtools.luau")(ctx)
local parryBuilder = moduleLoader.load("games/gakuran/modules/parry_builder.luau")(ctx)

local menuModules = {
	"games/gakuran/modules/combat.luau",
	"games/gakuran/modules/visuals.luau",
	"games/gakuran/modules/rhythm.luau",
	"games/gakuran/modules/basketball.luau",
}

local featureSetups = {}
for _, modulePath in ipairs(menuModules) do
	local feature = moduleLoader.load(modulePath)(ctx)
	if feature and type(feature.setup) == "function" then
		table.insert(featureSetups, feature.setup)
	end
end

local initialized, initError = library:Init()
assert(initialized, "[xanhub gakuran] initialization failed: " .. tostring(initError))

ctx.createOverlayRoot()
for _, setup in ipairs(featureSetups) do
	setup()
end
if devtoolsController and type(devtoolsController.setup) == "function" then
	devtoolsController.setup()
end
if parryBuilder and type(parryBuilder.setup) == "function" then
	parryBuilder.setup()
end

library:AddCleanup(function()
	state.unloading = true

	if type(runtime) == "table" then
		runtime.unloading = true
	end

	for flag, value in pairs(library.flags or {}) do
		if type(flag) == "string"
			and string.sub(flag, 1, 8) == "Gakuran "
			and type(value) == "boolean" then
			library.flags[flag] = false
		end
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

local detected = game.PlaceId == GAKURAN_PLACE_ID
if ctx.refs.runtimeStatus then
	ctx.refs.runtimeStatus.Text = detected
		and "Status: Gakuran edition · menu outline ready"
		or "Status: wrong place — Gakuran features unavailable"
end

ctx.notify("xanhub Gakuran edition loaded", 3)
print("[xanhub] Gakuran loaded for place", game.PlaceId)

return {
	library = library,
	runtime = runtime,
	state = state,
}
