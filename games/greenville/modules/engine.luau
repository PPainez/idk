--[[
    xanhub | Greenville | engine

    Engine and transmission controls.
]]

return function(ctx)
	local controller = assert(ctx.tuningController, "tuning controller is unavailable")
	local settings = controller.settings

	local engineSection = ctx.columns.engine:AddSection("Engine Tuning")
	engineSection:AddToggle({
		text = "Enable Tune",
		flag = "Greenville Tune Enabled",
		state = true,
		callback = function(enabled)
			settings.Enabled = enabled
			if enabled then
				controller.applySafely()
			else
				controller.restoreCurrentTune()
			end
		end,
	})

	engineSection:AddSlider({
		text = "Horsepower",
		flag = "Greenville Horsepower",
		min = 0,
		max = 1200,
		value = settings.Horsepower,
		suffix = " HP",
		callback = function(value)
			settings.Horsepower = value
			controller.applySafely()
		end,
	})

	engineSection:AddSlider({
		text = "Redline",
		flag = "Greenville Redline",
		min = 4000,
		max = 12000,
		value = settings.Redline,
		suffix = " RPM",
		float = 100,
		callback = function(value)
			settings.Redline = value
			controller.applySafely()
		end,
	})

	engineSection:AddToggle({
		text = "Lightweight Chassis",
		flag = "Greenville Lightweight Chassis",
		state = false,
		callback = function(enabled)
			settings.Lightweight = enabled
			controller.applySafely()
		end,
	})

	local gearboxSection = ctx.columns.engine:AddSection("Transmission")
	gearboxSection:AddToggle({
		text = "Performance Gearbox",
		flag = "Greenville Performance Gearbox",
		state = false,
		callback = function(enabled)
			settings.PerformanceGearbox = enabled
			controller.applySafely()
		end,
	})

	return true
end
