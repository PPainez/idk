--[[
    xanhub | gakuran | basketball

    Basketball menu outline — logic not wired yet.
]]

return function(ctx)
	local columns = ctx.columns

	local shoot = columns.basketballLeft:AddSection("Shooting")
	shoot:AddToggle({ text = "Auto Green", flag = "Gakuran Auto Green", state = false })
	shoot:AddToggle({ text = "Humanize", flag = "Gakuran Basketball Humanize", state = true })
	shoot:AddSlider({
		text = "Jitter",
		flag = "Gakuran Basketball Jitter",
		min = 0,
		max = 100,
		value = 22,
		float = 1,
		suffix = "%",
	})
	shoot:AddToggle({ text = "No Dribble Cooldown", flag = "Gakuran No Dribble Cooldown", state = false })

	local esp = columns.basketballRight:AddSection("Basketball ESP")
	esp:AddToggle({ text = "Basketball ESP", flag = "Gakuran Basketball ESP", state = false })
	esp:AddLabel("Ball, hoop, and contest indicators")
	esp:AddLabel("Feature logic coming soon")

	-- State for auto green runtime
	ctx.state.basketball = ctx.state.basketball or {
		active = false,
		connection = nil,
		lastShot = 0,
	}

	local function setup()
		-- Toggle callback for Auto Green
		local autoGreenOption = ctx.option("Gakuran Auto Green")
		if autoGreenOption then
			autoGreenOption.callback = function(enabled)
				if enabled then
					startAutoGreenRuntime()
				else
					stopAutoGreenRuntime()
				end
			end
		end

		-- If already enabled on load, start runtime
		if ctx.library.flags["Gakuran Auto Green"] then
			startAutoGreenRuntime()
		end
	end

	local function startAutoGreenRuntime()
		if ctx.state.basketball.active then
			return
		end

		ctx.state.basketball.active = true

		ctx.state.basketball.connection = ctx.addConnection(ctx.RunService.Heartbeat, function()
			if ctx.state.unloading or not ctx.library.flags["Gakuran Auto Green"] then
				stopAutoGreenRuntime()
				return
			end

			-- Check if we have the ball and are in shooting range
			local character = ctx.getCharacter()
			local humanoid = ctx.getHumanoid(character)
			local root = ctx.getRoot(character)

			if not character or not humanoid or not root then
				return
			end

			-- Find basketball tool/ball in character
			local ball = findBallInCharacter(character)
			if not ball then
				return
			end

			-- Check if we're near a hoop
			local hoop = findNearestHoop(root.Position)
			if not hoop then
				return
			end

			-- Check distance to hoop
			local distance = (hoop.Position - root.Position).Magnitude
			local shootRange = 30 -- studs

			if distance > shootRange then
				return
			end

			-- Cooldown check
			local now = tick()
			local cooldown = 1.5 -- seconds between shots
			if now - ctx.state.basketball.lastShot < cooldown then
				return
			end

			-- Auto green logic - attempt perfect shot
			local success = attemptAutoGreen(character, humanoid, root, ball, hoop)
			if success then
				ctx.state.basketball.lastShot = now
			end
		end)
	end

	local function stopAutoGreenRuntime()
		if not ctx.state.basketball.active then
			return
		end

		ctx.state.basketball.active = false
		ctx.disconnect(ctx.state.basketball.connection)
		ctx.state.basketball.connection = nil
	end

	-- Helper: Find basketball in character
	local function findBallInCharacter(character)
		for _, tool in ipairs(character:GetChildren()) do
			if tool:IsA("Tool") then
				local name = tool.Name:lower()
				if name:find("ball") or name:find("basket") then
					return tool
				end
			end
		end

		-- Check for ball model attached
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("BasePart") then
				local name = child.Name:lower()
				if name:find("ball") or name:find("basket") then
					return child
				end
			end
		end

		return nil
	end

	-- Helper: Find nearest hoop
	local function findNearestHoop(position)
		-- Common hoop names in Gakuran
		local hoopNames = { "Hoop", "Basket", "Goal", "Rim", "Net" }

		for _, name in ipairs(hoopNames) do
			local hoop = ctx.Workspace:FindFirstChild(name, true)
			if hoop and hoop:IsA("BasePart") then
				return hoop
			end
		end

		-- Try to find by model
		for _, descendant in ipairs(ctx.Workspace:GetDescendants()) do
			if descendant:IsA("Model") then
				local name = descendant.Name:lower()
				if name:find("hoop") or name:find("basket") or name:find("goal") then
					local primary = descendant.PrimaryPart or descendant:FindFirstChild("Hoop")
					if primary then
						return primary
					end
				end
			end
		end

		return nil
	end

	-- Core: Attempt auto green shot
	local function attemptAutoGreen(character, humanoid, root, ball, hoop)
		local library = ctx.library
		local humanize = library.flags["Gakuran Basketball Humanize"]
		local jitterPercent = tonumber(library.flags["Gakuran Basketball Jitter"]) or 22

		-- Calculate shot direction
		local direction = (hoop.Position - root.Position).Unit

		-- Apply humanization
		if humanize then
			local jitter = jitterPercent / 100
			local randomOffset = Vector3.new(
				math.random(-jitter, jitter),
				math.random(-jitter, jitter),
				math.random(-jitter, jitter)
			)
			direction = (direction + randomOffset).Unit
		end

		-- Trigger shooting animation/action
		-- This depends on Gakuran's specific ball mechanics
		-- Try common shooting methods:

		-- Method 1: FireServer if there's a shoot remote
		local shootRemote = ball:FindFirstChild("Shoot") or ball:FindFirstChild("Fire") or ball:FindFirstChild("Release")
		if shootRemote and shootRemote:IsA("RemoteEvent") then
			-- Calculate power based on distance
			local distance = (hoop.Position - root.Position).Magnitude
			local power = math.clamp(distance / 30, 0.5, 1)

			shootRemote:FireServer(direction, power)
			return true
		end

		-- Method 2: Activate tool
		if ball:IsA("Tool") then
			ball:Activate()
			return true
		end

		-- Method 3: Simulate input (space/jump to shoot)
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

		-- Small delay then release
		task.delay(0.1, function()
			if ball and ball:IsA("Tool") then
				ball:Activate()
			end
		end)

		return true
	end

	-- Cleanup on unload
	ctx.library:AddCleanup(function()
		stopAutoGreenRuntime()
	end)

	return { setup = setup }
end