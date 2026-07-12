--[[
    xanhub | universal | modules | esp

    Customizable player ESP with corner boxes, pulse glow, and live preview.
]]

local R15_BONES = {
	{"Head", "UpperTorso"},
	{"UpperTorso", "LowerTorso"},
	{"UpperTorso", "LeftUpperArm"},
	{"LeftUpperArm", "LeftLowerArm"},
	{"LeftLowerArm", "LeftHand"},
	{"UpperTorso", "RightUpperArm"},
	{"RightUpperArm", "RightLowerArm"},
	{"RightLowerArm", "RightHand"},
	{"LowerTorso", "LeftUpperLeg"},
	{"LeftUpperLeg", "LeftLowerLeg"},
	{"LeftLowerLeg", "LeftFoot"},
	{"LowerTorso", "RightUpperLeg"},
	{"RightUpperLeg", "RightLowerLeg"},
	{"RightLowerLeg", "RightFoot"},
}

local R6_BONES = {
	{"Head", "Torso"},
	{"Torso", "Left Arm"},
	{"Torso", "Right Arm"},
	{"Torso", "Left Leg"},
	{"Torso", "Right Leg"},
}

local BOUND_PARTS = {
	"Head", "UpperTorso", "LowerTorso", "Torso",
	"LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
	"LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg",
	"LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot",
	"Left Arm", "Right Arm", "Left Leg", "Right Leg",
	"HumanoidRootPart",
}

local function getPlayerLabel(player)
	local display = player.DisplayName
	local username = player.Name

	if type(display) ~= "string" or display == "" then
		return username
	end

	local trimmed = string.match(display, "^%s*(.-)%s*$") or display
	if trimmed == "" or string.match(trimmed, "^%?+$") then
		return username
	end

	return trimmed
end

local function safeClamp(value, minValue, maxValue)
	if minValue > maxValue then
		minValue, maxValue = maxValue, minValue
	end
	return math.clamp(value, minValue, maxValue)
end

