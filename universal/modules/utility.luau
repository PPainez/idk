--[[
    xanhub | universal | utility module

    Quality-of-life toggles and server utilities with complete restoration.
]]

return function(ctx)
	local utilitySection = ctx.columns.utilityLeft:AddSection("Quality of Life")
	utilitySection:AddToggle({text = "Anti-AFK", flag = "Universal Anti AFK", state = false})
	utilitySection:AddToggle({text = "Hide Roblox Interface", flag = "Universal Hide CoreGui", state = false})
	utilitySection:AddButton({
		text = "Reset Character",
		callback = function()
			local humanoid = ctx.getHumanoid()
			if humanoid then
				local ok, err = pcall(function()
					humanoid.Health = 0
				end)
				if not ok then
					ctx.notify("Reset failed: " .. tostring(err), 3)
				end
			else
				ctx.notify("Character is unavailable", 2)
			end
		end,
	})

	local serverSection = ctx.columns.utilityRight:AddSection("Server")
	serverSection:AddButton({
		text = "Copy Server Join Data",
		callback = function()
			ctx.safeClipboard(string.format("PlaceId=%s\nJobId=%s", game.PlaceId, game.JobId))
		end,
	})
	serverSection:AddButton({
		text = "Rejoin Current Server",
		callback = function()
			ctx.notify("Rejoining current server...", 2)
			local ok, err = pcall(function()
				ctx.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, ctx.LocalPlayer)
			end)
			if not ok then
				local fallbackOk, fallbackErr = pcall(function()
					ctx.TeleportService:Teleport(game.PlaceId, ctx.LocalPlayer)
				end)
				if not fallbackOk then
					ctx.notify("Rejoin failed: " .. tostring(fallbackErr or err), 4)
				end
			end
		end,
	})
	serverSection:AddLabel("Featured games are configured in loader.luau")

	local function setupUtilityRuntime()
		local antiAfkConnection
		local coreOriginal = {}
		local coreTypes = {
			Enum.CoreGuiType.Backpack,
			Enum.CoreGuiType.Chat,
			Enum.CoreGuiType.Health,
			Enum.CoreGuiType.PlayerList,
			Enum.CoreGuiType.EmotesMenu,
		}

		for _, coreType in ipairs(coreTypes) do
			local ok, enabled = pcall(function()
				return ctx.StarterGui:GetCoreGuiEnabled(coreType)
			end)
			if ok then
				coreOriginal[coreType] = enabled
			end
		end

		local function stopAntiAfk()
			ctx.disconnect(antiAfkConnection)
			antiAfkConnection = nil
		end

		local function setAntiAfk(enabled)
			stopAntiAfk()
			if enabled ~= true then
				return
			end

			antiAfkConnection = ctx.addConnection(ctx.LocalPlayer.Idled, function()
				pcall(function()
					ctx.VirtualUser:CaptureController()
					ctx.VirtualUser:ClickButton2(Vector2.new(0, 0))
				end)
			end)
		end

		local antiAfkOption = ctx.option("Universal Anti AFK")
		if antiAfkOption then
			local previousCallback = antiAfkOption.callback
			antiAfkOption.callback = function(enabled, ...)
				if type(previousCallback) == "function" then
					pcall(previousCallback, enabled, ...)
				end
				setAntiAfk(enabled)
			end
		end

		local function setCoreHidden(hidden)
			for _, coreType in ipairs(coreTypes) do
				local restore = coreOriginal[coreType]
				if restore ~= nil then
					pcall(function()
						ctx.StarterGui:SetCoreGuiEnabled(coreType, hidden and false or restore)
					end)
				end
			end
		end

		local coreOption = ctx.option("Universal Hide CoreGui")
		if coreOption then
			local previousCallback = coreOption.callback
			coreOption.callback = function(hidden, ...)
				if type(previousCallback) == "function" then
					pcall(previousCallback, hidden, ...)
				end
				setCoreHidden(hidden == true)
			end
		end

		-- Respect config-autoloaded values even when the control callback ran before
		-- this module's runtime was attached.
		setAntiAfk(ctx.library.flags["Universal Anti AFK"] == true)
		setCoreHidden(ctx.library.flags["Universal Hide CoreGui"] == true)

		ctx.library:AddCleanup(function()
			stopAntiAfk()
			for _, coreType in ipairs(coreTypes) do
				local restore = coreOriginal[coreType]
				if restore ~= nil then
					pcall(function()
						ctx.StarterGui:SetCoreGuiEnabled(coreType, restore)
					end)
				end
			end
		end)
	end

	return {setup = setupUtilityRuntime}
end
