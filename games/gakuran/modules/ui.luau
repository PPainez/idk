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
	local basketballTab = library:AddTab("Basketball", 6)
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
		basketballLeft = basketballTab:AddColumn(),
		basketballRight = basketballTab:AddColumn(),
		parryLeft = parryTab:AddColumn(),
		parryRight = parryTab:AddColumn(),
	}

	local intro = columns.homeLeft:AddSection("xanhub Gakuran")
	intro:AddLabel("Game: (学乱) Gakuran")
	intro:AddLabel("Edition: Featured · live systems")
	intro:AddLabel("Place ID: " .. tostring(game.PlaceId))
	intro:AddLabel("Expected: " .. tostring(ctx.gakuran.placeId))
	intro:AddDivider("Modules")
	intro:AddLabel("Combat — auto parry · rear dodge · attack DB")
	intro:AddLabel("Visuals — name/style/grade/stamina ESP")
	intro:AddLabel("Self — stamina · stun · dodge/parry CD · ragdoll")
	intro:AddLabel("Rhythm — humanized auto-play (all instruments)")
	intro:AddLabel("Basketball — green release · rim/ball ESP")
	intro:AddLabel("Parry Builder — animation profiles for AP")

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
	ctx.refs.featureStatus = runtimeSection:AddLabel("Loaded: —")
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
			basketball = basketballTab,
			parry = parryTab,
		},
		columns = columns,
	}
end
