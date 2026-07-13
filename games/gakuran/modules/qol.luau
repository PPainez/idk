--[[
    xanhub | gakuran | qol

    Quality-of-life: lighting, camera, AFK, server helpers + Voice Chat Bypass.
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
	local UserInputService = ctx.UserInputService or game:GetService("UserInputService")
	local VoiceChatService = game:GetService("VoiceChatService")
	local VoiceChatInternal = game:GetService("VoiceChatInternal")

	local LocalPlayer = Players.LocalPlayer

	if type(ctx.state.qol) ~= "table" then
		ctx.state.qol = {}
	end
	local st = ctx.state.qol

	-- VC Bypass State
	local vcBypassActive = false
	local micEnabled = true
	local vcStatusLabel = nil

	local getconnections = getconnections or nil

	local function updateVCStatus()
		if vcStatusLabel then
			local status = vcBypassActive and (micEnabled and "UNMUTED" or "MUTED") or "Bypass Off"
			vcStatusLabel.Text = "VC: " .. status
		end
	end

	local function StartVCBypass()
		if vcBypassActive then return end
		vcBypassActive = true

		if ctx.notify then ctx.notify("VC Bypass initializing...", 3) end

		pcall(function() VoiceChatService:leaveVoice() end)
		task.wait(1.8)

		pcall(function()
			if getconnections and VoiceChatInternal then
				local conns = getconnections(VoiceChatInternal.StateChanged)
				for i = 5, #conns do
					if conns[i] then conns[i]:Disable() end
				end
			end
		end)

		task.wait(1.5)
		pcall(function() VoiceChatService:joinVoice() end)

		if ctx.notify then ctx.notify("✅ VC Bypass Active", 4) end
		updateVCStatus()
	end

	local function ToggleMute()
		micEnabled = not micEnabled

		local input = LocalPlayer:FindFirstChildOfClass("AudioDeviceInput", true)
		          or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("AudioDeviceInput", true))

		if input then pcall(function() input.Active = micEnabled end) end
		pcall(function() if VoiceChatInternal then VoiceChatInternal:PublishPause(not micEnabled) end end)

		if ctx.notify then
			ctx.notify(micEnabled and "✅ UNMUTED" or "🔇 MUTED", 2)
		end
		updateVCStatus()
	end

	-- UI ------------------------------------------------------------------

	local vision = left:AddSection("Vision")
	vision:AddToggle({ text = "Fullbright", flag = "Gakuran Fullbright", state = false, tip = "Bright flat lighting · easier night/indoor fights" })
	vision:AddToggle({ text = "Remove Fog", flag = "Gakuran Remove Fog", state = false })
	vision:AddToggle({ text = "No Post FX", flag = "Gakuran No Post FX", state = false, tip = "Disables bloom/blur/color-correction style effects" })
	vision:AddToggle({ text = "No Shadows", flag = "Gakuran No Shadows", state = false })

	local camera = left:AddSection("Camera")
	camera:AddToggle({ text = "Custom FOV", flag = "Gakuran Custom FOV", state = false })
	camera:AddSlider({ text = "FOV", flag = "Gakuran FOV", min = 50, max = 120, value = 80, float = 1 })
	camera:AddToggle({ text = "Unlock Zoom", flag = "Gakuran Unlock Zoom", state = false, tip = "Raises CameraMaxZoomDistance" })
	camera:AddSlider({ text = "Max Zoom", flag = "Gakuran Max Zoom", min = 32, max = 400, value = 128, float = 1, suffix = " studs" })

	local util = right:AddSection("Utility")
	util:AddToggle({ text = "Anti-AFK", flag = "Gakuran Anti AFK", state = false, tip = "VirtualUser click on Idled" })
	util:AddToggle({ text = "Hide Core GUI", flag = "Gakuran Hide CoreGui", state = false, tip = "Hides backpack/chat/playerlist (menu still works)" })
	util:AddToggle({ text = "Performance Mode", flag = "Gakuran Performance Mode", state = false, tip = "Lower quality + kill particles when possible" })
	util:AddSlider({ text = "FPS Cap", flag = "Gakuran FPS Cap", min = 30, max = 360, value = 240, float = 1 })
	util:AddButton({
		text = "Apply FPS Cap",
		callback = function()
			local cap = tonumber(library.flags["Gakuran FPS Cap"]) or 240
			if type(setfpscap) == "function" then
				pcall(setfpscap, cap)
				if ctx.notify then ctx.notify("FPS cap " .. tostring(cap), 2) end
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
			if hum then hum.Health = 0 end
		end,
	})

	-- VOICE CHAT
	local vc = right:AddSection("Voice Chat")
	vc:AddButton({ text = "Start VC Bypass", callback = StartVCBypass })
	
	vc:AddKeybind({
		text = "Toggle Mic",
		flag = "Gakuran VC Mute Bind",
		default = Enum.KeyCode.V,
		callback = ToggleMute,
	})
	
	vcStatusLabel = vc:AddLabel("VC: Bypass Off")
	updateVCStatus()

	vc:AddLabel("Tip: Unmute yourself in Roblox settings first.")

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

	-- Runtime -------------------------------------------------------------
	-- (your existing flag, numFlag, setup, apply functions, wiring, etc. stay the same)

	local function flag(name, default)
		local v = library.flags[name]
		if v == nil then return default end
		return v
	end

	local function numFlag(name, default)
		return tonumber(library.flags[name]) or default
	end

	local function setup()
		-- ... your existing setup code (lighting, camera, anti-afk, etc.) ...

		-- Initial VC status
		task.defer(updateVCStatus)

		-- ... rest of setup (wiring, connections, cleanup) ...
	end

	return { setup = setup }
end