--[[
    xanhub | gakuran | basketball

    Auto Release only: after charging with F, release at perfect meter progress (~0.76 / ~0.50s).
    ESP: all floor balls + rims (unique instance keys; highlights parented to overlay).
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
		tip = "Releases your shot at the perfect meter window (~0.50s hold)",
	})
	shoot:AddToggle({
		text = "Humanize",
		flag = "Gakuran Basketball Humanize",
		state = false,
	})
	shoot:AddSlider({
		text = "Jitter",
		flag = "Gakuran Basketball Jitter",
		min = 0,
		max = 100,
		value = 15,
		float = 1,
		suffix = "%",
	})
	shoot:AddLabel("Hold F to charge · auto-releases at green window")

	local espSection = columns.basketballRight:AddSection("Basketball ESP")
	espSection:AddToggle({ text = "Basketball ESP", flag = "Gakuran Basketball ESP", state = false })
	espSection:AddToggle({ text = "Show Rims", flag = "Gakuran Basketball ESP Rims", state = true })
	espSection:AddToggle({ text = "Show Balls", flag = "Gakuran Basketball ESP Balls", state = true })
	espSection:AddToggle({ text = "Show Distance", flag = "Gakuran Basketball ESP Distance", state = true })

	local debugSection = columns.basketballRight:AddSection("Debug")
	debugSection:AddToggle({ text = "Basketball Debug Logs", flag = "Gakuran Basketball Debug", state = false })
	ctx.refs.basketballStatus = debugSection:AddLabel("Status: idle")

	-- State (gakuran seeds basketball = {}) --------------------------------

	if type(ctx.state.basketball) ~= "table" then
		ctx.state.basketball = {}
	end
	local bb = ctx.state.basketball
	bb.releaseToken = tonumber(bb.releaseToken) or 0
	bb.controller = nil
	bb.rimCache = type(bb.rimCache) == "table" and bb.rimCache or {}
	bb.rimCacheAt = tonumber(bb.rimCacheAt) or 0

	if type(bb.esp) ~= "table" then
		bb.esp = {}
	end
	if type(bb.esp.highlights) ~= "table" then
		bb.esp.highlights = {}
	end
	if type(bb.esp.billboards) ~= "table" then
		bb.esp.billboards = {}
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
		local label = ctx.refs.basketballStatus
		if label then
			label.Text = "Status: " .. tostring(text)
		end
	end

	local function hasBasketballEquipped(character)
		character = character or ctx.getCharacter()
		if not character then
			return false
		end
		return character:GetAttribute("ItemEquipped") == "Basketball"
			and character:GetAttribute("ItemPhase") == "Equipped"
	end

	local function getRootPart(instance)
		if not instance then
			return nil
		end
		if instance:IsA("BasePart") then
			return instance
		end
		if instance:IsA("Model") then
			return instance.PrimaryPart
				or instance:FindFirstChild("Basketball")
				or instance:FindFirstChild("Rim")
				or instance:FindFirstChildWhichIsA("BasePart", true)
		end
		return nil
	end

	local function getEspParent()
		local root = ctx.createOverlayRoot and ctx.createOverlayRoot()
		if root then
			return root
		end
		if library.base then
			return library.base
		end
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end

	-- BasketballClient controller (methods live on metatable) ------------

	local function isController(value)
		if type(value) ~= "table" then
			return false
		end
		local okShoot, shoot = pcall(function()
			return value._shootRemote
		end)
		if not okShoot or typeof(shoot) ~= "Instance" or shoot.Name ~= "BasketballShoot" then
			return false
		end
		local okRelease, release = pcall(function()
			return value._releaseShot
		end)
		return okRelease and type(release) == "function"
	end

	local function findController(force)
		if not force and bb.controller and isController(bb.controller) then
			return bb.controller
		end
		if type(getgc) ~= "function" then
			return nil
		end

		local ok, objects = pcall(getgc, true)
		if not ok or type(objects) ~= "table" then
			ok, objects = pcall(getgc)
			if not ok or type(objects) ~= "table" then
				return nil
			end
		end

		for _, value in ipairs(objects) do
			if isController(value) then
				bb.controller = value
				debugLog("controller found")
				return value
			end
		end
		return nil
	end

	local function releaseShotOnController(progress)
		local controller = findController(false)
		if not controller then
			controller = findController(true)
		end
		if not controller then
			return false, "no BasketballClient controller"
		end

		local okCharging, charging = pcall(function()
			return controller._isCharging
		end)
		if not okCharging or not charging then
			return false, "not charging"
		end

		local ok, err = pcall(function()
			controller:_releaseShot(progress)
		end)
		if not ok then
			return false, tostring(err)
		end
		return true
	end

	local function tryKeyRelease()
		-- Best-effort input simulation (some executors only).
		local methods = {}

		local vimOk, vim = pcall(function()
			return game:GetService("VirtualInputManager")
		end)
		if vimOk and vim then
			table.insert(methods, function()
				vim:SendKeyEvent(false, Enum.KeyCode.F, false, game)
			end)
		end

		if type(keyrelease) == "function" then
			table.insert(methods, function()
				keyrelease(Enum.KeyCode.F)
			end)
			table.insert(methods, function()
				keyrelease(0x46)
			end)
		end

		for _, method in ipairs(methods) do
			if pcall(method) then
				return true
			end
		end
		return false
	end

	local function computeReleaseProgress()
		local progress = PERFECT_PROGRESS
		if flag("Gakuran Basketball Humanize", false) then
			local jitter = math.clamp(tonumber(flag("Gakuran Basketball Jitter", 15)) or 15, 0, 100)
			if jitter > 0 then
				local spread = (jitter / 100) * 0.04
				progress = math.clamp(PERFECT_PROGRESS + (math.random() * 2 - 1) * spread, 0.70, 0.82)
			end
		end
		return progress
	end

	local function scheduleAutoRelease()
		if not flag("Gakuran Basketball Auto Release", false) then
			return
		end
		if not hasBasketballEquipped() then
			return
		end

		bb.releaseToken = (tonumber(bb.releaseToken) or 0) + 1
		local token = bb.releaseToken

		-- Warm controller lookup while charging starts.
		task.spawn(function()
			findController(true)
		end)

		local delaySec = METER_DURATION * PERFECT_PROGRESS
		if flag("Gakuran Basketball Humanize", false) then
			local jitter = math.clamp(tonumber(flag("Gakuran Basketball Jitter", 15)) or 15, 0, 100)
			local spread = (jitter / 100) * 0.03
			delaySec = delaySec + ((math.random() * 2 - 1) * spread * METER_DURATION)
		end
		delaySec = math.clamp(delaySec, 0.42, METER_DURATION * 0.92)

		task.delay(delaySec, function()
			if token ~= bb.releaseToken then
				return
			end
			if ctx.state.unloading or not flag("Gakuran Basketball Auto Release", false) then
				return
			end
			if not hasBasketballEquipped() then
				return
			end

			local progress = computeReleaseProgress()
			local released, reason = releaseShotOnController(progress)
			if released then
				setStatus(string.format("released @ %.0fms (%.2f)", delaySec * 1000, progress))
				debugLog("controller _releaseShot", progress)
				return
			end

			-- Fallback: synthetic key up (often no-ops on executors).
			if tryKeyRelease() then
				setStatus(string.format("key-release @ %.0fms (fallback)", delaySec * 1000))
				debugLog("key release fallback", reason)
				return
			end

			setStatus("auto-release failed: " .. tostring(reason))
			debugLog("release failed", reason)
		end)
	end

	-- Rim / ball discovery -----------------------------------------------

	local function refreshRimCache(force)
		local now = os.clock()
		if not force and (now - bb.rimCacheAt) < 1.5 and #bb.rimCache > 0 then
			return bb.rimCache
		end

		local rims = {}
		local seen = {}

		local function addRim(part)
			if part and part:IsA("BasePart") and not seen[part] then
				seen[part] = true
				table.insert(rims, part)
			end
		end

		-- Prefer structured paths first.
		local hoops = Workspace:FindFirstChild("Hoops")
		if hoops then
			for _, child in ipairs(hoops:GetChildren()) do
				local rim = child:FindFirstChild("Rim", true)
				if rim then
					addRim(rim)
				end
			end
			for _, descendant in ipairs(hoops:GetDescendants()) do
				if descendant.Name == "Rim" then
					addRim(descendant)
				end
			end
		end

		-- Fallback: workspace scan (Hoops folder can report empty children while rims still exist).
		if #rims == 0 then
			for _, descendant in ipairs(Workspace:GetDescendants()) do
				if descendant.Name == "Rim" and descendant:IsA("BasePart") then
					local parent = descendant.Parent
					if parent and (parent.Name == "Hoop" or parent.Name:find("Hoop") or parent.Name:find("Basket")) then
						addRim(descendant)
					elseif descendant:GetFullName():find("Hoops") then
						addRim(descendant)
					end
				end
			end
		end

		bb.rimCache = rims
		bb.rimCacheAt = now
		return rims
	end

	local function collectBalls()
		local balls = {}
		local items = Workspace:FindFirstChild("Items")
		if items then
			for _, model in ipairs(items:GetChildren()) do
				if model.Name == "Basketball" or model.Name:lower():find("basket") then
					table.insert(balls, model)
				end
			end
		end

		-- Held balls on characters.
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if character then
				local held = character:FindFirstChild("Basketball")
				if held then
					table.insert(balls, held)
				end
			end
		end

		return balls
	end

	-- ESP ----------------------------------------------------------------

	local function clearEsp()
		if type(bb.esp) ~= "table" then
			bb.esp = { highlights = {}, billboards = {} }
			return
		end
		bb.esp.highlights = type(bb.esp.highlights) == "table" and bb.esp.highlights or {}
		bb.esp.billboards = type(bb.esp.billboards) == "table" and bb.esp.billboards or {}

		for key, instance in pairs(bb.esp.highlights) do
			pcall(function()
				instance:Destroy()
			end)
			bb.esp.highlights[key] = nil
		end
		for key, instance in pairs(bb.esp.billboards) do
			pcall(function()
				instance:Destroy()
			end)
			bb.esp.billboards[key] = nil
		end
	end

	local function ensureHighlight(key, adorn, color)
		local parent = getEspParent()
		if not parent or not adorn then
			return nil
		end

		local existing = bb.esp.highlights[key]
		if existing and existing.Parent then
			existing.Adornee = adorn
			existing.FillColor = color
			existing.OutlineColor = color
			existing.Enabled = true
			return existing
		end

		local highlight = Instance.new("Highlight")
		highlight.Name = "XanhubBballESP"
		highlight.Adornee = adorn
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.FillTransparency = 0.55
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = parent
		bb.esp.highlights[key] = highlight
		return highlight
	end

	local function ensureBillboard(key, adorn, text, color)
		local parent = getEspParent()
		if not parent or not adorn then
			return nil
		end

		local gui = bb.esp.billboards[key]
		if not (gui and gui.Parent) then
			gui = Instance.new("BillboardGui")
			gui.Name = "XanhubBballESPLabel"
			gui.AlwaysOnTop = true
			gui.Size = UDim2.fromOffset(150, 28)
			gui.StudsOffset = Vector3.new(0, 2.4, 0)
			gui.Parent = parent

			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Enum.Font.Code
			label.TextSize = 13
			label.TextStrokeTransparency = 0.35
			label.Parent = gui
			bb.esp.billboards[key] = gui
		end

		gui.Adornee = adorn
		local label = gui:FindFirstChild("Label")
		if label then
			label.Text = text
			label.TextColor3 = color
		end
		return gui
	end

	local function updateEsp()
		if type(bb.esp) ~= "table" then
			bb.esp = { highlights = {}, billboards = {} }
		end
		bb.esp.highlights = type(bb.esp.highlights) == "table" and bb.esp.highlights or {}
		bb.esp.billboards = type(bb.esp.billboards) == "table" and bb.esp.billboards or {}

		if not flag("Gakuran Basketball ESP", false) then
			if next(bb.esp.highlights) or next(bb.esp.billboards) then
				clearEsp()
			end
			return
		end

		local root = ctx.getRoot()
		local rootPos = root and root.Position
		local seen = {}
		local ballIndex = 0
		local rimIndex = 0

		if flag("Gakuran Basketball ESP Rims", true) then
			local rims = refreshRimCache(false)
			local color = Color3.fromRGB(255, 140, 40)
			if not bb.esp._rimKeys then
				bb.esp._rimKeys = setmetatable({}, { __mode = "k" })
			end

			for _, rim in ipairs(rims) do
				if rim.Parent then
					rimIndex += 1
					local key = bb.esp._rimKeys[rim]
					if not key then
						bb.esp._rimId = (bb.esp._rimId or 0) + 1
						key = "rim:" .. bb.esp._rimId
						bb.esp._rimKeys[rim] = key
					end
					seen[key] = true

					local adorn = (rim.Parent and rim.Parent:IsA("Model") and rim.Parent) or rim
					ensureHighlight(key, adorn, color)

					if flag("Gakuran Basketball ESP Distance", true) and rootPos then
						local lkey = key .. ":label"
						seen[lkey] = true
						local dist = (rim.Position - rootPos).Magnitude
						ensureBillboard(lkey, rim, string.format("Rim  %.0fst", dist), color)
					end
				end
			end
		end

		if flag("Gakuran Basketball ESP Balls", true) then
			local color = Color3.fromRGB(255, 170, 60)
			local heldColor = Color3.fromRGB(80, 200, 255)
			if not bb.esp._ballKeys then
				bb.esp._ballKeys = setmetatable({}, { __mode = "k" })
			end

			for _, ball in ipairs(collectBalls()) do
				if ball.Parent then
					ballIndex += 1
					local key = bb.esp._ballKeys[ball]
					if not key then
						bb.esp._ballId = (bb.esp._ballId or 0) + 1
						key = "ball:" .. bb.esp._ballId
						bb.esp._ballKeys[ball] = key
					end
					seen[key] = true

					local adorn = ball:IsA("Model") and ball
						or (ball.Parent and ball.Parent:IsA("Model") and ball.Parent)
						or ball

					-- Floor balls under Workspace.Items; held balls under a character.
					local playerOwner = nil
					local parent = ball:IsA("Model") and ball or ball.Parent
					while parent and parent ~= Workspace do
						if parent:IsA("Model") then
							playerOwner = Players:GetPlayerFromCharacter(parent)
							if playerOwner then
								break
							end
						end
						parent = parent.Parent
					end

					local useColor = playerOwner and heldColor or color
					ensureHighlight(key, adorn, useColor)

					if flag("Gakuran Basketball ESP Distance", true) and rootPos then
						local part = getRootPart(ball)
						if part then
							local lkey = key .. ":label"
							seen[lkey] = true
							local dist = (part.Position - rootPos).Magnitude
							local tag = playerOwner and playerOwner.DisplayName or "Ball"
							ensureBillboard(lkey, part, string.format("%s  %.0fst", tag, dist), useColor)
						end
					end
				end
			end
		end

		for key, instance in pairs(bb.esp.highlights) do
			if not seen[key] then
				pcall(function()
					instance:Destroy()
				end)
				bb.esp.highlights[key] = nil
			end
		end
		for key, instance in pairs(bb.esp.billboards) do
			if not seen[key] then
				pcall(function()
					instance:Destroy()
				end)
				bb.esp.billboards[key] = nil
			end
		end

		if flag("Gakuran Basketball Debug", false) then
			setStatus(string.format("esp balls=%d rims=%d", ballIndex, #refreshRimCache(false)))
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
			if not hasBasketballEquipped() then
				return
			end
			if not flag("Gakuran Basketball Auto Release", false) then
				return
			end
			scheduleAutoRelease()
		end)

		ctx.addConnection(UserInputService.InputEnded, function(input)
			if input.KeyCode == Enum.KeyCode.F then
				-- User released manually — cancel pending auto-release.
				bb.releaseToken = (tonumber(bb.releaseToken) or 0) + 1
			end
		end)

		-- Re-find controller when ball is equipped.
		local function onCharacter(character)
			if not character then
				return
			end
			character:GetAttributeChangedSignal("ItemEquipped"):Connect(function()
				if character:GetAttribute("ItemEquipped") == "Basketball" then
					task.defer(function()
						findController(true)
					end)
				end
			end)
			character:GetAttributeChangedSignal("ItemPhase"):Connect(function()
				if hasBasketballEquipped(character) then
					task.defer(function()
						findController(true)
					end)
				end
			end)
		end

		if LocalPlayer.Character then
			onCharacter(LocalPlayer.Character)
		end
		ctx.addConnection(LocalPlayer.CharacterAdded, onCharacter)

		local espAccum = 0
		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end

			if flag("Gakuran Basketball ESP", false) then
				espAccum += dt
				if espAccum >= 0.3 then
					espAccum = 0
					local ok, err = pcall(updateEsp)
					if not ok then
						debugLog("esp error", err)
					end
				end
			elseif type(bb.esp.highlights) == "table" and (next(bb.esp.highlights) or next(bb.esp.billboards)) then
				clearEsp()
			end
		end)

		-- Warm rim cache once.
		task.defer(function()
			refreshRimCache(true)
			setStatus(string.format("idle · rims cached=%d", #bb.rimCache))
		end)
	end

	library:AddCleanup(function()
		bb.releaseToken = (tonumber(bb.releaseToken) or 0) + 1
		pcall(clearEsp)
		bb.controller = nil
	end)

	return { setup = setup }
end
