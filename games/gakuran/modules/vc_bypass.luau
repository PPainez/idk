--[[
    xanhub | gakuran | vc_bypass

    Minimal Voice Chat bypass + mute toggle.
    Works with the same ctx pattern as your other modules.
    The mute keybind is owned by qol.luau for UI consistency.
]]

return function(ctx)
	local Players = ctx.Players or game:GetService("Players")
	local VoiceChatService = game:GetService("VoiceChatService")
	local VoiceChatInternal = game:GetService("VoiceChatInternal")
	local UserInputService = ctx.UserInputService or game:GetService("UserInputService")

	local LocalPlayer = Players.LocalPlayer
	local library = ctx.library

	local getconnections = getconnections or nil

	local bypassActive = false
	local micEnabled = true -- start unmuted by default

	-- Core functions
	local function StartVCBypass()
		if bypassActive then return end
		bypassActive = true

		if ctx.notify then
			ctx.notify("VC Bypass initializing...", 3)
		end

		-- Leave current session
		pcall(function() VoiceChatService:leaveVoice() end)
		task.wait(1.8)

		-- Strip Roblox voice state connections
		pcall(function()
			if getconnections and VoiceChatInternal then
				local conns = getconnections(VoiceChatInternal.StateChanged)
				for i = 5, #conns do
					if conns[i] then
						conns[i]:Disable()
					end
				end
			end
		end)

		task.wait(1.5)

		-- Rejoin
		pcall(function() VoiceChatService:joinVoice() end)

		if ctx.notify then
			ctx.notify("VC Bypass → ACTIVE", 4)
		end
	end

	local function ToggleMute()
		micEnabled = not micEnabled

		local input = LocalPlayer:FindFirstChildOfClass("AudioDeviceInput", true)
		          or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("AudioDeviceInput", true))

		if input then
			pcall(function() input.Active = micEnabled end)
		end

		pcall(function()
			if VoiceChatInternal then
				VoiceChatInternal:PublishPause(not micEnabled)
			end
		end)

		if ctx.notify then
			ctx.notify(micEnabled and "Microphone UNMUTED" or "Microphone MUTED", 2)
		end
	end

	-- Keybind listener — the active key is stored in ctx.state.vc.muteKey
	-- qol.luau owns the UI for changing it; we just listen here.
	local vcState = ctx.state and ctx.state.vc or {}
	ctx.state.vc = vcState

	ctx.addConnection(UserInputService.InputBegan, function(input, gp)
		if gp then return end
		local key = vcState.muteKey or Enum.KeyCode.V
		if input.KeyCode == key then
			ToggleMute()
		end
	end)

	-- Cleanup
	if type(library.AddCleanup) == "function" then
		library:AddCleanup(function()
			bypassActive = false
		end)
	end

	return {
		Start = StartVCBypass,
		ToggleMute = ToggleMute,
		IsBypassActive = function() return bypassActive end,
		IsMicEnabled = function() return micEnabled end,
	}
end