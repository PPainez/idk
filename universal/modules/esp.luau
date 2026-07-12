--[[
    xanhub | universal | modules | esp

    Player ESP with box, skeleton, nametag, optional info card, and menu preview.
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
	"Head",
	"UpperTorso",
	"LowerTorso",
	"Torso",
	"LeftUpperArm",
	"RightUpperArm",
	"LeftLowerArm",
	"RightLowerArm",
	"LeftHand",
	"RightHand",
	"LeftUpperLeg",
	"RightUpperLeg",
	"LeftLowerLeg",
	"RightLowerLeg",
	"LeftFoot",
	"RightFoot",
	"Left Arm",
	"Right Arm",
	"Left Leg",
	"Right Leg",
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

return function(ctx)
	local espSection = ctx.columns.visualsLeft:AddSection("Player ESP")
	espSection:AddToggle({text = "Enabled", flag = "Universal ESP", state = false})
	espSection:AddToggle({text = "Box ESP", flag = "Universal ESP Box", state = true})
	espSection:AddToggle({text = "Filled Box", flag = "Universal ESP Box Fill", state = false})
	espSection:AddToggle({text = "Skeleton ESP", flag = "Universal ESP Skeleton", state = false})
	espSection:AddToggle({text = "Nametag", flag = "Universal ESP Nametag", state = true})
	espSection:AddToggle({text = "Tracer Line", flag = "Universal ESP Tracer", state = false})
	espSection:AddToggle({text = "Info Card (Top Bar)", flag = "Universal ESP Info Card", state = false})
	espSection:AddToggle({text = "Highlights", flag = "Universal ESP Highlights", state = false})
	espSection:AddDivider("Info Card Details")
	espSection:AddToggle({text = "Card Names", flag = "Universal ESP Names", state = true})
	espSection:AddToggle({text = "Card Health Bar", flag = "Universal ESP Health", state = true})
	espSection:AddToggle({text = "Card Distance", flag = "Universal ESP Distance", state = true})
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

	local previewSection = ctx.columns.visualsRight:AddSection("ESP Preview")
	previewSection:AddLabel("Live style preview")
	previewSection:AddLabel("Info card replaces nametag above the box")
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

		local function getViewportBounds(camera, character)
			local minX, minY = math.huge, math.huge
			local maxX, maxY = -math.huge, -math.huge
			local bestDepth = math.huge
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
									bestDepth = math.min(bestDepth, point.Z)
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
				depth = bestDepth,
			}
		end

		local function ensureDrawings(entry)
			entry.drawings = entry.drawings or {}
			local drawings = entry.drawings

			if not drawings.box then
				drawings.box = newDrawing("Square")
				drawings.boxFill = newDrawing("Square")
				drawings.nametag = newDrawing("Text")
				drawings.tracer = newDrawing("Line")
				drawings.healthBg = newDrawing("Line")
				drawings.healthFill = newDrawing("Line")
				drawings.skeleton = {}
			end

			local needed = #getBonePairs(entry.character)
			while #drawings.skeleton < needed do
				table.insert(drawings.skeleton, newDrawing("Line"))
			end

			return drawings
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
			nametag.Size = UDim2.fromOffset(180, 16)
			nametag.AnchorPoint = Vector2.new(0.5, 1)
			nametag.Font = Enum.Font.GothamMedium
			nametag.TextSize = 13
			nametag.TextColor3 = Color3.fromRGB(245, 247, 255)
			nametag.TextStrokeTransparency = 0.35
			nametag.TextTruncate = Enum.TextTruncate.AtEnd
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

			local card = Instance.new("Frame")
			card.Name = "InfoCard"
			card.AnchorPoint = Vector2.new(0.5, 1)
			card.Size = UDim2.fromOffset(150, 34)
			card.BackgroundColor3 = Color3.fromRGB(8, 11, 17)
			card.BackgroundTransparency = 0.18
			card.BorderSizePixel = 0
			card.ClipsDescendants = true
			card.Visible = false
			card.ZIndex = 514
			card.Parent = root
			ctx.createRounded(card, 6)

			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = Color3.fromRGB(0, 170, 255)
			cardStroke.Transparency = 0.28
			cardStroke.Parent = card

			local accent = Instance.new("Frame")
			accent.Size = UDim2.new(0, 2, 1, 0)
			accent.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
			accent.BorderSizePixel = 0
			accent.Parent = card

			local targetMarker = Instance.new("Frame")
			targetMarker.Position = UDim2.fromOffset(8, 8)
			targetMarker.Size = UDim2.fromOffset(6, 6)
			targetMarker.BackgroundColor3 = Color3.fromRGB(255, 82, 96)
			targetMarker.BackgroundTransparency = 1
			targetMarker.BorderSizePixel = 0
			targetMarker.Visible = false
			targetMarker.Parent = card
			ctx.createRounded(targetMarker, 999)

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Position = UDim2.fromOffset(18, 3)
			nameLabel.Size = UDim2.new(1, -62, 0, 15)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = getPlayerLabel(player)
			nameLabel.TextColor3 = Color3.fromRGB(245, 247, 255)
			nameLabel.TextSize = 12
			nameLabel.Font = Enum.Font.GothamMedium
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = card

			local distanceLabel = Instance.new("TextLabel")
			distanceLabel.AnchorPoint = Vector2.new(1, 0)
			distanceLabel.Position = UDim2.new(1, -7, 0, 3)
			distanceLabel.Size = UDim2.fromOffset(42, 15)
			distanceLabel.BackgroundTransparency = 1
			distanceLabel.Text = "0m"
			distanceLabel.TextColor3 = Color3.fromRGB(160, 170, 190)
			distanceLabel.TextSize = 10
			distanceLabel.Font = Enum.Font.GothamMedium
			distanceLabel.TextXAlignment = Enum.TextXAlignment.Right
			distanceLabel.Parent = card

			local barBackground = Instance.new("Frame")
			barBackground.Position = UDim2.fromOffset(8, 25)
			barBackground.Size = UDim2.new(1, -16, 0, 3)
			barBackground.BackgroundColor3 = Color3.fromRGB(28, 33, 43)
			barBackground.BorderSizePixel = 0
			barBackground.Parent = card
			ctx.createRounded(barBackground, 2)

			local healthFill = Instance.new("Frame")
			healthFill.Size = UDim2.fromScale(1, 1)
			healthFill.BackgroundColor3 = Color3.fromRGB(80, 225, 115)
			healthFill.BorderSizePixel = 0
			healthFill.Parent = barBackground
			ctx.createRounded(healthFill, 2)

			return {
				root = root,
				nametag = nametag,
				card = card,
				cardStroke = cardStroke,
				accent = accent,
				targetMarker = targetMarker,
				name = nameLabel,
				distance = distanceLabel,
				healthBackground = barBackground,
				health = healthFill,
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

			local overlayRoot = ctx.createOverlayRoot()
			local screen = createScreenElements(overlayRoot, player)

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
			if not screen or not screen.root then
				return
			end

			local showInfoCard = visible and flag("Universal ESP Info Card", false)
			local showNametag = visible and flag("Universal ESP Nametag", true) and not showInfoCard
			local showSideHealth = visible
				and flag("Universal ESP Health", true)
				and not showInfoCard

			screen.root.Visible = visible
			if not visible then
				screen.nametag.Visible = false
				screen.card.Visible = false
				screen.sideHealthBg.Visible = false
				return
			end

			local label = getPlayerLabel(player)
			local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
			entry.displayedHealth += (ratio - entry.displayedHealth) * 0.28

			local topLeft = bounds.topLeft
			local bottomRight = bounds.bottomRight
			local width = bottomRight.X - topLeft.X
			local height = bottomRight.Y - topLeft.Y
			local anchor = bounds.topCenter

			screen.nametag.Visible = showNametag
			screen.card.Visible = showInfoCard
			screen.sideHealthBg.Visible = showSideHealth

			if showNametag then
				local nametagSize = numberFlag("Universal ESP Nametag Size", 13)
				screen.nametag.Position = UDim2.fromOffset(anchor.X, anchor.Y - 2)
				screen.nametag.TextSize = nametagSize
				screen.nametag.TextTransparency = 1 - opacity
				screen.nametag.TextColor3 = isTarget and targetColor or Color3.fromRGB(245, 247, 255)
				if flag("Universal ESP Distance", true) then
					screen.nametag.Text = string.format("%s  [%dm]", label, math.floor(distance + 0.5))
				else
					screen.nametag.Text = label
				end
			end

			if showSideHealth then
				local barHeight = math.clamp(height * 0.84, 28, height)
				local barWidth = 3
				local barX = topLeft.X - 6
				local barY = topLeft.Y + (height - barHeight) * 0.5

				screen.sideHealthBg.Position = UDim2.fromOffset(barX, barY)
				screen.sideHealthBg.Size = UDim2.fromOffset(barWidth, barHeight)
				screen.sideHealthBg.BackgroundTransparency = 0.08 + fade * 0.66
				screen.sideHealthFill.Size = UDim2.new(1, 0, entry.displayedHealth, 0)
				screen.sideHealthFill.BackgroundColor3 = Color3.fromHSV(entry.displayedHealth * 0.33, 0.78, 1)
				screen.sideHealthFill.BackgroundTransparency = 1 - opacity
			end

			if showInfoCard then
				screen.card.Position = UDim2.fromOffset(anchor.X, anchor.Y - 2)
				screen.cardStroke.Color = displayColor
				screen.cardStroke.Thickness = isTarget and 2 or 1
				screen.cardStroke.Transparency = isTarget and 0.08 or (0.28 + fade * 0.52)
				screen.accent.BackgroundColor3 = displayColor
				screen.accent.Size = UDim2.new(0, isTarget and 4 or 2, 1, 0)
				screen.accent.BackgroundTransparency = isTarget and 0 or (1 - opacity)
				screen.card.BackgroundTransparency = isTarget and 0.06 or (0.18 + fade * 0.58)
				screen.name.TextTransparency = isTarget and 0 or (1 - opacity)
				screen.name.TextColor3 = isTarget and targetColor or Color3.fromRGB(245, 247, 255)
				screen.distance.TextTransparency = 1 - opacity
				screen.healthBackground.BackgroundTransparency = 0.08 + fade * 0.66
				screen.health.BackgroundTransparency = 1 - opacity
				screen.targetMarker.Visible = isTarget
				screen.targetMarker.BackgroundColor3 = targetColor
				screen.targetMarker.BackgroundTransparency = isTarget
					and (0.08 + math.abs(math.sin(os.clock() * 5)) * 0.28)
					or 1
				screen.name.Text = label
				screen.name.Visible = isTarget or flag("Universal ESP Names", true)
				screen.distance.Visible = flag("Universal ESP Distance", true)
				screen.healthBackground.Visible = flag("Universal ESP Health", true)
				screen.distance.Text = tostring(math.floor(distance + 0.5)) .. "m"
				screen.health.Size = UDim2.new(entry.displayedHealth, 0, 1, 0)
				screen.health.BackgroundColor3 = Color3.fromHSV(entry.displayedHealth * 0.33, 0.78, 1)
			end
		end

		local function updateScreenEsp(entry, player, camera, bounds, displayColor, skeletonColor, opacity, fade, distance, humanoid, isTarget)
			local drawings = ensureDrawings(entry)
			local boxThickness = numberFlag("Universal ESP Box Thickness", 1.5)
			local lineThickness = numberFlag("Universal ESP Line Thickness", 1.5)
			local showBox = flag("Universal ESP Box", true)
			local showFill = flag("Universal ESP Box Fill", false)
			local showSkeleton = flag("Universal ESP Skeleton", false)
			local showTracer = flag("Universal ESP Tracer", false)

			local topLeft = bounds.topLeft
			local bottomRight = bounds.bottomRight
			local width = bottomRight.X - topLeft.X
			local height = bottomRight.Y - topLeft.Y

			if drawings.box then
				drawings.box.Visible = showBox
				drawings.box.Position = topLeft
				drawings.box.Size = Vector2.new(width, height)
				drawings.box.Color = displayColor
				drawings.box.Thickness = boxThickness
				drawings.box.Filled = false
				drawings.box.Transparency = math.clamp(0.08 + fade * 0.45, 0.08, 0.9)
			end

			if drawings.boxFill then
				drawings.boxFill.Visible = showBox and showFill
				drawings.boxFill.Position = topLeft
				drawings.boxFill.Size = Vector2.new(width, height)
				drawings.boxFill.Color = displayColor
				drawings.boxFill.Filled = true
				drawings.boxFill.Thickness = 0
				drawings.boxFill.Transparency = math.clamp(0.82 + fade * 0.12, 0.82, 0.96)
			end

			if drawings.tracer then
				local viewport = camera.ViewportSize
				drawings.tracer.Visible = showTracer
				drawings.tracer.From = Vector2.new(viewport.X * 0.5, viewport.Y)
				drawings.tracer.To = bounds.bottomCenter
				drawings.tracer.Color = displayColor
				drawings.tracer.Thickness = lineThickness
				drawings.tracer.Transparency = math.clamp(0.2 + fade * 0.55, 0.2, 0.9)
			end

			hideDrawing(drawings.nametag)
			hideDrawing(drawings.healthBg)
			hideDrawing(drawings.healthFill)

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
							line.Transparency = math.clamp(0.12 + fade * 0.5, 0.12, 0.9)
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

		local function shouldShowPlayer(player, distance, enabled, isTarget, espSameTeam, targetSameTeam, maxDistance, targetMaxDistance)
			local visibleForESP = enabled and not espSameTeam and distance <= maxDistance
			local visibleForTarget = isTarget and not targetSameTeam and distance <= targetMaxDistance
			return visibleForESP or visibleForTarget, visibleForESP
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
			local fadeStart = math.clamp(numberFlag("Universal ESP Fade Start", 250), 0, maxDistance - 1)
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
						local targetingEnabled = flag("Universal Aim Preview", false)
						local isTarget = targetingEnabled and ctx.state.aimTarget == player
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

						local visible, visibleForESP = shouldShowPlayer(
							player,
							distance,
							enabled,
							isTarget,
							espSameTeam,
							targetSameTeam,
							maxDistance,
							targetMaxDistance
						)

						if not visible then
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
						else
							local displayMaxDistance = isTarget and not enabled and targetMaxDistance or maxDistance
							local displayFadeStart = math.min(fadeStart, displayMaxDistance - 1)
							local fade = math.clamp(
								(distance - displayFadeStart) / math.max(1, displayMaxDistance - displayFadeStart),
								0,
								1
							)
							local opacity = 1 - (fade * (isTarget and 0.42 or 0.72))

							local configuredTargetColor = colorFlag("Universal Aim Color", Color3.fromRGB(255, 82, 96))
							local targetColor = targetSync and color or configuredTargetColor
							local displayColor = isTarget and targetColor or color

							entry.highlight.Enabled = visibleForESP and flag("Universal ESP Highlights", false)
							entry.highlight.FillColor = displayColor
							entry.highlight.OutlineColor = displayColor
							entry.highlight.FillTransparency = 0.92 + fade * 0.06
							entry.highlight.OutlineTransparency = 0.28 + fade * 0.55

							local onScreen, bounds = getViewportBounds(camera, character)
							if onScreen then
								if hasDrawing then
									updateScreenEsp(
										entry,
										player,
										camera,
										bounds,
										displayColor,
										skeletonColor,
										opacity,
										fade,
										distance,
										humanoid,
										isTarget
									)
								end

								updateScreenOverlay(
									entry,
									player,
									bounds,
									true,
									displayColor,
									opacity,
									fade,
									isTarget,
									targetColor,
									distance,
									humanoid
								)
							else
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
						end
					end
				end
			end
		end

		local preview = {
			root = nil,
			box = nil,
			boxFill = nil,
			nametag = nil,
			infoCard = nil,
			cardName = nil,
			cardDistance = nil,
			cardHealthBg = nil,
			cardHealthFill = nil,
			healthBg = nil,
			healthFill = nil,
			skeleton = {},
			silhouette = {},
		}

		local function createPreviewLine(parent, color, thickness)
			local line = Instance.new("Frame")
			line.BackgroundColor3 = color
			line.BorderSizePixel = 0
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.Size = UDim2.fromOffset(0, thickness)
			line.Parent = parent
			return line
		end

		local function buildPreview()
			local section = ctx.refs.espPreviewSection
			if not section or not section.content or preview.root then
				return
			end

			local host = Instance.new("Frame")
			host.Name = "ESPPreviewHost"
			host.BackgroundTransparency = 1
			host.Size = UDim2.new(1, -8, 0, 220)
			host.Parent = section.content

			local panel = Instance.new("Frame")
			panel.Name = "ESPPreviewPanel"
			panel.Size = UDim2.new(1, 0, 1, 0)
			panel.BackgroundColor3 = Color3.fromRGB(8, 11, 17)
			panel.BorderSizePixel = 0
			panel.Parent = host
			ctx.createRounded(panel, 8)

			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(0, 170, 255)
			stroke.Transparency = 0.45
			stroke.Parent = panel

			local stage = Instance.new("Frame")
			stage.Name = "Stage"
			stage.AnchorPoint = Vector2.new(0.5, 0.5)
			stage.Position = UDim2.fromScale(0.5, 0.56)
			stage.Size = UDim2.fromOffset(88, 150)
			stage.BackgroundTransparency = 1
			stage.Parent = panel

			local function part(name, size, position, round)
				local frame = Instance.new("Frame")
				frame.Name = name
				frame.Size = size
				frame.Position = position
				frame.BackgroundColor3 = Color3.fromRGB(24, 30, 42)
				frame.BackgroundTransparency = 0.08
				frame.BorderSizePixel = 0
				frame.Parent = stage
				ctx.createRounded(frame, round or 4)
				table.insert(preview.silhouette, frame)
				return frame
			end

			part("Head", UDim2.fromOffset(24, 24), UDim2.fromOffset(32, 0), 999)
			part("Torso", UDim2.fromOffset(34, 48), UDim2.fromOffset(27, 28), 6)
			part("LeftArm", UDim2.fromOffset(12, 40), UDim2.fromOffset(12, 32), 4)
			part("RightArm", UDim2.fromOffset(12, 40), UDim2.fromOffset(64, 32), 4)
			part("LeftLeg", UDim2.fromOffset(14, 48), UDim2.fromOffset(30, 78), 4)
			part("RightLeg", UDim2.fromOffset(14, 48), UDim2.fromOffset(44, 78), 4)

			preview.root = stage
			preview.box = Instance.new("Frame")
			preview.box.Name = "PreviewBox"
			preview.box.BackgroundTransparency = 1
			preview.box.Size = UDim2.fromOffset(74, 132)
			preview.box.Position = UDim2.fromOffset(7, -6)
			preview.box.Parent = stage

			local boxStroke = Instance.new("UIStroke")
			boxStroke.Thickness = 1.5
			boxStroke.Color = Color3.fromRGB(0, 170, 255)
			boxStroke.Parent = preview.box

			preview.boxFill = Instance.new("Frame")
			preview.boxFill.Size = UDim2.fromScale(1, 1)
			preview.boxFill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
			preview.boxFill.BackgroundTransparency = 0.9
			preview.boxFill.BorderSizePixel = 0
			preview.boxFill.Parent = preview.box
			ctx.createRounded(preview.boxFill, 4)

			preview.nametag = Instance.new("TextLabel")
			preview.nametag.BackgroundTransparency = 1
			preview.nametag.Size = UDim2.new(1, 0, 0, 14)
			preview.nametag.AnchorPoint = Vector2.new(0.5, 1)
			preview.nametag.Position = UDim2.new(0.5, 0, 0, -2)
			preview.nametag.Font = Enum.Font.GothamMedium
			preview.nametag.TextSize = 12
			preview.nametag.Text = "Preview"
			preview.nametag.TextColor3 = Color3.fromRGB(245, 247, 255)
			preview.nametag.Parent = preview.box

			preview.infoCard = Instance.new("Frame")
			preview.infoCard.AnchorPoint = Vector2.new(0.5, 1)
			preview.infoCard.Position = UDim2.new(0.5, 0, 0, -2)
			preview.infoCard.Size = UDim2.fromOffset(118, 30)
			preview.infoCard.BackgroundColor3 = Color3.fromRGB(8, 11, 17)
			preview.infoCard.BackgroundTransparency = 0.18
			preview.infoCard.BorderSizePixel = 0
			preview.infoCard.Visible = false
			preview.infoCard.Parent = preview.box
			ctx.createRounded(preview.infoCard, 6)

			local previewCardStroke = Instance.new("UIStroke")
			previewCardStroke.Color = Color3.fromRGB(0, 170, 255)
			previewCardStroke.Transparency = 0.28
			previewCardStroke.Parent = preview.infoCard

			preview.cardName = Instance.new("TextLabel")
			preview.cardName.BackgroundTransparency = 1
			preview.cardName.Position = UDim2.fromOffset(8, 2)
			preview.cardName.Size = UDim2.new(1, -36, 0, 14)
			preview.cardName.Font = Enum.Font.GothamMedium
			preview.cardName.TextSize = 11
			preview.cardName.Text = "Preview"
			preview.cardName.TextColor3 = Color3.fromRGB(245, 247, 255)
			preview.cardName.TextXAlignment = Enum.TextXAlignment.Left
			preview.cardName.Parent = preview.infoCard

			preview.cardDistance = Instance.new("TextLabel")
			preview.cardDistance.BackgroundTransparency = 1
			preview.cardDistance.AnchorPoint = Vector2.new(1, 0)
			preview.cardDistance.Position = UDim2.new(1, -6, 0, 2)
			preview.cardDistance.Size = UDim2.fromOffset(28, 14)
			preview.cardDistance.Font = Enum.Font.GothamMedium
			preview.cardDistance.TextSize = 10
			preview.cardDistance.Text = "64m"
			preview.cardDistance.TextColor3 = Color3.fromRGB(160, 170, 190)
			preview.cardDistance.TextXAlignment = Enum.TextXAlignment.Right
			preview.cardDistance.Parent = preview.infoCard

			preview.cardHealthBg = Instance.new("Frame")
			preview.cardHealthBg.Position = UDim2.fromOffset(8, 22)
			preview.cardHealthBg.Size = UDim2.new(1, -16, 0, 3)
			preview.cardHealthBg.BackgroundColor3 = Color3.fromRGB(28, 33, 43)
			preview.cardHealthBg.BorderSizePixel = 0
			preview.cardHealthBg.Parent = preview.infoCard
			ctx.createRounded(preview.cardHealthBg, 2)

			preview.cardHealthFill = Instance.new("Frame")
			preview.cardHealthFill.Size = UDim2.new(0.72, 0, 1, 0)
			preview.cardHealthFill.BackgroundColor3 = Color3.fromRGB(80, 225, 115)
			preview.cardHealthFill.BorderSizePixel = 0
			preview.cardHealthFill.Parent = preview.cardHealthBg
			ctx.createRounded(preview.cardHealthFill, 2)

			preview.healthBg = Instance.new("Frame")
			preview.healthBg.BackgroundColor3 = Color3.fromRGB(28, 33, 43)
			preview.healthBg.BorderSizePixel = 0
			preview.healthBg.AnchorPoint = Vector2.new(1, 0.5)
			preview.healthBg.Position = UDim2.new(0, -4, 0.5, 0)
			preview.healthBg.Size = UDim2.fromOffset(3, 112)
			preview.healthBg.Parent = preview.box
			ctx.createRounded(preview.healthBg, 2)

			preview.healthFill = Instance.new("Frame")
			preview.healthFill.AnchorPoint = Vector2.new(0, 1)
			preview.healthFill.Position = UDim2.fromScale(0, 1)
			preview.healthFill.BackgroundColor3 = Color3.fromRGB(80, 225, 115)
			preview.healthFill.BorderSizePixel = 0
			preview.healthFill.Size = UDim2.new(1, 0, 0.72, 0)
			preview.healthFill.Parent = preview.healthBg
			ctx.createRounded(preview.healthFill, 2)

			local skeletonPairs = {
				{Vector2.new(44, 12), Vector2.new(44, 40)},
				{Vector2.new(44, 40), Vector2.new(44, 72)},
				{Vector2.new(44, 34), Vector2.new(18, 52)},
				{Vector2.new(44, 34), Vector2.new(70, 52)},
				{Vector2.new(18, 52), Vector2.new(18, 84)},
				{Vector2.new(70, 52), Vector2.new(70, 84)},
				{Vector2.new(37, 72), Vector2.new(37, 118)},
				{Vector2.new(51, 72), Vector2.new(51, 118)},
			}

			for index, pair in ipairs(skeletonPairs) do
				local line = createPreviewLine(stage, Color3.fromRGB(0, 210, 255), 1)
				local delta = pair[2] - pair[1]
				local length = delta.Magnitude
				local midpoint = pair[1] + delta / 2
				line.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
				line.Size = UDim2.fromOffset(length, 1)
				line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
				preview.skeleton[index] = line
			end
		end

		local function updatePreview()
			if not preview.root then
				return
			end

			local color = colorFlag("Universal ESP Color", Color3.fromRGB(0, 170, 255))
			local skeletonColor = colorFlag("Universal ESP Skeleton Color", Color3.fromRGB(0, 210, 255))
			local showBox = flag("Universal ESP Box", true)
			local showFill = flag("Universal ESP Box Fill", false)
			local showSkeleton = flag("Universal ESP Skeleton", false)
			local showInfoCard = flag("Universal ESP Info Card", false)
			local showNametag = flag("Universal ESP Nametag", true) and not showInfoCard
			local showSideHealth = flag("Universal ESP Health", true) and not showInfoCard
			local showCardHealth = flag("Universal ESP Health", true) and showInfoCard

			preview.box.Visible = showBox
			preview.boxFill.Visible = showBox and showFill
			preview.nametag.Visible = showNametag
			preview.infoCard.Visible = showInfoCard
			preview.healthBg.Visible = showSideHealth
			preview.healthFill.Visible = showSideHealth
			preview.cardHealthBg.Visible = showCardHealth
			preview.cardHealthFill.Visible = showCardHealth
			preview.cardName.Visible = showInfoCard and flag("Universal ESP Names", true)
			preview.cardDistance.Visible = showInfoCard and flag("Universal ESP Distance", true)

			local boxStroke = preview.box:FindFirstChildOfClass("UIStroke")
			if boxStroke then
				boxStroke.Color = color
			end
			local cardStroke = preview.infoCard:FindFirstChildOfClass("UIStroke")
			if cardStroke then
				cardStroke.Color = color
			end
			preview.boxFill.BackgroundColor3 = color
			preview.nametag.Text = showNametag and "Preview  [64m]" or ""
			preview.nametag.TextSize = numberFlag("Universal ESP Nametag Size", 13)

			for _, line in ipairs(preview.skeleton) do
				line.Visible = showSkeleton
				line.BackgroundColor3 = skeletonColor
			end
		end

		renderConnection = ctx.addConnection(ctx.RunService.RenderStepped, function()
			render()
		end)

		playerRemovingConnection = ctx.addConnection(ctx.Players.PlayerRemoving, destroyEntry)

		previewConnection = ctx.addConnection(ctx.RunService.Heartbeat, function()
			if not preview.root then
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

		local infoCardControl = ctx.option("Universal ESP Info Card")
		if infoCardControl then
			local previousCallback = infoCardControl.callback
			infoCardControl.callback = function(enabled)
				if enabled then
					ctx.setToggle("Universal ESP Nametag", false)
				end
				if previousCallback then
					previousCallback(enabled)
				end
			end
		end

		ctx.library:AddCleanup(function()
			ctx.disconnect(renderConnection)
			ctx.disconnect(playerRemovingConnection)
			ctx.disconnect(previewConnection)

			if preview.root and preview.root.Parent then
				pcall(function()
					preview.root.Parent.Parent:Destroy()
				end)
			end

			local playersToRemove = {}
			for player in pairs(ctx.state.esp) do
				table.insert(playersToRemove, player)
			end
			for _, player in ipairs(playersToRemove) do
				destroyEntry(player)
			end
		end)
	end

	return { setup = setupESPRuntime }
end
