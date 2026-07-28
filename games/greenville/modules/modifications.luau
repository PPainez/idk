--[[
    xanhub | Greenville | modifications

    Brake controls and explicit apply/restore actions.
]]

return function(ctx)
	local library = ctx.library
	local controller = assert(ctx.tuningController, "tuning controller is unavailable")
	local settings = controller.settings
	local modificationSection = ctx.columns.boost:AddSection("Modifications")

	modificationSection:AddToggle({
		text = "Upgraded Brakes",
		flag = "Greenville Upgraded Brakes",
		state = false,
		callback = function(enabled)
			settings.UpgradedBrakes = enabled
			controller.applySafely()
		end,
	})

	modificationSection:AddButton({
		text = "Apply Tune",
		callback = function()
			controller.invalidate()
			controller.applySafely()
		end,
	})

	modificationSection:AddButton({
		text = "Restore Stock Tune",
		callback = function()
			settings.Enabled = false

			local toggle = library.options["Greenville Tune Enabled"]
			if toggle and toggle.SetState then
				toggle:SetState(false)
			else
				controller.restoreCurrentTune()
			end
		end,
	})

	return true
end
