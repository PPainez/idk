--[[
    xanhub | gakuran | basketball

    Minimal / crash-safe:
      - No getgc, no getloadedmodules, no hookfunction, no namecall hooks
      - Auto Release only synthesizes F key-up after the perfect meter delay
      - ESP only touches Workspace.Items + Workspace.Hoops (no full Workspace:GetDescendants)
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local Players = ctx.Players
	local RunService = ctx.RunService
	local UserInputService = ctx.UserInputService
	local Workspace = ctx.Workspace
	local LocalPlayer = Players.LocalPlayer

	local METER_DURATION = 0.6578947368421053
	local PERFECT_PROGRESS = 0.76

	-- UI -----------------------------------------------------------------

	local shoot = columns.basketballLeft:AddSection("Shooting")
	shoot:AddToggle({
		text = "Auto Release",
		flag = "Gakuran Basketball Auto Release",
		state = false,
		tip = "Releases F at the perfect meter window (~0.50s)",
	})
	shoot:AddSlider({
		text = "Release Delay",
		flag = "Gakuran Basketball Release Delay",
		min = 350,
		max = 650,
		value = 500,
		float = 5,
		suffix = " ms",
		tip = "Default 500ms matches green center (0.76 * meter)",
	})
	shoot:AddLabel("Hold F · auto key-up at delay · no game hooks")

	local espSection = columns.basketballRight:AddSection("Basketball ESP")
	espSection:AddToggle({ text = "Basketball ESP", flag = "Gakuran Basketball ESP", state = false })
	espSection:AddToggle({ text = "Show Rims", flag = "Gakuran Basketball ESP Rims", state = true })
	espSection:AddToggle({ text = "Show Balls", flag = "Gakuran Basketball ESP Balls", state = true })

	local debugSection = columns.basketballRight:AddSection("Debug")
	debugSection:AddToggle({ text = "Basketball Debug Logs", flag = "Gakuran Basketball Debug", state = false })
	ctx.refs.basketballStatus = debugSection:AddLabel("Status: idle")

	-- State --------------------------------------------------------------

	if type(ctx.state.basketball) ~= "table" then
		ctx.state.basketball = {}
	end
	local bb = ctx.state.basketball
	bb.releaseToken = 0
	bb.espFolder = nil

	if type(bb.highlights) ~= "table" then
		bb.highlights = {}
	end

	-- Helpers ------------------------------------------------------------

	local function flag(name, default)
		local value = library.flags[name]
		if value == nil then
			return default
		end
		return value
	end

	local function debugLog(...)
		if flag("Gakuran Basketball Debug", false) then
			print("[xanhub basketball]", ...)
		end
	end

	local function setStatus(text)
		local ok = pcall(function()
			if ctx.refs.basketballStatus then
				ctx.refs.basketballStatus.Text = "Status: " .. tostring(text)
			end
		end)
		if not ok then
			debugLog(text)
		end
	end

	local function hasBall()
		local character = LocalPlayer.Character
		if not character then
			return false
		end
		return character:GetAttribute("ItemEquipped") == "Basketball"
			and character:GetAttribute("ItemPhase") == "Equipped"
	end

	local function releaseFKey()
		-- Try a few executor input APIs. All wrapped; none should hard-crash.
		local tried = {}

		local function attempt(name, fn)
			local ok, err = pcall(fn)
			table.insert(tried, name .. "=" .. tostring(ok))
			return ok
		end

		if type(keyrelease) == "function" then
			if attempt("keyrelease-enum", function()
				keyrelease(Enum.KeyCode.F)
			end) then
				return true, tried
			end
			if attempt("keyrelease-0x46", function()
				keyrelease(0x46)
			end) then
				return true, tried
			end
		end

		if type(keypress) == "function" and type(keyrelease) == "function" then
			-- some stacks only release after press tracking
		end

		local vimOk, vim = pcall(function()
			return game:GetService("VirtualInputManager")
		end)
		if vimOk and vim then
			if attempt("vim", function()
				vim:SendKeyEvent(false, Enum.KeyCode.F, false, game)
			end) then
				return true, tried
			end
		end

		if type(Input) == "table" and type(Input.KeyRelease) == "function" then
			if attempt("Input.KeyRelease", function()
				Input.KeyRelease(Enum.KeyCode.F)
			end) then
				return true, tried
			end
		end

		return false, tried
	end

	local function scheduleAutoRelease()
		if not flag("Gakuran Basketball Auto Release", false) then
			return
		end
		if not hasBall() then
			return
		end

		bb.releaseToken = (tonumber(bb.releaseToken) or 0) + 1
		local token = bb.releaseToken

		local delayMs = tonumber(flag("Gakuran Basketball Release Delay", 500)) or 500
		delayMs = math.clamp(delayMs, 350, 650)
		local delaySec = delayMs / 1000

		task.delay(delaySec, function()
			if token ~= bb.releaseToken then
				return
			end
			if ctx.state.unloading then
				return
			end
			if not flag("Gakuran Basketball Auto Release", false) then
				return
			end
			if not hasBall() then
				return
			end

			-- Only release if F is still held (avoids fighting manual release).
			local held = false
			pcall(function()
				held = UserInputService:IsKeyDown(Enum.KeyCode.F)
			end)
			if not held then
				setStatus("skipped (F already up)")
				return
			end

			local ok, tried = releaseFKey()
			if ok then
				setStatus(string.format("released @ %dms", delayMs))
			else
				setStatus("release unsupported on this executor")
				debugLog("release failed", table.concat(tried or {}, ", "))
			end
		end)
	end

	-- ESP (lightweight) --------------------------------------------------

	local function getEspFolder()
		if bb.espFolder and bb.espFolder.Parent then
			return bb.espFolder
		end
		local parent = nil
		pcall(function()
			if ctx.createOverlayRoot then
				parent = ctx.createOverlayRoot()
			end
		end)
		if not parent then
			parent = library.base
		end
		if not parent then
			return nil
		end

		local folder = Instance.new("Folder")
		folder.Name = "XanhubBasketballESP"
		folder.Parent = parent
		bb.espFolder = folder
		return folder
	end

	local function clearEsp()
		if type(bb.highlights) == "table" then
			for key, highlight in pairs(bb.highlights) do
				pcall(function()
					highlight:Destroy()
				end)
				bb.highlights[key] = nil
			end
		else
			bb.highlights = {}
		end
		if bb.espFolder then
			pcall(function()
				bb.espFolder:Destroy()
			end)
			bb.espFolder = nil
		end
	end

	local function ensureHighlight(key, adorn, color)
		local folder = getEspFolder()
		if not folder or not adorn then
			return
		end

		local highlight = bb.highlights[key]
		if highlight and highlight.Parent then
			highlight.Adornee = adorn
			highlight.FillColor = color
			highlight.OutlineColor = color
			highlight.Enabled = true
			return
		end

		local ok, created = pcall(function()
			local h = Instance.new("Highlight")
			h.Name = "BballESP"
			h.Adornee = adorn
			h.FillColor = color
			h.OutlineColor = color
			h.FillTransparency = 0.55
			h.OutlineTransparency = 0
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.Parent = folder
			return h
		end)
		if ok and created then
			bb.highlights[key] = created
		end
	end

	local function updateEsp()
		if not flag("Gakuran Basketball ESP", false) then
			if type(bb.highlights) == "table" and next(bb.highlights) then
				clearEsp()
			end
			return
		end

		if type(bb.highlights) ~= "table" then
			bb.highlights = {}
		end

		local seen = {}
		local ballN = 0
		local rimN = 0

		if flag("Gakuran Basketball ESP Balls", true) then
			local items = Workspace:FindFirstChild("Items")
			if items then
				local index = 0
				for _, child in ipairs(items:GetChildren()) do
					if child.Name == "Basketball" then
						index = index + 1
						ballN = ballN + 1
						local key = "ball:" .. index
						-- Prefer a stable-ish key using the instance itself as table key.
						key = child
						seen[key] = true
						ensureHighlight(key, child, Color3.fromRGB(255, 170, 60))
					end
				end
			end

			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if character then
					local held = character:FindFirstChild("Basketball")
					if held then
						ballN = ballN + 1
						local key = held
						seen[key] = true
						ensureHighlight(key, held, Color3.fromRGB(80, 200, 255))
					end
				end
			end
		end

		if flag("Gakuran Basketball ESP Rims", true) then
			local hoops = Workspace:FindFirstChild("Hoops")
			if hoops then
				-- Only scan under Hoops folder (not whole Workspace).
				local ok, descendants = pcall(function()
					return hoops:GetDescendants()
				end)
				if ok and type(descendants) == "table" then
					for _, descendant in ipairs(descendants) do
						if descendant.Name == "Rim" and descendant:IsA("BasePart") then
							rimN = rimN + 1
							local key = descendant
							seen[key] = true
							local adorn = descendant.Parent
							if not (adorn and adorn:IsA("Model")) then
								adorn = descendant
							end
							ensureHighlight(key, adorn, Color3.fromRGB(255, 140, 40))
						end
					end
				end

				-- Alternate path: Hoops.Hoop / children named Hoop
				for _, child in ipairs(hoops:GetChildren()) do
					local rim = child:FindFirstChild("Rim", true)
					if rim and rim:IsA("BasePart") and not seen[rim] then
						rimN = rimN + 1
						seen[rim] = true
						ensureHighlight(rim, child:IsA("Model") and child or rim, Color3.fromRGB(255, 140, 40))
					end
				end
			end
		end

		for key, highlight in pairs(bb.highlights) do
			if not seen[key] then
				pcall(function()
					highlight:Destroy()
				end)
				bb.highlights[key] = nil
			end
		end

		if flag("Gakuran Basketball Debug", false) then
			setStatus(string.format("esp balls=%d rims=%d", ballN, rimN))
		end
	end

	-- Setup --------------------------------------------------------------

	local function setup()
		ctx.addConnection(UserInputService.InputBegan, function(input, gameProcessed)
			if gameProcessed or ctx.state.unloading then
				return
			end
			if input.KeyCode ~= Enum.KeyCode.F then
				return
			end
			if not flag("Gakuran Basketball Auto Release", false) then
				return
			end
			if not hasBall() then
				return
			end

			local ok, err = pcall(scheduleAutoRelease)
			if not ok then
				debugLog("schedule error", err)
				setStatus("schedule error")
			end
		end)

		ctx.addConnection(UserInputService.InputEnded, function(input)
			if input.KeyCode == Enum.KeyCode.F then
				bb.releaseToken = (tonumber(bb.releaseToken) or 0) + 1
			end
		end)

		local espAccum = 0
		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end
			if not flag("Gakuran Basketball ESP", false) then
				if type(bb.highlights) == "table" and next(bb.highlights) then
					pcall(clearEsp)
				end
				return
			end

			espAccum = espAccum + (tonumber(dt) or 0)
			if espAccum < 0.35 then
				return
			end
			espAccum = 0

			local ok, err = pcall(updateEsp)
			if not ok then
				debugLog("esp error", err)
			end
		end)

		setStatus("idle")
	end

	library:AddCleanup(function()
		bb.releaseToken = (tonumber(bb.releaseToken) or 0) + 1
		pcall(clearEsp)
	end)

	return { setup = setup }
end
