--[[
    xanhub | universal | home UI

    Tab layout and home/quick-action sections.
]]

return function(ctx)
	local library = ctx.library

	local homeTab = library:AddTab("Home", 1)
	local combatTab = library:AddTab("Combat", 2)
	local visualsTab = library:AddTab("Visuals", 3)
	local playerTab = library:AddTab("Player", 4)
	local worldTab = library:AddTab("World", 5)
	local utilityTab = library:AddTab("Utility", 6)
	local bindsTab = library:AddTab("Keybinds", 7)

	local columns = {
		homeLeft = homeTab:AddColumn(),
		homeRight = homeTab:AddColumn(),
		combatLeft = combatTab:AddColumn(),
		combatRight = combatTab:AddColumn(),
		visualsLeft = visualsTab:AddColumn(),
		visualsRight = visualsTab:AddColumn(),
		playerLeft = playerTab:AddColumn(),
		playerRight = playerTab:AddColumn(),
		worldLeft = worldTab:AddColumn(),
		worldRight = worldTab:AddColumn(),
		utilityLeft = utilityTab:AddColumn(),
		utilityRight = utilityTab:AddColumn(),
		bindsLeft = bindsTab:AddColumn(),
		bindsRight = bindsTab:AddColumn(),
	}

	local intro = columns.homeLeft:AddSection("xanhub Universal")
	intro:AddLabel("Loaded for: " .. tostring(game.Name))
	intro:AddLabel("Place ID: " .. tostring(game.PlaceId))
	intro:AddLabel("Universe ID: " .. tostring(game.GameId))
	local buildRevision = ctx.runtime and ctx.runtime.buildRevision
	local buildVersion = ctx.runtime and ctx.runtime.buildVersion or "unknown"
	intro:AddLabel("Build: " .. tostring(buildVersion) .. " · " .. (buildRevision and string.sub(buildRevision, 1, 10) or "local"))
	intro:AddLabel("Signature ESP · Targeting · Movement · Developer tools")
	intro:AddLabel("General client tools with complete unload restoration")

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

	local runtimeSection = columns.homeRight:AddSection("Runtime")
	ctx.refs.runtimeStatus = runtimeSection:AddLabel("Status: initializing")
	runtimeSection:AddButton({
		text = "Copy Build Info",
		callback = function()
			local runtime = ctx.runtime or {}
			ctx.safeClipboard(string.format(
				"xanhub build=%s revision=%s loader=%s place=%s",
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
			for flag, value in pairs(library.flags) do
				if value == true then
					print("[xanhub active]", flag)
				end
			end
		end,
	})

	return {
		tabs = {
			home = homeTab,
			combat = combatTab,
			visuals = visualsTab,
			player = playerTab,
			world = worldTab,
			utility = utilityTab,
			binds = bindsTab,
		},
		columns = columns,
	}
end
