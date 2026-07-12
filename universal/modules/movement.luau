--[[
    xanhub | universal | movement

    Walk speed, jump, fly, noclip, and click teleport features.
]]

return function(ctx)
	local movementSection = ctx.columns.playerLeft:AddSection("Movement")
	movementSection:AddToggle({
		text = "Walk Speed Override [RISK]",
		flag = "Universal Speed Enabled",
		state = false,
	})
	movementSection:AddSlider({
		text = "Walk Speed",
		flag = "Universal Walk Speed",
		min = 8,
		max = 250,
		value = 32,
		float = 1,
	})
	movementSection:AddToggle({
		text = "Jump Override [RISK]",
		flag = "Universal Jump Enabled",
		state = false,
	})
	movementSection:AddSlider({
		text = "Jump Power",
		flag = "Universal Jump Power",
		min = 20,
		max = 250,
		value = 70,
		float = 1,
	})
	movementSection:AddToggle({
		text = "Infinite Jump [RISK]",
		flag = "Universal Infinite Jump",
		state = false,
	})

	local advancedMovement = ctx.columns.playerRight:AddSection("Advanced Movement")
	advancedMovement:AddToggle({
		text = "Fly [RISK]",
		flag = "Universal Fly",
		state = false,
	})
	advancedMovement:AddSlider({
		text = "Fly Speed",
		flag = "Universal Fly Speed",
		min = 10,
		max = 300,
		value = 70,
		float = 5,
	})
	advancedMovement:AddToggle({
		text = "Noclip [RISK]",
		flag = "Universal Noclip",
		state = false,
	})
	advancedMovement:AddToggle({
		text = "Ctrl + Click Teleport [RISK]",
		flag = "Universal Click Teleport",
		state = false,
	})
	advancedMovement:AddLabel("Risk features are client-side and may be detected by games")

	local function setupMovementRuntime()
		local movementConnection
		local infiniteJumpConnection
		local clickTeleportConnection

		local function rememberHumanoid(humanoid)
			if humanoid and not ctx.state.movementOriginal[humanoid] then
				ctx.state.movementOriginal[humanoid] = {
					WalkSpeed = humanoid.WalkSpeed,
					JumpPower = humanoid.JumpPower,
					JumpHeight = humanoid.JumpHeight,
					UseJumpPower = humanoid.UseJumpPower,
					AutoRotate = humanoid.AutoRotate,
					PlatformStand = humanoid.PlatformStand,
				}
			end
		end

		local function restoreHumanoid(humanoid)
			local original = humanoid and ctx.state.movementOriginal[humanoid]
			if humanoid and original and humanoid.Parent then
				pcall(function()
					humanoid.WalkSpeed = original.WalkSpeed
					humanoid.JumpPower = original.JumpPower
					humanoid.JumpHeight = original.JumpHeight
					humanoid.UseJumpPower = original.UseJumpPower
					humanoid.AutoRotate = original.AutoRotate
					humanoid.PlatformStand = original.PlatformStand
				end)
			end
		end

		movementConnection = ctx.addConnection(ctx.RunService.Heartbeat, function()
			if ctx.state.unloading then
				return
			end

			local humanoid = ctx.getHumanoid()
			if not humanoid then
				return
			end

			rememberHumanoid(humanoid)

			if ctx.library.flags["Universal Speed Enabled"] then
				humanoid.WalkSpeed = tonumber(ctx.library.flags["Universal Walk Speed"]) or 32
			elseif not ctx.library.flags["Universal Fly"] then
				local original = ctx.state.movementOriginal[humanoid]
				if original then
					humanoid.WalkSpeed = original.WalkSpeed
				end
			end

			if ctx.library.flags["Universal Jump Enabled"] then
				local value = tonumber(ctx.library.flags["Universal Jump Power"]) or 70
				if humanoid.UseJumpPower then
					humanoid.JumpPower = value
				else
					humanoid.JumpHeight = math.max(7.2, value / 7)
				end
			else
				local original = ctx.state.movementOriginal[humanoid]
				if original then
					humanoid.JumpPower = original.JumpPower
					humanoid.JumpHeight = original.JumpHeight
				end
			end
		end)

		infiniteJumpConnection = ctx.addConnection(ctx.UserInputService.JumpRequest, function()
			if ctx.library.flags["Universal Infinite Jump"] then
				local humanoid = ctx.getHumanoid()
				if humanoid then
					humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				end
			end
		end)

		local mouse = ctx.LocalPlayer:GetMouse()
		clickTeleportConnection = ctx.addConnection(mouse.Button1Down, function()
			if not ctx.library.flags["Universal Click Teleport"]
				or not ctx.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
				return
			end

			local root = ctx.getRoot()
			if root and mouse.Hit then
				root.CFrame = mouse.Hit + Vector3.new(0, 3, 0)
			end
		end)

		ctx.library:AddCleanup(function()
			ctx.disconnect(movementConnection)
			ctx.disconnect(infiniteJumpConnection)
			ctx.disconnect(clickTeleportConnection)
			for humanoid in pairs(ctx.state.movementOriginal) do
				restoreHumanoid(humanoid)
			end
		end)
	end

	local function setupFlyRuntime()
		local flyConnection

		local function stopFly()
			ctx.disconnect(flyConnection)
			flyConnection = nil

			if ctx.state.fly.velocity then
				pcall(function()
					ctx.state.fly.velocity:Destroy()
				end)
			end
			if ctx.state.fly.gyro then
				pcall(function()
					ctx.state.fly.gyro:Destroy()
				end)
			end

			local humanoid = ctx.getHumanoid()
			if humanoid then
				local original = ctx.state.movementOriginal[humanoid]
				humanoid.PlatformStand = original and original.PlatformStand or false
				humanoid.AutoRotate = original and original.AutoRotate or true
			end

			ctx.state.fly.velocity = nil
			ctx.state.fly.gyro = nil
		end

		local function startFly()
			stopFly()

			local root = ctx.getRoot()
			local humanoid = ctx.getHumanoid()
			if not root or not humanoid then
				ctx.setToggle("Universal Fly", false)
				return
			end

			if not ctx.state.movementOriginal[humanoid] then
				ctx.state.movementOriginal[humanoid] = {
					WalkSpeed = humanoid.WalkSpeed,
					JumpPower = humanoid.JumpPower,
					JumpHeight = humanoid.JumpHeight,
					UseJumpPower = humanoid.UseJumpPower,
					AutoRotate = humanoid.AutoRotate,
					PlatformStand = humanoid.PlatformStand,
				}
			end

			local velocity = Instance.new("BodyVelocity")
			velocity.Name = "xanhub_fly_velocity"
			velocity.MaxForce = Vector3.new(1e9, 1e9, 1e9)
			velocity.Velocity = Vector3.zero
			velocity.Parent = root

			local gyro = Instance.new("BodyGyro")
			gyro.Name = "xanhub_fly_gyro"
			gyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
			gyro.P = 30000
			gyro.CFrame = root.CFrame
			gyro.Parent = root

			ctx.state.fly.velocity = velocity
			ctx.state.fly.gyro = gyro
			humanoid.PlatformStand = true
			humanoid.AutoRotate = false

			flyConnection = ctx.addConnection(ctx.RunService.RenderStepped, function()
				if ctx.state.unloading or not ctx.library.flags["Universal Fly"] then
					return
				end

				local camera = ctx.Workspace.CurrentCamera
				local currentRoot = ctx.getRoot()
				if not camera or not currentRoot or velocity.Parent ~= currentRoot then
					ctx.setToggle("Universal Fly", false)
					return
				end

				local direction = Vector3.zero
				if ctx.UserInputService:IsKeyDown(Enum.KeyCode.W) then direction += camera.CFrame.LookVector end
				if ctx.UserInputService:IsKeyDown(Enum.KeyCode.S) then direction -= camera.CFrame.LookVector end
				if ctx.UserInputService:IsKeyDown(Enum.KeyCode.A) then direction -= camera.CFrame.RightVector end
				if ctx.UserInputService:IsKeyDown(Enum.KeyCode.D) then direction += camera.CFrame.RightVector end
				if ctx.UserInputService:IsKeyDown(Enum.KeyCode.Space) then direction += Vector3.new(0, 1, 0) end
				if ctx.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then direction -= Vector3.new(0, 1, 0) end

				local speed = tonumber(ctx.library.flags["Universal Fly Speed"]) or 70
				velocity.Velocity = direction.Magnitude > 0 and direction.Unit * speed or Vector3.zero
				gyro.CFrame = CFrame.lookAt(currentRoot.Position, currentRoot.Position + camera.CFrame.LookVector)
			end)
		end

		local flyOption = ctx.option("Universal Fly")
		if flyOption then
			flyOption.callback = function(enabled)
				if enabled then
					startFly()
				else
					stopFly()
				end
			end
		end

		ctx.library:AddCleanup(stopFly)

		ctx.addConnection(ctx.LocalPlayer.CharacterAdded, function()
			if ctx.state.unloading or not ctx.library.flags["Universal Fly"] then
				return
			end

			task.defer(function()
				if not ctx.state.unloading and ctx.library.flags["Universal Fly"] then
					startFly()
				end
			end)
		end)
	end

	local function setupNoclipRuntime()
		local connection

		local function restore()
			for part, canCollide in pairs(ctx.state.noclipOriginal) do
				if part and part.Parent then
					pcall(function()
						part.CanCollide = canCollide
					end)
				end
				ctx.state.noclipOriginal[part] = nil
			end
		end

		connection = ctx.addConnection(ctx.RunService.Stepped, function()
			if not ctx.library.flags["Universal Noclip"] then
				restore()
				return
			end

			local character = ctx.getCharacter()
			if not character then
				return
			end

			for _, object in ipairs(character:GetDescendants()) do
				if object:IsA("BasePart") then
					if ctx.state.noclipOriginal[object] == nil then
						ctx.state.noclipOriginal[object] = object.CanCollide
					end
					object.CanCollide = false
				end
			end
		end)

		local control = ctx.option("Universal Noclip")
		if control then
			control.callback = function(enabled)
				if not enabled then
					restore()
				end
			end
		end

		ctx.library:AddCleanup(function()
			ctx.disconnect(connection)
			restore()
		end)
	end

	local function setup()
		setupMovementRuntime()
		setupFlyRuntime()
		setupNoclipRuntime()
	end

	return { setup = setup }
end
