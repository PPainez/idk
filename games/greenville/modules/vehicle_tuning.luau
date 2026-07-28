--[[
    xanhub | Greenville | vehicle tuning

    Owns vehicle discovery, stock snapshots, tune application, and cleanup.
]]

return function(ctx)
	local library = ctx.library
	local player = ctx.LocalPlayer
	local sessionVehicles = ctx.Workspace:WaitForChild("SessionVehicles")
	local tuningState = ctx.state.tuning

	tuningState.settings = {
		Enabled = true,
		Horsepower = 200,
		Redline = 10000,
		Turbochargers = 0,
		Superchargers = 0,
		PerformanceGearbox = false,
		UpgradedBrakes = false,
		Lightweight = false,
	}
	tuningState.cachedCar = nil
	tuningState.cachedTune = nil
	tuningState.originalTune = nil
	tuningState.running = false
	tuningState.lastError = nil

	local settings = tuningState.settings
	local controller = {
		settings = settings,
	}

	local function cloneTable(source)
		if type(source) ~= "table" then
			return source
		end

		local copy = {}
		for key, value in pairs(source) do
			if type(value) == "table" then
				copy[key] = cloneTable(value)
			else
				copy[key] = value
			end
		end
		return copy
	end

	local function saveOriginalTune(tune)
		return {
			Horsepower = tune.Horsepower,
			E_Horsepower = tune.E_Horsepower,
			Redline = tune.Redline,
			ClutchTol = tune.ClutchTol,
			TurboEnabled = tune.TurboEnabled,
			Turbochargers = tune.Turbochargers,
			Superchargers = tune.Superchargers,
			FinalDrive = tune.FinalDrive,
			Ratios = cloneTable(tune.Ratios),
			BrakeForce = tune.BrakeForce,
			PBrakeForce = tune.PBrakeForce,
			Weight = tune.Weight,
		}
	end

	function controller.restoreCurrentTune()
		local cachedTune = tuningState.cachedTune
		local originalTune = tuningState.originalTune
		if not cachedTune or not originalTune then
			return
		end

		cachedTune.Horsepower = originalTune.Horsepower
		cachedTune.E_Horsepower = originalTune.E_Horsepower
		cachedTune.Redline = originalTune.Redline
		cachedTune.ClutchTol = originalTune.ClutchTol
		cachedTune.TurboEnabled = originalTune.TurboEnabled
		cachedTune.Turbochargers = originalTune.Turbochargers
		cachedTune.Superchargers = originalTune.Superchargers
		cachedTune.FinalDrive = originalTune.FinalDrive
		cachedTune.Ratios = cloneTable(originalTune.Ratios)
		cachedTune.BrakeForce = originalTune.BrakeForce
		cachedTune.PBrakeForce = originalTune.PBrakeForce
		cachedTune.Weight = originalTune.Weight
	end

	function controller.invalidate()
		tuningState.cachedCar = nil
		tuningState.cachedTune = nil
		tuningState.originalTune = nil
	end

	function controller.getTune()
		local carName = player.Name .. "-Car"
		local car = sessionVehicles:FindFirstChild(carName)

		if not car then
			return nil, "Could not find " .. carName
		end

		if car ~= tuningState.cachedCar then
			tuningState.cachedCar = car
			tuningState.cachedTune = nil
			tuningState.originalTune = nil

			local tuneModule = car:FindFirstChild("A-Chassis Tune", true)
			if not tuneModule then
				return nil, "A-Chassis Tune was not found"
			end
			if not tuneModule:IsA("ModuleScript") then
				return nil, "A-Chassis Tune is not a ModuleScript"
			end

			local success, result = pcall(require, tuneModule)
			if not success then
				return nil, "Failed to require tune: " .. tostring(result)
			end
			if type(result) ~= "table" then
				return nil, "Tune module did not return a table"
			end

			tuningState.cachedTune = result
			tuningState.originalTune = saveOriginalTune(result)
		end

		return tuningState.cachedTune
	end

	function controller.applyTune()
		if not settings.Enabled then
			return true
		end

		local tune, tuneError = controller.getTune()
		if not tune then
			return false, tuneError
		end

		tune.Horsepower = settings.Horsepower
		tune.E_Horsepower = settings.Horsepower
		tune.Redline = settings.Redline
		tune.ClutchTol = 10000

		tune.Turbochargers = settings.Turbochargers
		tune.Superchargers = settings.Superchargers
		tune.TurboEnabled = settings.Turbochargers > 0

		local originalTune = tuningState.originalTune
		if settings.PerformanceGearbox then
			tune.FinalDrive = 2.5
			tune.Ratios = {
				3.7,
				0,
				2.84,
				1.55,
				1.00,
				0.65,
			}
		else
			tune.FinalDrive = originalTune.FinalDrive
			tune.Ratios = cloneTable(originalTune.Ratios)
		end

		if settings.UpgradedBrakes then
			tune.BrakeForce = 10000000000000
			tune.PBrakeForce = 10000000000000
		else
			tune.BrakeForce = originalTune.BrakeForce
			tune.PBrakeForce = originalTune.PBrakeForce
		end

		if settings.Lightweight then
			tune.Weight = 3
		else
			tune.Weight = originalTune.Weight
		end

		return true
	end

	function controller.applySafely()
		local callSuccess, applied, applyError = pcall(controller.applyTune)

		if not callSuccess then
			applyError = applied
			applied = false
		end

		if applied == false then
			applyError = tostring(applyError)
			if tuningState.lastError ~= applyError then
				tuningState.lastError = applyError
				warn("[Tuning Garage] " .. applyError)
			end
		else
			tuningState.lastError = nil
		end
	end

	function controller.setup()
		if tuningState.running then
			return
		end

		tuningState.running = true
		task.spawn(function()
			while tuningState.running and not library.unloaded do
				if settings.Enabled then
					controller.applySafely()
				end
				task.wait(0.1)
			end
		end)
	end

	function controller.cleanup()
		tuningState.running = false
		controller.restoreCurrentTune()
	end

	return controller
end
