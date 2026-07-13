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
			-- Static world box (not limb-AABB — limbs expand every frame)
			stableWidth = nil,
			stableHeight = nil,
			stableOffsetY = nil,
			stableChar = nil,
			stableAt = 0,
		}
		espState.entries[player] = entry
		return entry
	end

	local function hideEntry(entry)
		if not entry then
			return
		end
		entry.box.Visible = false
		entry.fill.Visible = false
		entry.hpBg.Visible = false
		entry.stmBg.Visible = false
		entry.nameLabel.Visible = false
		entry.detailLabel.Visible = false
		if entry.highlight then
			entry.highlight.Enabled = false
		end
	end

	local function isR6(character)
		return character
			and character:FindFirstChild("Torso") ~= nil
			and character:FindFirstChild("UpperTorso") == nil
	end

	local function snap(n)
		return math.floor((tonumber(n) or 0) + 0.5)
	end

	-- IgnoreGuiInset ScreenGui (xanhub_ui): AbsolutePosition.Y is -GuiInset (~-58).
	-- WorldToViewportPoint is already full-viewport pixels; Position offsets on that
	-- overlay are also full-viewport. Subtracting AbsolutePosition pushed boxes ~58px down.
	local function worldToOverlay(camera, worldPos)
		local sp, onScreen = camera:WorldToViewportPoint(worldPos)
		if sp.Z <= 0.05 then
			return nil, nil, false, sp.Z
		end
		return sp.X, sp.Y, onScreen, sp.Z
	end

	-- Fixed world-space size from height scale + HipHeight (not animated limbs).
	local function measureStableBounds(character, rootPart)
		local hum = character:FindFirstChildOfClass("Humanoid")
		local r6 = isR6(character)
		local pd = getPlayerData(character)
		local scale = tonumber(attr(pd, "CurrentHeight") or attr(pd, "Height")) or 1
		scale = math.clamp(scale, 0.75, 1.6)

		local hip = hum and tonumber(hum.HipHeight) or (r6 and 0 or 2 * scale)
		if hip <= 0 then
			hip = r6 and 0 or 2 * scale
		end

		-- Feet: Humanoid HipHeight is ground→HRP bottom (pose-independent).
		local hrpHalf = rootPart.Size.Y * 0.5
		local feetBelow = hip + hrpHalf

		-- Crown: clamp head relative height so idle bob can't stretch the box.
		-- Live Gakuran R15 sits ~1.7×scale above HRP (crown), not full GetBoundingBox.
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
		local headAbove = math.clamp(rawHeadAbove, lo, hi)

		local height = math.clamp(feetBelow + headAbove, r6 and 4.0 or 4.4, r6 and 6.8 or 7.6)
		local offsetY = (headAbove - feetBelow) * 0.5
		-- Shoulder width tracks height attr (taller students → slightly wider)
		local width = math.clamp((r6 and 1.95 or 2.05) * scale, 1.65, 3.2)

		return width, height, offsetY
	end

	local function ensureStableBounds(entry, character, rootPart)
		local now = os.clock()
		if entry.stableChar == character
			and entry.stableWidth
			and entry.stableHeight
			and (now - (entry.stableAt or 0)) < 2.5
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

	-- Camera-facing billboard of FIXED stud size — no limb AABB expansion.
	local function getCharacterBounds(camera, character, rootPart, entry)
		local width, height, offsetY = ensureStableBounds(entry, character, rootPart)
		local center = rootPart.Position + Vector3.new(0, offsetY, 0)
		local worldUp = Vector3.new(0, height * 0.5, 0)
		local cameraRight = camera.CFrame.RightVector * (width * 0.5)
		local corners = {
			center + worldUp - cameraRight,
			center + worldUp + cameraRight,
			center - worldUp - cameraRight,
			center - worldUp + cameraRight,
		}

		local minX, minY = math.huge, math.huge
		local maxX, maxY = -math.huge, -math.huge
		for _, world in ipairs(corners) do
			local x, y, _, z = worldToOverlay(camera, world)
			if not x or z <= 0.05 then
				return nil
			end
			minX = math.min(minX, x)
			minY = math.min(minY, y)
			maxX = math.max(maxX, x)
			maxY = math.max(maxY, y)
		end

		if maxX <= minX or maxY <= minY then
			return nil
		end

		local projectedH = maxY - minY
		local pad = math.clamp(projectedH * 0.02, 1, 4)
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

	local function updatePlayer(player, camera, localRoot)
		if player == LocalPlayer and not flag("Gakuran ESP Show Self", false) then
			local entry = espState.entries[player]
			if entry then
				hideEntry(entry)
			end
			return
		end

		-- Gakuran characters live under Workspace.Players (same instance as Character usually)
		local character = player.Character
		local folder = Workspace:FindFirstChild("Players")
		if folder then
			local named = folder:FindFirstChild(player.Name)
			if named and named:FindFirstChildOfClass("Humanoid") then
				character = named
			end
		end
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and (
			character:FindFirstChild("HumanoidRootPart")
			or character:FindFirstChild("Torso")
			or character:FindFirstChild("UpperTorso")
			or character.PrimaryPart
		)

		if not character or not humanoid or not rootPart or humanoid.Health <= 0 then
			local entry = espState.entries[player]
			if entry then
				hideEntry(entry)
			end
			return
		end

		local dist = localRoot and (rootPart.Position - localRoot.Position).Magnitude or 0
		local maxDist = numFlag("Gakuran ESP Max Distance", 600)
		if dist > maxDist then
			local entry = espState.entries[player]
			if entry then
				hideEntry(entry)
			end
			return
		end

		local entry = ensureEntry(player)
		if not entry then
			return
		end

		-- Static camera-facing box (height-scale sized, no limb expansion)
		local minX, minY, maxX, maxY = getCharacterBounds(camera, character, rootPart, entry)
		if not minX then
			hideEntry(entry)
			return
		end

		local color = colorFlag("Gakuran ESP Color", ACCENT)
		local nameColor = colorFlag("Gakuran ESP Name Color", WHITE)
		local textSize = numFlag("Gakuran ESP Text Size", 13)
		local thickness = numFlag("Gakuran ESP Box Thickness", 2)
		local fillOpacity = numFlag("Gakuran ESP Fill Opacity", 14) / 100

		local w = maxX - minX
		local h = maxY - minY
		local x = minX
		local y = minY
		if w < 3 or h < 6 then
			hideEntry(entry)
			return
		end

		-- Cache PlayerData text ~6.5x/sec (attrs rarely change mid-frame).
		local now = os.clock()
		local info = entry.infoCache
		if not info or (now - (entry.infoCacheAt or 0)) > 0.15 then
			info = resolveInfo(player, character)
			entry.infoCache = info
			entry.infoCacheAt = now
		end

		-- Box (pixel-snapped static rect)
		if flag("Gakuran ESP Boxes", true) then
			entry.box.Visible = true
			entry.box.Position = UDim2.fromOffset(x, y)
			entry.box.Size = UDim2.fromOffset(w, h)
			entry.boxStroke.Color = color
			entry.boxStroke.Thickness = thickness
			entry.box.BackgroundTransparency = 1
		else
			entry.box.Visible = false
		end

		if flag("Gakuran ESP Filled Boxes", false) then
			entry.fill.Visible = true
			entry.fill.Position = UDim2.fromOffset(x, y)
			entry.fill.Size = UDim2.fromOffset(w, h)
			entry.fill.BackgroundColor3 = color
			entry.fill.BackgroundTransparency = math.clamp(1 - fillOpacity, 0.4, 1)
		else
			entry.fill.Visible = false
		end

		-- Health bar (left)
		if flag("Gakuran ESP Health Bar", true) then
			local ratio = math.clamp(info.health / math.max(info.maxHealth, 1), 0, 1)
			local barW = 3
			entry.hpBg.Visible = true
			entry.hpBg.Position = UDim2.fromOffset(x - barW - 3, y)
			entry.hpBg.Size = UDim2.fromOffset(barW, h)
			entry.hpFill.Size = UDim2.new(1, 0, ratio, 0)
			entry.hpFill.BackgroundColor3 = healthColor(ratio)
			entry.hpFill.Visible = true
		else
			entry.hpBg.Visible = false
		end

		-- Stamina bar (right)
		if flag("Gakuran ESP Stamina Bar", true) then
			local ratio = math.clamp(info.stamina / math.max(info.maxStamina, 1), 0, 1)
			local barW = 3
			entry.stmBg.Visible = true
			entry.stmBg.Position = UDim2.fromOffset(x + w + 3, y)
			entry.stmBg.Size = UDim2.fromOffset(barW, h)
			entry.stmFill.Size = UDim2.new(1, 0, ratio, 0)
			entry.stmFill.BackgroundColor3 = STM
			entry.stmFill.Visible = true
		else
			entry.stmBg.Visible = false
		end

		-- Name + details
		local showNames = flag("Gakuran ESP Names", true)
		local linesTop = {}
		local linesBottom = {}

		if showNames then
			table.insert(linesTop, info.gameName)
			if flag("Gakuran ESP Real Names", false) then
				table.insert(linesTop, "@" .. info.robloxName)
			end
		end

		if flag("Gakuran ESP Distance", true) then
			table.insert(linesBottom, string.format("%.0fst", dist))
		end
		if flag("Gakuran ESP Combat Style", true) and type(info.style) == "string" and info.style ~= "" then
			table.insert(linesBottom, tostring(info.style))
		end
		if flag("Gakuran ESP Grade", true) and type(info.grade) == "string" and info.grade ~= "" then
			table.insert(linesBottom, info.grade)
		end
		if flag("Gakuran ESP Age", false) and info.age ~= nil then
			table.insert(linesBottom, "Age " .. tostring(info.age))
		end
		if flag("Gakuran ESP Height", false) and info.heightImperial then
			table.insert(linesBottom, info.heightImperial .. " / " .. (info.heightMetric or ""))
		end

		if #linesTop > 0 then
			entry.nameLabel.Visible = true
			entry.nameLabel.Text = table.concat(linesTop, "\n")
			entry.nameLabel.TextColor3 = nameColor
			entry.nameLabel.TextSize = textSize
			local lineCount = #linesTop
			local nameH = textSize * lineCount + 4
			entry.nameLabel.Size = UDim2.fromOffset(math.max(w + 80, 120), nameH)
			entry.nameLabel.Position = UDim2.fromOffset(x + w * 0.5 - entry.nameLabel.Size.X.Offset * 0.5, y - nameH - 2)
		else
			entry.nameLabel.Visible = false
		end

		if #linesBottom > 0 then
			entry.detailLabel.Visible = true
			entry.detailLabel.Text = table.concat(linesBottom, " · ")
			entry.detailLabel.TextColor3 = MUTED
			entry.detailLabel.TextSize = math.max(10, textSize - 2)
			local detH = textSize + 2
			entry.detailLabel.Size = UDim2.fromOffset(math.max(w + 100, 140), detH)
			entry.detailLabel.Position = UDim2.fromOffset(x + w * 0.5 - entry.detailLabel.Size.X.Offset * 0.5, maxY + 2)
		else
			entry.detailLabel.Visible = false
		end

		if flag("Gakuran ESP Highlight", false) then
			entry.highlight.Enabled = true
			entry.highlight.Adornee = character
			entry.highlight.FillColor = color
			entry.highlight.OutlineColor = color
		else
			entry.highlight.Enabled = false
			entry.highlight.Adornee = nil
		end
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

		ctx.addConnection(Players.PlayerRemoving, function(player)
			destroyEntry(player)
		end)

		ctx.addConnection(RunService.RenderStepped, function(dt)
			if ctx.state.unloading then
				return
			end

			if not flag("Gakuran Player ESP", false) then
				if next(espState.entries) then
					clearAll()
				end
				return
			end

			local camera = Workspace.CurrentCamera
			if not camera then
				return
			end

			local localChar = LocalPlayer.Character
			local localRoot = localChar and (
				localChar:FindFirstChild("HumanoidRootPart")
				or localChar:FindFirstChild("Torso")
				or localChar:FindFirstChild("UpperTorso")
				or localChar.PrimaryPart
			)

			local drawn = 0
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(updatePlayer, player, camera, localRoot)
				if not ok then
					-- keep going
				else
					local entry = espState.entries[player]
					if entry and entry.box and entry.box.Visible then
						drawn = drawn + 1
					elseif entry and entry.nameLabel and entry.nameLabel.Visible then
						drawn = drawn + 1
					end
				end
			end

			-- prune disconnected
			for player in pairs(espState.entries) do
				if not player.Parent then
					destroyEntry(player)
				end
			end

			statusAccum = statusAccum + (tonumber(dt) or 0)
			if statusAccum >= 1 then
				statusAccum = 0
				setStatus(string.format("drawing %d players", drawn))
			end
		end)

		setStatus("idle · enable Player ESP")
	end

	library:AddCleanup(function()
		clearAll()
	end)

	return { setup = setup }
end
