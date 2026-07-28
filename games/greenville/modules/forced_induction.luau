--[[
    xanhub | Greenville | forced induction

    Turbocharger and supercharger controls.
]]

return function(ctx)
	local controller = assert(ctx.tuningController, "tuning controller is unavailable")
	local settings = controller.settings
	local boostSection = ctx.columns.boost:AddSection("Forced Induction")

	boostSection:AddSlider({
		text = "Turbochargers",
		flag = "Greenville Turbochargers",
		min = 0,
		max = 4,
		value = settings.Turbochargers,
		float = 1,
		callback = function(value)
			settings.Turbochargers = math.floor(value)
			controller.applySafely()
		end,
	})

	boostSection:AddSlider({
		text = "Superchargers",
		flag = "Greenville Superchargers",
		min = 0,
		max = 2,
		value = settings.Superchargers,
		float = 1,
		callback = function(value)
			settings.Superchargers = math.floor(value)
			controller.applySafely()
		end,
	})

	return true
end
