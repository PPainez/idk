--[[
    xanhub | universal | world module

    Lighting, performance, and world runtime tweaks with full restoration.
]]

return function(ctx)
	local lightingSection = ctx.columns.worldLeft:AddSection("Lighting")
	lightingSection:AddToggle({text = "Fullbright", flag = "Universal Fullbright", state = false})
	lightingSection:AddToggle({text = "Remove Fog", flag = "Universal Remove Fog", state = false})
	lightingSection:AddToggle({text = "Disable Post Effects", flag = "Universal Disable Effects", state = false})
	lightingSection:AddToggle({text = "Disable Shadows", flag = "Universal Disable Shadows", state = false})

	local performanceSection = ctx.columns.worldRight:AddSection("Performance")
	performanceSection:AddToggle({text = "Performance Mode", flag = "Universal Performance Mode", state = false})
	performanceSection:AddToggle({text = "Disable Particles", flag = "Universal Disable Particles", state = false})
	performanceSection:AddSlider({text = "FPS Cap", flag = "Universal FPS Cap", min = 30, max = 360, value = 144, float = 1})
	performanceSection:AddButton({
		text = "Apply FPS Cap",
		callback = function()
			if type(setfpscap) == "function" then
				local cap = math.clamp(tonumber(ctx.library.flags["Universal FPS Cap"]) or 144, 30, 360)
				local ok, err = pcall(setfpscap, cap)
				ctx.notify(ok and ("FPS cap set to " .. tostring(cap)) or ("FPS cap failed: " .. tostring(err)), ok and 2 or 4)
			else
				ctx.notify("setfpscap is unavailable", 3)
			end
		end,
	})

	local function setupWorldRuntime()
		ctx.state.original.lighting = {
			Brightness = ctx.Lighting.Brightness,
			ClockTime = ctx.Lighting.ClockTime,
			Ambient = ctx.Lighting.Ambient,
			OutdoorAmbient = ctx.Lighting.OutdoorAmbient,
			ExposureCompensation = ctx.Lighting.ExposureCompensation,
			GlobalShadows = ctx.Lighting.GlobalShadows,
			FogStart = ctx.Lighting.FogStart,
			FogEnd = ctx.Lighting.FogEnd,
		}

		local originalQuality = Enum.QualityLevel.Automatic
		pcall(function()
			originalQuality = settings().Rendering.QualityLevel
		end)

		local particleOriginal = setmetatable({}, {__mode = "k"})
		local descendantConnection
		local lightingChildConnection
		local heartbeatConnection
		local accumulator = 0

		local function rememberEffect(effect)
			if not effect or ctx.state.effectOriginal[effect] ~= nil then
				return
			end

			pcall(function()
				if effect:IsA("PostEffect") then
					ctx.state.effectOriginal[effect] = effect.Enabled
				elseif effect:IsA("Atmosphere") then
					ctx.state.effectOriginal[effect] = {
						Density = effect.Density,
						Haze = effect.Haze,
						Glare = effect.Glare,
					}
				end
			end)
		end

		local function isParticle(object)
			if not object then
				return false
			end
			return object:IsA("ParticleEmitter")
				or object:IsA("Trail")
				or object:IsA("Beam")
				or object:IsA("Smoke")
				or object:IsA("Fire")
				or object:IsA("Sparkles")
		end

		local function setParticle(object, disabled)
			if not isParticle(object) then
				return
			end

			pcall(function()
				if particleOriginal[object] == nil then
					particleOriginal[object] = object.Enabled
				end
				object.Enabled = disabled and false or particleOriginal[object]
			end)
		end

		local function applyEffect(effect, removeFog, disableEffects)
			rememberEffect(effect)
			local saved = ctx.state.effectOriginal[effect]

			pcall(function()
				if effect:IsA("PostEffect") then
					effect.Enabled = disableEffects and false or saved
				elseif effect:IsA("Atmosphere") and type(saved) == "table" then
					effect.Density = removeFog and 0 or saved.Density
					effect.Haze = removeFog and 0 or saved.Haze
					effect.Glare = removeFog and 0 or saved.Glare
				end
			end)
		end

		local function applyLighting()
			local original = ctx.state.original.lighting
			local fullbright = ctx.library.flags["Universal Fullbright"] == true
			local removeFog = ctx.library.flags["Universal Remove Fog"] == true
			local disableEffects = ctx.library.flags["Universal Disable Effects"] == true
			local performanceMode = ctx.library.flags["Universal Performance Mode"] == true
			local disableShadows = ctx.library.flags["Universal Disable Shadows"] == true or performanceMode

			pcall(function()
				ctx.Lighting.Brightness = fullbright and 3 or original.Brightness
				ctx.Lighting.ClockTime = fullbright and 14 or original.ClockTime
				ctx.Lighting.Ambient = fullbright and Color3.fromRGB(255, 255, 255) or original.Ambient
				ctx.Lighting.OutdoorAmbient = fullbright and Color3.fromRGB(255, 255, 255) or original.OutdoorAmbient
				ctx.Lighting.ExposureCompensation = fullbright and 0 or original.ExposureCompensation
				ctx.Lighting.GlobalShadows = disableShadows and false or original.GlobalShadows
				ctx.Lighting.FogStart = removeFog and 0 or original.FogStart
				ctx.Lighting.FogEnd = removeFog and 1000000 or original.FogEnd
			end)

			for _, effect in ipairs(ctx.Lighting:GetChildren()) do
				applyEffect(effect, removeFog, disableEffects)
			end

			pcall(function()
				settings().Rendering.QualityLevel = performanceMode and Enum.QualityLevel.Level01 or originalQuality
			end)
		end

		for _, effect in ipairs(ctx.Lighting:GetChildren()) do
			rememberEffect(effect)
		end

		for _, object in ipairs(ctx.Workspace:GetDescendants()) do
			if isParticle(object) then
				pcall(function()
					particleOriginal[object] = object.Enabled
				end)
			end
		end

		descendantConnection = ctx.addConnection(ctx.Workspace.DescendantAdded, function(object)
			if isParticle(object) then
				setParticle(
					object,
					ctx.library.flags["Universal Disable Particles"] == true
						or ctx.library.flags["Universal Performance Mode"] == true
				)
			end
		end)

		lightingChildConnection = ctx.addConnection(ctx.Lighting.ChildAdded, function(effect)
			rememberEffect(effect)
			task.defer(function()
				if not effect or not effect.Parent or ctx.state.unloading then
					return
				end
				applyEffect(
					effect,
					ctx.library.flags["Universal Remove Fog"] == true,
					ctx.library.flags["Universal Disable Effects"] == true
				)
			end)
		end)

		heartbeatConnection = ctx.addConnection(ctx.RunService.Heartbeat, function(deltaTime)
			accumulator += tonumber(deltaTime) or 0
			if accumulator < 0.35 or ctx.state.unloading then
				return
			end
			accumulator = 0

			applyLighting()

			local disableParticles = ctx.library.flags["Universal Disable Particles"] == true
				or ctx.library.flags["Universal Performance Mode"] == true
			for object, enabled in pairs(particleOriginal) do
				if object and object.Parent then
					pcall(function()
						object.Enabled = disableParticles and false or enabled
					end)
				else
					particleOriginal[object] = nil
				end
			end
		end)

		applyLighting()

		ctx.library:AddCleanup(function()
			ctx.disconnect(descendantConnection)
			ctx.disconnect(lightingChildConnection)
			ctx.disconnect(heartbeatConnection)

			local original = ctx.state.original.lighting
			for property, value in pairs(original) do
				pcall(function()
					ctx.Lighting[property] = value
				end)
			end

			for effect, saved in pairs(ctx.state.effectOriginal) do
				if effect and effect.Parent then
					pcall(function()
						if effect:IsA("PostEffect") then
							effect.Enabled = saved
						elseif effect:IsA("Atmosphere") and type(saved) == "table" then
							effect.Density = saved.Density
							effect.Haze = saved.Haze
							effect.Glare = saved.Glare
						end
					end)
				end
			end

			for object, enabled in pairs(particleOriginal) do
				if object and object.Parent then
					pcall(function()
						object.Enabled = enabled
					end)
				end
			end

			pcall(function()
				settings().Rendering.QualityLevel = originalQuality
			end)
		end)
	end

	return {setup = setupWorldRuntime}
end
