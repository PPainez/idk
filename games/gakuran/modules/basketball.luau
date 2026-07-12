--[[
    xanhub | gakuran | basketball

    100% green auto-release (crash-safe path):
      - BasketballClient is a live singleton from getloadedmodules()+require
      - On charge, when elapsed >= METER*0.76, call controller:_releaseShot(0.76)
      - Optional FireServer offset rewrite to Perfect zone offset (number swap only)
      - No getgc, no __namecall hooks, no full-workspace scans
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
		text = "Auto Green Release",
		flag = "Gakuran Basketball Auto Release",
		state = false,
		tip = "Releases at perfect meter progress and forces Perfect zone offset",
	})
	shoot:AddToggle({
		text = "Force Perfect Offset",
		flag = "Gakuran Basketball Force Offset",
		state = true,
		tip = "Rewrites BasketballShoot offset to the Perfect zone (distance/contest aware)",
	})
	shoot:AddSlider({
		text = "Release Bias",
		flag = "Gakuran Basketball Release Bias",
		min = -30,
		max = 30,
		value = 0,
		float = 1,
		suffix = " ms",
		tip = "Shift release earlier (-) or later (+) around the green center",
	})
	shoot:AddLabel("Hold F · releases on perfect window · no getgc")

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

	bb.client = nil
	bb.bmod = nil
	bb.releasedThisCharge = false
	bb.wasCharging = false
	bb.fireHooked = false
	bb.cachedOffset = 0
	bb.cachedLabel = "Perfect"
	bb.cachedDist = 0
	bb.highlights = type(bb.highlights) == "table" and bb.highlights or {}
	bb.espFolder = bb.espFolder

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
		pcall(function()
			if ctx.refs.basketballStatus then
				ctx.refs.basketballStatus.Text = "Status: " .. tostring(text)
			end
		end)
	end

	local function findLoaded(name)
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

	local function getClient()
		local client = bb.client
		-- Invalidate if the singleton was replaced after unequip/re-equip.
		if type(client) == "table" and type(client._releaseShot) == "function" then
			return client
		end
		client = findLoaded("BasketballClient")
		if type(client) == "table" and type(client._releaseShot) == "function" then
			bb.client = client
			return client
		end
		bb.client = nil
		return nil
	end

	local function getBMod()
		if type(bb.bmod) == "table" and type(bb.bmod.evaluateTimingFromZones) == "function" then
			return bb.bmod
		end
		local mod = findLoaded("BasketballModule")
		if type(mod) == "table" then
			bb.bmod = mod
			if type(mod.METER_DURATION) == "number" then
				METER_DURATION = mod.METER_DURATION
			end
			return mod
		end
		return nil
	end

	local function refreshPerfectOffset()
		local bmod = getBMod()
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (bmod and root and type(bmod.getZonesForDistance) == "function") then
			bb.cachedOffset = 0
			bb.cachedLabel = "Perfect"
			return
		end

		local dist = 20
		if type(bmod.findClosestRimXZ) == "function" then
			local ok, rim, rimDist = pcall(bmod.findClosestRimXZ, root.Position)
			if ok and type(rimDist) == "number" then
				dist = rimDist
			end
		else
			local hoops = Workspace:FindFirstChild("Hoops")
			if hoops then
				local best
				for _, d in ipairs(hoops:GetDescendants()) do
					if d.Name == "Rim" and d:IsA("BasePart") then
						local delta = d.Position - root.Position
						local xz = Vector3.new(delta.X, 0, delta.Z).Magnitude
						if not best or xz < best then
							best = xz
						end
					end
				end
				if best then
					dist = best
				end
			end
		end

		local contest = 0
		if type(bmod.computeContestPctForShooter) == "function" then
			local ok, value = pcall(bmod.computeContestPctForShooter, character, LocalPlayer)
			if ok and type(value) == "number" then
				contest = value
			end
		end

		local ok, result = pcall(function()
			local zones = bmod.getZonesForDistance(dist)
			if type(bmod.applyContestToZones) == "function" then
				zones = bmod.applyContestToZones(zones, contest)
			end
			if type(bmod.applyDistanceOffsetToZones) == "function" then
				zones = bmod.applyDistanceOffsetToZones(zones, dist, contest)
			end
			return bmod.evaluateTimingFromZones(PERFECT_PROGRESS, zones)
		end)

		if ok and type(result) == "table" and type(result.offset) == "number" then
			bb.cachedOffset = result.offset
			bb.cachedLabel = tostring(result.id or result.label or "Perfect")
			bb.cachedDist = dist
			bb.cachedContest = contest
		else
			bb.cachedOffset = 0
			bb.cachedLabel = "Perfect"
			bb.cachedDist = dist
		end
	end

	local function installFireHook()
		if bb.fireHooked then
			return true
		end
		if type(hookfunction) ~= "function" then
			return false
		end

		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local remote = remotes and remotes:FindFirstChild("BasketballShoot")
		if not remote then
			return false
		end

		local oldFire
		local function fireHook(self, ...)
			local force = flag("Gakuran Basketball Auto Release", false)
				and flag("Gakuran Basketball Force Offset", true)
			if force and self == remote then
				local a, b, c, offset, rim = ...
				if type(offset) == "number" then
					local forced = tonumber(bb.cachedOffset) or 0
					if flag("Gakuran Basketball Debug", false) then
						task.defer(function()
							debugLog(
								"offset",
								offset,
								"->",
								forced,
								bb.cachedLabel,
								"dist",
								bb.cachedDist
							)
						end)
					end
					return oldFire(self, a, b, c, forced, rim)
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
			bb.fireHooked = true
			bb.shootRemote = remote
			debugLog("FireServer hook armed")
			return true
		end
		debugLog("FireServer hook failed", err)
		return false
	end

	local function tryAutoRelease(client)
		if not flag("Gakuran Basketball Auto Release", false) then
			return
		end
		if type(client) ~= "table" then
			return
		end

		local charging = false
		pcall(function()
			charging = client._isCharging == true
		end)

		if not charging then
			bb.releasedThisCharge = false
			bb.wasCharging = false
			return
		end

		if not bb.wasCharging then
			bb.wasCharging = true
			bb.releasedThisCharge = false
			refreshPerfectOffset()
		end

		if bb.releasedThisCharge then
			return
		end

		local chargeStart = nil
		pcall(function()
			chargeStart = client._chargeStart
		end)
		if type(chargeStart) ~= "number" then
			return
		end

		local biasMs = tonumber(flag("Gakuran Basketball Release Bias", 0)) or 0
		local target = (METER_DURATION * PERFECT_PROGRESS) + (biasMs / 1000)
		local elapsed = tick() - chargeStart
		if elapsed < target then
			return
		end

		bb.releasedThisCharge = true
		refreshPerfectOffset()

		local ok, err = pcall(function()
			client:_releaseShot(PERFECT_PROGRESS)
		end)

		if ok then
			setStatus(string.format(
				"greened · %s off=%.3f · %.0fst",
				tostring(bb.cachedLabel),
				tonumber(bb.cachedOffset) or 0,
				tonumber(bb.cachedDist) or 0
			))
			debugLog("released", PERFECT_PROGRESS, bb.cachedOffset, bb.cachedLabel)
		else
			bb.releasedThisCharge = false
			setStatus("release failed: " .. tostring(err))
			debugLog("release error", err)
		end
	end

	-- ESP ----------------------------------------------------------------

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
		parent = parent or library.base
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
		if type(bb.highlights) ~= "table" then
			bb.highlights = {}
			return
		end
		for key, highlight in pairs(bb.highlights) do
			pcall(function()
				highlight:Destroy()
			end)
			bb.highlights[key] = nil
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
		local existing = bb.highlights[key]
		if existing and existing.Parent then
			existing.Adornee = adorn
			existing.FillColor = color
			existing.OutlineColor = color
			existing.Enabled = true
			return
		end
		local ok, highlight = pcall(function()
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
		if ok and highlight then
			bb.highlights[key] = highlight
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

		if flag("Gakuran Basketball ESP Balls", true) then
			local items = Workspace:FindFirstChild("Items")
			if items then
				for _, child in ipairs(items:GetChildren()) do
					if child.Name == "Basketball" then
						seen[child] = true
						ensureHighlight(child, child, Color3.fromRGB(255, 170, 60))
					end
				end
			end
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if character then
					local held = character:FindFirstChild("Basketball")
					if held then
						seen[held] = true
						ensureHighlight(held, held, Color3.fromRGB(80, 200, 255))
					end
				end
			end
		end

		if flag("Gakuran Basketball ESP Rims", true) then
			local hoops = Workspace:FindFirstChild("Hoops")
			if hoops then
				local ok, descendants = pcall(function()
					return hoops:GetDescendants()
				end)
				if ok and type(descendants) == "table" then
					for _, d in ipairs(descendants) do
						if d.Name == "Rim" and d:IsA("BasePart") then
							seen[d] = true
							local adorn = d.Parent
							if not (adorn and adorn:IsA("Model")) then
								adorn = d
							end
							ensureHighlight(d, adorn, Color3.fromRGB(255, 140, 40))
						end
					end
				end
				for _, child in ipairs(hoops:GetChildren()) do
					local rim = child:FindFirstChild("Rim", true)
					if rim and rim:IsA("BasePart") and not seen[rim] then
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
	end

	-- Setup --------------------------------------------------------------

	local function setup()
		getClient()
		getBMod()
		installFireHook()

		local cacheAccum = 0
		local espAccum = 0
		local resolveAccum = 0

		ctx.addConnection(RunService.Heartbeat, function(dt)
			if ctx.state.unloading then
				return
			end

			dt = tonumber(dt) or 0

			-- Resolve modules/hooks lazily (ball systems load when used).
			resolveAccum = resolveAccum + dt
			if resolveAccum >= 1.5 then
				resolveAccum = 0
				if not bb.client then
					getClient()
				end
				if not bb.bmod then
					getBMod()
				end
				if not bb.fireHooked then
					installFireHook()
				end
			end

			local auto = flag("Gakuran Basketball Auto Release", false)
			if auto then
				cacheAccum = cacheAccum + dt
				if cacheAccum >= 0.1 then
					cacheAccum = 0
					pcall(refreshPerfectOffset)
				end

				local client = getClient()
				if client then
					local ok, err = pcall(tryAutoRelease, client)
					if not ok then
						debugLog("auto error", err)
					end
				end
			else
				bb.releasedThisCharge = false
				bb.wasCharging = false
			end

			if flag("Gakuran Basketball ESP", false) then
				espAccum = espAccum + dt
				if espAccum >= 0.35 then
					espAccum = 0
					pcall(updateEsp)
				end
			elseif type(bb.highlights) == "table" and next(bb.highlights) then
				pcall(clearEsp)
			end
		end)

		-- Manual F cancel only updates status; release is driven by controller charge clock.
		ctx.addConnection(UserInputService.InputBegan, function(input, gameProcessed)
			if gameProcessed or input.KeyCode ~= Enum.KeyCode.F then
				return
			end
			if flag("Gakuran Basketball Auto Release", false) then
				getClient()
				getBMod()
				installFireHook()
				refreshPerfectOffset()
				setStatus(string.format(
					"charging · target green · off=%.3f",
					tonumber(bb.cachedOffset) or 0
				))
			end
		end)

		local client = getClient()
		setStatus(string.format(
			"idle · client=%s · hook=%s",
			client and "yes" or "pending",
			bb.fireHooked and "yes" or "no"
		))
	end

	library:AddCleanup(function()
		bb.releasedThisCharge = true
		pcall(clearEsp)
	end)

	return { setup = setup }
end
