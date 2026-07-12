--[[
    xanhub | gakuran | basketball

    Real basketball features reversed from Gakuran client modules:
      - BasketballModule (zones, meter duration, contest/distance offsets)
      - BasketballClient (F charge/release, BasketballShoot remote)
      - AuthServiceClient:NextForKey("Basketball.Shoot")

    FireServer(tokenA, tokenB, tokenC, timingOffset, rimPosition)
    Perfect meter center is always ~0.76 progress (~0.50s hold).
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local Players = ctx.Players
	local RunService = ctx.RunService
	local UserInputService = ctx.UserInputService
	local Workspace = ctx.Workspace
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local METER_DURATION = 0.6578947368421053
	local PERFECT_PROGRESS = 0.76
	local SHOOT_KEYS = {
		[Enum.KeyCode.F] = true,
		[Enum.KeyCode.ButtonR2] = true,
	}

	-- Base zones mirrored from BasketballModule.ZONES (close-range defaults).
	local BASE_ZONES = {
		{ id = "Perfect", label = "Perfect", min = 0.72, max = 0.8, offset = 0 },
		{ id = "SlightlyEarly", label = "Slightly Early", min = 0.66, max = 0.72, offset = 0.28 },
		{ id = "SlightlyLate", label = "Slightly Late", min = 0.8, max = 0.86, offset = 0.28 },
		{ id = "Early", label = "Early", min = 0.57, max = 0.66, offset = 1.5 },
		{ id = "Late", label = "Late", min = 0.86, max = 0.93, offset = 1.5 },
		{ id = "VeryEarly", label = "Very Early", min = 0, max = 0.76, offset = 4 },
		{ id = "VeryLate", label = "Very Late", min = 0.76, max = 1, offset = 4 },
	}

	local shoot = columns.basketballLeft:AddSection("Shooting")
	shoot:AddToggle({
		text = "Auto Green",
		flag = "Gakuran Auto Green",
		state = false,
		tip = "Forces perfect timing offset on BasketballShoot and auto-releases F at green",
	})
	shoot:AddToggle({
		text = "Auto Release",
		flag = "Gakuran Basketball Auto Release",
		state = true,
		tip = "While holding shoot, releases at the perfect meter window",
	})
	shoot:AddToggle({
		text = "Humanize",
		flag = "Gakuran Basketball Humanize",
		state = true,
	})
	shoot:AddSlider({
		text = "Jitter",
		flag = "Gakuran Basketball Jitter",
		min = 0,
		max = 100,
		value = 22,
		float = 1,
		suffix = "%",
	})
	shoot:AddToggle({
		text = "No Dribble Cooldown",
		flag = "Gakuran No Dribble Cooldown",
		state = false,
		tip = "Bypasses the client 0.15s Z/C dribble move gate when possible",
	})
	shoot:AddLabel("Shoot key: F  ·  Dribble: Z / C  ·  Meter ~0.50s")

	local esp = columns.basketballRight:AddSection("Basketball ESP")
	esp:AddToggle({ text = "Basketball ESP", flag = "Gakuran Basketball ESP", state = false })
	esp:AddToggle({ text = "Show Rims", flag = "Gakuran Basketball ESP Rims", state = true })
	esp:AddToggle({ text = "Show Balls", flag = "Gakuran Basketball ESP Balls", state = true })
	esp:AddToggle({ text = "Show Distance", flag = "Gakuran Basketball ESP Distance", state = true })
	esp:AddLabel("Rim / floor ball markers with range")

	local debugSection = columns.basketballRight:AddSection("Debug")
	debugSection:AddToggle({ text = "Basketball Debug Logs", flag = "Gakuran Basketball Debug", state = false })
	ctx.refs.basketballStatus = debugSection:AddLabel("Status: idle")

	ctx.state.basketball = ctx.state.basketball or {
		active = false,
		hookInstalled = false,
		hookCleanup = nil,
		releaseToken = 0,
		esp = {
			highlights = {},
			billboards = {},
		},
		lastShotAt = 0,
		module = nil,
		auth = nil,
	}

	local bb = ctx.state.basketball

	local function debugLog(...)
		if library.flags["Gakuran Basketball Debug"] then
			print("[xanhub basketball]", ...)
		end
	end

	local function setStatus(text)
		if ctx.refs.basketballStatus then
			ctx.refs.basketballStatus.Text = "Status: " .. tostring(text)
		end
	end

	local function flag(name, default)
		local value = library.flags[name]
		if value == nil then
			return default
		end
		return value
	end

	local function hasBasketballEquipped(character)
		character = character or ctx.getCharacter()
		if not character then
			return false
		end
		return character:GetAttribute("ItemEquipped") == "Basketball"
			and character:GetAttribute("ItemPhase") == "Equipped"
	end

	local function findLoadedModule(name)
		if type(getloadedmodules) ~= "function" then
			return nil
		end
		for _, moduleScript in ipairs(getloadedmodules()) do
			if moduleScript.Name == name then
				local ok, result = pcall(require, moduleScript)
				if ok and type(result) == "table" then
					return result
				end
			end
		end
		return nil
	end

	local function getBasketballModule()
		if bb.module then
			return bb.module
		end
		bb.module = findLoadedModule("BasketballModule")
		if bb.module and type(bb.module.METER_DURATION) == "number" then
			METER_DURATION = bb.module.METER_DURATION
		end
		return bb.module
	end

	local function getAuthService()
		if bb.auth then
			return bb.auth
		end
		local auth = findLoadedModule("AuthServiceClient")
		if type(auth) == "table" then
			if type(auth.Get) == "function" then
				local ok, instance = pcall(function()
					return auth:Get()
				end)
				if ok and type(instance) == "table" then
					bb.auth = instance
					return bb.auth
				end
			end
			bb.auth = auth
		end
		return bb.auth
	end

	local function getShootRemote()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		return remotes and remotes:FindFirstChild("BasketballShoot")
	end

	local function getDribbleRemote()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		return remotes and remotes:FindFirstChild("BasketballDribble")
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
				or instance:FindFirstChild("Rim")
				or instance:FindFirstChild("Basketball")
				or instance:FindFirstChildWhichIsA("BasePart", true)
		end
		return nil
	end

	local function findClosestRim(position)
		local mod = getBasketballModule()
		if mod and type(mod.findClosestRimXZ) == "function" then
			local ok, rim, dist = pcall(mod.findClosestRimXZ, position)
			if ok and rim then
				return rim, dist
			end
		end

		local best, bestDist
		local hoops = Workspace:FindFirstChild("Hoops")
		if not hoops then
			return nil, nil
		end

		for _, descendant in ipairs(hoops:GetDescendants()) do
			if descendant.Name == "Rim" and descendant:IsA("BasePart") then
				local delta = descendant.Position - position
				local dist = Vector3.new(delta.X, 0, delta.Z).Magnitude
				if not bestDist or dist < bestDist then
					best = descendant
					bestDist = dist
				end
			end
		end

		return best, bestDist
	end

	local function evaluatePerfect(rimDist, contestPct)
		rimDist = tonumber(rimDist) or 20
		contestPct = tonumber(contestPct) or 0

		local mod = getBasketballModule()
		if mod and type(mod.getZonesForDistance) == "function" then
			local zones = mod.getZonesForDistance(rimDist)
			if type(mod.applyContestToZones) == "function" then
				zones = mod.applyContestToZones(zones, contestPct)
			end
			if type(mod.applyDistanceOffsetToZones) == "function" then
				zones = mod.applyDistanceOffsetToZones(zones, rimDist, contestPct)
			end
			if type(mod.evaluateTimingFromZones) == "function" then
				local result = mod.evaluateTimingFromZones(PERFECT_PROGRESS, zones)
				if type(result) == "table" and result.offset ~= nil then
					return result
				end
			end
		end

		-- Fallback when BasketballModule is not loaded yet.
		return {
			id = "Perfect",
			label = "Perfect",
			offset = 0,
			min = 0.72,
			max = 0.8,
		}
	end

	local function evaluateHumanized(rimDist, contestPct)
		local perfect = evaluatePerfect(rimDist, contestPct)
		if not flag("Gakuran Basketball Humanize", true) then
			return perfect
		end

		local jitter = math.clamp(tonumber(flag("Gakuran Basketball Jitter", 22)) or 22, 0, 100)
		if jitter <= 0 then
			return perfect
		end

		-- Higher jitter => more chance to leave perfect for slight early/late.
		local roll = math.random(1, 100)
		if roll > jitter then
			return perfect
		end

		local mod = getBasketballModule()
		local zones
		if mod and type(mod.getZonesForDistance) == "function" then
			zones = mod.getZonesForDistance(rimDist or 20)
			if type(mod.applyContestToZones) == "function" then
				zones = mod.applyContestToZones(zones, contestPct or 0)
			end
			if type(mod.applyDistanceOffsetToZones) == "function" then
				zones = mod.applyDistanceOffsetToZones(zones, rimDist or 20, contestPct or 0)
			end
		else
			zones = BASE_ZONES
		end

		local side = (math.random() < 0.5) and "SlightlyEarly" or "SlightlyLate"
		for _, zone in ipairs(zones) do
			if zone.id == side then
				local progress = (zone.min + zone.max) * 0.5
				if mod and type(mod.evaluateTimingFromZones) == "function" then
					local result = mod.evaluateTimingFromZones(progress, zones)
					if type(result) == "table" then
						return result
					end
				end
				return zone
			end
		end

		return perfect
	end

	local function computeOffsetForRim(rimPosition)
		local root = ctx.getRoot()
		if not root then
			return evaluateHumanized(20, 0).offset
		end

		local rimPart = nil
		local rimDist = 20
		if typeof(rimPosition) == "Vector3" then
			local delta = rimPosition - root.Position
			rimDist = Vector3.new(delta.X, 0, delta.Z).Magnitude
		else
			rimPart, rimDist = findClosestRim(root.Position)
			if rimPart then
				rimPosition = rimPart.Position
			end
		end

		local contestPct = 0
		local mod = getBasketballModule()
		local character = ctx.getCharacter()
		if mod and character and type(mod.computeContestPctForShooter) == "function" then
			local ok, value = pcall(mod.computeContestPctForShooter, character, Players.LocalPlayer)
			if ok and type(value) == "number" then
				contestPct = value
			end
		end

		local result = evaluateHumanized(rimDist, contestPct)
		debugLog(
			"offset",
			result.id,
			result.offset,
			"dist",
			string.format("%.1f", rimDist),
			"contest",
			string.format("%.0f", contestPct)
		)
		return result.offset, result, rimDist, contestPct
	end

	local function installShootHook()
		if bb.hookInstalled then
			return true
		end

		local remote = getShootRemote()
		if not remote then
			setStatus("waiting for BasketballShoot remote")
			return false
		end

		if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
			setStatus("no hookmetamethod — auto-release only")
			return false
		end

		local oldNamecall
		local function namecallHook(self, ...)
			local method = getnamecallmethod()
			if
				flag("Gakuran Auto Green", false)
				and self == remote
				and method == "FireServer"
				and (type(checkcaller) ~= "function" or not checkcaller())
			then
				local args = { ... }
				-- BasketballClient: FireServer(tokenA, tokenB, tokenC, offset, rimPos?)
				if #args >= 4 and type(args[4]) == "number" then
					local rimPos = args[5]
					local newOffset = computeOffsetForRim(rimPos)
					args[4] = newOffset
					bb.lastShotAt = os.clock()
					setStatus(string.format("greened offset=%.3f", newOffset))
					return oldNamecall(self, table.unpack(args, 1, #args))
				end
			end
			return oldNamecall(self, ...)
		end

		if type(newcclosure) == "function" then
			namecallHook = newcclosure(namecallHook)
		end

		local ok, err = pcall(function()
			oldNamecall = hookmetamethod(game, "__namecall", namecallHook)
		end)

		if not ok then
			setStatus("hook failed: " .. tostring(err))
			debugLog("hook failed", err)
			return false
		end

		bb.hookInstalled = true
		bb.hookCleanup = function()
			-- Most executors cannot fully restore namecall; leave hooked but gated by flags.
			bb.hookInstalled = false
		end
		setStatus("auto green hook armed")
		debugLog("BasketballShoot hook installed")
		return true
	end

	local function sendKeyUp(keyCode)
		local vim
		local ok = pcall(function()
			vim = game:GetService("VirtualInputManager")
		end)
		if ok and vim then
			local sent = pcall(function()
				vim:SendKeyEvent(false, keyCode, false, game)
			end)
			return sent
		end
		return false
	end

	local function scheduleAutoRelease(keyCode)
		if not flag("Gakuran Auto Green", false) then
			return
		end
		if not flag("Gakuran Basketball Auto Release", true) then
			return
		end
		if not hasBasketballEquipped() then
			return
		end

		bb.releaseToken += 1
		local token = bb.releaseToken
		local delaySec = METER_DURATION * PERFECT_PROGRESS

		-- Slight humanized release timing around the perfect center.
		if flag("Gakuran Basketball Humanize", true) then
			local jitter = math.clamp(tonumber(flag("Gakuran Basketball Jitter", 22)) or 22, 0, 100)
			local spread = (jitter / 100) * 0.04
			delaySec += (math.random() * 2 - 1) * spread * METER_DURATION
		end

		delaySec = math.clamp(delaySec, 0.35, METER_DURATION * 0.95)

		task.delay(delaySec, function()
			if token ~= bb.releaseToken then
				return
			end
			if ctx.state.unloading or not flag("Gakuran Auto Green", false) then
				return
			end
			if not hasBasketballEquipped() then
				return
			end

			if sendKeyUp(keyCode) then
				setStatus(string.format("auto-released @ %.0fms", delaySec * 1000))
				debugLog("auto release", delaySec)
			else
				-- Fallback: fire perfect shot remote if VIM unavailable.
				local auth = getAuthService()
				local shootRemote = getShootRemote()
				local root = ctx.getRoot()
				if not (auth and shootRemote and root and type(auth.NextForKey) == "function") then
					setStatus("auto-release unsupported (no VIM/auth)")
					return
				end

				local rim = findClosestRim(root.Position)
				local rimPos = rim and getRootPart(rim) and getRootPart(rim).Position or nil
				local offset = computeOffsetForRim(rimPos)
				local a, b, c = auth:NextForKey("Basketball.Shoot")
				shootRemote:FireServer(a, b, c, offset, rimPos)
				bb.lastShotAt = os.clock()
				setStatus(string.format("remote greened offset=%.3f", offset))
			end
		end)
	end

	local function clearEsp()
		for _, highlight in pairs(bb.esp.highlights) do
			pcall(function()
				highlight:Destroy()
			end)
		end
		for _, billboard in pairs(bb.esp.billboards) do
			pcall(function()
				billboard:Destroy()
			end)
		end
		table.clear(bb.esp.highlights)
		table.clear(bb.esp.billboards)
	end

	local function ensureHighlight(key, adorn, color)
		local existing = bb.esp.highlights[key]
		if existing and existing.Parent then
			existing.FillColor = color
			existing.OutlineColor = color
			existing.Adornee = adorn
			existing.Enabled = true
			return existing
		end

		local highlight = Instance.new("Highlight")
		highlight.Name = "XanhubBasketballESP"
		highlight.Adornee = adorn
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.FillTransparency = 0.65
		highlight.OutlineTransparency = 0.1
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = adorn
		bb.esp.highlights[key] = highlight
		return highlight
	end

	local function ensureBillboard(key, adorn, text, color)
		local gui = bb.esp.billboards[key]
		if not (gui and gui.Parent) then
			gui = Instance.new("BillboardGui")
			gui.Name = "XanhubBasketballESPLabel"
			gui.AlwaysOnTop = true
			gui.Size = UDim2.fromOffset(140, 28)
			gui.StudsOffset = Vector3.new(0, 2.2, 0)
			gui.Parent = adorn

			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Enum.Font.Code
			label.TextSize = 13
			label.TextStrokeTransparency = 0.4
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
		if not flag("Gakuran Basketball ESP", false) then
			clearEsp()
			return
		end

		local root = ctx.getRoot()
		local rootPos = root and root.Position
		local seen = {}

		if flag("Gakuran Basketball ESP Rims", true) then
			local hoops = Workspace:FindFirstChild("Hoops")
			if hoops then
				for index, descendant in ipairs(hoops:GetDescendants()) do
					if descendant.Name == "Rim" and descendant:IsA("BasePart") then
						local key = "rim:" .. descendant:GetFullName()
						seen[key] = true
						local color = Color3.fromRGB(255, 140, 40)
						ensureHighlight(key, descendant.Parent or descendant, color)
						if flag("Gakuran Basketball ESP Distance", true) and rootPos then
							local dist = (descendant.Position - rootPos).Magnitude
							ensureBillboard(
								key .. ":label",
								descendant,
								string.format("Rim  %.0fst", dist),
								color
							)
							seen[key .. ":label"] = true
						end
					end
				end
			end
		end

		if flag("Gakuran Basketball ESP Balls", true) then
			local items = Workspace:FindFirstChild("Items")
			if items then
				for _, model in ipairs(items:GetChildren()) do
					if model.Name == "Basketball" then
						local part = getRootPart(model)
						if part then
							local key = "ball:" .. model:GetFullName()
							seen[key] = true
							local color = Color3.fromRGB(255, 170, 60)
							ensureHighlight(key, model, color)
							if flag("Gakuran Basketball ESP Distance", true) and rootPos then
								local dist = (part.Position - rootPos).Magnitude
								ensureBillboard(
									key .. ":label",
									part,
									string.format("Ball  %.0fst", dist),
									color
								)
								seen[key .. ":label"] = true
							end
						end
					end
				end
			end

			-- Equipped ball on local / other characters.
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if character and character:GetAttribute("ItemEquipped") == "Basketball" then
					local ballModel = character:FindFirstChild("Basketball")
					local adorn = ballModel or character:FindFirstChild("HumanoidRootPart")
					if adorn then
						local key = "held:" .. player.UserId
						seen[key] = true
						ensureHighlight(key, ballModel or character, Color3.fromRGB(80, 200, 255))
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
	end

	local function tryBypassDribbleCooldown()
		if not flag("Gakuran No Dribble Cooldown", false) then
			return
		end
		if type(getgc) ~= "function" then
			return
		end

		-- Best-effort: zero last Z/C timestamps on live BasketballClient controllers.
		for _, value in ipairs(getgc(true)) do
			if type(value) == "table" then
				local hasDribble = rawget(value, "_dribbleRemote") ~= nil
				local hasLastZ = rawget(value, "_lastZTime") ~= nil
				if hasDribble and hasLastZ then
					value._lastZTime = 0
					value._lastCTime = 0
				end
			end
		end
	end

	local function setup()
		installShootHook()

		-- Re-attempt hook if remotes appear later.
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if remotes then
			ctx.addConnection(remotes.ChildAdded, function(child)
				if child.Name == "BasketballShoot" then
					installShootHook()
				end
			end)
		end

		ctx.addConnection(UserInputService.InputBegan, function(input, gameProcessed)
			if gameProcessed or ctx.state.unloading then
				return
			end

			-- BasketballClient binds charge to F / gamepad R2.
			if SHOOT_KEYS[input.KeyCode] and hasBasketballEquipped() then
				getBasketballModule()
				getAuthService()
				scheduleAutoRelease(input.KeyCode)
			end

			if flag("Gakuran No Dribble Cooldown", false) then
				if
					input.KeyCode == Enum.KeyCode.Z
					or input.KeyCode == Enum.KeyCode.C
					or input.KeyCode == Enum.KeyCode.X
				then
					tryBypassDribbleCooldown()
				end
			end
		end)

		ctx.addConnection(UserInputService.InputEnded, function(input)
			if SHOOT_KEYS[input.KeyCode] then
				bb.releaseToken += 1
			end
		end)

		local espAccum = 0
		local dribbleAccum = 0
		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end

			if flag("Gakuran Basketball ESP", false) then
				espAccum += dt
				if espAccum >= 0.2 then
					espAccum = 0
					updateEsp()
				end
			elseif next(bb.esp.highlights) or next(bb.esp.billboards) then
				clearEsp()
			end

			if flag("Gakuran No Dribble Cooldown", false) then
				dribbleAccum += dt
				if dribbleAccum >= 0.1 then
					dribbleAccum = 0
					tryBypassDribbleCooldown()
				end
			end

			if flag("Gakuran Auto Green", false) and not bb.hookInstalled then
				installShootHook()
			end
		end)

		if flag("Gakuran Auto Green", false) then
			setStatus(bb.hookInstalled and "auto green ready" or "auto green (release assist)")
		else
			setStatus("idle")
		end
	end

	library:AddCleanup(function()
		bb.releaseToken += 1
		clearEsp()
		if bb.hookCleanup then
			pcall(bb.hookCleanup)
			bb.hookCleanup = nil
		end
	end)

	return { setup = setup }
end
