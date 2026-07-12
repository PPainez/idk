--[[
    xanhub | universal | utility module

    Quality-of-life toggles and server utilities.
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
				humanoid.Health = 0
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
			pcall(function()
				ctx.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, ctx.LocalPlayer)
			end)
		end,
	})
	serverSection:AddLabel("Featured games are configured in main/loader.luau")

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

		local antiAfkOption = ctx.option("Universal Anti AFK")
		if antiAfkOption then
			antiAfkOption.callback = function(enabled)
				ctx.disconnect(antiAfkConnection)
				antiAfkConnection = nil
				if enabled then
					antiAfkConnection = ctx.LocalPlayer.Idled:Connect(function()
						pcall(function()
							ctx.VirtualUser:CaptureController()
							ctx.VirtualUser:ClickButton2(Vector2.new(0, 0))
						end)
					end)
				end
			end
		end

		local coreOption = ctx.option("Universal Hide CoreGui")
		if coreOption then
			coreOption.callback = function(hidden)
				for _, coreType in ipairs(coreTypes) do
					pcall(function()
						ctx.StarterGui:SetCoreGuiEnabled(coreType, hidden and false or coreOriginal[coreType])
					end)
				end
			end
		end

		ctx.library:AddCleanup(function()
			ctx.disconnect(antiAfkConnection)
			for _, coreType in ipairs(coreTypes) do
				pcall(function()
					ctx.StarterGui:SetCoreGuiEnabled(coreType, coreOriginal[coreType])
				end)
			end
		end)
	end

	return { setup = setupUtilityRuntime }
end
