--[[
    xanhub | gakuran | vc_bypass
    
    Minimal Voice Chat bypass + mute toggle.
    Works with the same ctx pattern as your other modules.
]]

return function(ctx)
	local Players = ctx.Players or game:GetService("Players")
	local VoiceChatService = game:GetService("VoiceChatService")
	local VoiceChatInternal = game:GetService("VoiceChatInternal")
	
	local LocalPlayer = Players.LocalPlayer
	local library = ctx.library
	
	local getconnections = getconnections or nil
	
	local bypassActive = false
	local micEnabled = true  -- start unmuted by default
	
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
	
	-- UI
	if ctx.columns and ctx.columns.misc then
		local vc = ctx.columns.misc:AddSection("Voice Chat")
		
		vc:AddButton({
			text = "Start VC Bypass",
			callback = StartVCBypass,
		})
		
		vc:AddButton({
			text = "Toggle Mic (V)",
			callback = ToggleMute,
		})
		
		vc:AddLabel("Tip: Unmute in Roblox settings first, then run bypass.")
	end
	
	-- Hotkey (V)
	ctx.addConnection(game:GetService("UserInputService").InputBegan, function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.V then
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
		IsBypassActive = function() return bypassActive end
	}
end