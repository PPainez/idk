--[[
    xanhub | gakuran | visuals

    Player ESP using character.PlayerData attributes:
      FirstName, LastName, CombatStyle, Grade, Age, Height/CurrentHeight,
      character.Stamina, Humanoid health.

    Height scale → inches: ((scale - 1) * 60) + 60  (from CharacterServiceUtils)
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local Players = ctx.Players
	local RunService = ctx.RunService
	local Workspace = ctx.Workspace
	local LocalPlayer = Players.LocalPlayer

	local ACCENT = Color3.fromRGB(255, 168, 64)
	local WHITE = Color3.fromRGB(245, 247, 255)
	local MUTED = Color3.fromRGB(160, 168, 185)
	local DARK = Color3.fromRGB(10, 12, 18)
	local HP_HIGH = Color3.fromRGB(90, 220, 130)
	local HP_MID = Color3.fromRGB(240, 190, 70)
	local HP_LOW = Color3.fromRGB(235, 80, 90)
	local STM = Color3.fromRGB(90, 180, 255)

	-- UI -----------------------------------------------------------------

	local espSec = columns.visualsLeft:AddSection("Player ESP")
	espSec:AddToggle({ text = "Player ESP", flag = "Gakuran Player ESP", state = false })
	espSec:AddToggle({ text = "Boxes", flag = "Gakuran ESP Boxes", state = true })
	espSec:AddToggle({ text = "Filled Boxes", flag = "Gakuran ESP Filled Boxes", state = false })
	espSec:AddToggle({ text = "Health Bar", flag = "Gakuran ESP Health Bar", state = true })
	espSec:AddToggle({ text = "Stamina Bar", flag = "Gakuran ESP Stamina Bar", state = true })
	espSec:AddToggle({ text = "Highlight", flag = "Gakuran ESP Highlight", state = false })
	espSec:AddSlider({
		text = "Max Distance",
		flag = "Gakuran ESP Max Distance",
		min = 50,
		max = 2000,
		value = 600,
		float = 10,
		suffix = " studs",
	})
	espSec:AddSlider({
		text = "Text Size",
		flag = "Gakuran ESP Text Size",
		min = 10,
		max = 18,
		value = 13,
		float = 1,
	})

	local info = columns.visualsRight:AddSection("Player Info")
	info:AddToggle({ text = "Names", flag = "Gakuran ESP Names", state = true })
	info:AddToggle({
		text = "Real Roblox Name",
		flag = "Gakuran ESP Real Names",
		state = false,
		tip = "Appends @Username under the character name",
	})
	info:AddLabel("Uses game First/Last name (e.g. Terry Yuuki)")
	info:AddToggle({ text = "Distance", flag = "Gakuran ESP Distance", state = true })
	info:AddToggle({ text = "Combat Style", flag = "Gakuran ESP Combat Style", state = true })
	info:AddToggle({ text = "Grade", flag = "Gakuran ESP Grade", state = true })
	info:AddToggle({ text = "Age", flag = "Gakuran ESP Age", state = false })
	info:AddToggle({ text = "Height", flag = "Gakuran ESP Height", state = false })
	info:AddToggle({ text = "Show Self", flag = "Gakuran ESP Show Self", state = false })

	local style = columns.visualsRight:AddSection("Style")
	style:AddColor({ text = "ESP Color", flag = "Gakuran ESP Color", color = ACCENT })
	style:AddColor({ text = "Name Color", flag = "Gakuran ESP Name Color", color = WHITE })
	style:AddSlider({
		text = "Fill Opacity",
		flag = "Gakuran ESP Fill Opacity",
		min = 0,
		max = 60,
		value = 14,
		float = 1,
		suffix = "%",
	})
	style:AddSlider({
		text = "Box Thickness",
		flag = "Gakuran ESP Box Thickness",
		min = 1,
		max = 4,
		value = 2,
		float = 0.5,
	})

	local debugSec = columns.visualsLeft:AddSection("ESP Status")
	ctx.refs.visualsStatus = debugSec:AddLabel("Status: idle")

	-- State --------------------------------------------------------------

	if type(ctx.state.esp) ~= "table" then
		ctx.state.esp = {}
	end
	local espState = ctx.state.esp
	espState.entries = type(espState.entries) == "table" and espState.entries or {}
	espState.folder = espState.folder

	-- Helpers ------------------------------------------------------------

	local function flag(name, default)
		local value = library.flags[name]
		if value == nil then
			return default
		end
		return value
	end

	local function numFlag(name, default)
		return tonumber(library.flags[name]) or default
	end

	local function colorFlag(name, fallback)
		local value = library.flags[name]
		if typeof(value) == "Color3" then
			return value
		end
		return fallback
	end

	local function setStatus(text)
		pcall(function()
			if ctx.refs.visualsStatus then
				ctx.refs.visualsStatus.Text = "Status: " .. tostring(text)
			end
		end)
	end

	local function getPlayerData(character)
		if not character then
			return nil
		end
		return character:FindFirstChild("PlayerData")
	end

	local function attr(inst, key)
		if not inst then
			return nil
		end
		local ok, value = pcall(function()
			return inst:GetAttribute(key)
		end)
		if ok then
			return value
		end
		return nil
	end

	local function formatGrade(raw)
		if type(raw) ~= "string" or raw == "" then
			return nil
		end
		-- FirstYear → First Year
		local spaced = raw:gsub("(%l)(%u)", "%1 %2")
		spaced = spaced:gsub("(%d+)", " %1")
		spaced = spaced:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
		return spaced
	end

	local function heightScaleToDisplay(scale)
		scale = tonumber(scale)
		if not scale then
			return nil, nil
		end
		local totalInches = ((scale - 1) * 60) + 60
		totalInches = math.clamp(totalInches, 48, 90)
		local feet = math.floor(totalInches / 12)
		local inches = totalInches - feet * 12
		local cm = totalInches * 2.54
		local imperial = string.format("%d'%.1f\"", feet, inches)
		local metric = string.format("%.0fcm", cm)
		return imperial, metric
	end

	local function resolveInfo(player, character)
		local pd = getPlayerData(character)
		local first = attr(pd, "FirstName")
		local last = attr(pd, "LastName")
		local gameName = nil
		if type(first) == "string" and first ~= "" then
			if type(last) == "string" and last ~= "" then
				gameName = first .. " " .. last
			else
				gameName = first
			end
		end

		-- Billboard fallback (matches in-world nameplate)
		if not gameName and character then
			local bill = character:FindFirstChild("PlayerInfoBillboard")
			local infoLabel = bill and bill:FindFirstChild("Info", true)
			if infoLabel and type(infoLabel.Text) == "string" and infoLabel.Text ~= "" then
				gameName = infoLabel.Text
			end
		end

		if not gameName or gameName == "" then
			gameName = player.DisplayName
			if type(gameName) ~= "string" or gameName == "" then
				gameName = player.Name
			end
		end

		local scale = attr(pd, "CurrentHeight") or attr(pd, "Height")
		local imperial, metric = heightScaleToDisplay(scale)

		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local health = humanoid and humanoid.Health or 0
		local maxHealth = humanoid and math.max(humanoid.MaxHealth, 1) or 100
		local stamina = tonumber(attr(character, "Stamina")) or 0
		-- Stamina appears 0-100 on this build
		local maxStamina = 100

		return {
			gameName = gameName,
			robloxName = player.Name,
			style = attr(pd, "CombatStyle") or attr(pd, "CombatType"),
			grade = formatGrade(attr(pd, "Grade")),
			age = attr(pd, "Age"),
			heightImperial = imperial,
			heightMetric = metric,
			health = health,
			maxHealth = maxHealth,
			stamina = stamina,
			maxStamina = maxStamina,
			loaded = attr(pd, "Loaded") == true,
		}
	end

	local function getOverlay()
		if espState.folder and espState.folder.Parent then
			return espState.folder
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
		folder.Name = "XanhubGakuranESP"
		folder.Parent = parent
		espState.folder = folder
		return folder
	end

	local function newFrame(parent, name, z)
		local f = Instance.new("Frame")
		f.Name = name
		f.BorderSizePixel = 0
		f.BackgroundTransparency = 1
		f.Visible = false
		f.ZIndex = z or 600
		f.Parent = parent
		return f
	end

	local function newText(parent, name, z)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.BorderSizePixel = 0
		t.Font = Enum.Font.Code
		t.TextSize = 13
		t.TextColor3 = WHITE
		t.TextStrokeTransparency = 0.35
		t.TextStrokeColor3 = Color3.new(0, 0, 0)
		t.TextXAlignment = Enum.TextXAlignment.Center
		t.TextYAlignment = Enum.TextYAlignment.Center
		t.Visible = false
		t.ZIndex = z or 610
		t.Parent = parent
		return t
	end

	local function destroyEntry(player)
		local entry = espState.entries[player]
		if not entry then
			return
		end
		pcall(function()
			if entry.root then
				entry.root:Destroy()
			end
		end)
		pcall(function()
			if entry.highlight then
				entry.highlight:Destroy()
			end
		end)
		espState.entries[player] = nil
	end

	local function ensureEntry(player)
		local existing = espState.entries[player]
		if existing and existing.root and existing.root.Parent then
			return existing
		end

		local overlay = getOverlay()
		if not overlay then
			return nil
		end

		local root = newFrame(overlay, "ESP_" .. player.Name, 600)
		root.Visible = true
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromScale(1, 1)

		local box = newFrame(root, "Box", 601)
		box.BackgroundTransparency = 1
		local boxStroke = Instance.new("UIStroke")
		boxStroke.Thickness = 2
		boxStroke.Color = ACCENT
		boxStroke.Parent = box

		local fill = newFrame(root, "Fill", 600)
		fill.BackgroundColor3 = ACCENT
		fill.BackgroundTransparency = 0.86

		local hpBg = newFrame(root, "HpBg", 602)
		hpBg.BackgroundColor3 = DARK
		hpBg.BackgroundTransparency = 0.25
		local hpFill = newFrame(hpBg, "HpFill", 603)
		hpFill.BackgroundColor3 = HP_HIGH
		hpFill.BackgroundTransparency = 0
		hpFill.AnchorPoint = Vector2.new(0, 1)
		hpFill.Position = UDim2.fromScale(0, 1)
		hpFill.Visible = true

		local stmBg = newFrame(root, "StmBg", 602)
		stmBg.BackgroundColor3 = DARK
		stmBg.BackgroundTransparency = 0.25
		local stmFill = newFrame(stmBg, "StmFill", 603)
		stmFill.BackgroundColor3 = STM
		stmFill.BackgroundTransparency = 0
		stmFill.AnchorPoint = Vector2.new(0, 1)
		stmFill.Position = UDim2.fromScale(0, 1)
		stmFill.Visible = true

		local nameLabel = newText(root, "Name", 612)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.TextYAlignment = Enum.TextYAlignment.Bottom

		local detailLabel = newText(root, "Detail", 612)
		detailLabel.TextColor3 = MUTED
		detailLabel.TextYAlignment = Enum.TextYAlignment.Top

		local highlight = Instance.new("Highlight")
		highlight.Name = "XanhubGakuranHL"
		highlight.Enabled = false
		highlight.FillTransparency = 0.88
		highlight.OutlineTransparency = 0.2
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = overlay

			local entry = {
			player = player,
			root = root,
			box = box,
			boxStroke = boxStroke,
			fill = fill,
			hpBg = hpBg,
			hpFill = hpFill,
			stmBg = stmBg,
			stmFill = stmFill,
			nameLabel = nameLabel,
			detailLabel = detailLabel,
			highlight = highlight,
			infoCache = nil,
			infoCacheAt = 0,
			textAt = 0,
			nameText = "",
			detailText = "",
			nameLines = 1,
			-- Cached character refs (avoid FindFirstChild every frame)
			char = nil,
			humanoid = nil,
			rootPart = nil,
			-- Static world box (not limb-AABB)
			stableWidth = nil,
			stableHeight = nil,
			stableOffsetY = nil,
			stableChar = nil,
			stableAt = 0,
			-- Last drawn rect (skip redundant GUI writes)
			lx = nil,
			ly = nil,
			lw = nil,
			lh = nil,
			lastHp = nil,
			lastStm = nil,
			drawn = false,
		}
		espState.entries[player] = entry
		return entry
	end

	local function hideEntry(entry)
		if not entry or not entry.drawn then
			if entry then
				entry.drawn = false
			end
			return
		end
		entry.drawn = false
		entry.box.Visible = false
		entry.fill.Visible = false
		entry.hpBg.Visible = false
		entry.stmBg.Visible = false
		entry.nameLabel.Visible = false
		entry.detailLabel.Visible = false
		if entry.highlight and entry.highlight.Enabled then
			entry.highlight.Enabled = false
			entry.highlight.Adornee = nil
		end
		entry.lx, entry.ly, entry.lw, entry.lh = nil, nil, nil, nil
	end

	local function isR6(character)
		return character
			and character:FindFirstChild("Torso") ~= nil
			and character:FindFirstChild("UpperTorso") == nil
	end

	local function snap(n)
		return math.floor(n + 0.5)
	end

	-- Fixed world-space size from height scale + HipHeight (not animated limbs).
	local function measureStableBounds(character, rootPart)
		local hum = character:FindFirstChildOfClass("Humanoid")
		local r6 = isR6(character)
		local pd = getPlayerData(character)
		local scale = tonumber(attr(pd, "CurrentHeight") or attr(pd, "Height")) or 1
		if scale < 0.75 then
			scale = 0.75
		elseif scale > 1.6 then
			scale = 1.6
		end

		local hip = hum and tonumber(hum.HipHeight) or (r6 and 0 or 2 * scale)
		if not hip or hip <= 0 then
			hip = r6 and 0 or 2 * scale
		end

		local hrpHalf = rootPart.Size.Y * 0.5
		local feetBelow = hip + hrpHalf

		local head = character:FindFirstChild("Head")
		local headHalf = (head and head:IsA("BasePart") and head.Size.Y * 0.5) or (0.5 * scale)
		local rawHeadAbove
		if head and head:IsA("BasePart") then
			rawHeadAbove = (head.Position.Y - rootPart.Position.Y) + headHalf
		else
			rawHeadAbove = (r6 and 2.4 or 1.72) * scale
		end
		local lo = (r6 and 2.0 or 1.35) * scale
		local hi = (r6 and 2.8 or 2.15) * scale
		local headAbove = rawHeadAbove
		if headAbove < lo then
			headAbove = lo
		elseif headAbove > hi then
			headAbove = hi
		end

		local height = feetBelow + headAbove
		local minH = r6 and 4.0 or 4.4
		local maxH = r6 and 6.8 or 7.6
		if height < minH then
			height = minH
		elseif height > maxH then
			height = maxH
		end
		local offsetY = (headAbove - feetBelow) * 0.5
		local width = (r6 and 1.95 or 2.05) * scale
		if width < 1.65 then
			width = 1.65
		elseif width > 3.2 then
			width = 3.2
		end

		return width, height, offsetY
	end

	local function ensureStableBounds(entry, character, rootPart, now)
		if entry.stableChar == character
			and entry.stableWidth
			and (now - (entry.stableAt or 0)) < 3
		then
			return entry.stableWidth, entry.stableHeight, entry.stableOffsetY
		end
		local w, h, oy = measureStableBounds(character, rootPart)
		entry.stableWidth = w
		entry.stableHeight = h
		entry.stableOffsetY = oy
		entry.stableChar = character
		entry.stableAt = now
		return w, h, oy
	end

	-- Zero-alloc camera billboard: 4 WorldToViewport calls, no tables.
	-- Full rate — boxes stay glued to characters with zero tick lag.
	local function projectBox(camera, rootPart, width, height, offsetY, camRightX, camRightY, camRightZ)
		local rp = rootPart.Position
		local cx = rp.X
		local cy = rp.Y + offsetY
		local cz = rp.Z
		local halfH = height * 0.5
		local halfW = width * 0.5
		local rx = camRightX * halfW
		local ry = camRightY * halfW
		local rz = camRightZ * halfW

		local minX, minY = 1e9, 1e9
		local maxX, maxY = -1e9, -1e9

		-- four corners: (±right, ±up)
		local function accum(wx, wy, wz)
			local sp, _ = camera:WorldToViewportPoint(Vector3.new(wx, wy, wz))
			if sp.Z <= 0.05 then
				return false
			end
			local x, y = sp.X, sp.Y
			if x < minX then
				minX = x
			end
			if y < minY then
				minY = y
			end
			if x > maxX then
				maxX = x
			end
			if y > maxY then
				maxY = y
			end
			return true
		end

		if not accum(cx - rx, cy + halfH, cz - rz) then
			return nil
		end
		if not accum(cx + rx, cy + halfH, cz + rz) then
			return nil
		end
		if not accum(cx - rx, cy - halfH, cz - rz) then
			return nil
		end
		if not accum(cx + rx, cy - halfH, cz + rz) then
			return nil
		end

		if maxX <= minX or maxY <= minY then
			return nil
		end

		local projectedH = maxY - minY
		local pad = projectedH * 0.02
		if pad < 1 then
			pad = 1
		elseif pad > 4 then
			pad = 4
		end
		return snap(minX - pad), snap(minY - pad), snap(maxX + pad), snap(maxY + pad)
	end

	local function healthColor(ratio)
		if ratio > 0.55 then
			return HP_HIGH
		elseif ratio > 0.28 then
			return HP_MID
		end
		return HP_LOW
	end

	-- Resolve Workspace.Players char once; cache parts on entry.
	local function resolveCharacter(player, playersFolder)
		local character = player.Character
		if playersFolder then
			local named = playersFolder:FindFirstChild(player.Name)
			if named and named:FindFirstChildOfClass("Humanoid") then
				character = named
			end
		end
		return character
	end

	local function cacheParts(entry, character)
		if entry.char == character and entry.rootPart and entry.rootPart.Parent and entry.humanoid and entry.humanoid.Parent then
			return entry.humanoid, entry.rootPart
		end
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and (
			character:FindFirstChild("HumanoidRootPart")
			or character:FindFirstChild("Torso")
			or character:FindFirstChild("UpperTorso")
			or character.PrimaryPart
		)
		entry.char = character
		entry.humanoid = humanoid
		entry.rootPart = rootPart
		-- force remeasure when body swaps
		entry.stableChar = nil
		return humanoid, rootPart
	end

	-- settings = frame-cached flags (read once per RenderStepped)
	local function updatePlayer(player, camera, localRoot, playersFolder, settings, now)
		if player == LocalPlayer and not settings.showSelf then
			hideEntry(espState.entries[player])
			return false
		end

		local character = resolveCharacter(player, playersFolder)
		if not character then
			hideEntry(espState.entries[player])
			return false
		end

		local entry = espState.entries[player]
		local humanoid, rootPart
		if entry then
			humanoid, rootPart = cacheParts(entry, character)
		else
			humanoid = character:FindFirstChildOfClass("Humanoid")
			rootPart = character:FindFirstChild("HumanoidRootPart")
				or character:FindFirstChild("Torso")
				or character:FindFirstChild("UpperTorso")
				or character.PrimaryPart
		end

		if not humanoid or not rootPart or humanoid.Health <= 0 then
			hideEntry(entry)
			return false
		end

		-- Squared distance — no sqrt until we need display
		local dx, dy, dz = 0, 0, 0
		if localRoot then
			local rp = rootPart.Position
			local lp = localRoot.Position
			dx = rp.X - lp.X
			dy = rp.Y - lp.Y
			dz = rp.Z - lp.Z
		end
		local distSq = dx * dx + dy * dy + dz * dz
		if distSq > settings.maxDistSq then
			hideEntry(entry)
			return false
		end

		entry = entry or ensureEntry(player)
		if not entry then
			return false
		end
		if entry.char ~= character then
			cacheParts(entry, character)
			humanoid, rootPart = entry.humanoid, entry.rootPart
			if not humanoid or not rootPart then
				hideEntry(entry)
				return false
			end
		end

		local width, height, offsetY = ensureStableBounds(entry, character, rootPart, now)
		local minX, minY, maxX, maxY = projectBox(
			camera,
			rootPart,
			width,
			height,
			offsetY,
			settings.camRightX,
			settings.camRightY,
			settings.camRightZ
		)
		if not minX then
			hideEntry(entry)
			return false
		end

		local w = maxX - minX
		local h = maxY - minY
		-- Floor screen width so distant boxes stay readable (not needle-thin)
		if w < 10 then
			local mid = (minX + maxX) * 0.5
			minX = snap(mid - 5)
			maxX = minX + 10
			w = 10
		end
		if w < 3 or h < 6 then
			hideEntry(entry)
			return false
		end

		local x, y = minX, minY
		local color = settings.color
		local rectChanged = entry.lx ~= x or entry.ly ~= y or entry.lw ~= w or entry.lh ~= h
		if rectChanged then
			entry.lx, entry.ly, entry.lw, entry.lh = x, y, w, h
		end
		entry.drawn = true

		-- Geometry every frame (smooth). Property writes only when rect moves.
		if settings.boxes then
			if not entry.box.Visible then
				entry.box.Visible = true
			end
			if rectChanged then
				entry.box.Position = UDim2.fromOffset(x, y)
				entry.box.Size = UDim2.fromOffset(w, h)
			end
			if entry.boxStroke.Color ~= color then
				entry.boxStroke.Color = color
			end
			if entry.boxStroke.Thickness ~= settings.thickness then
				entry.boxStroke.Thickness = settings.thickness
			end
		elseif entry.box.Visible then
			entry.box.Visible = false
		end

		if settings.filled then
			if not entry.fill.Visible then
				entry.fill.Visible = true
			end
			if rectChanged then
				entry.fill.Position = UDim2.fromOffset(x, y)
				entry.fill.Size = UDim2.fromOffset(w, h)
			end
			if entry.fill.BackgroundColor3 ~= color then
				entry.fill.BackgroundColor3 = color
			end
			local ft = settings.fillTransparency
			if entry.fill.BackgroundTransparency ~= ft then
				entry.fill.BackgroundTransparency = ft
			end
		elseif entry.fill.Visible then
			entry.fill.Visible = false
		end

		-- Bars: position full-rate, fill values throttled with info
		local refreshText = (now - (entry.infoCacheAt or 0)) > 0.2
		local info = entry.infoCache
		if refreshText or not info then
			info = resolveInfo(player, character)
			-- Live vitals still cheap
			info.health = humanoid.Health
			info.maxHealth = math.max(humanoid.MaxHealth, 1)
			info.stamina = tonumber(attr(character, "Stamina")) or info.stamina or 0
			entry.infoCache = info
			entry.infoCacheAt = now
		else
			-- Vitals every frame without full attr resolve
			info.health = humanoid.Health
			info.maxHealth = math.max(humanoid.MaxHealth, 1)
		end

		if settings.hpBar then
			local ratio = info.health / info.maxHealth
			if ratio < 0 then
				ratio = 0
			elseif ratio > 1 then
				ratio = 1
			end
			if not entry.hpBg.Visible then
				entry.hpBg.Visible = true
			end
			if rectChanged then
				entry.hpBg.Position = UDim2.fromOffset(x - 6, y)
				entry.hpBg.Size = UDim2.fromOffset(3, h)
			end
			if entry.lastHp ~= ratio then
				entry.lastHp = ratio
				entry.hpFill.Size = UDim2.new(1, 0, ratio, 0)
				entry.hpFill.BackgroundColor3 = healthColor(ratio)
			end
		elseif entry.hpBg.Visible then
			entry.hpBg.Visible = false
		end

		if settings.stmBar then
			-- Stamina attr: sample with text refresh (not every frame FindAttribute spam)
			if refreshText then
				info.stamina = tonumber(attr(character, "Stamina")) or 0
			end
			local ratio = (info.stamina or 0) / (info.maxStamina or 100)
			if ratio < 0 then
				ratio = 0
			elseif ratio > 1 then
				ratio = 1
			end
			if not entry.stmBg.Visible then
				entry.stmBg.Visible = true
			end
			if rectChanged then
				entry.stmBg.Position = UDim2.fromOffset(x + w + 3, y)
				entry.stmBg.Size = UDim2.fromOffset(3, h)
			end
			if entry.lastStm ~= ratio then
				entry.lastStm = ratio
				entry.stmFill.Size = UDim2.new(1, 0, ratio, 0)
			end
		elseif entry.stmBg.Visible then
			entry.stmBg.Visible = false
		end

		-- Labels: position every frame, string rebuild ~5/s (no ticky box, no GC spam)
		local dist = math.sqrt(distSq)
		local needTextRebuild = refreshText or (now - (entry.textAt or 0)) > 0.12
		if needTextRebuild then
			entry.textAt = now
			local nameText = ""
			local nameLines = 0
			if settings.names then
				nameText = info.gameName or ""
				nameLines = 1
				if settings.realNames then
					nameText = nameText .. "\n@" .. info.robloxName
					nameLines = 2
				end
			end
			entry.nameText = nameText
			entry.nameLines = nameLines

			local parts = nil
			local n = 0
			if settings.distance then
				n = n + 1
				parts = parts or {}
				parts[n] = string.format("%.0fst", dist)
			end
			if settings.style and type(info.style) == "string" and info.style ~= "" then
				n = n + 1
				parts = parts or {}
				parts[n] = info.style
			end
			if settings.grade and type(info.grade) == "string" and info.grade ~= "" then
				n = n + 1
				parts = parts or {}
				parts[n] = info.grade
			end
			if settings.age and info.age ~= nil then
				n = n + 1
				parts = parts or {}
				parts[n] = "Age " .. tostring(info.age)
			end
			if settings.height and info.heightImperial then
				n = n + 1
				parts = parts or {}
				parts[n] = info.heightImperial .. " / " .. (info.heightMetric or "")
			end
			entry.detailText = (parts and table.concat(parts, " · ")) or ""
		elseif settings.distance and entry.detailText ~= "" then
			-- keep distance roughly fresh without full rebuild every frame
			-- (handled in rebuild window above)
		end

		if entry.nameLines > 0 and entry.nameText ~= "" then
			local nameH = settings.textSize * entry.nameLines + 4
			local nameW = w + 80
			if nameW < 120 then
				nameW = 120
			end
			if not entry.nameLabel.Visible then
				entry.nameLabel.Visible = true
			end
			if entry.nameLabel.Text ~= entry.nameText then
				entry.nameLabel.Text = entry.nameText
			end
			if entry.nameLabel.TextColor3 ~= settings.nameColor then
				entry.nameLabel.TextColor3 = settings.nameColor
			end
			if entry.nameLabel.TextSize ~= settings.textSize then
				entry.nameLabel.TextSize = settings.textSize
			end
			if rectChanged or needTextRebuild then
				entry.nameLabel.Size = UDim2.fromOffset(nameW, nameH)
				entry.nameLabel.Position = UDim2.fromOffset(x + w * 0.5 - nameW * 0.5, y - nameH - 2)
			end
		elseif entry.nameLabel.Visible then
			entry.nameLabel.Visible = false
		end

		if entry.detailText ~= "" then
			local detH = settings.textSize + 2
			local detW = w + 100
			if detW < 140 then
				detW = 140
			end
			local detSize = settings.textSize - 2
			if detSize < 10 then
				detSize = 10
			end
			if not entry.detailLabel.Visible then
				entry.detailLabel.Visible = true
			end
			if entry.detailLabel.Text ~= entry.detailText then
				entry.detailLabel.Text = entry.detailText
			end
			if entry.detailLabel.TextSize ~= detSize then
				entry.detailLabel.TextSize = detSize
			end
			if rectChanged or needTextRebuild then
				entry.detailLabel.Size = UDim2.fromOffset(detW, detH)
				entry.detailLabel.Position = UDim2.fromOffset(x + w * 0.5 - detW * 0.5, maxY + 2)
			end
		elseif entry.detailLabel.Visible then
			entry.detailLabel.Visible = false
		end

		-- Highlight is expensive — only when enabled
		if settings.highlight then
			if not entry.highlight.Enabled then
				entry.highlight.Enabled = true
			end
			if entry.highlight.Adornee ~= character then
				entry.highlight.Adornee = character
			end
			if entry.highlight.FillColor ~= color then
				entry.highlight.FillColor = color
				entry.highlight.OutlineColor = color
			end
		elseif entry.highlight.Enabled then
			entry.highlight.Enabled = false
			entry.highlight.Adornee = nil
		end

		return true
	end

	local function clearAll()
		for player in pairs(espState.entries) do
			destroyEntry(player)
		end
		if espState.folder then
			pcall(function()
				espState.folder:Destroy()
			end)
			espState.folder = nil
		end
	end

	-- Setup --------------------------------------------------------------

	local function setup()
		local statusAccum = 0
		local playersFolderCache = nil
		local playersFolderAt = 0
		local pruneAccum = 0
		-- Reused settings table — no alloc per frame
		local settings = {
			showSelf = false,
			boxes = true,
			filled = false,
			hpBar = true,
			stmBar = true,
			highlight = false,
			names = true,
			realNames = false,
			distance = true,
			style = true,
			grade = true,
			age = false,
			height = false,
			color = ACCENT,
			nameColor = WHITE,
			textSize = 13,
			thickness = 2,
			fillTransparency = 0.86,
			maxDistSq = 600 * 600,
			camRightX = 1,
			camRightY = 0,
			camRightZ = 0,
		}

		ctx.addConnection(Players.PlayerRemoving, function(player)
			destroyEntry(player)
		end)

		-- RenderStepped = same cadence as camera (no tick lag / stutter)
		ctx.addConnection(RunService.RenderStepped, function(dt)
			if ctx.state.unloading then
				return
			end

			if library.flags["Gakuran Player ESP"] ~= true then
				if next(espState.entries) then
					clearAll()
				end
				return
			end

			local camera = Workspace.CurrentCamera
			if not camera then
				return
			end

			local now = os.clock()
			dt = tonumber(dt) or 0

			-- Flags once/frame
			settings.showSelf = library.flags["Gakuran ESP Show Self"] == true
			settings.boxes = library.flags["Gakuran ESP Boxes"] ~= false
			settings.filled = library.flags["Gakuran ESP Filled Boxes"] == true
			settings.hpBar = library.flags["Gakuran ESP Health Bar"] ~= false
			settings.stmBar = library.flags["Gakuran ESP Stamina Bar"] ~= false
			settings.highlight = library.flags["Gakuran ESP Highlight"] == true
			settings.names = library.flags["Gakuran ESP Names"] ~= false
			settings.realNames = library.flags["Gakuran ESP Real Names"] == true
			settings.distance = library.flags["Gakuran ESP Distance"] ~= false
			settings.style = library.flags["Gakuran ESP Combat Style"] ~= false
			settings.grade = library.flags["Gakuran ESP Grade"] ~= false
			settings.age = library.flags["Gakuran ESP Age"] == true
			settings.height = library.flags["Gakuran ESP Height"] == true
			local c = library.flags["Gakuran ESP Color"]
			settings.color = (typeof(c) == "Color3") and c or ACCENT
			local nc = library.flags["Gakuran ESP Name Color"]
			settings.nameColor = (typeof(nc) == "Color3") and nc or WHITE
			settings.textSize = tonumber(library.flags["Gakuran ESP Text Size"]) or 13
			settings.thickness = tonumber(library.flags["Gakuran ESP Box Thickness"]) or 2
			local fillOp = (tonumber(library.flags["Gakuran ESP Fill Opacity"]) or 14) / 100
			local ft = 1 - fillOp
			if ft < 0.4 then
				ft = 0.4
			elseif ft > 1 then
				ft = 1
			end
			settings.fillTransparency = ft
			local maxDist = tonumber(library.flags["Gakuran ESP Max Distance"]) or 600
			settings.maxDistSq = maxDist * maxDist

			local right = camera.CFrame.RightVector
			settings.camRightX = right.X
			settings.camRightY = right.Y
			settings.camRightZ = right.Z

			-- Cache Workspace.Players ~2/s
			if not playersFolderCache or (now - playersFolderAt) > 0.5 then
				playersFolderCache = Workspace:FindFirstChild("Players")
				playersFolderAt = now
			end

			local localChar = LocalPlayer.Character
			local localRoot = localChar and (
				localChar:FindFirstChild("HumanoidRootPart")
				or localChar.PrimaryPart
			)

			local drawn = 0
			local list = Players:GetPlayers()
			for i = 1, #list do
				local player = list[i]
				local ok, result = pcall(updatePlayer, player, camera, localRoot, playersFolderCache, settings, now)
				if ok and result then
					drawn = drawn + 1
				end
			end

			-- Prune rare (not every frame)
			pruneAccum = pruneAccum + dt
			if pruneAccum >= 1.5 then
				pruneAccum = 0
				for player in pairs(espState.entries) do
					if not player.Parent then
						destroyEntry(player)
					end
				end
			end

			statusAccum = statusAccum + dt
			if statusAccum >= 1 then
				statusAccum = 0
				setStatus(string.format("drawing %d · full-rate", drawn))
			end
		end)

		setStatus("idle · enable Player ESP")
	end

	library:AddCleanup(function()
		clearAll()
	end)

	return { setup = setup }
end
