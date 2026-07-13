--[[
    xanhub | gakuran | qol

    Quality-of-life: lighting, camera, AFK, server helpers, Voice Chat bypass.
    Basketball lives in its own section (basketball.luau) on this tab.
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local left = columns.qolLeft or columns.basketballLeft
	local right = columns.qolRight or columns.basketballRight
	if not left or not right then
		warn("[xanhub gakuran] qol: columns missing")
		return { setup = function() end }
	end

	local Lighting = ctx.Lighting or game:GetService("Lighting")
	local Workspace = ctx.Workspace or game:GetService("Workspace")
	local Players = ctx.Players or game:GetService("Players")
	local RunService = ctx.RunService or game:GetService("RunService")
	local StarterGui = ctx.StarterGui or game:GetService("StarterGui")
	local VirtualUser = ctx.VirtualUser or game:GetService("VirtualUser")
	local TeleportService = ctx.TeleportService or game:GetService("TeleportService")
	local LocalPlayer = Players.LocalPlayer

	if type(ctx.state.qol) ~= "table" then
		ctx.state.qol = {}
	end
	local st = ctx.state.qol

	-- UI ------------------------------------------------------------------

	local vision = left:AddSection("Vision")
	vision:AddToggle({
		text = "Fullbright",
		flag = "Gakuran Fullbright",
		state = false,
		tip = "Bright flat lighting · easier night/indoor fights",
	})
	vision:AddToggle({
		text = "Remove Fog",
		flag = "Gakuran Remove Fog",
		state = false,
	})
	vision:AddToggle({
		text = "No Post FX",
		flag = "Gakuran No Post FX",
		state = false,
		tip = "Disables bloom/blur/color-correction style effects",
	})
	vision:AddToggle({
		text = "No Shadows",
		flag = "Gakuran No Shadows",
		state = false,
	})

	local camera = left:AddSection("Camera")
	camera:AddToggle({
		text = "Custom FOV",
		flag = "Gakuran Custom FOV",
		state = false,
	})
	camera:AddSlider({
		text = "FOV",
		flag = "Gakuran FOV",
		min = 50,
		max = 120,
		value = 80,
		float = 1,
	})
	camera:AddToggle({
		text = "Unlock Zoom",
		flag = "Gakuran Unlock Zoom",
		state = false,
		tip = "Raises CameraMaxZoomDistance",
	})
	camera:AddSlider({
		text = "Max Zoom",
		flag = "Gakuran Max Zoom",
		min = 32,
		max = 400,
		value = 128,
		float = 1,
		suffix = " studs",
	})

	local util = right:AddSection("Utility")
	util:AddToggle({
		text = "Anti-AFK",
		flag = "Gakuran Anti AFK",
		state = false,
		tip = "VirtualUser click on Idled",
	})
	util:AddToggle({
		text = "Hide Core GUI",
		flag = "Gakuran Hide CoreGui",
		state = false,
		tip = "Hides backpack/chat/playerlist (menu still works)",
	})
	util:AddToggle({
		text = "Performance Mode",
		flag = "Gakuran Performance Mode",
		state = false,
		tip = "Lower quality + kill particles when possible",
	})
	util:AddSlider({
		text = "FPS Cap",
		flag = "Gakuran FPS Cap",
		min = 30,
		max = 360,
		value = 240,
		float = 1,
	})
	util:AddButton({
		text = "Apply FPS Cap",
		callback = function()
			local cap = tonumber(library.flags["Gakuran FPS Cap"]) or 240
			if type(setfpscap) == "function" then
				pcall(setfpscap, cap)
				if ctx.notify then
					ctx.notify("FPS cap " .. tostring(cap), 2)
				end
			elseif ctx.notify then
				ctx.notify("setfpscap unavailable", 3)
			end
		end,
	})
	util:AddButton({
		text = "Reset Character",
		callback = function()
			local ch = LocalPlayer.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = 0
			end
		end,
	})

	local server = right:AddSection("Server")
	server:AddButton({
		text = "Copy Join Data",
		callback = function()
			ctx.safeClipboard(string.format("PlaceId=%s\nJobId=%s", game.PlaceId, game.JobId))
		end,
	})
	server:AddButton({
		text = "Rejoin Server",
		callback = function()
			pcall(function()
				TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
			end)
		end,
	})
	ctx.refs.qolStatus = server:AddLabel("QOL: idle")

	-- Voice Chat ----------------------------------------------------------------
	local vc = right:AddSection("Voice Chat")

	local vcBypassBtn = vc:AddButton({
		text = "Start VC Bypass",
		callback = function()
			local vcc = ctx.vcController
			if not vcc or type(vcc.Start) ~= "function" then
				if ctx.notify then ctx.notify("VC module not ready", 3) end
				return
			end
			if vcc.IsBypassActive and vcc.IsBypassActive() then
				if ctx.notify then ctx.notify("VC bypass already active", 2) end
				return
			end
			vcc.Start()
			-- Gray out + rename the button so it's clear bypass is running
			task.delay(3.5, function()
				if vcc.IsBypassActive and vcc.IsBypassActive() then
					pcall(function()
						if vcBypassBtn and vcBypassBtn.title then
							vcBypassBtn.title.Text = "VC Bypass ✓ Active"
							vcBypassBtn.title.TextColor3 = Color3.fromRGB(90, 100, 115)
						end
					end)
				end
			end)
		end,
	})

	vc:AddBind({
		text = "Mute / Unmute",
		flag = "Gakuran VC Mute Bind",
		key = "V",
		mode = "toggle",
		callback = function()
			local vcc = ctx.vcController
			if not vcc then return end
			if vcc.IsBypassActive and not vcc.IsBypassActive() then
				if ctx.notify then ctx.notify("⚠ VC not bypassed", 3) end
				return
			end
			if type(vcc.ToggleMute) == "function" then
				vcc.ToggleMute()
			end
		end,
	})

	vc:AddLabel("Tip: Unmute in Roblox settings first, then run bypass.")

	-- Runtime -------------------------------------------------------------

	local function flag(name, default)
		local v = library.flags[name]
		if v == nil then
			return default
		end
		return v
	end

	local function numFlag(name, default)
		return tonumber(library.flags[name]) or default
	end

	local function setup()
		st.lighting = {
			Brightness = Lighting.Brightness,
			ClockTime = Lighting.ClockTime,
			Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient,
			ExposureCompensation = Lighting.ExposureCompensation,
			GlobalShadows = Lighting.GlobalShadows,
			FogStart = Lighting.FogStart,
			FogEnd = Lighting.FogEnd,
		}
		st.zoomMin = LocalPlayer.CameraMinZoomDistance
		st.zoomMax = LocalPlayer.CameraMaxZoomDistance
		st.fov = Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView or 70
		st.quality = Enum.QualityLevel.Automatic
		pcall(function()
			st.quality = settings().Rendering.QualityLevel
		end)
		st.core = {}
		st.effect = setmetatable({}, { __mode = "k" })
		st.particle = setmetatable({}, { __mode = "k" })

		local coreTypes = {
			Enum.CoreGuiType.Backpack,
			Enum.CoreGuiType.Chat,
			Enum.CoreGuiType.Health,
			Enum.CoreGuiType.PlayerList,
			Enum.CoreGuiType.EmotesMenu,
		}
		for i = 1, #coreTypes do
			local ok, enabled = pcall(function()
				return StarterGui:GetCoreGuiEnabled(coreTypes[i])
			end)
			if ok then
				st.core[coreTypes[i]] = enabled
			end
		end

		local function rememberEffect(effect)
			if st.effect[effect] ~= nil then
				return
			end
			if effect:IsA("PostEffect") then
				st.effect[effect] = effect.Enabled
			elseif effect:IsA("Atmosphere") then
				st.effect[effect] = {
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
			if st.particle[object] == nil then
				st.particle[object] = object.Enabled
			end
			object.Enabled = (not disabled) and st.particle[object] or false
		end

		local function applyLighting()
			local o = st.lighting
			local fullbright = flag("Gakuran Fullbright", false)
			local removeFog = flag("Gakuran Remove Fog", false)
			local noFx = flag("Gakuran No Post FX", false)
			local noShadows = flag("Gakuran No Shadows", false) or flag("Gakuran Performance Mode", false)

			Lighting.Brightness = fullbright and 3 or o.Brightness
			Lighting.ClockTime = fullbright and 14 or o.ClockTime
			Lighting.Ambient = fullbright and Color3.new(1, 1, 1) or o.Ambient
			Lighting.OutdoorAmbient = fullbright and Color3.new(1, 1, 1) or o.OutdoorAmbient
			Lighting.ExposureCompensation = fullbright and 0 or o.ExposureCompensation
			Lighting.GlobalShadows = noShadows and false or o.GlobalShadows
			Lighting.FogStart = removeFog and 0 or o.FogStart
			Lighting.FogEnd = removeFog and 1e6 or o.FogEnd

			for _, effect in ipairs(Lighting:GetChildren()) do
				rememberEffect(effect)
				local saved = st.effect[effect]
				if effect:IsA("PostEffect") then
					effect.Enabled = noFx and false or (saved == true)
				elseif effect:IsA("Atmosphere") and type(saved) == "table" then
					effect.Density = removeFog and 0 or saved.Density
					effect.Haze = removeFog and 0 or saved.Haze
					effect.Glare = removeFog and 0 or saved.Glare
				end
			end
		end

		local function applyCamera()
			local cam = Workspace.CurrentCamera
			if cam and flag("Gakuran Custom FOV", false) then
				cam.FieldOfView = numFlag("Gakuran FOV", 80)
			elseif cam and st.fov then
				cam.FieldOfView = st.fov
			end
			if flag("Gakuran Unlock Zoom", false) then
				pcall(function()
					LocalPlayer.CameraMaxZoomDistance = numFlag("Gakuran Max Zoom", 128)
					if LocalPlayer.CameraMinZoomDistance > 0.5 then
						LocalPlayer.CameraMinZoomDistance = 0.5
					end
				end)
			else
				pcall(function()
					LocalPlayer.CameraMaxZoomDistance = st.zoomMax
					LocalPlayer.CameraMinZoomDistance = st.zoomMin
				end)
			end
		end

		local function applyCore()
			local hide = flag("Gakuran Hide CoreGui", false)
			for i = 1, #coreTypes do
				local t = coreTypes[i]
				pcall(function()
					StarterGui:SetCoreGuiEnabled(t, hide and false or (st.core[t] ~= false))
				end)
			end
		end

		local antiConn
		local function applyAntiAfk()
			if antiConn then
				pcall(function()
					antiConn:Disconnect()
				end)
				antiConn = nil
			end
			if flag("Gakuran Anti AFK", false) then
				antiConn = ctx.addConnection(LocalPlayer.Idled, function()
					pcall(function()
						VirtualUser:CaptureController()
						VirtualUser:ClickButton2(Vector2.new())
					end)
				end)
			end
		end

		-- Wire option callbacks where present
		local function wire(flagName, fn)
			local opt = library.options and library.options[flagName]
			if opt then
				local prev = opt.callback
				opt.callback = function(...)
					if type(prev) == "function" then
						pcall(prev, ...)
					end
					fn()
				end
			end
		end

		wire("Gakuran Fullbright", applyLighting)
		wire("Gakuran Remove Fog", applyLighting)
		wire("Gakuran No Post FX", applyLighting)
		wire("Gakuran No Shadows", applyLighting)
		wire("Gakuran Performance Mode", function()
			applyLighting()
			local disable = flag("Gakuran Performance Mode", false)
			for _, d in ipairs(Workspace:GetDescendants()) do
				pcall(setParticle, d, disable)
			end
			pcall(function()
				settings().Rendering.QualityLevel = disable and Enum.QualityLevel.Level01 or st.quality
			end)
		end)
		wire("Gakuran Custom FOV", applyCamera)
		wire("Gakuran FOV", applyCamera)
		wire("Gakuran Unlock Zoom", applyCamera)
		wire("Gakuran Max Zoom", applyCamera)
		wire("Gakuran Hide CoreGui", applyCore)
		wire("Gakuran Anti AFK", applyAntiAfk)

		ctx.addConnection(Workspace.DescendantAdded, function(obj)
			if flag("Gakuran Performance Mode", false) then
				pcall(setParticle, obj, true)
			end
		end)

		ctx.addConnection(Lighting.ChildAdded, function(effect)
			rememberEffect(effect)
			if flag("Gakuran Remove Fog", false) or flag("Gakuran No Post FX", false) then
				task.defer(applyLighting)
			end
		end)

		local accum = 0
		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end
			accum = accum + (tonumber(dt) or 0)
			if accum < 0.2 then
				return
			end
			accum = 0
			if flag("Gakuran Fullbright", false)
				or flag("Gakuran Remove Fog", false)
				or flag("Gakuran No Post FX", false)
				or flag("Gakuran No Shadows", false)
			then
				applyLighting()
			end
			if flag("Gakuran Custom FOV", false) or flag("Gakuran Unlock Zoom", false) then
				applyCamera()
			end
			pcall(function()
				if ctx.refs.qolStatus then
					local bits = {}
					if flag("Gakuran Fullbright", false) then
						bits[#bits + 1] = "fb"
					end
					if flag("Gakuran Custom FOV", false) then
						bits[#bits + 1] = "fov"
					end
					if flag("Gakuran Anti AFK", false) then
						bits[#bits + 1] = "afk"
					end
					if flag("Gakuran Performance Mode", false) then
						bits[#bits + 1] = "perf"
					end
					ctx.refs.qolStatus.Text = "QOL: " .. (#bits > 0 and table.concat(bits, " · ") or "idle")
				end
			end)
		end)

		-- initial apply for already-on flags (autoload)
		task.defer(function()
			applyLighting()
			applyCamera()
			applyCore()
			applyAntiAfk()
		end)

		if type(library.AddCleanup) == "function" then
			library:AddCleanup(function()
				if antiConn then
					pcall(function()
						antiConn:Disconnect()
					end)
				end
				local o = st.lighting
				if o then
					pcall(function()
						Lighting.Brightness = o.Brightness
						Lighting.ClockTime = o.ClockTime
						Lighting.Ambient = o.Ambient
						Lighting.OutdoorAmbient = o.OutdoorAmbient
						Lighting.ExposureCompensation = o.ExposureCompensation
						Lighting.GlobalShadows = o.GlobalShadows
						Lighting.FogStart = o.FogStart
						Lighting.FogEnd = o.FogEnd
					end)
				end
				pcall(function()
					LocalPlayer.CameraMaxZoomDistance = st.zoomMax
					LocalPlayer.CameraMinZoomDistance = st.zoomMin
					local cam = Workspace.CurrentCamera
					if cam then
						cam.FieldOfView = st.fov
					end
				end)
				for effect, saved in pairs(st.effect or {}) do
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
				for particle, enabled in pairs(st.particle or {}) do
					if particle and particle.Parent then
						pcall(function()
							particle.Enabled = enabled
						end)
					end
				end
				pcall(function()
					settings().Rendering.QualityLevel = st.quality
				end)
				for t, enabled in pairs(st.core or {}) do
					pcall(function()
						StarterGui:SetCoreGuiEnabled(t, enabled)
					end)
				end
			end)
		end
	end

	return { setup = setup }
end