return function(ctx)
	local espSection = ctx.columns.visualsLeft:AddSection("Player ESP")
	espSection:AddToggle({text = "Enabled", flag = "Universal ESP", state = false})
	espSection:AddToggle({text = "Box ESP", flag = "Universal ESP Box", state = true})
	espSection:AddList({
		text = "Box Style",
		flag = "Universal ESP Box Style",
		values = {"Full", "Corners", "Double"},
		value = "Corners",
	})
	espSection:AddToggle({text = "Filled Box", flag = "Universal ESP Box Fill", state = false})
	espSection:AddSlider({
		text = "Fill Opacity",
		flag = "Universal ESP Fill Opacity",
		min = 5,
		max = 60,
		value = 18,
		float = 1,
		suffix = "%",
	})
	espSection:AddToggle({text = "Pulse Glow", flag = "Universal ESP Pulse", state = true})
	espSection:AddToggle({text = "Chroma Shift", flag = "Universal ESP Chroma", state = false})
	espSection:AddSlider({
		text = "Glow Strength",
		flag = "Universal ESP Glow Strength",
		min = 0,
		max = 100,
		value = 55,
		float = 5,
		suffix = "%",
	})
	espSection:AddSlider({
		text = "Corner Length",
		flag = "Universal ESP Corner Length",
		min = 10,
		max = 45,
		value = 24,
		float = 1,
		suffix = "%",
	})
	espSection:AddToggle({text = "Skeleton ESP", flag = "Universal ESP Skeleton", state = false})
	espSection:AddToggle({text = "Head Dot", flag = "Universal ESP Head Dot", state = false})
	espSection:AddToggle({text = "Nametag", flag = "Universal ESP Nametag", state = true})
	espSection:AddToggle({text = "Show Username", flag = "Universal ESP Show Username", state = false})
	espSection:AddToggle({text = "Distance Tag", flag = "Universal ESP Distance", state = true})
	espSection:AddToggle({text = "Health Bar", flag = "Universal ESP Health", state = true})
	espSection:AddList({
		text = "Health Bar Side",
		flag = "Universal ESP Health Side",
		values = {"Left", "Right"},
		value = "Left",
	})
	espSection:AddToggle({text = "Tracer Line", flag = "Universal ESP Tracer", state = false})
	espSection:AddList({
		text = "Tracer From",
		flag = "Universal ESP Tracer From",
		values = {"Bottom", "Center", "Top"},
		value = "Bottom",
	})
	espSection:AddToggle({text = "Highlights", flag = "Universal ESP Highlights", state = false})
	espSection:AddToggle({text = "Team Check", flag = "Universal ESP Team Check", state = false})
	espSection:AddSlider({
		text = "Box Thickness",
		flag = "Universal ESP Box Thickness",
		min = 1,
		max = 4,
		value = 1.5,
		float = 0.5,
	})
	espSection:AddSlider({
		text = "Line Thickness",
		flag = "Universal ESP Line Thickness",
		min = 1,
		max = 3,
		value = 1.5,
		float = 0.5,
	})
	espSection:AddSlider({
		text = "Nametag Size",
		flag = "Universal ESP Nametag Size",
		min = 10,
		max = 18,
		value = 13,
		float = 1,
	})
	espSection:AddSlider({
		text = "Fade Start",
		flag = "Universal ESP Fade Start",
		min = 50,
		max = 1200,
		value = 250,
		float = 10,
		suffix = " studs",
	})
	espSection:AddSlider({
		text = "Maximum Distance",
		flag = "Universal ESP Max Distance",
		min = 50,
		max = 2000,
		value = 650,
		float = 10,
		suffix = " studs",
	})
	espSection:AddColor({
		text = "ESP Color",
		flag = "Universal ESP Color",
		color = Color3.fromRGB(0, 170, 255),
	})
	espSection:AddColor({
		text = "Skeleton Color",
		flag = "Universal ESP Skeleton Color",
		color = Color3.fromRGB(0, 210, 255),
	})

	local styleSection = ctx.columns.visualsRight:AddSection("ESP Style")
	styleSection:AddLabel("Corners + pulse glow = xanhub signature look")
	styleSection:AddLabel("Chroma Shift cycles hue per player")
	styleSection:AddLabel("Double style stacks outline + corner brackets")

	local previewSection = ctx.columns.visualsRight:AddSection("ESP Preview")
	previewSection:AddLabel("Live Roblox character preview")
	ctx.refs.espPreviewSection = previewSection

	local function setupESPRuntime()
		local renderConnection
		local playerRemovingConnection
		local previewConnection

		local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"
		if not hasDrawing then
			ctx.notify("Drawing API unavailable; box/skeleton ESP disabled", 4)
		end

		local function flag(name, default)
			local value = ctx.library.flags[name]
			if type(value) == "boolean" then
				return value
			end
			return default
		end

		local function colorFlag(name, fallback)
			local value = ctx.library.flags[name]
			if typeof(value) == "Color3" then
				return value
			end
			return fallback
		end

		local function numberFlag(name, default)
			return tonumber(ctx.library.flags[name]) or default
		end

		local function newDrawing(className)
			if not hasDrawing then
				return nil
			end
			local ok, drawing = pcall(Drawing.new, className)
			if ok then
				drawing.Visible = false
				return drawing
			end
			return nil
		end

		local function hideDrawing(drawing)
			if drawing then
				drawing.Visible = false
			end
		end

		local function destroyDrawings(drawings)
			if not drawings then
				return
			end
			for key, value in pairs(drawings) do
				if type(value) == "table" then
					for _, item in ipairs(value) do
						pcall(function()
							item:Remove()
						end)
					end
				elseif value then
					pcall(function()
						value:Remove()
					end)
				end
				drawings[key] = nil
			end
		end

		local function getBonePairs(character)
			if character:FindFirstChild("UpperTorso") then
				return R15_BONES
			end
			return R6_BONES
		end

		local function buildNametagText(player, distance)
			local label = getPlayerLabel(player)
			local lines = { label }

			if flag("Universal ESP Show Username", false) and player.Name ~= label then
				table.insert(lines, "@" .. player.Name)
			end

			if flag("Universal ESP Distance", true) then
				lines[1] = lines[1] .. string.format("  [%dm]", math.floor(distance + 0.5))
			end

			return table.concat(lines, "\n")
		end

		local function getViewportBounds(camera, character)
			local minX, minY = math.huge, math.huge
			local maxX, maxY = -math.huge, -math.huge
			local anyOnScreen = false

			for _, partName in ipairs(BOUND_PARTS) do
				local part = character:FindFirstChild(partName)
				if part and part:IsA("BasePart") then
					local cframe = part.CFrame
					local size = part.Size
					for sx = -1, 1, 2 do
						for sy = -1, 1, 2 do
							for sz = -1, 1, 2 do
								local world = cframe:PointToWorldSpace(Vector3.new(
									size.X * 0.5 * sx,
									size.Y * 0.5 * sy,
									size.Z * 0.5 * sz
								))
								local point, onScreen = camera:WorldToViewportPoint(world)
								if onScreen then
									anyOnScreen = true
									minX = math.min(minX, point.X)
									minY = math.min(minY, point.Y)
									maxX = math.max(maxX, point.X)
									maxY = math.max(maxY, point.Y)
								end
							end
						end
					end
				end
			end

			if not anyOnScreen then
				return false
			end

			local padding = 3
			return true, {
				topLeft = Vector2.new(minX - padding, minY - padding),
				bottomRight = Vector2.new(maxX + padding, maxY + padding),
				center = Vector2.new((minX + maxX) * 0.5, (minY + maxY) * 0.5),
				topCenter = Vector2.new((minX + maxX) * 0.5, minY - padding),
				bottomCenter = Vector2.new((minX + maxX) * 0.5, maxY + padding),
			}
		end

		local function ensureDrawings(entry)
			entry.drawings = entry.drawings or {}
			local drawings = entry.drawings

			if not drawings.box then
				drawings.box = newDrawing("Square")
				drawings.boxFill = newDrawing("Square")
				drawings.tracer = newDrawing("Line")
				drawings.headDot = newDrawing("Circle")
				drawings.glow = newDrawing("Square")
				drawings.corners = {}
				for _ = 1, 8 do
					table.insert(drawings.corners, newDrawing("Line"))
				end
				drawings.skeleton = {}
			end

			local needed = #getBonePairs(entry.character)
			while #drawings.skeleton < needed do
				table.insert(drawings.skeleton, newDrawing("Line"))
			end

			return drawings
		end

		local function resolveDisplayColor(baseColor, player, isTarget, targetColor)
			if isTarget then
				return targetColor
			end
			if flag("Universal ESP Chroma", false) then
				local hue = (os.clock() * 0.14 + (player.UserId % 997) * 0.0013) % 1
				return Color3.fromHSV(hue, 0.82, 1)
			end
			return baseColor
		end

		local function getBoxStyle()
			local style = ctx.library.flags["Universal ESP Box Style"]
			if style == "Full" or style == "Corners" or style == "Double" then
				return style
			end
			return "Corners"
		end

		local function drawCornerBox(drawings, topLeft, width, height, color, thickness, transparency, visible, cornerRatio)
			if not visible or width < 2 or height < 2 then
				for _, line in ipairs(drawings.corners) do
					hideDrawing(line)
				end
				hideDrawing(drawings.box)
				return
			end

			hideDrawing(drawings.box)

			local ratio = (cornerRatio or 24) / 100
			local corner = safeClamp(math.min(width, height) * ratio, 4, math.min(width, height) * 0.48)
			local x1, y1 = topLeft.X, topLeft.Y
			local x2, y2 = topLeft.X + width, topLeft.Y + height

			local segments = {
				{Vector2.new(x1, y1), Vector2.new(x1 + corner, y1)},
				{Vector2.new(x1, y1), Vector2.new(x1, y1 + corner)},
				{Vector2.new(x2, y1), Vector2.new(x2 - corner, y1)},
				{Vector2.new(x2, y1), Vector2.new(x2, y1 + corner)},
				{Vector2.new(x1, y2), Vector2.new(x1 + corner, y2)},
				{Vector2.new(x1, y2), Vector2.new(x1, y2 - corner)},
				{Vector2.new(x2, y2), Vector2.new(x2 - corner, y2)},
				{Vector2.new(x2, y2), Vector2.new(x2, y2 - corner)},
			}

			for index, segment in ipairs(segments) do
				local line = drawings.corners[index]
				if line then
					line.Visible = true
					line.From = segment[1]
					line.To = segment[2]
					line.Color = color
					line.Thickness = thickness
					line.Transparency = transparency
				end
			end
		end

		local function destroyEntry(player)
			local entry = ctx.state.esp[player]
			if not entry then
				return
			end

			if entry.highlight then
				pcall(function()
					entry.highlight:Destroy()
				end)
			end

			if entry.screen and entry.screen.root then
				pcall(function()
					entry.screen.root:Destroy()
				end)
			end

			destroyDrawings(entry.drawings)
			ctx.state.esp[player] = nil
		end

		local function createScreenElements(overlayRoot, player)
			local root = Instance.new("Frame")
			root.Name = "ESP_" .. player.Name
			root.BackgroundTransparency = 1
			root.Size = UDim2.fromOffset(0, 0)
			root.Visible = false
			root.ZIndex = 512
			root.Parent = overlayRoot

			local nametag = Instance.new("TextLabel")
			nametag.Name = "Nametag"
			nametag.BackgroundTransparency = 1
			nametag.Size = UDim2.fromOffset(200, 32)
			nametag.AnchorPoint = Vector2.new(0.5, 1)
			nametag.Font = Enum.Font.GothamMedium
			nametag.TextSize = 13
			nametag.TextColor3 = Color3.fromRGB(245, 247, 255)
			nametag.TextStrokeTransparency = 0.35
			nametag.TextTruncate = Enum.TextTruncate.AtEnd
			nametag.TextYAlignment = Enum.TextYAlignment.Bottom
			nametag.Visible = false
			nametag.ZIndex = 514
			nametag.Parent = root

			local sideHealthBg = Instance.new("Frame")
			sideHealthBg.Name = "SideHealthBg"
			sideHealthBg.BackgroundColor3 = Color3.fromRGB(28, 33, 43)
			sideHealthBg.BorderSizePixel = 0
			sideHealthBg.Visible = false
			sideHealthBg.ZIndex = 513
			sideHealthBg.Parent = root
			ctx.createRounded(sideHealthBg, 2)

			local sideHealthFill = Instance.new("Frame")
			sideHealthFill.Name = "SideHealthFill"
			sideHealthFill.AnchorPoint = Vector2.new(0, 1)
			sideHealthFill.Position = UDim2.fromScale(0, 1)
			sideHealthFill.Size = UDim2.fromScale(1, 1)
			sideHealthFill.BackgroundColor3 = Color3.fromRGB(80, 225, 115)
			sideHealthFill.BorderSizePixel = 0
			sideHealthFill.ZIndex = 514
			sideHealthFill.Parent = sideHealthBg
			ctx.createRounded(sideHealthFill, 2)

			return {
				root = root,
				nametag = nametag,
				sideHealthBg = sideHealthBg,
				sideHealthFill = sideHealthFill,
			}
		end

		local function createEntry(player, character)
			destroyEntry(player)

			local root = character:FindFirstChild("HumanoidRootPart")
				or character:FindFirstChild("UpperTorso")
				or character:FindFirstChild("Torso")
				or character:FindFirstChild("Head")

			if not root then
				return nil
			end

			local highlight = Instance.new("Highlight")
			highlight.Name = "xanhub_universal_highlight"
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.FillTransparency = 0.92
			highlight.OutlineTransparency = 0.28
			highlight.Adornee = character
			highlight.Enabled = false
			highlight.Parent = character

			local screen = createScreenElements(ctx.createOverlayRoot(), player)

			local entry = {
				character = character,
				root = root,
				highlight = highlight,
				screen = screen,
				displayedHealth = 1,
				drawings = nil,
			}

			ctx.state.esp[player] = entry
			return entry
		end

		local function updateScreenOverlay(entry, player, bounds, visible, displayColor, opacity, fade, isTarget, targetColor, distance, humanoid)
			local screen = entry.screen
			if not screen or not screen.root or not humanoid then
				return
			end

			local showNametag = visible and flag("Universal ESP Nametag", true)
			local showSideHealth = visible and flag("Universal ESP Health", true)

			screen.root.Visible = visible
			if not visible then
				screen.nametag.Visible = false
				screen.sideHealthBg.Visible = false
				return
			end

			local maxHealth = math.max(1, humanoid.MaxHealth)
			local ratio = safeClamp(humanoid.Health / maxHealth, 0, 1)
			entry.displayedHealth += (ratio - entry.displayedHealth) * 0.28

			local topLeft = bounds.topLeft
			local bottomRight = bounds.bottomRight
			local width = math.max(0, bottomRight.X - topLeft.X)
			local height = math.max(0, bottomRight.Y - topLeft.Y)
			local anchor = bounds.topCenter

			if width < 2 or height < 2 then
				screen.nametag.Visible = false
				screen.sideHealthBg.Visible = false
				return
			end

			screen.nametag.Visible = showNametag
			screen.sideHealthBg.Visible = showSideHealth

			if showNametag then
				local nametagSize = numberFlag("Universal ESP Nametag Size", 13)
				local tagText = buildNametagText(player, distance)
				local _, lineCount = tagText:gsub("\n", "\n")
				screen.nametag.Position = UDim2.fromOffset(anchor.X, anchor.Y - 2)
				screen.nametag.Size = UDim2.fromOffset(200, 12 + (lineCount + 1) * nametagSize)
				screen.nametag.TextSize = nametagSize
				screen.nametag.TextTransparency = safeClamp(1 - opacity, 0, 1)
				screen.nametag.TextColor3 = isTarget and targetColor or Color3.fromRGB(245, 247, 255)
				screen.nametag.Text = tagText
			end

			if showSideHealth then
				local barHeight = safeClamp(height * 0.86, 4, height)
				local barWidth = 3
				local healthSide = ctx.library.flags["Universal ESP Health Side"] == "Right" and "Right" or "Left"
				local barX = healthSide == "Right" and (bottomRight.X + 6) or (topLeft.X - 6)
				local barY = topLeft.Y + (height - barHeight) * 0.5

				screen.sideHealthBg.Position = UDim2.fromOffset(barX, barY)
				screen.sideHealthBg.Size = UDim2.fromOffset(barWidth, barHeight)
				screen.sideHealthBg.BackgroundTransparency = safeClamp(0.08 + fade * 0.66, 0, 1)
				screen.sideHealthFill.Size = UDim2.new(1, 0, safeClamp(entry.displayedHealth, 0, 1), 0)
				screen.sideHealthFill.BackgroundColor3 = Color3.fromHSV(safeClamp(entry.displayedHealth, 0, 1) * 0.33, 0.78, 1)
				screen.sideHealthFill.BackgroundTransparency = safeClamp(1 - opacity, 0, 1)
			end
		end

		local function updateScreenEsp(entry, player, camera, bounds, displayColor, skeletonColor, opacity, fade, distance, humanoid, isTarget)
			local drawings = ensureDrawings(entry)
			local boxThickness = numberFlag("Universal ESP Box Thickness", 1.5)
			local lineThickness = numberFlag("Universal ESP Line Thickness", 1.5)
			local fillOpacity = numberFlag("Universal ESP Fill Opacity", 18) / 100
			local cornerLength = numberFlag("Universal ESP Corner Length", 24)
			local glowStrength = numberFlag("Universal ESP Glow Strength", 55) / 100
			local showBox = flag("Universal ESP Box", true)
			local showFill = flag("Universal ESP Box Fill", false)
			local showSkeleton = flag("Universal ESP Skeleton", false)
			local showTracer = flag("Universal ESP Tracer", false)
			local showHeadDot = flag("Universal ESP Head Dot", false)
			local showPulse = flag("Universal ESP Pulse", true)
			local boxStyle = getBoxStyle()
			local cornerStyle = boxStyle == "Corners" or boxStyle == "Double"

			local topLeft = bounds.topLeft
			local width = math.max(0, bounds.bottomRight.X - topLeft.X)
			local height = math.max(0, bounds.bottomRight.Y - topLeft.Y)

			if width < 2 or height < 2 then
				hideDrawing(drawings.glow)
				hideDrawing(drawings.box)
				hideDrawing(drawings.boxFill)
				hideDrawing(drawings.tracer)
				hideDrawing(drawings.headDot)
				for _, line in ipairs(drawings.corners) do
					hideDrawing(line)
				end
				for _, line in ipairs(drawings.skeleton) do
					hideDrawing(line)
				end
				return
			end

			local pulse = showPulse and (0.5 + math.abs(math.sin(os.clock() * (isTarget and 5 or 3))) * 0.5) or 1
			pulse = math.max(pulse, 0.01)
			local boxAlpha = safeClamp((0.08 + fade * 0.45) / pulse, 0.05, 0.92)

			if showPulse and drawings.glow and showBox and glowStrength > 0 then
				drawings.glow.Visible = true
				drawings.glow.Position = topLeft - Vector2.new(2, 2)
				drawings.glow.Size = Vector2.new(width + 4, height + 4)
				drawings.glow.Color = displayColor
				drawings.glow.Filled = true
				drawings.glow.Thickness = 0
				drawings.glow.Transparency = safeClamp(0.96 - glowStrength * pulse * 0.24, 0.72, 0.97)
			else
				hideDrawing(drawings.glow)
			end

			if cornerStyle then
				drawCornerBox(
					drawings,
					topLeft,
					width,
					height,
					displayColor,
					boxThickness * pulse,
					boxAlpha,
					showBox,
					cornerLength
				)
			end

			if boxStyle == "Full" or boxStyle == "Double" then
				if drawings.box then
					drawings.box.Visible = showBox
					drawings.box.Position = topLeft
					drawings.box.Size = Vector2.new(width, height)
					drawings.box.Color = displayColor
					drawings.box.Thickness = boxStyle == "Double" and boxThickness * 0.65 or boxThickness * pulse
					drawings.box.Filled = false
					drawings.box.Transparency = boxStyle == "Double" and safeClamp(boxAlpha + 0.18, 0.1, 0.95) or boxAlpha
				end
			elseif drawings.box then
				hideDrawing(drawings.box)
				if not cornerStyle then
					for _, line in ipairs(drawings.corners) do
						hideDrawing(line)
					end
				end
			end

			if not cornerStyle then
				for _, line in ipairs(drawings.corners) do
					hideDrawing(line)
				end
			end

			if drawings.boxFill then
				drawings.boxFill.Visible = showBox and showFill
				drawings.boxFill.Position = topLeft
				drawings.boxFill.Size = Vector2.new(width, height)
				drawings.boxFill.Color = displayColor
				drawings.boxFill.Filled = true
				drawings.boxFill.Thickness = 0
				drawings.boxFill.Transparency = safeClamp(1 - fillOpacity + fade * 0.2, 0.4, 0.96)
			end

			if drawings.tracer then
				local viewport = camera.ViewportSize
				local tracerFrom = ctx.library.flags["Universal ESP Tracer From"] or "Bottom"
				local origin
				if tracerFrom == "Center" then
					origin = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
				elseif tracerFrom == "Top" then
					origin = Vector2.new(viewport.X * 0.5, 0)
				else
					origin = Vector2.new(viewport.X * 0.5, viewport.Y)
				end

				drawings.tracer.Visible = showTracer
				drawings.tracer.From = origin
				drawings.tracer.To = bounds.bottomCenter
				drawings.tracer.Color = displayColor
				drawings.tracer.Thickness = lineThickness
				drawings.tracer.Transparency = safeClamp(0.2 + fade * 0.55, 0.2, 0.9)
			end

			if drawings.headDot then
				local head = entry.character:FindFirstChild("Head")
				if head and showHeadDot then
					local point, onScreen = camera:WorldToViewportPoint(head.Position + Vector3.new(0, head.Size.Y * 0.35, 0))
					if onScreen then
						drawings.headDot.Visible = true
						drawings.headDot.Position = Vector2.new(point.X, point.Y)
						drawings.headDot.Radius = safeClamp(3 + pulse, 3, 5)
						drawings.headDot.Color = displayColor
						drawings.headDot.Filled = true
						drawings.headDot.Transparency = safeClamp(1 - opacity, 0, 1)
					else
						hideDrawing(drawings.headDot)
					end
				else
					hideDrawing(drawings.headDot)
				end
			end

			local pairsList = getBonePairs(entry.character)
			for index, line in ipairs(drawings.skeleton) do
				local pair = pairsList[index]
				if not pair or not showSkeleton then
					hideDrawing(line)
				else
					local a = entry.character:FindFirstChild(pair[1])
					local b = entry.character:FindFirstChild(pair[2])
					if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
						local ap, aOn = camera:WorldToViewportPoint(a.Position)
						local bp, bOn = camera:WorldToViewportPoint(b.Position)
						if aOn and bOn then
							line.Visible = true
							line.From = Vector2.new(ap.X, ap.Y)
							line.To = Vector2.new(bp.X, bp.Y)
							line.Color = skeletonColor
							line.Thickness = lineThickness
							line.Transparency = safeClamp(0.12 + fade * 0.5, 0.12, 0.9)
						else
							hideDrawing(line)
						end
					else
						hideDrawing(line)
					end
				end
			end
		end

		local function hideEntryDrawings(entry)
			if entry.highlight then
				entry.highlight.Enabled = false
			end
			if entry.screen and entry.screen.root then
				entry.screen.root.Visible = false
			end
			if entry.drawings then
				for key, value in pairs(entry.drawings) do
					if type(value) == "table" then
						for _, item in ipairs(value) do
							hideDrawing(item)
						end
					else
						hideDrawing(value)
					end
				end
			end
		end

		local function render()
			if ctx.state.unloading then
				return
			end

			local camera = ctx.Workspace.CurrentCamera
			if not camera then
				return
			end

			local enabled = flag("Universal ESP", false)
			local localRoot = ctx.getRoot()
			local maxDistance = math.max(50, numberFlag("Universal ESP Max Distance", 650))
			local fadeStart = safeClamp(numberFlag("Universal ESP Fade Start", 250), 0, math.max(0, maxDistance - 1))
			local color = colorFlag("Universal ESP Color", Color3.fromRGB(0, 170, 255))
			local skeletonColor = colorFlag("Universal ESP Skeleton Color", Color3.fromRGB(0, 210, 255))

			for _, player in ipairs(ctx.Players:GetPlayers()) do
				if player ~= ctx.LocalPlayer then
					local character = player.Character
					local humanoid = ctx.getHumanoid(character)
					local root = ctx.getRoot(character)
					local entry = ctx.state.esp[player]

					if character and root and humanoid and humanoid.Health > 0 then
						if not entry or entry.character ~= character or entry.root ~= root then
							entry = createEntry(player, character)
						end
					elseif entry then
						destroyEntry(player)
						entry = nil
					end

					if entry then
						local distance = localRoot and (localRoot.Position - root.Position).Magnitude or math.huge
						local isTarget = ctx.state.aimTarget == player
						local targetSync = ctx.library.flags["Universal Targeting Sync ESP"] ~= false

						local espSameTeam = flag("Universal ESP Team Check", false)
							and ctx.LocalPlayer.Team ~= nil
							and player.Team == ctx.LocalPlayer.Team
						local targetingTeamCheck
						if targetSync then
							targetingTeamCheck = flag("Universal ESP Team Check", false)
						else
							targetingTeamCheck = flag("Universal Aim Team Check", true)
						end
						local targetSameTeam = targetingTeamCheck
							and ctx.LocalPlayer.Team ~= nil
							and player.Team == ctx.LocalPlayer.Team

						local targetMaxDistance = targetSync
							and maxDistance
							or math.max(50, numberFlag("Universal Aim Max Distance", 500))

						local visibleForESP = enabled and not espSameTeam and distance <= maxDistance
						local visibleForTarget = isTarget and not targetSameTeam and distance <= targetMaxDistance
						local visible = visibleForESP or visibleForTarget

						if not visible then
							hideEntryDrawings(entry)
						else
							local displayMaxDistance = isTarget and not enabled and targetMaxDistance or maxDistance
							local displayFadeStart = math.min(fadeStart, math.max(0, displayMaxDistance - 1))
							local fade = safeClamp(
								(distance - displayFadeStart) / math.max(1, displayMaxDistance - displayFadeStart),
								0,
								1
							)
							local opacity = 1 - (fade * (isTarget and 0.42 or 0.72))

							local configuredTargetColor = colorFlag("Universal Aim Color", Color3.fromRGB(255, 82, 96))
							local targetColor = targetSync and color or configuredTargetColor
							local displayColor = resolveDisplayColor(color, player, isTarget, targetColor)

							entry.highlight.Enabled = visibleForESP and flag("Universal ESP Highlights", false)
							entry.highlight.FillColor = displayColor
							entry.highlight.OutlineColor = displayColor
							entry.highlight.FillTransparency = 0.92 + fade * 0.06
							entry.highlight.OutlineTransparency = 0.28 + fade * 0.55

							local onScreen, bounds = getViewportBounds(camera, character)
							if onScreen then
								if hasDrawing then
									updateScreenEsp(entry, player, camera, bounds, displayColor, skeletonColor, opacity, fade, distance, humanoid, isTarget)
								end
								updateScreenOverlay(entry, player, bounds, true, displayColor, opacity, fade, isTarget, targetColor, distance, humanoid)
							else
								hideEntryDrawings(entry)
							end
						end
					end
				end
			end
		end

		local preview = {
			built = false,
			overlay = nil,
			box = nil,
			boxFill = nil,
			glow = nil,
			nametag = nil,
			healthBg = nil,
			healthFill = nil,
			corners = {},
			skeleton = {},
			headDot = nil,
			pulse = 0,
		}

		local function createPreviewCorner(parent, fromScale, toScale, color)
			local line = Instance.new("Frame")
			line.BackgroundColor3 = color
			line.BorderSizePixel = 0
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.Parent = parent
			return line, fromScale, toScale
		end

		local function buildPreview()
			local section = ctx.refs.espPreviewSection
			if not section or not section.content or preview.built then
				return
			end

			local host = Instance.new("Frame")
			host.Name = "ESPPreviewHost"
			host.BackgroundTransparency = 1
			host.Size = UDim2.new(1, -8, 0, 240)
			host.Parent = section.content

			local panel = Instance.new("Frame")
			panel.Size = UDim2.new(1, 0, 1, 0)
			panel.BackgroundColor3 = Color3.fromRGB(8, 11, 17)
			panel.BorderSizePixel = 0
			panel.Parent = host
			ctx.createRounded(panel, 8)

			local panelStroke = Instance.new("UIStroke")
			panelStroke.Color = Color3.fromRGB(0, 170, 255)
			panelStroke.Transparency = 0.45
			panelStroke.Parent = panel

			local viewport = Instance.new("ViewportFrame")
			viewport.Name = "CharacterViewport"
			viewport.Size = UDim2.new(1, -16, 1, -16)
			viewport.Position = UDim2.fromOffset(8, 8)
			viewport.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
			viewport.BorderSizePixel = 0
			viewport.Parent = panel
			ctx.createRounded(viewport, 6)

			local viewportStroke = Instance.new("UIStroke")
			viewportStroke.Color = Color3.fromRGB(0, 170, 255)
			viewportStroke.Transparency = 0.72
			viewportStroke.Parent = viewport

			local world = Instance.new("WorldModel")
			world.Parent = viewport

			local camera = Instance.new("Camera")
			camera.Parent = viewport
			viewport.CurrentCamera = camera

			local model = Instance.new("Model")
			model.Name = "PreviewRig"
			model.Parent = world

			local function block(name, size, position, color)
				local part = Instance.new("Part")
				part.Name = name
				part.Size = size
				part.CFrame = CFrame.new(position)
				part.Color = color
				part.Material = Enum.Material.SmoothPlastic
				part.Anchored = true
				part.CanCollide = false
				part.CastShadow = false
				part.Parent = model
				return part
			end

			local skin = Color3.fromRGB(234, 184, 146)
			local shirt = Color3.fromRGB(13, 105, 172)
			local pants = Color3.fromRGB(75, 151, 75)

			block("Head", Vector3.new(1.15, 1.15, 1.15), Vector3.new(0, 3.35, 0), skin)
			block("UpperTorso", Vector3.new(1.9, 1.85, 0.95), Vector3.new(0, 2.05, 0), shirt)
			block("LowerTorso", Vector3.new(1.75, 0.75, 0.9), Vector3.new(0, 0.95, 0), shirt)
			block("LeftUpperArm", Vector3.new(0.75, 1.55, 0.75), Vector3.new(-1.35, 2.15, 0), skin)
			block("LeftLowerArm", Vector3.new(0.65, 1.35, 0.65), Vector3.new(-1.35, 0.95, 0), skin)
			block("RightUpperArm", Vector3.new(0.75, 1.55, 0.75), Vector3.new(1.35, 2.15, 0), skin)
			block("RightLowerArm", Vector3.new(0.65, 1.35, 0.65), Vector3.new(1.35, 0.95, 0), skin)
			block("LeftUpperLeg", Vector3.new(0.85, 1.55, 0.85), Vector3.new(-0.45, -0.35, 0), pants)
			block("LeftLowerLeg", Vector3.new(0.8, 1.35, 0.8), Vector3.new(-0.45, -1.35, 0), pants)
			block("RightUpperLeg", Vector3.new(0.85, 1.55, 0.85), Vector3.new(0.45, -0.35, 0), pants)
			block("RightLowerLeg", Vector3.new(0.8, 1.35, 0.8), Vector3.new(0.45, -1.35, 0), pants)
			block("LeftFoot", Vector3.new(0.9, 0.45, 1.2), Vector3.new(-0.45, -1.35, 0.08), skin)
			block("RightFoot", Vector3.new(0.9, 0.45, 1.2), Vector3.new(0.45, -1.35, 0.08), skin)

			local face = Instance.new("Decal")
			face.Texture = "rbxasset://textures/face.png"
			face.Face = Enum.NormalId.Front
			face.Parent = model:FindFirstChild("Head")

			local light = Instance.new("PointLight")
			light.Brightness = 1.4
			light.Range = 14
			light.Color = Color3.fromRGB(255, 248, 240)
			light.Parent = model:FindFirstChild("UpperTorso")

			camera.CFrame = CFrame.new(Vector3.new(5.8, 2.8, 5.8), Vector3.new(0, 1.8, 0))

			preview.overlay = Instance.new("Frame")
			preview.overlay.Name = "PreviewOverlay"
			preview.overlay.BackgroundTransparency = 1
			preview.overlay.Size = UDim2.fromScale(1, 1)
			preview.overlay.Parent = viewport

			preview.glow = Instance.new("Frame")
			preview.glow.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
			preview.glow.BackgroundTransparency = 0.88
			preview.glow.BorderSizePixel = 0
			preview.glow.AnchorPoint = Vector2.new(0.5, 0.5)
			preview.glow.Position = UDim2.fromScale(0.5, 0.56)
			preview.glow.Size = UDim2.fromOffset(92, 150)
			preview.glow.ZIndex = 2
			preview.glow.Parent = preview.overlay
			ctx.createRounded(preview.glow, 4)

			preview.box = Instance.new("Frame")
			preview.box.BackgroundTransparency = 1
			preview.box.AnchorPoint = Vector2.new(0.5, 0.5)
			preview.box.Position = UDim2.fromScale(0.5, 0.56)
			preview.box.Size = UDim2.fromOffset(86, 144)
			preview.box.ZIndex = 3
			preview.box.Parent = preview.overlay

			local boxStroke = Instance.new("UIStroke")
			boxStroke.Thickness = 1.5
			boxStroke.Color = Color3.fromRGB(0, 170, 255)
			boxStroke.Parent = preview.box

			preview.boxFill = Instance.new("Frame")
			preview.boxFill.Size = UDim2.fromScale(1, 1)
			preview.boxFill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
			preview.boxFill.BackgroundTransparency = 0.9
			preview.boxFill.BorderSizePixel = 0
			preview.boxFill.ZIndex = 2
			preview.boxFill.Parent = preview.box
			ctx.createRounded(preview.boxFill, 4)

			for index = 1, 8 do
				local corner = Instance.new("Frame")
				corner.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
				corner.BorderSizePixel = 0
				corner.ZIndex = 4
				corner.Parent = preview.overlay
				preview.corners[index] = corner
			end

			preview.nametag = Instance.new("TextLabel")
			preview.nametag.BackgroundTransparency = 1
			preview.nametag.AnchorPoint = Vector2.new(0.5, 1)
			preview.nametag.Position = UDim2.fromScale(0.5, 0.245)
			preview.nametag.Size = UDim2.fromOffset(160, 28)
			preview.nametag.Font = Enum.Font.GothamMedium
			preview.nametag.TextSize = 12
			preview.nametag.Text = "Player  [64m]"
			preview.nametag.TextColor3 = Color3.fromRGB(245, 247, 255)
			preview.nametag.ZIndex = 5
			preview.nametag.Parent = preview.overlay

			preview.healthBg = Instance.new("Frame")
			preview.healthBg.BackgroundColor3 = Color3.fromRGB(28, 33, 43)
			preview.healthBg.BorderSizePixel = 0
			preview.healthBg.AnchorPoint = Vector2.new(1, 0.5)
			preview.healthBg.Position = UDim2.fromScale(0.31, 0.56)
			preview.healthBg.Size = UDim2.fromOffset(3, 124)
			preview.healthBg.ZIndex = 4
			preview.healthBg.Parent = preview.overlay
			ctx.createRounded(preview.healthBg, 2)

			preview.healthFill = Instance.new("Frame")
			preview.healthFill.AnchorPoint = Vector2.new(0, 1)
			preview.healthFill.Position = UDim2.fromScale(0, 1)
			preview.healthFill.BackgroundColor3 = Color3.fromRGB(80, 225, 115)
			preview.healthFill.BorderSizePixel = 0
			preview.healthFill.Size = UDim2.new(1, 0, 0.72, 0)
			preview.healthFill.ZIndex = 5
			preview.healthFill.Parent = preview.healthBg
			ctx.createRounded(preview.healthFill, 2)

			preview.headDot = Instance.new("Frame")
			preview.headDot.AnchorPoint = Vector2.new(0.5, 0.5)
			preview.headDot.Position = UDim2.fromScale(0.5, 0.245)
			preview.headDot.Size = UDim2.fromOffset(6, 6)
			preview.headDot.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
			preview.headDot.BorderSizePixel = 0
			preview.headDot.ZIndex = 5
			preview.headDot.Parent = preview.overlay
			ctx.createRounded(preview.headDot, 999)

			local skeletonPairs = {
				{UDim2.fromScale(0.5, 0.28), UDim2.fromScale(0.5, 0.42)},
				{UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.5, 0.56)},
				{UDim2.fromScale(0.5, 0.40), UDim2.fromScale(0.34, 0.48)},
				{UDim2.fromScale(0.5, 0.40), UDim2.fromScale(0.66, 0.48)},
				{UDim2.fromScale(0.34, 0.48), UDim2.fromScale(0.28, 0.66)},
				{UDim2.fromScale(0.66, 0.48), UDim2.fromScale(0.72, 0.66)},
				{UDim2.fromScale(0.46, 0.56), UDim2.fromScale(0.44, 0.78)},
				{UDim2.fromScale(0.54, 0.56), UDim2.fromScale(0.56, 0.78)},
			}

			for index, pair in ipairs(skeletonPairs) do
				local line = Instance.new("Frame")
				line.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
				line.BorderSizePixel = 0
				line.AnchorPoint = Vector2.new(0.5, 0.5)
				line.ZIndex = 4
				line.Parent = preview.overlay
				preview.skeleton[index] = {line = line, from = pair[1], to = pair[2]}
			end

			preview.built = true
		end

		local function layoutPreviewCorner(corner, boxPos, boxSize, cornerIndex, color, thickness)
			local x, y = boxPos.X.Offset, boxPos.Y.Offset
			local w, h = boxSize.X.Offset, boxSize.Y.Offset
			local len = safeClamp(math.min(w, h) * (numberFlag("Universal ESP Corner Length", 24) / 100), 6, 18)
			local segments = {
				{x, y, x + len, y, 0},
				{x, y, x, y + len, 90},
				{x + w, y, x + w - len, y, 0},
				{x + w, y, x + w, y + len, 90},
				{x, y + h, x + len, y + h, 0},
				{x, y + h, x, y + h - len, 90},
				{x + w, y + h, x + w - len, y + h, 0},
				{x + w, y + h, x + w, y + h - len, 90},
			}
			local seg = segments[cornerIndex]
			if not seg then
				corner.Visible = false
				return
			end
			corner.Visible = true
			corner.BackgroundColor3 = color
			corner.Size = seg[5] == 0 and UDim2.fromOffset(len, thickness) or UDim2.fromOffset(thickness, len)
			corner.Position = UDim2.fromOffset(seg[5] == 0 and (seg[1] + seg[3]) * 0.5 or seg[1], seg[5] == 90 and (seg[2] + seg[4]) * 0.5 or seg[2])
		end

		local function updatePreview()
			if not preview.built then
				return
			end

			preview.pulse = 0.5 + math.abs(math.sin(os.clock() * 3)) * 0.5

			local color = colorFlag("Universal ESP Color", Color3.fromRGB(0, 170, 255))
			local skeletonColor = colorFlag("Universal ESP Skeleton Color", Color3.fromRGB(0, 210, 255))
			local showBox = flag("Universal ESP Box", true)
			local showFill = flag("Universal ESP Box Fill", false)
			local showSkeleton = flag("Universal ESP Skeleton", false)
			local showNametag = flag("Universal ESP Nametag", true)
			local showHealth = flag("Universal ESP Health", true)
			local showHeadDot = flag("Universal ESP Head Dot", false)
			local showPulse = flag("Universal ESP Pulse", true)
			local boxStyle = getBoxStyle()
			local cornerStyle = boxStyle == "Corners" or boxStyle == "Double"
			local fillOpacity = numberFlag("Universal ESP Fill Opacity", 18) / 100
			local glowStrength = numberFlag("Universal ESP Glow Strength", 55) / 100
			local chroma = flag("Universal ESP Chroma", false)

			local previewColor = color
			if chroma then
				previewColor = Color3.fromHSV((os.clock() * 0.14) % 1, 0.82, 1)
			end

			preview.box.Visible = showBox and boxStyle == "Full"
			preview.boxFill.Visible = showBox and showFill
			preview.nametag.Visible = showNametag
			preview.healthBg.Visible = showHealth
			preview.healthFill.Visible = showHealth
			preview.glow.Visible = showBox and showPulse and glowStrength > 0
			preview.headDot.Visible = showHeadDot

			local boxStroke = preview.box:FindFirstChildOfClass("UIStroke")
			if boxStroke then
				boxStroke.Color = previewColor
			end

			preview.boxFill.BackgroundColor3 = previewColor
			preview.boxFill.BackgroundTransparency = safeClamp(1 - fillOpacity, 0, 1)
			preview.glow.BackgroundColor3 = previewColor
			preview.glow.BackgroundTransparency = safeClamp(0.96 - glowStrength * preview.pulse * 0.24, 0.72, 0.97)
			preview.headDot.BackgroundColor3 = previewColor

			for index, corner in ipairs(preview.corners) do
				corner.Visible = showBox and cornerStyle
				if corner.Visible then
					layoutPreviewCorner(corner, preview.box.Position, preview.box.Size, index, previewColor, 2)
				end
			end

			if showBox and boxStyle == "Double" then
				preview.box.Visible = true
				if boxStroke then
					boxStroke.Transparency = 0.45
				end
			end

			local previewName = "Player"
			if flag("Universal ESP Show Username", false) then
				previewName = "Player\n@player"
			end
			if flag("Universal ESP Distance", true) then
				preview.nametag.Text = previewName .. "  [64m]"
			else
				preview.nametag.Text = previewName
			end
			preview.nametag.TextSize = numberFlag("Universal ESP Nametag Size", 13)

			for _, item in ipairs(preview.skeleton) do
				local line = item.line
				line.Visible = showSkeleton
				line.BackgroundColor3 = skeletonColor
				local from = item.from
				local to = item.to
				local viewport = preview.overlay.AbsoluteSize
				if viewport.X > 0 and viewport.Y > 0 then
					local fromPoint = Vector2.new(from.X.Scale * viewport.X + from.X.Offset, from.Y.Scale * viewport.Y + from.Y.Offset)
					local toPoint = Vector2.new(to.X.Scale * viewport.X + to.X.Offset, to.Y.Scale * viewport.Y + to.Y.Offset)
					local delta = toPoint - fromPoint
					line.Position = UDim2.fromOffset((fromPoint.X + toPoint.X) * 0.5, (fromPoint.Y + toPoint.Y) * 0.5)
					line.Size = UDim2.fromOffset(math.max(delta.Magnitude, 1), 1)
					line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
				end
			end
		end

		renderConnection = ctx.addConnection(ctx.RunService.RenderStepped, function()
			render()
		end)

		playerRemovingConnection = ctx.addConnection(ctx.Players.PlayerRemoving, destroyEntry)

		previewConnection = ctx.addConnection(ctx.RunService.Heartbeat, function()
			if not preview.built then
				buildPreview()
			end
			updatePreview()
		end)

		local control = ctx.option("Universal ESP")
		if control then
			control.callback = function(enabled)
				if not enabled then
					for _, entry in pairs(ctx.state.esp) do
						hideEntryDrawings(entry)
					end
				end
			end
		end

		ctx.library:AddCleanup(function()
			ctx.disconnect(renderConnection)
			ctx.disconnect(playerRemovingConnection)
			ctx.disconnect(previewConnection)

			if preview.overlay and preview.overlay.Parent then
				pcall(function()
					preview.overlay.Parent.Parent.Parent:Destroy()
				end)
			end

			for player in pairs(ctx.state.esp) do
				destroyEntry(player)
			end
		end)
	end

	return { setup = setupESPRuntime }
end
