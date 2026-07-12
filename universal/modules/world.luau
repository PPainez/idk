--[[
    xanhub | universal | world module

    Lighting, performance, and world runtime tweaks.
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
				pcall(setfpscap, tonumber(ctx.library.flags["Universal FPS Cap"]) or 144)
				ctx.notify("FPS cap applied")
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

		local particleOriginal = setmetatable({}, {__mode = "k"})
		local descendantConnection
		local heartbeatConnection
		local accumulator = 0

		local function rememberEffect(effect)
			if ctx.state.effectOriginal[effect] ~= nil then
				return
			end
			if effect:IsA("PostEffect") then
				ctx.state.effectOriginal[effect] = effect.Enabled
			elseif effect:IsA("Atmosphere") then
				ctx.state.effectOriginal[effect] = {
					Density = effect.Density,
					Haze = effect.Haze,
					Glare = effect.Glare,
				}
			end
		end

		local function isParticle(object)
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
			if particleOriginal[object] == nil then
				particleOriginal[object] = object.Enabled
			end
			object.Enabled = not disabled and particleOriginal[object] or false
		end

		local function applyLighting()
			local original = ctx.state.original.lighting
			local fullbright = ctx.library.flags["Universal Fullbright"] == true
			local removeFog = ctx.library.flags["Universal Remove Fog"] == true
			local disableEffects = ctx.library.flags["Universal Disable Effects"] == true
			local disableShadows = ctx.library.flags["Universal Disable Shadows"] == true
				or ctx.library.flags["Universal Performance Mode"] == true

			ctx.Lighting.Brightness = fullbright and 3 or original.Brightness
			ctx.Lighting.ClockTime = fullbright and 14 or original.ClockTime
			ctx.Lighting.Ambient = fullbright and Color3.fromRGB(255, 255, 255) or original.Ambient
			ctx.Lighting.OutdoorAmbient = fullbright and Color3.fromRGB(255, 255, 255) or original.OutdoorAmbient
			ctx.Lighting.ExposureCompensation = fullbright and 0 or original.ExposureCompensation
			ctx.Lighting.GlobalShadows = disableShadows and false or original.GlobalShadows
			ctx.Lighting.FogStart = removeFog and 0 or original.FogStart
			ctx.Lighting.FogEnd = removeFog and 1000000 or original.FogEnd

			for _, effect in ipairs(ctx.Lighting:GetChildren()) do
				rememberEffect(effect)
				local saved = ctx.state.effectOriginal[effect]
				if effect:IsA("PostEffect") then
					effect.Enabled = disableEffects and false or saved
				elseif effect:IsA("Atmosphere") and type(saved) == "table" then
					effect.Density = removeFog and 0 or saved.Density
					effect.Haze = removeFog and 0 or saved.Haze
					effect.Glare = removeFog and 0 or saved.Glare
				end
			end

			pcall(function()
				settings().Rendering.QualityLevel = ctx.library.flags["Universal Performance Mode"]
					and Enum.QualityLevel.Level01
					or Enum.QualityLevel.Automatic
			end)
		end

		descendantConnection = ctx.addConnection(ctx.Workspace.DescendantAdded, function(object)
			if ctx.library.flags["Universal Disable Particles"] or ctx.library.flags["Universal Performance Mode"] then
				pcall(setParticle, object, true)
			end
		end)

		heartbeatConnection = ctx.addConnection(ctx.RunService.Heartbeat, function(deltaTime)
			accumulator += deltaTime
			if accumulator < 0.35 then
				return
			end
			accumulator = 0
			applyLighting()

			local disableParticles = ctx.library.flags["Universal Disable Particles"] == true
				or ctx.library.flags["Universal Performance Mode"] == true
			for object in pairs(particleOriginal) do
				if object and object.Parent then
					object.Enabled = disableParticles and false or particleOriginal[object]
				end
			end
		end)

		for _, object in ipairs(ctx.Workspace:GetDescendants()) do
			if isParticle(object) then
				particleOriginal[object] = object.Enabled
			end
		end

		ctx.library:AddCleanup(function()
			ctx.disconnect(descendantConnection)
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
				settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
			end)
		end)
	end

	return { setup = setupWorldRuntime }
end
