--[[
    xanhub | gakuran | basketball

    Reversed from BasketballModule / BasketballClient:
      BasketballShoot:FireServer(tokenA, tokenB, tokenC, timingOffset, rimPos?)
      Perfect meter center ≈ 0.76 progress (~0.50s hold on F)

    Critical design rules:
      - Never call Roblox methods (namecall) from inside a __namecall hook
      - Precompute the green offset on Heartbeat; hook only swaps a number
      - Do not FireServer ourselves (desyncs BasketballClient and blocks shooting)
      - gakuran.luau seeds state.basketball = {} so fields must be filled in
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local Players = ctx.Players
	local RunService = ctx.RunService
	local UserInputService = ctx.UserInputService
	local Workspace = ctx.Workspace
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local LocalPlayer = Players.LocalPlayer

	local METER_DURATION = 0.6578947368421053
	local PERFECT_PROGRESS = 0.76

	-- UI -----------------------------------------------------------------

	local shoot = columns.basketballLeft:AddSection("Shooting")
	shoot:AddToggle({
		text = "Auto Green",
		flag = "Gakuran Auto Green",
		state = false,
		tip = "Rewrites BasketballShoot timing offset to the Perfect zone",
	})
	shoot:AddToggle({
		text = "Auto Release",
		flag = "Gakuran Basketball Auto Release",
		state = true,
		tip = "Releases F at the perfect meter window (needs VirtualInputManager)",
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
	shoot:AddToggle({
		text = "No Dribble Cooldown",
		flag = "Gakuran No Dribble Cooldown",
		state = false,
		tip = "Clears client Z/C dribble move cooldown when possible",
	})
	shoot:AddLabel("Hold F to shoot · green ~0.50s · no gamepad")

	local espSection = columns.basketballRight:AddSection("Basketball ESP")
	espSection:AddToggle({ text = "Basketball ESP", flag = "Gakuran Basketball ESP", state = false })
	espSection:AddToggle({ text = "Show Rims", flag = "Gakuran Basketball ESP Rims", state = true })
	espSection:AddToggle({ text = "Show Balls", flag = "Gakuran Basketball ESP Balls", state = true })
	espSection:AddToggle({ text = "Show Distance", flag = "Gakuran Basketball ESP Distance", state = true })

	local debugSection = columns.basketballRight:AddSection("Debug")
	debugSection:AddToggle({ text = "Basketball Debug Logs", flag = "Gakuran Basketball Debug", state = false })
	ctx.refs.basketballStatus = debugSection:AddLabel("Status: idle")

	-- State (must merge — gakuran.luau already sets state.basketball = {}) -

	if type(ctx.state.basketball) ~= "table" then
		ctx.state.basketball = {}
	end
	local bb = ctx.state.basketball

	bb.hookInstalled = bb.hookInstalled == true
	bb.releaseToken = tonumber(bb.releaseToken) or 0
	bb.lastShotAt = tonumber(bb.lastShotAt) or 0
	bb.cachedOffset = tonumber(bb.cachedOffset) or 0
	bb.cachedLabel = bb.cachedLabel or "Perfect"
	bb.cachedDist = tonumber(bb.cachedDist) or 0
	bb.module = bb.module
	bb.shootRemote = bb.shootRemote

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

	local function getBasketballModule()
		if type(bb.module) == "table" then
			return bb.module
		end
		local mod = findLoadedModule("BasketballModule")
		if mod then
			bb.module = mod
			if type(mod.METER_DURATION) == "number" then
				METER_DURATION = mod.METER_DURATION
			end
		end
		return bb.module
	end

	local function getShootRemote()
		if bb.shootRemote and bb.shootRemote.Parent then
			return bb.shootRemote
		end
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local remote = remotes and remotes:FindFirstChild("BasketballShoot")
		if remote then
			bb.shootRemote = remote
		end
		return remote
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

	-- Timing (safe to call outside namecall hooks) -----------------------

	local function evaluateAtProgress(rimDist, contestPct, progress)
		rimDist = tonumber(rimDist) or 20
		contestPct = tonumber(contestPct) or 0
		progress = tonumber(progress) or PERFECT_PROGRESS

		local mod = getBasketballModule()
		if mod and type(mod.getZonesForDistance) == "function" then
			local ok, result = pcall(function()
				local zones = mod.getZonesForDistance(rimDist)
				if type(mod.applyContestToZones) == "function" then
					zones = mod.applyContestToZones(zones, contestPct)
				end
				if type(mod.applyDistanceOffsetToZones) == "function" then
					zones = mod.applyDistanceOffsetToZones(zones, rimDist, contestPct)
				end
				if type(mod.evaluateTimingFromZones) == "function" then
					return mod.evaluateTimingFromZones(progress, zones)
				end
				return nil
			end)
			if ok and type(result) == "table" and type(result.offset) == "number" then
				return result
			end
		end

		return {
			id = "Perfect",
			label = "Perfect",
			offset = 0,
		}
	end

	local function refreshCachedOffset()
		local root = ctx.getRoot()
		if not root then
			bb.cachedOffset = 0
			bb.cachedLabel = "Perfect"
			bb.cachedDist = 0
			return
		end

		local rim, rimDist = findClosestRim(root.Position)
		if not rimDist then
			rimDist = 20
		end

		local contestPct = 0
		local mod = getBasketballModule()
		local character = ctx.getCharacter()
		if mod and character and type(mod.computeContestPctForShooter) == "function" then
			local ok, value = pcall(mod.computeContestPctForShooter, character, LocalPlayer)
			if ok and type(value) == "number" then
				contestPct = value
			end
		end

		local progress = PERFECT_PROGRESS
		local label = "Perfect"

		if flag("Gakuran Basketball Humanize", false) then
			local jitter = math.clamp(tonumber(flag("Gakuran Basketball Jitter", 15)) or 15, 0, 100)
			if jitter > 0 and math.random(1, 100) <= jitter then
				-- Nudge progress slightly inside slight-early / slight-late band.
				local side = (math.random() < 0.5) and -1 or 1
				progress = math.clamp(PERFECT_PROGRESS + side * (0.02 + math.random() * 0.03), 0.05, 0.95)
				label = side < 0 and "SlightEarly" or "SlightLate"
			end
		end

		local result = evaluateAtProgress(rimDist, contestPct, progress)
		bb.cachedOffset = tonumber(result.offset) or 0
		bb.cachedLabel = tostring(result.id or result.label or label)
		bb.cachedDist = rimDist
		bb.cachedContest = contestPct
	end

	-- Hook: ONLY swaps a number from cache — no Roblox API calls ---------

	local function installShootHook()
		if bb.hookInstalled then
			return true
		end

		local remote = getShootRemote()
		if not remote then
			setStatus("waiting for BasketballShoot")
			return false
		end

		-- Prefer hookfunction on FireServer (no global namecall pollution).
		if type(hookfunction) == "function" then
			local oldFire
			local function fireHook(self, ...)
				if flag("Gakuran Auto Green", false) and self == remote then
					local args = { ... }
					if type(args[4]) == "number" then
						local newOffset = tonumber(bb.cachedOffset) or 0
						debugLog("FireServer offset", args[4], "->", newOffset, bb.cachedLabel)
						args[4] = newOffset
						bb.lastShotAt = os.clock()
						setStatus(string.format("greened %.3f (%s)", newOffset, bb.cachedLabel))
						return oldFire(self, table.unpack(args, 1, math.max(#args, 5)))
					end
				end
				return oldFire(self, ...)
			end

			if type(newcclosure) == "function" then
				fireHook = newcclosure(fireHook)
			end

			local ok, err = pcall(function()
				oldFire = hookfunction(remote.FireServer, fireHook)
			end)
			if ok and oldFire then
				bb.hookInstalled = true
				bb.hookKind = "hookfunction"
				setStatus("auto green ready (FireServer)")
				debugLog("hookfunction on BasketballShoot.FireServer")
				return true
			end
			debugLog("hookfunction failed", err)
		end

		if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
			setStatus("no hook APIs — manual timing only")
			return false
		end

		local oldNamecall
		local function namecallHook(self, ...)
			local method = getnamecallmethod()
			-- Strict checks; never call any Instance method inside this branch.
			if
				method == "FireServer"
				and self == remote
				and flag("Gakuran Auto Green", false)
			then
				if type(checkcaller) == "function" and checkcaller() then
					return oldNamecall(self, ...)
				end
				local a1, a2, a3, a4, a5, a6, a7 = ...
				if type(a4) == "number" then
					local newOffset = tonumber(bb.cachedOffset) or 0
					bb.lastShotAt = os.clock()
					-- Status/debug deferred so we don't namecall from here.
					task.defer(function()
						setStatus(string.format("greened %.3f (%s)", newOffset, tostring(bb.cachedLabel)))
						debugLog("namecall offset", a4, "->", newOffset, bb.cachedLabel)
					end)
					return oldNamecall(self, a1, a2, a3, newOffset, a5, a6, a7)
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
		if not ok or not oldNamecall then
			setStatus("hook failed: " .. tostring(err))
			debugLog("hookmetamethod failed", err)
			return false
		end

		bb.hookInstalled = true
		bb.hookKind = "namecall"
		setStatus("auto green ready (namecall)")
		debugLog("namecall hook installed")
		return true
	end

	-- Auto-release (VIM only — never FireServer ourselves) --------------

	local function sendKeyUp(keyCode)
		local vim
		local ok = pcall(function()
			vim = game:GetService("VirtualInputManager")
		end)
		if not (ok and vim) then
			return false
		end
		local sent = pcall(function()
			vim:SendKeyEvent(false, keyCode, false, game)
		end)
		return sent == true
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

		bb.releaseToken = (tonumber(bb.releaseToken) or 0) + 1
		local token = bb.releaseToken
		local delaySec = METER_DURATION * PERFECT_PROGRESS

		if flag("Gakuran Basketball Humanize", false) then
			local jitter = math.clamp(tonumber(flag("Gakuran Basketball Jitter", 15)) or 15, 0, 100)
			local spread = (jitter / 100) * 0.03
			delaySec = delaySec + ((math.random() * 2 - 1) * spread * METER_DURATION)
		end
		delaySec = math.clamp(delaySec, 0.40, METER_DURATION * 0.92)

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
			-- Only key-up. Never fire the shoot remote here.
			if sendKeyUp(keyCode) then
				setStatus(string.format("auto-released @ %.0fms", delaySec * 1000))
			else
				setStatus("hold F ~0.50s (no VIM; hook still greens)")
			end
		end)
	end

	-- ESP ----------------------------------------------------------------

	local function clearEsp()
		if type(bb.esp) ~= "table" then
			bb.esp = { highlights = {}, billboards = {} }
			return
		end
		if type(bb.esp.highlights) ~= "table" then
			bb.esp.highlights = {}
		end
		if type(bb.esp.billboards) ~= "table" then
			bb.esp.billboards = {}
		end

		for key, highlight in pairs(bb.esp.highlights) do
			pcall(function()
				highlight:Destroy()
			end)
			bb.esp.highlights[key] = nil
		end
		for key, billboard in pairs(bb.esp.billboards) do
			pcall(function()
				billboard:Destroy()
			end)
			bb.esp.billboards[key] = nil
		end
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
	end

	local function updateEsp()
		if type(bb.esp) ~= "table" or type(bb.esp.highlights) ~= "table" then
			bb.esp = { highlights = {}, billboards = {} }
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

		if flag("Gakuran Basketball ESP Rims", true) then
			local hoops = Workspace:FindFirstChild("Hoops")
			if hoops then
				for _, descendant in ipairs(hoops:GetDescendants()) do
					if descendant.Name == "Rim" and descendant:IsA("BasePart") then
						local key = "rim:" .. descendant:GetFullName()
						seen[key] = true
						local color = Color3.fromRGB(255, 140, 40)
						ensureHighlight(key, descendant.Parent or descendant, color)
						if flag("Gakuran Basketball ESP Distance", true) and rootPos then
							local dist = (descendant.Position - rootPos).Magnitude
							local labelKey = key .. ":label"
							ensureBillboard(labelKey, descendant, string.format("Rim  %.0fst", dist), color)
							seen[labelKey] = true
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
								local labelKey = key .. ":label"
								ensureBillboard(labelKey, part, string.format("Ball  %.0fst", dist), color)
								seen[labelKey] = true
							end
						end
					end
				end
			end

			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if character and character:GetAttribute("ItemEquipped") == "Basketball" then
					local ballModel = character:FindFirstChild("Basketball")
					local adorn = ballModel or character:FindFirstChild("HumanoidRootPart")
					if adorn then
						local key = "held:" .. tostring(player.UserId)
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
		local ok, objects = pcall(getgc, true)
		if not ok or type(objects) ~= "table" then
			return
		end
		for _, value in ipairs(objects) do
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

	-- Setup --------------------------------------------------------------

	local function setup()
		getBasketballModule()
		installShootHook()

		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if remotes then
			ctx.addConnection(remotes.ChildAdded, function(child)
				if child.Name == "BasketballShoot" then
					bb.shootRemote = child
					bb.hookInstalled = false
					installShootHook()
				end
			end)
		end

		ctx.addConnection(UserInputService.InputBegan, function(input, gameProcessed)
			if gameProcessed or ctx.state.unloading then
				return
			end

			if input.KeyCode == Enum.KeyCode.F and hasBasketballEquipped() then
				getBasketballModule()
				refreshCachedOffset()
				scheduleAutoRelease(Enum.KeyCode.F)
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
			if input.KeyCode == Enum.KeyCode.F then
				bb.releaseToken = (tonumber(bb.releaseToken) or 0) + 1
			end
		end)

		local espAccum = 0
		local cacheAccum = 0
		local dribbleAccum = 0

		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end

			-- Keep green offset fresh for the hook (never computed inside namecall).
			if flag("Gakuran Auto Green", false) and hasBasketballEquipped() then
				cacheAccum = cacheAccum + dt
				if cacheAccum >= 0.1 then
					cacheAccum = 0
					refreshCachedOffset()
				end
			end

			if flag("Gakuran Basketball ESP", false) then
				espAccum = espAccum + dt
				if espAccum >= 0.25 then
					espAccum = 0
					local ok, err = pcall(updateEsp)
					if not ok then
						debugLog("esp error", err)
					end
				end
			else
				if type(bb.esp) == "table" and type(bb.esp.highlights) == "table" then
					if next(bb.esp.highlights) or next(bb.esp.billboards) then
						clearEsp()
					end
				end
			end

			if flag("Gakuran No Dribble Cooldown", false) then
				dribbleAccum = dribbleAccum + dt
				if dribbleAccum >= 0.15 then
					dribbleAccum = 0
					pcall(tryBypassDribbleCooldown)
				end
			end

			if flag("Gakuran Auto Green", false) and not bb.hookInstalled then
				installShootHook()
			end
		end)

		if flag("Gakuran Auto Green", false) then
			setStatus(bb.hookInstalled and ("ready · " .. tostring(bb.hookKind)) or "waiting for hook")
		else
			setStatus("idle")
		end
	end

	library:AddCleanup(function()
		bb.releaseToken = (tonumber(bb.releaseToken) or 0) + 1
		pcall(clearEsp)
	end)

	return { setup = setup }
end
