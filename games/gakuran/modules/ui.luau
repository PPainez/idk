--[[
    xanhub | gakuran | ui

    Tab layout and home sections for the Gakuran edition.
]]

return function(ctx)
	local library = ctx.library

	local homeTab = library:AddTab("Home", 1)
	local combatTab = library:AddTab("Combat", 2)
	local visualsTab = library:AddTab("Visuals", 3)
	local selfTab = library:AddTab("Self", 4)
	local rhythmTab = library:AddTab("Rhythm", 5)
	local qolTab = library:AddTab("QOL", 6)
	local parryTab = library:AddTab("Parry Builder", 7)

	local columns = {
		homeLeft = homeTab:AddColumn(),
		homeRight = homeTab:AddColumn(),
		combatLeft = combatTab:AddColumn(),
		combatRight = combatTab:AddColumn(),
		visualsLeft = visualsTab:AddColumn(),
		visualsRight = visualsTab:AddColumn(),
		selfLeft = selfTab:AddColumn(),
		selfRight = selfTab:AddColumn(),
		rhythmLeft = rhythmTab:AddColumn(),
		rhythmRight = rhythmTab:AddColumn(),
		qolLeft = qolTab:AddColumn(),
		qolRight = qolTab:AddColumn(),
		parryLeft = parryTab:AddColumn(),
		parryRight = parryTab:AddColumn(),
	}
	-- Back-compat aliases (basketball module / older hooks)
	columns.basketballLeft = columns.qolLeft
	columns.basketballRight = columns.qolRight

	local intro = columns.homeLeft:AddSection("xanhub Gakuran")
	intro:AddLabel("Game: (学乱) Gakuran")
	intro:AddLabel("Edition: Featured · live systems")
	intro:AddLabel("Place ID: " .. tostring(game.PlaceId))
	intro:AddLabel("Expected: " .. tostring(ctx.gakuran.placeId))
	local buildRevision = ctx.runtime and ctx.runtime.buildRevision
	intro:AddLabel("Build: " .. tostring(ctx.runtime and ctx.runtime.buildVersion or "unknown") .. " · " .. (buildRevision and string.sub(buildRevision, 1, 10) or "local"))
	intro:AddDivider("Modules")
	intro:AddLabel("Combat — auto parry · rear dodge · attack DB")
	intro:AddLabel("Visuals — name/style/grade/stamina ESP")
	intro:AddLabel("Self — stamina · stun · dodge/parry CD · ragdoll")
	intro:AddLabel("Rhythm — humanized auto-play (all instruments)")
	intro:AddLabel("QOL — basketball · lighting · FOV · zoom · AFK")
	intro:AddLabel("Parry Builder — animation profiles for AP")
	intro:AddLabel("Settings → Configs: place-scoped autoload")

	local quick = columns.homeRight:AddSection("Quick Actions")
	quick:AddButton({
		text = "Copy Place ID",
		callback = function()
			ctx.safeClipboard(game.PlaceId)
		end,
	})
	quick:AddButton({
		text = "Copy Job ID",
		callback = function()
			ctx.safeClipboard(game.JobId)
		end,
	})
	quick:AddButton({
		text = "Rejoin Server",
		callback = function()
			ctx.notify("Rejoining...")
			local ok = pcall(function()
				ctx.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, ctx.LocalPlayer)
			end)
			if not ok then
				pcall(function()
					ctx.TeleportService:Teleport(game.PlaceId, ctx.LocalPlayer)
				end)
			end
		end,
	})
	quick:AddButton({
		text = "Save + Autoload Cfg (this place)",
		callback = function()
			if type(library.SetAutoloadConfig) ~= "function" then
				ctx.notify("Config API missing", 3)
				return
			end
			local name = library:ResolveConfigName(library.flags["Config List"] or library.flags["Config Name"])
			if not name or name == "" then
				name = "gakuran"
			end
			if not table.find(library:GetConfigs(), name) then
				library:CreateConfig(name)
			end
			if library:SaveConfig(name) and library:SetAutoloadConfig(name) then
				ctx.notify("Saved + autoload '" .. name .. "' @ " .. tostring(game.PlaceId), 3)
			else
				ctx.notify("Save/autoload failed", 3)
			end
			if library.UpdateAutoloadLabel then
				library:UpdateAutoloadLabel()
			end
		end,
	})

	local runtimeSection = columns.homeRight:AddSection("Runtime")
	ctx.refs.runtimeStatus = runtimeSection:AddLabel("Status: initializing")
	ctx.refs.featureStatus = runtimeSection:AddLabel("Loaded: —")
	runtimeSection:AddButton({
		text = "Copy Build Info",
		callback = function()
			local runtime = ctx.runtime or {}
			ctx.safeClipboard(string.format(
				"xanhub-gakuran build=%s revision=%s loader=%s place=%s",
				tostring(runtime.buildVersion or "unknown"),
				tostring(runtime.buildRevision or "local"),
				tostring(runtime.loaderVersion or "standalone"),
				tostring(game.PlaceId)
			))
		end,
	})
	runtimeSection:AddButton({
		text = "Print Active Flags",
		callback = function()
			local count = 0
			for flag, value in pairs(library.flags) do
				if type(flag) == "string" and string.sub(flag, 1, 8) == "Gakuran " and value == true then
					print("[xanhub gakuran active]", flag)
					count = count + 1
				end
			end
			ctx.notify(count .. " active Gakuran flags (console)", 2)
		end,
	})
	runtimeSection:AddButton({
		text = "Unload xanhub",
		callback = function()
			if library.Unload then
				library:Unload()
			end
		end,
	})
	runtimeSection:AddLabel("Dev Tools: Settings tab · animation logger/viewer")

	return {
		tabs = {
			home = homeTab,
			combat = combatTab,
			visuals = visualsTab,
			self = selfTab,
			rhythm = rhythmTab,
			qol = qolTab,
			basketball = qolTab, -- alias
			parry = parryTab,
		},
		columns = columns,
	}
end
