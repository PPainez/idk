--[[
    xanhub | gakuran | basketball

    Auto Release: hooks BasketballClient._beginShotCharge (via getloadedmodules),
    then calls self:_releaseShot(perfectProgress) after ~0.50s.
    No getgc — that freezes/crashes many clients.

    ESP: unique per-instance keys (GetFullName is NOT unique for rack balls).
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

	-- State (gakuran seeds basketball = {} — always fill fields) ----------

	if type(ctx.state.basketball) ~= "table" then
		ctx.state.basketball = {}
	end
	local bb = ctx.state.basketball

	bb.releaseToken = tonumber(bb.releaseToken) or 0
	bb.hooked = bb.hooked == true
	bb.rimCache = type(bb.rimCache) == "table" and bb.rimCache or {}
	bb.rimCacheAt = tonumber(bb.rimCacheAt) or 0
	bb.nextEspId = tonumber(bb.nextEspId) or 0

	if type(bb.esp) ~= "table" then
		bb.esp = {}
	end
	if type(bb.esp.highlights) ~= "table" then
		bb.esp.highlights = {}
	end
	if type(bb.esp.billboards) ~= "table" then
		bb.esp.billboards = {}
	end
	if type(bb.esp.instanceKeys) ~= "table" then
		bb.esp.instanceKeys = setmetatable({}, { __mode = "k" })
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

	local function bumpToken()
		bb.releaseToken = (tonumber(bb.releaseToken) or 0) + 1
		return bb.releaseToken
	end

	local function instanceKey(inst)
		local map = bb.esp.instanceKeys
		local key = map[inst]
		if key then
			return key
		end
		bb.nextEspId = (tonumber(bb.nextEspId) or 0) + 1
		key = "esp:" .. tostring(bb.nextEspId)
		map[inst] = key
		return key
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
		if ctx.createOverlayRoot then
			local root = ctx.createOverlayRoot()
			if root then
				return root
			end
		end
		if library.base then
			return library.base
		end
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end

	local function findLoadedModule(name)
		if type(getloadedmodules) ~= "function" then
			return nil
		end
		local ok, modules = pcall(getloadedmodules)
		if not ok or type(modules) ~= "table" then
			return nil
		end
		for _, moduleScript in ipairs(modules) do
			if moduleScript and moduleScript.Name == name then
				local reqOk, result = pcall(require, moduleScript)
				if reqOk and type(result) == "table" then
					return result
				end
			end
		end
		return nil
	end

	local function releaseProgress()
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

	local function releaseDelay()
		local delaySec = METER_DURATION * PERFECT_PROGRESS
		if flag("Gakuran Basketball Humanize", false) then
			local jitter = math.clamp(tonumber(flag("Gakuran Basketball Jitter", 15)) or 15, 0, 100)
			local spread = (jitter / 100) * 0.03
			delaySec = delaySec + ((math.random() * 2 - 1) * spread * METER_DURATION)
		end
		return math.clamp(delaySec, 0.42, METER_DURATION * 0.92)
	end

	local function scheduleReleaseFromController(controller)
		if type(controller) ~= "table" then
			return
		end
		if not flag("Gakuran Basketball Auto Release", false) then
			return
		end

		local token = bumpToken()
		local delaySec = releaseDelay()

		task.delay(delaySec, function()
			if token ~= bb.releaseToken then
				return
			end
			if ctx.state.unloading or not flag("Gakuran Basketball Auto Release", false) then
				return
			end

			local stillCharging = false
			pcall(function()
				stillCharging = controller._isCharging == true
			end)
			if not stillCharging then
				return
			end

			local progress = releaseProgress()
			local ok, err = pcall(function()
				controller:_releaseShot(progress)
			end)

			if ok then
				setStatus(string.format("released @ %.0fms (%.2f)", delaySec * 1000, progress))
				debugLog("released", progress)
			else
				setStatus("release failed: " .. tostring(err))
				debugLog("release error", err)
			end
		end)
	end

	-- Hook BasketballClient class methods (safe — no getgc) --------------

	local function installClientHook()
		if bb.hooked then
			return true
		end

		local clientClass = findLoadedModule("BasketballClient")
		if not clientClass then
			setStatus("waiting for BasketballClient module")
			return false
		end

		local originalBegin = clientClass._beginShotCharge
		if type(originalBegin) ~= "function" then
			-- Some dumps put methods only on the prototype metatable.
			local mt = getmetatable(clientClass)
			if type(mt) == "table" and type(mt.__index) == "table" then
				originalBegin = mt.__index._beginShotCharge
				if type(originalBegin) == "function" then
					clientClass = mt.__index
				end
			end
		end

		if type(originalBegin) ~= "function" then
			setStatus("BasketballClient has no _beginShotCharge")
			debugLog("no _beginShotCharge on", clientClass)
			return false
		end

		if type(clientClass._releaseShot) ~= "function" then
			setStatus("BasketballClient has no _releaseShot")
			return false
		end

		local function hookedBegin(self, ...)
			local results = table.pack(originalBegin(self, ...))

			if flag("Gakuran Basketball Auto Release", false) then
				local charging = false
				pcall(function()
					charging = self._isCharging == true
				end)
				if charging then
					scheduleReleaseFromController(self)
				else
					-- Charge may set _isCharging after begin returns; retry next frame.
					task.defer(function()
						local ok = false
						pcall(function()
							ok = self._isCharging == true
						end)
						if ok and flag("Gakuran Basketball Auto Release", false) then
							scheduleReleaseFromController(self)
						end
					end)
				end
			end

			return table.unpack(results, 1, results.n)
		end

		local ok, err = pcall(function()
			if type(hookfunction) == "function" then
				local old
				old = hookfunction(originalBegin, function(self, ...)
					return hookedBegin(self, ...)
				end)
				if type(old) == "function" then
					originalBegin = old
				end
				-- Prefer direct overwrite as well for non-C closures.
				clientClass._beginShotCharge = hookedBegin
			else
				clientClass._beginShotCharge = hookedBegin
			end
		end)

		if not ok then
			-- Plain overwrite fallback.
			local overwriteOk, overwriteErr = pcall(function()
				clientClass._beginShotCharge = hookedBegin
			end)
			if not overwriteOk then
				setStatus("hook failed: " .. tostring(err or overwriteErr))
				return false
			end
		end

		bb.hooked = true
		bb.clientClass = clientClass
		setStatus("auto release ready")
		debugLog("BasketballClient._beginShotCharge hooked")
		return true
	end

	-- Rim / ball discovery -----------------------------------------------

	local function refreshRimCache(force)
		local now = os.clock()
		local cacheAge = now - (tonumber(bb.rimCacheAt) or 0)
		if not force and cacheAge < 1.5 and type(bb.rimCache) == "table" and #bb.rimCache > 0 then
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

		local hoops = Workspace:FindFirstChild("Hoops")
		if hoops then
			for _, child in ipairs(hoops:GetChildren()) do
				addRim(child:FindFirstChild("Rim", true))
			end
			for _, descendant in ipairs(hoops:GetDescendants()) do
				if descendant.Name == "Rim" then
					addRim(descendant)
				end
			end
		end

		if #rims == 0 then
			for _, descendant in ipairs(Workspace:GetDescendants()) do
				if descendant.Name == "Rim" and descendant:IsA("BasePart") then
					local fullName = descendant:GetFullName()
					if string.find(fullName, "Hoop", 1, true) or string.find(fullName, "Hoops", 1, true) then
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
				if model.Name == "Basketball" then
					table.insert(balls, model)
				end
			end
		end
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
			bb.esp = { highlights = {}, billboards = {}, instanceKeys = setmetatable({}, { __mode = "k" }) }
			return
		end
		if type(bb.esp.highlights) ~= "table" then
			bb.esp.highlights = {}
		end
		if type(bb.esp.billboards) ~= "table" then
			bb.esp.billboards = {}
		end

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
			bb.esp = {
				highlights = {},
				billboards = {},
				instanceKeys = setmetatable({}, { __mode = "k" }),
			}
		end
		if type(bb.esp.highlights) ~= "table" then
			bb.esp.highlights = {}
		end
		if type(bb.esp.billboards) ~= "table" then
			bb.esp.billboards = {}
		end
		if type(bb.esp.instanceKeys) ~= "table" then
			bb.esp.instanceKeys = setmetatable({}, { __mode = "k" })
		end

		if not flag("Gakuran Basketball ESP", false) then
			if next(bb.esp.highlights) or next(bb.esp.billboards) then
				clearEsp()
			end
			return
		end

		local root = ctx.getRoot()
		local rootPos = root and root.Position
		local seen = {}
		local ballCount = 0
		local rimCount = 0

		if flag("Gakuran Basketball ESP Rims", true) then
			local color = Color3.fromRGB(255, 140, 40)
			for _, rim in ipairs(refreshRimCache(false)) do
				if rim.Parent then
					rimCount = rimCount + 1
					local key = instanceKey(rim)
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
			local floorColor = Color3.fromRGB(255, 170, 60)
			local heldColor = Color3.fromRGB(80, 200, 255)

			for _, ball in ipairs(collectBalls()) do
				if ball.Parent then
					ballCount = ballCount + 1
					local key = instanceKey(ball)
					seen[key] = true

					local adorn = ball:IsA("Model") and ball
						or (ball.Parent and ball.Parent:IsA("Model") and ball.Parent)
						or ball

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

					local color = playerOwner and heldColor or floorColor
					ensureHighlight(key, adorn, color)

					if flag("Gakuran Basketball ESP Distance", true) and rootPos then
						local part = getRootPart(ball)
						if part then
							local lkey = key .. ":label"
							seen[lkey] = true
							local dist = (part.Position - rootPos).Magnitude
							local tag = playerOwner and playerOwner.DisplayName or "Ball"
							ensureBillboard(lkey, part, string.format("%s  %.0fst", tag, dist), color)
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
			setStatus(string.format("esp balls=%d rims=%d hooked=%s", ballCount, rimCount, tostring(bb.hooked)))
		end
	end

	-- Setup --------------------------------------------------------------

	local function setup()
		-- Install when ball module exists; retry until equipped once.
		installClientHook()

		ctx.addConnection(UserInputService.InputBegan, function(input, gameProcessed)
			if gameProcessed or ctx.state.unloading then
				return
			end
			if input.KeyCode ~= Enum.KeyCode.F then
				return
			end
			-- Ensure hook is installed once player starts using basketball.
			if not bb.hooked then
				installClientHook()
			end
		end)

		ctx.addConnection(UserInputService.InputEnded, function(input)
			if input.KeyCode == Enum.KeyCode.F then
				-- Manual release cancels pending auto-release.
				bumpToken()
			end
		end)

		local function watchCharacter(character)
			if not character then
				return
			end
			ctx.addConnection(character:GetAttributeChangedSignal("ItemEquipped"), function()
				if character:GetAttribute("ItemEquipped") == "Basketball" then
					if not bb.hooked then
						installClientHook()
					end
				end
			end)
		end

		if LocalPlayer.Character then
			watchCharacter(LocalPlayer.Character)
		end
		ctx.addConnection(LocalPlayer.CharacterAdded, watchCharacter)

		local espAccum = 0
		local hookAccum = 0
		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end

			if not bb.hooked then
				hookAccum = hookAccum + dt
				if hookAccum >= 2 then
					hookAccum = 0
					installClientHook()
				end
			end

			if flag("Gakuran Basketball ESP", false) then
				espAccum = espAccum + dt
				if espAccum >= 0.3 then
					espAccum = 0
					local ok, err = pcall(updateEsp)
					if not ok then
						debugLog("esp error", err)
					end
				end
			elseif type(bb.esp) == "table" and type(bb.esp.highlights) == "table" then
				if next(bb.esp.highlights) or next(bb.esp.billboards) then
					clearEsp()
				end
			end
		end)

		task.defer(function()
			refreshRimCache(true)
			setStatus(string.format(
				"idle · rims=%d · hook=%s",
				#bb.rimCache,
				bb.hooked and "on" or "pending"
			))
		end)
	end

	library:AddCleanup(function()
		bumpToken()
		pcall(clearEsp)
	end)

	return { setup = setup }
end
