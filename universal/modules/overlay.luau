--[[
    xanhub | universal | overlay

    Local visuals, targeting preview, and combat aim features.
]]

return function(ctx)
	local localVisuals = ctx.columns.visualsRight:AddSection("Local Visuals")
	localVisuals:AddSlider({
		text = "Field of View",
		flag = "Universal FOV",
		min = 50,
		max = 120,
		value = 70,
		float = 1,
	})
	localVisuals:AddToggle({text = "Crosshair", flag = "Universal Crosshair", state = false})
	localVisuals:AddSlider({text = "Crosshair Size", flag = "Universal Crosshair Size", min = 4, max = 30, value = 9, float = 1})
	localVisuals:AddSlider({text = "Crosshair Gap", flag = "Universal Crosshair Gap", min = 0, max = 18, value = 4, float = 1})
	localVisuals:AddColor({text = "Crosshair Color", flag = "Universal Crosshair Color", color = Color3.fromRGB(0, 170, 255)})
	localVisuals:AddToggle({text = "Coordinates", flag = "Universal Coordinates", state = false})

	local targetingSection = ctx.columns.combatLeft:AddSection("Targeting")
	targetingSection:AddToggle({text = "Enabled", flag = "Universal Aim Preview", state = false})
	targetingSection:AddToggle({
		text = "Sync With ESP",
		flag = "Universal Targeting Sync ESP",
		state = true,
	})
	targetingSection:AddToggle({text = "Show FOV Circle", flag = "Universal Aim Show FOV", state = true})
	targetingSection:AddToggle({text = "Team Check", flag = "Universal Aim Team Check", state = true})
	targetingSection:AddList({
		text = "Target Part",
		flag = "Universal Aim Part",
		values = {"Head", "Torso"},
		value = "Head",
	})
	targetingSection:AddSlider({
		text = "Targeting Radius",
		flag = "Universal Aim FOV",
		min = 35,
		max = 400,
		value = 140,
		float = 5,
		suffix = " px",
	})
	targetingSection:AddSlider({
		text = "Maximum Distance",
		flag = "Universal Aim Max Distance",
		min = 50,
		max = 1500,
		value = 500,
		float = 10,
		suffix = " studs",
	})
	targetingSection:AddToggle({text = "Show Target Line", flag = "Universal Aim Show Line", state = true})
	targetingSection:AddColor({
		text = "Target Color",
		flag = "Universal Aim Color",
		color = Color3.fromRGB(255, 82, 96),
	})
	ctx.refs.targetingStatus = targetingSection:AddLabel("Target: none")
	targetingSection:AddLabel("Sync With ESP uses its team, range, and color settings")

	local combatAimSection = ctx.columns.combatRight:AddSection("Combat Aim")
	combatAimSection:AddToggle({
		text = "Aim Lock (Camera Track)",
		flag = "Universal Combat Aim Lock",
		state = false,
	})
	combatAimSection:AddToggle({
		text = "Silent Aim",
		flag = "Universal Combat Silent Aim",
		state = false,
	})
	combatAimSection:AddSlider({
		text = "Smoothness",
		flag = "Universal Combat Smoothness",
		min = 1,
		max = 25,
		value = 6,
		float = 0.5,
	})
	combatAimSection:AddSlider({
		text = "Prediction",
		flag = "Universal Combat Prediction",
		min = 0,
		max = 2.5,
		value = 1.1,
		float = 0.05,
	})
	combatAimSection:AddToggle({
		text = "Lock Only (No Auto Switch)",
		flag = "Universal Combat Lock Only",
		state = false,
	})
	combatAimSection:AddLabel("Q toggles Aim Lock · Silent Aim snaps instantly")

	local function setupOverlayRuntime()
		local renderConnection
		local root = ctx.createOverlayRoot()
		local crosshair = {}

		for index = 1, 4 do
			local line = Instance.new("Frame")
			line.Name = "CrosshairLine" .. index
			line.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
			line.BorderSizePixel = 0
			line.Visible = false
			line.ZIndex = 510
			line.Parent = root
			crosshair[index] = line
		end

		local coordinates = Instance.new("TextLabel")
		coordinates.AnchorPoint = Vector2.new(0.5, 1)
		coordinates.Position = UDim2.new(0.5, 0, 1, -22)
		coordinates.Size = UDim2.fromOffset(330, 26)
		coordinates.BackgroundColor3 = Color3.fromRGB(8, 11, 17)
		coordinates.BackgroundTransparency = 0.16
		coordinates.BorderSizePixel = 0
		coordinates.TextColor3 = Color3.fromRGB(235, 240, 250)
		coordinates.TextSize = 12
		coordinates.Font = Enum.Font.Code
		coordinates.Visible = false
		coordinates.ZIndex = 510
		coordinates.Parent = root
		ctx.createRounded(coordinates, 7)

		local coordinatesStroke = Instance.new("UIStroke")
		coordinatesStroke.Color = Color3.fromRGB(0, 170, 255)
		coordinatesStroke.Transparency = 0.38
		coordinatesStroke.Parent = coordinates

		local fovCircle = Instance.new("Frame")
		fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
		fovCircle.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
		fovCircle.BackgroundTransparency = 0.985
		fovCircle.BorderSizePixel = 0
		fovCircle.Visible = false
		fovCircle.ZIndex = 505
		fovCircle.Parent = root
		ctx.createRounded(fovCircle, 999)

		local fovStroke = Instance.new("UIStroke")
		fovStroke.Thickness = 1
		fovStroke.Transparency = 0.56
		fovStroke.Color = Color3.fromRGB(0, 170, 255)
		fovStroke.Parent = fovCircle

		local targetLine = Instance.new("Frame")
		targetLine.AnchorPoint = Vector2.new(0.5, 0.5)
		targetLine.BackgroundColor3 = Color3.fromRGB(255, 82, 96)
		targetLine.BackgroundTransparency = 0.56
		targetLine.BorderSizePixel = 0
		targetLine.Visible = false
		targetLine.ZIndex = 506
		targetLine.Parent = root

		local function setScreenLine(frame, from, to, thickness)
			local delta = to - from
			local length = delta.Magnitude
			if length <= 0.001 then
				frame.Visible = false
				return
			end
			local midpoint = from + delta / 2
			frame.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
			frame.Size = UDim2.fromOffset(length, thickness or 1)
			frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		end

		local function targetingSettings()
			local syncESP = ctx.library.flags["Universal Targeting Sync ESP"] ~= false
			local teamCheck
			if syncESP then
				teamCheck = ctx.library.flags["Universal ESP Team Check"] == true
			else
				teamCheck = ctx.library.flags["Universal Aim Team Check"] == true
			end

			local targetMaximum = math.max(
				50,
				tonumber(ctx.library.flags["Universal Aim Max Distance"]) or 500
			)
			if syncESP then
				targetMaximum = math.min(
					targetMaximum,
					math.max(50, tonumber(ctx.library.flags["Universal ESP Max Distance"]) or 800)
				)
			end

			local espColor = typeof(ctx.library.flags["Universal ESP Color"]) == "Color3"
				and ctx.library.flags["Universal ESP Color"]
				or Color3.fromRGB(0, 170, 255)
			local configuredColor = typeof(ctx.library.flags["Universal Aim Color"]) == "Color3"
				and ctx.library.flags["Universal Aim Color"]
				or Color3.fromRGB(255, 82, 96)

			return syncESP, teamCheck, targetMaximum, syncESP and espColor or configuredColor
		end

		local function targetValid(player, camera, localRoot, center, radius, maxDistance, teamCheck)
			if not player or player == ctx.LocalPlayer then
				return nil
			end

			local character = player.Character
			local humanoid = ctx.getHumanoid(character)
			local targetPart = ctx.getTargetPart(character)
			local targetRoot = ctx.getRoot(character)

			if not character or not humanoid or humanoid.Health <= 0 or not targetPart or not targetRoot then
				return nil
			end

			if teamCheck and ctx.LocalPlayer.Team ~= nil and player.Team == ctx.LocalPlayer.Team then
				return nil
			end

			local worldDistance = localRoot and (localRoot.Position - targetRoot.Position).Magnitude or math.huge
			if worldDistance > maxDistance then
				return nil
			end

			local point, onScreen = camera:WorldToViewportPoint(targetPart.Position)
			if not onScreen or point.Z <= 0 then
				return nil
			end

			local screenPoint = Vector2.new(point.X, point.Y)
			local screenDistance = (screenPoint - center).Magnitude
			if screenDistance > radius then
				return nil
			end

			return {
				player = player,
				part = targetPart,
				point = screenPoint,
				screenDistance = screenDistance,
				worldDistance = worldDistance,
			}
		end

		local function findNearestTarget(camera, localRoot, center, radius, maxDistance, teamCheck)
			local best
			for _, player in ipairs(ctx.Players:GetPlayers()) do
				local candidate = targetValid(
					player,
					camera,
					localRoot,
					center,
					radius,
					maxDistance,
					teamCheck
				)
				if candidate and (not best or candidate.screenDistance < best.screenDistance) then
					best = candidate
				end
			end
			return best
		end

		renderConnection = ctx.addConnection(ctx.RunService.RenderStepped, function()
			if ctx.state.unloading then
				return
			end

			local camera = ctx.Workspace.CurrentCamera
			if not camera then
				return
			end

			camera.FieldOfView = tonumber(ctx.library.flags["Universal FOV"]) or 70

			local viewport = camera.ViewportSize
			local center = viewport / 2
			local showCrosshair = ctx.library.flags["Universal Crosshair"] == true
			local size = tonumber(ctx.library.flags["Universal Crosshair Size"]) or 9
			local gap = tonumber(ctx.library.flags["Universal Crosshair Gap"]) or 4
			local crosshairColor = typeof(ctx.library.flags["Universal Crosshair Color"]) == "Color3"
				and ctx.library.flags["Universal Crosshair Color"]
				or Color3.fromRGB(0, 170, 255)

			for _, line in ipairs(crosshair) do
				line.Visible = showCrosshair
				line.BackgroundColor3 = crosshairColor
			end

			if showCrosshair then
				crosshair[1].Position = UDim2.fromOffset(center.X - 1, center.Y - gap - size)
				crosshair[1].Size = UDim2.fromOffset(2, size)
				crosshair[2].Position = UDim2.fromOffset(center.X - 1, center.Y + gap)
				crosshair[2].Size = UDim2.fromOffset(2, size)
				crosshair[3].Position = UDim2.fromOffset(center.X - gap - size, center.Y - 1)
				crosshair[3].Size = UDim2.fromOffset(size, 2)
				crosshair[4].Position = UDim2.fromOffset(center.X + gap, center.Y - 1)
				crosshair[4].Size = UDim2.fromOffset(size, 2)
			end

			local showCoordinates = ctx.library.flags["Universal Coordinates"] == true
			coordinates.Visible = showCoordinates
			if showCoordinates then
				local characterRoot = ctx.getRoot()
				if characterRoot then
					coordinates.Text = string.format(
						"X %.1f   Y %.1f   Z %.1f",
						characterRoot.Position.X,
						characterRoot.Position.Y,
						characterRoot.Position.Z
					)
				else
					coordinates.Text = "Position unavailable"
				end
			end

			local targetingEnabled = ctx.library.flags["Universal Aim Preview"] == true
			local lockEnabled = ctx.library.flags["Universal Combat Aim Lock"] == true
			local silentEnabled = ctx.library.flags["Universal Combat Silent Aim"] == true
			local acquireTarget = targetingEnabled or lockEnabled or silentEnabled
			local requestedRadius = math.max(20, tonumber(ctx.library.flags["Universal Aim FOV"]) or 140)
			local radius = math.min(requestedRadius, math.min(viewport.X, viewport.Y) * 0.47)
			local _, teamCheck, maxDistance, targetColor = targetingSettings()

			fovCircle.Position = UDim2.fromOffset(center.X, center.Y)
			fovCircle.Size = UDim2.fromOffset(radius * 2, radius * 2)
			fovCircle.Visible = targetingEnabled and ctx.library.flags["Universal Aim Show FOV"] == true
			fovCircle.BackgroundColor3 = targetColor
			fovStroke.Color = targetColor
			targetLine.BackgroundColor3 = targetColor

			if not acquireTarget then
				ctx.state.aimTarget = nil
				targetLine.Visible = false
				if ctx.refs.targetingStatus then
					ctx.refs.targetingStatus.Text = "Target: none"
				end
			else
				local localRoot = ctx.getRoot()
				local combatLockOnly = ctx.library.flags["Universal Combat Lock Only"] == true
				local locked = combatLockOnly or lockEnabled
				local autoSwitch = not locked
				local target

				if locked and ctx.state.aimTarget then
					target = targetValid(
						ctx.state.aimTarget,
						camera,
						localRoot,
						center,
						radius,
						maxDistance,
						teamCheck
					)
				end

				if not target and (not locked or autoSwitch) then
					target = findNearestTarget(
						camera,
						localRoot,
						center,
						radius,
						maxDistance,
						teamCheck
					)
					ctx.state.aimTarget = target and target.player or nil
				elseif target and not locked then
					ctx.state.aimTarget = target.player
				elseif not target and locked and not autoSwitch then
					ctx.state.aimTarget = nil
				end

				if target and ctx.refs.targetingStatus then
					ctx.refs.targetingStatus.Text = string.format(
						"Target: %s | %dm",
						ctx.getPlayerLabel(target.player),
						math.floor(target.worldDistance + 0.5)
					)

					if ctx.library.flags["Universal Aim Show Line"] == true then
						setScreenLine(targetLine, center, target.point, 1)
						targetLine.Visible = true
					else
						targetLine.Visible = false
					end
				else
					if ctx.refs.targetingStatus then
						ctx.refs.targetingStatus.Text = locked and "Target: lost" or "Target: none in radius"
					end
					targetLine.Visible = false
				end
			end

			if lockEnabled or silentEnabled then
				local targetPlayer = ctx.state.aimTarget
				if targetPlayer then
					local character = targetPlayer.Character
					local targetPart = ctx.getTargetPart(character)
					local rootPart = ctx.getRoot(character)

					if targetPart and rootPart then
						local prediction = tonumber(ctx.library.flags["Universal Combat Prediction"]) or 1.1
						local vel = rootPart.AssemblyLinearVelocity or Vector3.zero
						local predictedPos = targetPart.Position + vel * prediction * (1 / 60)
						local targetCF = CFrame.lookAt(camera.CFrame.Position, predictedPos)

						if lockEnabled then
							local smoothness = tonumber(ctx.library.flags["Universal Combat Smoothness"]) or 6
							camera.CFrame = camera.CFrame:Lerp(targetCF, 1 / smoothness)
						elseif silentEnabled then
							camera.CFrame = targetCF
						end
					end
				end
			end
		end)

		ctx.state.overlays.coordinates = coordinates
		ctx.state.overlays.crosshair = crosshair
		ctx.state.overlays.fovCircle = fovCircle
		ctx.state.overlays.targetLine = targetLine

		ctx.library:AddCleanup(function()
			ctx.disconnect(renderConnection)
			ctx.state.aimTarget = nil
		end)
	end

	return { setup = setupOverlayRuntime }
end
