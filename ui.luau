--[[
    xanhub UI Library
    Rebuilt from the legacy uwuware 2.x interface.

    Goals:
    - executor-compatible GUI parenting
    - no legacy GuiObject tween errors
    - safe callback and connection handling
    - complete unload support
    - optional filesystem/config support
    - dark theme with electric-blue accents
]]

--LIBRARY START
	-- Services and executor environment
	local env = (type(getgenv) == "function" and getgenv()) or _G
	local runService = game:GetService("RunService")
	local textService = game:GetService("TextService")
	local inputService = game:GetService("UserInputService")
	local tweenService = game:GetService("TweenService")
	local playersService = game:GetService("Players")
	local httpService = game:GetService("HttpService")

	-- Keep the old service globals for compatibility with older scripts.
	env.runService = runService
	env.textService = textService
	env.inputService = inputService
	env.tweenService = tweenService

	local previousLibrary = env.xanhub
	if type(previousLibrary) ~= "table" and type(env.library) == "table" and env.library.__xanhub then
		previousLibrary = env.library
	end
	if type(previousLibrary) == "table" and type(previousLibrary.Unload) == "function" then
		pcall(function()
			previousLibrary:Unload()
		end)
	end

	local DEFAULT_ACCENT = Color3.fromRGB(0, 170, 255)
	local PALETTE = {
		accent = DEFAULT_ACCENT,
		background = Color3.fromRGB(10, 12, 17),
		surface = Color3.fromRGB(15, 18, 25),
		surfaceRaised = Color3.fromRGB(21, 25, 34),
		control = Color3.fromRGB(35, 40, 52),
		controlHover = Color3.fromRGB(43, 49, 64),
		text = Color3.fromRGB(245, 247, 255),
		textMuted = Color3.fromRGB(170, 180, 198),
		border = Color3.fromRGB(4, 6, 10),
	}
	local library = {
		__xanhub = true,
		brand = "xanhub",
		version = "3.1.0",
		design = "xanhub",
		tabs = {},
		draggable = true,
		flags = {},
		title = "xanhub",
		open = false,
		mousestate = inputService.MouseIconEnabled,
		popup = nil,
		instances = {},
		connections = {},
		options = {},
		notifications = {},
		cleaners = {},
		tabSize = 0,
		theme = {},
		brandLabels = {},
		foldername = "xanhub_configs",
		fileext = ".xan",
		defaultAccent = DEFAULT_ACCENT,
		palette = PALETTE,
		windowHeight = 600,
		minimumWindowWidth = 494,
		userScale = 1,
		autoScale = 1,
	}

	-- Seed theme flags before any controls initialize. Older versions left the
	-- accent nil until the Settings tab loaded, which could create white or
	-- partially styled controls on the first frame.
	library.flags["Menu Accent Color"] = DEFAULT_ACCENT
	library.flags["UI Background"] = "None"
	library.flags["Menu Background Color"] = Color3.new(0, 0, 0)
	library.flags["Menu Background Color Transparency"] = 1

	env.xanhub = library
	env.library = library
	env.uwuware = nil

	library.capabilities = {
		filesystem = type(isfolder) == "function" and type(makefolder) == "function" and type(listfiles) == "function" and type(readfile) == "function" and type(writefile) == "function",
		deletefile = type(isfile) == "function" and type(delfile) == "function",
		gethui = type(gethui) == "function" or type(get_hidden_gui) == "function" or type(gethiddengui) == "function",
	}

	--Locals
	local dragging, dragInput, dragStart, startPos, dragObject

	local blacklistedKeys = { --add or remove keys if you find the need to
		Enum.KeyCode.Unknown,Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,Enum.KeyCode.Slash,Enum.KeyCode.Tab,Enum.KeyCode.Escape
	}
	local whitelistedMouseinputs = { --add or remove mouse inputs if you find the need to
		Enum.UserInputType.MouseButton1,Enum.UserInputType.MouseButton2,Enum.UserInputType.MouseButton3
	}

	--Functions
	-- Some executors incorrectly reject GUI tweens. Direct property updates are
	-- therefore the safe default; callers can opt into tweens when supported.
	library.enableTweens = false
	function library:SafeTween(object, tweenInfo, properties)
		if not object or type(properties) ~= "table" then
			return nil
		end

		if self.enableTweens and typeof(object) == "Instance" and object.Parent then
			local success, tween = pcall(function()
				return tweenService:Create(object, tweenInfo or TweenInfo.new(0), properties)
			end)
			if success and tween then
				local played = pcall(function()
					tween:Play()
				end)
				if played then
					return tween
				end
			end
		end

		for property, value in next, properties do
			pcall(function()
				object[property] = value
			end)
		end
		return nil
	end

	function library.round(num, bracket)
		if typeof(num) == "Vector2" then
			return Vector2.new(library.round(num.X), library.round(num.Y))
		elseif typeof(num) == "Vector3" then
			return Vector3.new(library.round(num.X), library.round(num.Y), library.round(num.Z))
		elseif typeof(num) == "Color3" then
			return library.round(num.R * 255), library.round(num.G * 255), library.round(num.B * 255)
		end

		num = tonumber(num) or 0
		bracket = tonumber(bracket) or 1
		if bracket == 0 then
			return num
		end
		return math.floor((num / bracket) + 0.5) * bracket
	end

	local function escapeRichText(value)
		return tostring(value or "")
			:gsub("&", "&amp;")
			:gsub("<", "&lt;")
			:gsub(">", "&gt;")
			:gsub('"', "&quot;")
			:gsub("'", "&apos;")
	end

	function library:FormatBrand(value)
		local textValue = tostring(value or self.title or self.brand)
		local lowerValue = string.lower(textValue)
		local first, last = string.find(lowerValue, "xanhub", 1, true)
		if not first then
			return escapeRichText(textValue)
		end

		local accent = self.flags["Menu Accent Color"] or self.defaultAccent or DEFAULT_ACCENT
		local r, g, b = self.round(accent)
		local before = escapeRichText(string.sub(textValue, 1, first - 1))
		local after = escapeRichText(string.sub(textValue, last + 1))
		return before
			.. string.format('<font color="rgb(%d,%d,%d)">xan</font>', r, g, b)
			.. '<font color="rgb(255,255,255)">hub</font>'
			.. after
	end

	function library:FormatTitle(value)
		local titleValue = tostring(value or self.title or self.brand)
		if titleValue == "" then
			titleValue = self.brand
		end
		if not string.find(string.lower(titleValue), "xanhub", 1, true) then
			titleValue = self.brand .. "  |  " .. titleValue
		end
		return self:FormatBrand(titleValue)
	end

	function library:RegisterBrandLabel(label, value, formatAsTitle)
		if typeof(label) ~= "Instance" then
			return label
		end
		table.insert(self.brandLabels, {
			label = label,
			value = tostring(value or self.brand),
			formatAsTitle = formatAsTitle == true,
		})
		pcall(function()
			label.RichText = true
			label.Text = formatAsTitle and self:FormatTitle(value) or self:FormatBrand(value)
		end)
		return label
	end

	function library:RefreshBranding()
		for index = #self.brandLabels, 1, -1 do
			local entry = self.brandLabels[index]
			local label = entry and entry.label
			if typeof(label) ~= "Instance" or label.Parent == nil then
				table.remove(self.brandLabels, index)
			else
				pcall(function()
					label.Text = entry.formatAsTitle and self:FormatTitle(entry.value) or self:FormatBrand(entry.value)
				end)
			end
		end
	end

	function library:AddThemeObject(object)
		if typeof(object) == "Instance" then
			table.insert(self.theme, object)
		end
		return object
	end

	function library:SetAccent(color)
		if typeof(color) ~= "Color3" then
			return false
		end
		self.flags["Menu Accent Color"] = color
		if self.currentTab and self.currentTab.button then
			pcall(function()
				self.currentTab.button.TextColor3 = color
			end)
		end
		for index = #self.theme, 1, -1 do
			local object = self.theme[index]
			if typeof(object) ~= "Instance" or object.Parent == nil then
				table.remove(self.theme, index)
			else
				pcall(function()
					if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
						object.TextColor3 = color
					elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
						object.ImageColor3 = color
					else
						object.BackgroundColor3 = color
					end
				end)
			end
		end
		self:RefreshBranding()
		return true
	end

	function library:SetTitle(value)
		self.title = tostring(value or self.brand)
		if self.titleLabel then
			for _, entry in ipairs(self.brandLabels) do
				if entry.label == self.titleLabel then
					entry.value = self.title
					break
				end
			end
			pcall(function()
				self.titleLabel.Text = self:FormatTitle(self.title)
			end)
		end
		return self.title
	end

	function library:Invoke(callback, ...)
		if type(callback) ~= "function" then
			return false, "callback is not a function"
		end
		local arguments = table.pack(...)
		local ok, result = pcall(function()
			return callback(table.unpack(arguments, 1, arguments.n))
		end)
		if not ok then
			warn("[xanhub] Callback error: " .. tostring(result))
		end
		return ok, result
	end

	function library:Create(class, properties)
		properties = properties or {}
		if not class or self.unloaded then
			return nil
		end

		local isDrawing = class == "Square" or class == "Line" or class == "Text" or class == "Quad" or class == "Circle" or class == "Triangle"
		if isDrawing and (typeof(Drawing) ~= "table" or type(Drawing.new) ~= "function") then
			return nil
		end

		local success, inst = pcall(function()
			return (isDrawing and Drawing or Instance).new(class)
		end)
		if not success or not inst then
			warn("[xanhub] Unable to create " .. tostring(class) .. ": " .. tostring(inst))
			return nil
		end

		local parent = properties.Parent
		for property, value in next, properties do
			if property ~= "Parent" then
				local propertySuccess, propertyError = pcall(function()
					inst[property] = value
				end)
				if not propertySuccess then
					warn("[xanhub] Skipped unsupported property " .. tostring(property) .. " on " .. tostring(class) .. ": " .. tostring(propertyError))
				end
			end
		end
		if parent ~= nil then
			local parentSuccess, parentError = pcall(function()
				inst.Parent = parent
			end)
			if not parentSuccess then
				warn("[xanhub] Failed to parent " .. tostring(class) .. ": " .. tostring(parentError))
			end
		end

		table.insert(self.instances, {object = inst, method = isDrawing})
		return inst
	end

	function library:AddConnection(signal, name, callback)
		callback = type(name) == "function" and name or callback
		if not signal or type(callback) ~= "function" then
			return nil
		end

		local success, connection = pcall(function()
			return signal:Connect(callback)
		end)
		if not success then
			warn("[xanhub] Failed to connect signal: " .. tostring(connection))
			return nil
		end

		if type(name) == "string" then
			if self.connections[name] then
				pcall(function() self.connections[name]:Disconnect() end)
			end
			self.connections[name] = connection
		else
			table.insert(self.connections, connection)
		end
		return connection
	end

	function library:AddCleanup(callback)
		if type(callback) ~= "function" then
			return nil
		end
		table.insert(self.cleaners, callback)
		return callback
	end

	function library:RemoveCleanup(callback)
		local index = table.find(self.cleaners, callback)
		if index then
			table.remove(self.cleaners, index)
			return true
		end
		return false
	end

	function library:SetTweening(enabled)
		self.enableTweens = enabled == true
		return self.enableTweens
	end

	function library:GetAccent()
		return self.flags["Menu Accent Color"] or self.defaultAccent
	end

	function library:Unload()
		if self.unloaded then
			return false
		end
		self.unloaded = true
		self.open = false
		dragging = false
		dragInput = nil
		dragObject = nil

		pcall(function()
			inputService.MouseIconEnabled = self.mousestate
		end)

		-- Give enabled features a chance to clean themselves up.
		for _, option in next, self.options do
			if option.type == "toggle" and option.state and option.SetState then
				pcall(function()
					option:SetState(false)
				end)
			end
		end

		-- Run custom cleanup handlers in reverse registration order. Menu code can
		-- register feature cleanup with library:AddCleanup(function() ... end).
		for index = #self.cleaners, 1, -1 do
			local cleaner = self.cleaners[index]
			self.cleaners[index] = nil
			if type(cleaner) == "function" then
				local ok, err = pcall(cleaner)
				if not ok then
					warn("[xanhub] Cleanup error: " .. tostring(err))
				end
			end
		end

		for key, connection in next, self.connections do
			pcall(function()
				connection:Disconnect()
			end)
			self.connections[key] = nil
		end

		for index = #self.instances, 1, -1 do
			local item = self.instances[index]
			if item and item.object then
				pcall(function()
					if item.method then
						item.object:Remove()
					else
						item.object:Destroy()
					end
				end)
			end
			self.instances[index] = nil
		end

		self.notifications = {}
		self.brandLabels = {}
		self.popup = nil
		self.slider = nil
		self.warning = nil
		self.base = nil
		self.main = nil
		self.uiScale = nil
		self.top = nil
		self.currentTab = nil
		self.initialized = false
		self.hasInit = false
		self.ready = false

		if env.xanhub == self then
			env.xanhub = nil
		end
		if env.library == self then
			env.library = nil
		end
		if env.uwuware == self then
			env.uwuware = nil
		end
		return true
	end

	library.Destroy = library.Unload

	function library:GetConfigs()
		if not self.capabilities.filesystem then
			return {}
		end

		local ok, result = pcall(function()
			if not isfolder(self.foldername) then
				makefolder(self.foldername)
			end
			local files = {}
			for _, path in next, listfiles(self.foldername) do
				if path:sub(-#self.fileext) == self.fileext then
					local name = path:gsub("\\", "/"):match("([^/]+)$") or path
					name = name:sub(1, #name - #self.fileext)
					table.insert(files, name)
				end
			end
			table.sort(files)
			return files
		end)
		return ok and result or {}
	end

	function library:CreateConfig(config)
		if not self.capabilities.filesystem then return false, "filesystem unavailable" end
		config = tostring(config or ""):gsub("[^%w%-%_ ]", ""):sub(1, 64)
		if config == "" then return false, "invalid config name" end
		local ok, err = pcall(function()
			if not isfolder(self.foldername) then makefolder(self.foldername) end
			writefile(self.foldername .. "/" .. config .. self.fileext, "{}")
		end)
		return ok, err
	end

	function library:DeleteConfig(config)
		if not self.capabilities.deletefile then return false, "deletefile unavailable" end
		config = tostring(config or "")
		local path = self.foldername .. "/" .. config .. self.fileext
		local ok, err = pcall(function()
			if isfile(path) then delfile(path) end
		end)
		return ok, err
	end

	function library:LoadConfig(config)
		if not self.capabilities.filesystem or not table.find(self:GetConfigs(), config) then
			return false
		end

		local ok, Config = pcall(function()
			return httpService:JSONDecode(readfile(self.foldername .. "/" .. config .. self.fileext))
		end)
		if not ok or type(Config) ~= "table" then return false end

		for _, option in next, self.options do
			if option.hasInit and option.type ~= "button" and option.flag and not option.skipflag then
				pcall(function()
					if option.type == "toggle" then
						option:SetState(Config[option.flag] == 1)
					elseif option.type == "color" and Config[option.flag] then
						option:SetColor(Config[option.flag])
						if option.trans and Config[option.flag .. " Transparency"] ~= nil then
							option:SetTrans(Config[option.flag .. " Transparency"])
						end
					elseif option.type == "bind" and Config[option.flag] ~= nil then
						option:SetKey(Config[option.flag])
					elseif Config[option.flag] ~= nil then
						option:SetValue(Config[option.flag])
					end
				end)
			end
		end
		return true
	end

	function library:SaveConfig(config)
		if not self.capabilities.filesystem then return false end
		config = tostring(config or ""):gsub("[^%w%-%_ ]", ""):sub(1, 64)
		if config == "" then return false end

		local Config = {}
		for _, option in next, self.options do
			if option.type ~= "button" and option.flag and not option.skipflag then
				if option.type == "toggle" then
					Config[option.flag] = option.state and 1 or 0
				elseif option.type == "color" then
					Config[option.flag] = {option.color.r, option.color.g, option.color.b}
					if option.trans then Config[option.flag .. " Transparency"] = option.trans end
				elseif option.type == "bind" then
					if option.key ~= "none" then Config[option.flag] = option.key end
				else
					Config[option.flag] = option.value
				end
			end
		end

		local ok = pcall(function()
			if not isfolder(self.foldername) then makefolder(self.foldername) end
			writefile(self.foldername .. "/" .. config .. self.fileext, httpService:JSONEncode(Config))
		end)
		return ok
	end

	library.createLabel = function(option, parent)
		option.main = library:Create("TextLabel", {
			LayoutOrder = option.position,
			Position = UDim2.new(0, 6, 0, 0),
			Size = UDim2.new(1, -12, 0, 24),
			BackgroundTransparency = 1,
			TextSize = 15,
			Font = Enum.Font.Code,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Parent = parent
		})

		setmetatable(option, {__newindex = function(t, i, v)
			if i == "Text" then
				option.main.Text = tostring(v)
				option.main.Size = UDim2.new(1, -12, 0, textService:GetTextSize(option.main.Text, 15, Enum.Font.Code, Vector2.new(option.main.AbsoluteSize.X, 9e9)).Y + 6)
			end
		end})
		option.Text = option.text
	end

	library.createDivider = function(option, parent)
		option.main = library:Create("Frame", {
			LayoutOrder = option.position,
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Parent = parent
		})

		library:Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1, -24, 0, 1),
			BackgroundColor3 = Color3.fromRGB(44, 50, 65),
			BorderColor3 = Color3.new(),
			Parent = option.main
		})

		option.title = library:Create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			BackgroundColor3 = Color3.fromRGB(18, 21, 28),
			BorderSizePixel = 0,
			TextColor3 =  Color3.new(1, 1, 1),
			TextSize = 15,
			Font = Enum.Font.Code,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = option.main
		})

		setmetatable(option, {__newindex = function(t, i, v)
			if i == "Text" then
				if v then
					option.title.Text = tostring(v)
					option.title.Size = UDim2.new(0, textService:GetTextSize(option.title.Text, 15, Enum.Font.Code, Vector2.new(9e9, 9e9)).X + 12, 0, 20)
					option.main.Size = UDim2.new(1, 0, 0, 18)
				else
					option.title.Text = ""
					option.title.Size = UDim2.new()
					option.main.Size = UDim2.new(1, 0, 0, 6)
				end
			end
		end})
		option.Text = option.text
	end

	library.createToggle = function(option, parent)
		option.hasInit = true

		option.main = library:Create("Frame", {
			LayoutOrder = option.position,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Parent = parent
		})

		local tickbox
		local tickboxOverlay
		if option.style then
			tickbox = library:Create("ImageLabel", {
				Position = UDim2.new(0, 6, 0, 4),
				Size = UDim2.new(0, 12, 0, 12),
				BackgroundTransparency = 1,
				Image = "rbxassetid://3570695787",
				ImageColor3 = Color3.new(),
				Parent = option.main
			})

			library:Create("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(1, -2, 1, -2),
				BackgroundTransparency = 1,
				Image = "rbxassetid://3570695787",
				ImageColor3 = Color3.fromRGB(44, 50, 65),
				Parent = tickbox
			})

			library:Create("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(1, -6, 1, -6),
				BackgroundTransparency = 1,
				Image = "rbxassetid://3570695787",
				ImageColor3 = Color3.fromRGB(24, 28, 37),
				Parent = tickbox
			})

			tickboxOverlay = library:Create("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(1, -6, 1, -6),
				BackgroundTransparency = 1,
				Image = "rbxassetid://3570695787",
				ImageColor3 = library.flags["Menu Accent Color"],
				Visible = option.state,
				Parent = tickbox
			})

			library:Create("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Image = "rbxassetid://5941353943",
				ImageTransparency = 0.6,
				Parent = tickbox
			})

			library:AddThemeObject(tickboxOverlay)
		else
			tickbox = library:Create("Frame", {
				Position = UDim2.new(0, 6, 0, 4),
				Size = UDim2.new(0, 12, 0, 12),
				BackgroundColor3 = library.flags["Menu Accent Color"],
				BorderColor3 = Color3.new(),
				Parent = option.main
			})

			tickboxOverlay = library:Create("ImageLabel", {
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = option.state and 1 or 0,
				BackgroundColor3 = Color3.fromRGB(30, 35, 46),
				BorderColor3 = Color3.new(),
				Image = "rbxassetid://4155801252",
				ImageTransparency = 0.6,
				ImageColor3 = Color3.new(),
				Parent = tickbox
			})

			library:Create("ImageLabel", {
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Image = "rbxassetid://2592362371",
				ImageColor3 = Color3.fromRGB(44, 50, 65),
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = Rect.new(2, 2, 62, 62),
				Parent = tickbox
			})

			library:Create("ImageLabel", {
				Size = UDim2.new(1, -2, 1, -2),
				Position = UDim2.new(0, 1, 0, 1),
				BackgroundTransparency = 1,
				Image = "rbxassetid://2592362371",
				ImageColor3 = Color3.new(),
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = Rect.new(2, 2, 62, 62),
				Parent = tickbox
			})

			library:AddThemeObject(tickbox)
		end

		option.interest = library:Create("Frame", {
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Parent = option.main
		})

		option.title = library:Create("TextLabel", {
			Position = UDim2.new(0, 24, 0, 0),
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = option.text,
			TextColor3 =  option.state and Color3.fromRGB(210, 210, 210) or Color3.fromRGB(180, 180, 180),
			TextSize = 15,
			Font = Enum.Font.Code,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = option.interest
		})

		option.interest.InputBegan:Connect(function(input)
			if input.UserInputType.Name == "MouseButton1" then
				option:SetState(not option.state)
			end
			if input.UserInputType.Name == "MouseMovement" then
				if not library.warning and not library.slider then
					if option.style then
						tickbox.ImageColor3 = library.flags["Menu Accent Color"]
					else
						tickbox.BorderColor3 = library.flags["Menu Accent Color"]
						tickboxOverlay.BorderColor3 = library.flags["Menu Accent Color"]
					end
				end
				if option.tip then
					library.tooltip.Text = option.tip
					library.tooltip.Size = UDim2.new(0, textService:GetTextSize(option.tip, 15, Enum.Font.Code, Vector2.new(9e9, 9e9)).X, 0, 20)
				end
			end
		end)

		option.interest.InputChanged:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				if option.tip then
					library.tooltip.Position = UDim2.new(0, input.Position.X + 26, 0, input.Position.Y + 36)
				end
			end
		end)

		option.interest.InputEnded:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				if option.style then
					tickbox.ImageColor3 = Color3.new()
				else
					tickbox.BorderColor3 = Color3.new()
					tickboxOverlay.BorderColor3 = Color3.new()
				end
				library.tooltip.Position = UDim2.new(2)
			end
		end)

		function option:SetState(state, nocallback)
			state = typeof(state) == "boolean" and state
			state = state or false
			library.flags[self.flag] = state
			self.state = state
			option.title.TextColor3 = state and Color3.fromRGB(210, 210, 210) or Color3.fromRGB(160, 160, 160)
			if option.style then
				tickboxOverlay.Visible = state
			else
				tickboxOverlay.BackgroundTransparency = state and 1 or 0
			end
			if not nocallback then
				library:Invoke(self.callback, state)
			end
		end

		if option.state ~= nil then
			task.defer(function()
				if library and not library.unloaded then
					library:Invoke(option.callback, option.state)
				end
			end)
		end

		setmetatable(option, {__newindex = function(t, i, v)
			if i == "Text" then
				option.title.Text = tostring(v)
			end
		end})
	end

	library.createButton = function(option, parent)
		option.hasInit = true

		option.main = library:Create("Frame", {
			LayoutOrder = option.position,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			Parent = parent
		})

		option.title = library:Create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -5),
			Size = UDim2.new(1, -12, 0, 20),
			BackgroundColor3 = Color3.fromRGB(30, 35, 46),
			BorderColor3 = Color3.new(),
			Text = option.text,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 15,
			Font = Enum.Font.Code,
			Parent = option.main
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.fromRGB(44, 50, 65),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.title
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, -2, 1, -2),
			Position = UDim2.new(0, 1, 0, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.new(),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.title
		})

		library:Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 180, 180)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(253, 253, 253)),
			}),
			Rotation = -90,
			Parent = option.title
		})

		option.title.InputBegan:Connect(function(input)
			if input.UserInputType.Name == "MouseButton1" then
				library:Invoke(option.callback)
				if library and not library.unloaded then
					library.flags[option.flag] = true
				end
				if option.tip then
					library.tooltip.Text = option.tip
					library.tooltip.Size = UDim2.new(0, textService:GetTextSize(option.tip, 15, Enum.Font.Code, Vector2.new(9e9, 9e9)).X, 0, 20)
				end
			end
			if input.UserInputType.Name == "MouseMovement" then
				if not library.warning and not library.slider then
					option.title.BorderColor3 = library.flags["Menu Accent Color"]
				end
			end
		end)

		option.title.InputChanged:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				if option.tip then
					library.tooltip.Position = UDim2.new(0, input.Position.X + 26, 0, input.Position.Y + 36)
				end
			end
		end)

		option.title.InputEnded:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				option.title.BorderColor3 = Color3.new()
				library.tooltip.Position = UDim2.new(2)
			end
		end)
	end

	library.createBind = function(option, parent)
		option.hasInit = true

		local binding
		local holding
		local Loop

		if option.sub then
			option.main = option:getMain()
		else
			option.main = option.main or library:Create("Frame", {
				LayoutOrder = option.position,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Parent = parent
			})

			library:Create("TextLabel", {
				Position = UDim2.new(0, 6, 0, 0),
				Size = UDim2.new(1, -12, 1, 0),
				BackgroundTransparency = 1,
				Text = option.text,
				TextSize = 15,
				Font = Enum.Font.Code,
				TextColor3 = Color3.fromRGB(210, 210, 210),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = option.main
			})
		end

		local bindinput = library:Create(option.sub and "TextButton" or "TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6 - (option.subpos or 0), 0, option.sub and 2 or 3),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			BackgroundColor3 = Color3.fromRGB(18, 21, 28),
			BorderSizePixel = 0,
			TextSize = 15,
			Font = Enum.Font.Code,
			TextColor3 = Color3.fromRGB(160, 160, 160),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = option.main
		})

		if option.sub then
			bindinput.AutoButtonColor = false
		end

		local interest = option.sub and bindinput or option.main
		local inContact
		interest.InputEnded:Connect(function(input)
			if input.UserInputType.Name == "MouseButton1" then
				binding = true
				bindinput.Text = "[...]"
				bindinput.Size = UDim2.new(0, textService:GetTextSize(bindinput.Text, 16, Enum.Font.Code, Vector2.new(9e9, 9e9)).X, 0, 16)
				bindinput.TextColor3 = library.flags["Menu Accent Color"]
			end
		end)

		library:AddConnection(inputService.InputBegan, function(input)
			if inputService:GetFocusedTextBox() then return end
			if binding then
				local key = (table.find(whitelistedMouseinputs, input.UserInputType) and not option.nomouse) and input.UserInputType
				option:SetKey(key or (not table.find(blacklistedKeys, input.KeyCode)) and input.KeyCode)
			else
				if (input.KeyCode.Name == option.key or input.UserInputType.Name == option.key) and not binding then
					if option.mode == "toggle" then
						library.flags[option.flag] = not library.flags[option.flag]
						library:Invoke(option.callback, library.flags[option.flag], 0)
					else
						library.flags[option.flag] = true
						if Loop then
							Loop:Disconnect()
							Loop = nil
						end
						library:Invoke(option.callback, true, 0)
						Loop = library:AddConnection(runService.RenderStepped, function(step)
							if not inputService:GetFocusedTextBox() then
								library:Invoke(option.callback, nil, step)
							end
						end)
					end
				end
			end
		end)

		library:AddConnection(inputService.InputEnded, function(input)
			if option.key ~= "none" then
				if input.KeyCode.Name == option.key or input.UserInputType.Name == option.key then
					if Loop then
						Loop:Disconnect()
						Loop = nil
						library.flags[option.flag] = false
						library:Invoke(option.callback, false, 0)
					end
				end
			end
		end)

		function option:SetKey(key)
			binding = false
			bindinput.TextColor3 = Color3.fromRGB(160, 160, 160)
			if Loop then
				Loop:Disconnect()
				Loop = nil
				library.flags[option.flag] = false
				library:Invoke(option.callback, false, 0)
			end
			self.key = (key and key.Name) or key or self.key
			if self.key == "Backspace" then
				self.key = "none"
				bindinput.Text = "[NONE]"
			else
				local a = self.key
				if self.key:match"Mouse" then
					a = self.key:gsub("Button", ""):gsub("Mouse", "M")
				elseif self.key:match"Shift" or self.key:match"Alt" or self.key:match"Control" then
					a = self.key:gsub("Left", "L"):gsub("Right", "R")
				end
				bindinput.Text = "[" .. a:gsub("Control", "CTRL"):upper() .. "]"
			end
			bindinput.Size = UDim2.new(0, textService:GetTextSize(bindinput.Text, 16, Enum.Font.Code, Vector2.new(9e9, 9e9)).X, 0, 16)
		end
		option:SetKey()
	end

	local function setSliderFill(option, value)
		local minimum = tonumber(option.min) or 0
		local maximum = tonumber(option.max) or minimum + 1
		if maximum <= minimum then
			maximum = minimum + 1
		end
		local range = maximum - minimum
		local valueAlpha = math.clamp((value - minimum) / range, 0, 1)
		local zeroAlpha
		if minimum >= 0 then
			zeroAlpha = 0
		elseif maximum <= 0 then
			zeroAlpha = 1
		else
			zeroAlpha = math.clamp((0 - minimum) / range, 0, 1)
		end
		local left = math.min(valueAlpha, zeroAlpha)
		local width = math.abs(valueAlpha - zeroAlpha)
		library:SafeTween(option.fill, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(left, 0, 0, 0),
			Size = UDim2.new(width, 0, 1, 0),
		})
	end

	library.createSlider = function(option, parent)
		option.hasInit = true

		if option.sub then
			option.main = option:getMain()
			option.main.Size = UDim2.new(1, 0, 0, 42)
		else
			option.main = library:Create("Frame", {
				LayoutOrder = option.position,
				Size = UDim2.new(1, 0, 0, option.textpos and 24 or 40),
				BackgroundTransparency = 1,
				Parent = parent
			})
		end

		option.slider = library:Create("Frame", {
			Position = UDim2.new(0, 6, 0, (option.sub and 22 or option.textpos and 4 or 20)),
			Size = UDim2.new(1, -12, 0, 16),
			BackgroundColor3 = Color3.fromRGB(30, 35, 46),
			BorderColor3 = Color3.new(),
			Parent = option.main
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2454009026",
			ImageColor3 = Color3.new(),
			ImageTransparency = 0.8,
			Parent = option.slider
		})

		option.fill = library:Create("Frame", {
			BackgroundColor3 = library.flags["Menu Accent Color"],
			BorderSizePixel = 0,
			Parent = option.slider
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.fromRGB(44, 50, 65),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.slider
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, -2, 1, -2),
			Position = UDim2.new(0, 1, 0, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.new(),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.slider
		})

		option.title = library:Create("TextBox", {
			Position = UDim2.new(0, (option.sub or option.textpos) and 0 or 6, 0, 0),
			Size = UDim2.new(1, (option.sub or option.textpos) and 0 or -12, 0, (option.sub or option.textpos) and 14 or 18),
			BackgroundTransparency = 1,
			Text = (option.text == "nil" and "" or option.text .. ": ") .. option.value .. option.suffix,
			TextSize = (option.sub or option.textpos) and 14 or 15,
			Font = Enum.Font.Code,
			TextColor3 = Color3.fromRGB(210, 210, 210),
			TextXAlignment = Enum.TextXAlignment[(option.sub or option.textpos) and "Center" or "Left"],
			Parent = (option.sub or option.textpos) and option.slider or option.main
		})
		library:AddThemeObject(option.fill)

		library:Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(115, 115, 115)),
				ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
			}),
			Rotation = -90,
			Parent = option.fill
		})

		setSliderFill(option, option.value)

		local manualInput
		option.title.Focused:Connect(function()
			if manualInput then
				option.title.Text = tostring(option.value)
				option.title.CursorPosition = #option.title.Text + 1
			else
				option.title:ReleaseFocus()
				option.title.Text = (option.text == "nil" and "" or option.text .. ": ") .. option.value .. option.suffix
			end
		end)

		option.title.FocusLost:Connect(function()
			option.slider.BorderColor3 = Color3.new()
			if manualInput then
				if tonumber(option.title.Text) then
					option:SetValue(tonumber(option.title.Text))
				else
					option.title.Text = (option.text == "nil" and "" or option.text .. ": ") .. option.value .. option.suffix
				end
			end
			manualInput = false
		end)

		local interest = (option.sub or option.textpos) and option.slider or option.main
		interest.InputBegan:Connect(function(input)
			if input.UserInputType.Name == "MouseButton1" then
				if inputService:IsKeyDown(Enum.KeyCode.LeftControl) or inputService:IsKeyDown(Enum.KeyCode.RightControl) then
					manualInput = true
					option.title:CaptureFocus()
				else
					library.slider = option
					option.slider.BorderColor3 = library.flags["Menu Accent Color"]
					local width = option.slider.AbsoluteSize.X
					if width > 0 then
						option:SetValue(option.min + ((input.Position.X - option.slider.AbsolutePosition.X) / width) * (option.max - option.min))
					end
				end
			end
			if input.UserInputType.Name == "MouseMovement" then
				if not library.warning and not library.slider then
					option.slider.BorderColor3 = library.flags["Menu Accent Color"]
				end
				if option.tip then
					library.tooltip.Text = option.tip
					library.tooltip.Size = UDim2.new(0, textService:GetTextSize(option.tip, 15, Enum.Font.Code, Vector2.new(9e9, 9e9)).X, 0, 20)
				end
			end
		end)

		interest.InputChanged:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				if option.tip then
					library.tooltip.Position = UDim2.new(0, input.Position.X + 26, 0, input.Position.Y + 36)
				end
			end
		end)

		interest.InputEnded:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				library.tooltip.Position = UDim2.new(2)
				if option ~= library.slider then
					option.slider.BorderColor3 = Color3.new()
					--option.fill.BorderColor3 = Color3.new()
				end
			end
		end)

		function option:SetValue(value, nocallback)
			if typeof(value) ~= "number" then value = self.value or self.min end
			value = library.round(value, option.float)
			value = math.clamp(value, self.min, self.max)
			setSliderFill(option, value)
			library.flags[self.flag] = value
			self.value = value
			option.title.Text = (option.text == "nil" and "" or option.text .. ": ") .. option.value .. option.suffix
			if not nocallback then
				library:Invoke(self.callback, value)
			end
		end
		task.defer(function()
			if library and not library.unloaded then
				option:SetValue(option.value)
			end
		end)
	end

	library.createList = function(option, parent)
		option.hasInit = true

		if option.sub then
			option.main = option:getMain()
			option.main.Size = UDim2.new(1, 0, 0, 48)
		else
			option.main = library:Create("Frame", {
				LayoutOrder = option.position,
				Size = UDim2.new(1, 0, 0, option.text == "nil" and 30 or 48),
				BackgroundTransparency = 1,
				Parent = parent
			})

			if option.text ~= "nil" then
				library:Create("TextLabel", {
					Position = UDim2.new(0, 6, 0, 0),
					Size = UDim2.new(1, -12, 0, 18),
					BackgroundTransparency = 1,
					Text = option.text,
					TextSize = 15,
					Font = Enum.Font.Code,
					TextColor3 = Color3.fromRGB(210, 210, 210),
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = option.main
				})
			end
		end

		local function getMultiText()
			local s = ""
			for _, value in next, option.values do
				s = s .. (option.value[value] and (tostring(value) .. ", ") or "")
			end
			return string.sub(s, 1, #s - 2)
		end

		option.listvalue = library:Create("TextLabel", {
			Position = UDim2.new(0, 6, 0, (option.text == "nil" and not option.sub) and 4 or 22),
			Size = UDim2.new(1, -12, 0, 22),
			BackgroundColor3 = Color3.fromRGB(30, 35, 46),
			BorderColor3 = Color3.new(),
			Text = " " .. (typeof(option.value) == "string" and option.value or getMultiText()),
			TextSize = 15,
			Font = Enum.Font.Code,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = option.main
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2454009026",
			ImageColor3 = Color3.new(),
			ImageTransparency = 0.8,
			Parent = option.listvalue
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.fromRGB(44, 50, 65),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.listvalue
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, -2, 1, -2),
			Position = UDim2.new(0, 1, 0, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.new(),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.listvalue
		})

		option.arrow = library:Create("ImageLabel", {
			Position = UDim2.new(1, -16, 0, 7),
			Size = UDim2.new(0, 8, 0, 8),
			Rotation = 90,
			BackgroundTransparency = 1,
			Image = "rbxassetid://4918373417",
			ImageColor3 = Color3.new(1, 1, 1),
			ScaleType = Enum.ScaleType.Fit,
			ImageTransparency = 0.4,
			Parent = option.listvalue
		})

		option.holder = library:Create("TextButton", {
			ZIndex = 4,
			BackgroundColor3 = Color3.fromRGB(24, 28, 37),
			BorderColor3 = Color3.new(),
			Text = "",
			AutoButtonColor = false,
			Visible = false,
			Parent = library.base
		})

		option.content = library:Create("ScrollingFrame", {
			ZIndex = 4,
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarImageColor3 = Color3.new(),
			ScrollBarThickness = 3,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			VerticalScrollBarInset = Enum.ScrollBarInset.Always,
			TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
			BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
			Parent = option.holder
		})

		library:Create("ImageLabel", {
			ZIndex = 4,
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.fromRGB(44, 50, 65),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.holder
		})

		library:Create("ImageLabel", {
			ZIndex = 4,
			Size = UDim2.new(1, -2, 1, -2),
			Position = UDim2.new(0, 1, 0, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.new(),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.holder
		})

		local layout = library:Create("UIListLayout", {
			Padding = UDim.new(0, 2),
			Parent = option.content
		})

		library:Create("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 4),
			Parent = option.content
		})

		local valueCount = 0
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			option.holder.Size = UDim2.new(0, option.listvalue.AbsoluteSize.X, 0, 8 + (valueCount > option.max and (-2 + (option.max * 22)) or layout.AbsoluteContentSize.Y))
			option.content.CanvasSize = UDim2.new(0, 0, 0, 8 + layout.AbsoluteContentSize.Y)
		end)
		local interest = option.sub and option.listvalue or option.main

		option.listvalue.InputBegan:Connect(function(input)
			if input.UserInputType.Name == "MouseButton1" then
				if library.popup == option then library.popup:Close() return end
				if library.popup then
					library.popup:Close()
				end
				option.arrow.Rotation = -90
				option.open = true
				option.holder.Visible = true
				local pos = option.main.AbsolutePosition
				option.holder.Position = UDim2.new(0, pos.X + 6, 0, pos.Y + ((option.text == "nil" and not option.sub) and 66 or 84))
				library.popup = option
				option.listvalue.BorderColor3 = library.flags["Menu Accent Color"]
			end
			if input.UserInputType.Name == "MouseMovement" then
				if not library.warning and not library.slider then
					option.listvalue.BorderColor3 = library.flags["Menu Accent Color"]
				end
			end
		end)

		option.listvalue.InputEnded:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				if not option.open then
					option.listvalue.BorderColor3 = Color3.new()
				end
			end
		end)

		interest.InputBegan:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				if option.tip then
					library.tooltip.Text = option.tip
					library.tooltip.Size = UDim2.new(0, textService:GetTextSize(option.tip, 15, Enum.Font.Code, Vector2.new(9e9, 9e9)).X, 0, 20)
				end
			end
		end)

		interest.InputChanged:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				if option.tip then
					library.tooltip.Position = UDim2.new(0, input.Position.X + 26, 0, input.Position.Y + 36)
				end
			end
		end)

		interest.InputEnded:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				library.tooltip.Position = UDim2.new(2)
			end
		end)

		local selected
		function option:AddValue(value, state)
			value = tostring(value)
			if self.labels[value] then return end
			valueCount = valueCount + 1

			if not table.find(self.values, value) then
				table.insert(self.values, value)
			end
			if self.multiselect and self.value[value] == nil then
				self.value[value] = state == true
			end

			local label = library:Create("TextLabel", {
				ZIndex = 4,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = value,
				TextSize = 15,
				Font = Enum.Font.Code,
				TextTransparency = self.multiselect and (self.value[value] and 1 or 0) or self.value == value and 1 or 0,
				TextColor3 = Color3.fromRGB(210, 210, 210),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = option.content
			})
			self.labels[value] = label

			local labelOverlay = library:Create("TextLabel", {
				ZIndex = 4,	
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 0.8,
				Text = " " ..value,
				TextSize = 15,
				Font = Enum.Font.Code,
				TextColor3 = library.flags["Menu Accent Color"],
				TextXAlignment = Enum.TextXAlignment.Left,
				Visible = self.multiselect and self.value[value] or self.value == value,
				Parent = label
			})
			selected = selected or (self.value == value and label)
			library:AddThemeObject(labelOverlay)

			label.InputBegan:Connect(function(input)
				if input.UserInputType.Name == "MouseButton1" then
					if self.multiselect then
						self.value[value] = not self.value[value]
						self:SetValue(self.value)
					else
						self:SetValue(value)
						self:Close()
					end
				end
			end)
		end

		for i, value in next, option.values do
			option:AddValue(tostring(typeof(i) == "number" and value or i))
		end

		function option:RemoveValue(value)
			local label = self.labels[value]
			if label then
				label:Destroy()
				self.labels[value] = nil
				valueCount = valueCount - 1
				local valueIndex = table.find(self.values, value)
				if valueIndex then
					table.remove(self.values, valueIndex)
				end
				if self.multiselect then
					self.value[value] = nil
					self:SetValue(self.value)
				else
					if self.value == value then
						selected = nil
						self:SetValue(self.values[1] or "")
					end
				end
			end
		end

		function option:SetValue(value, nocallback)
			if self.multiselect and typeof(value) ~= "table" then
				value = {}
				for i,v in next, self.values do
					value[v] = false
				end
			end
			if typeof(value) == "table" then
				self.value = value
			else
				local selectedValue = table.find(self.values, value) and value or self.values[1] or ""
				self.value = tostring(selectedValue)
			end
			library.flags[self.flag] = self.value
			option.listvalue.Text = " " .. (self.multiselect and getMultiText() or self.value)
			if self.multiselect then
				for name, label in next, self.labels do
					label.TextTransparency = self.value[name] and 1 or 0
					if label:FindFirstChild"TextLabel" then
						label.TextLabel.Visible = self.value[name]
					end
				end
			else
				if selected then
					selected.TextTransparency = 0
					if selected:FindFirstChild"TextLabel" then
						selected.TextLabel.Visible = false
					end
				end
				if self.labels[self.value] then
					selected = self.labels[self.value]
					selected.TextTransparency = 1
					if selected:FindFirstChild"TextLabel" then
						selected.TextLabel.Visible = true
					end
				end
			end
			if not nocallback then
				library:Invoke(self.callback, self.value)
			end
		end
		task.defer(function()
			if library and not library.unloaded then
				option:SetValue(option.value)
			end
		end)

		function option:Close()
			library.popup = nil
			option.arrow.Rotation = 90
			self.open = false
			option.holder.Visible = false
			option.listvalue.BorderColor3 = Color3.new()
		end

		return option
	end

	library.createBox = function(option, parent)
		option.hasInit = true

		option.main = library:Create("Frame", {
			LayoutOrder = option.position,
			Size = UDim2.new(1, 0, 0, option.text == "nil" and 28 or 44),
			BackgroundTransparency = 1,
			Parent = parent
		})

		if option.text ~= "nil" then
			option.title = library:Create("TextLabel", {
				Position = UDim2.new(0, 6, 0, 0),
				Size = UDim2.new(1, -12, 0, 18),
				BackgroundTransparency = 1,
				Text = option.text,
				TextSize = 15,
				Font = Enum.Font.Code,
				TextColor3 = Color3.fromRGB(210, 210, 210),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = option.main
			})
		end

		option.holder = library:Create("Frame", {
			Position = UDim2.new(0, 6, 0, option.text == "nil" and 4 or 20),
			Size = UDim2.new(1, -12, 0, 20),
			BackgroundColor3 = Color3.fromRGB(30, 35, 46),
			BorderColor3 = Color3.new(),
			Parent = option.main
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2454009026",
			ImageColor3 = Color3.new(),
			ImageTransparency = 0.8,
			Parent = option.holder
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.fromRGB(44, 50, 65),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.holder
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, -2, 1, -2),
			Position = UDim2.new(0, 1, 0, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.new(),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.holder
		})

		local inputvalue = library:Create("TextBox", {
			Position = UDim2.new(0, 4, 0, 0),
			Size = UDim2.new(1, -4, 1, 0),
			BackgroundTransparency = 1,
			Text = "  " .. option.value,
			TextSize = 15,
			Font = Enum.Font.Code,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			ClearTextOnFocus = false,
			Parent = option.holder
		})

		inputvalue.FocusLost:Connect(function(enter)
			option.holder.BorderColor3 = Color3.new()
			option:SetValue(inputvalue.Text, enter)
		end)

		inputvalue.Focused:Connect(function()
			option.holder.BorderColor3 = library.flags["Menu Accent Color"]
		end)

		inputvalue.InputBegan:Connect(function(input)
			if input.UserInputType.Name == "MouseButton1" then
				inputvalue.Text = ""
			end
			if input.UserInputType.Name == "MouseMovement" then
				if not library.warning and not library.slider then
					option.holder.BorderColor3 = library.flags["Menu Accent Color"]
				end
				if option.tip then
					library.tooltip.Text = option.tip
					library.tooltip.Size = UDim2.new(0, textService:GetTextSize(option.tip, 15, Enum.Font.Code, Vector2.new(9e9, 9e9)).X, 0, 20)
				end
			end
		end)

		inputvalue.InputChanged:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				if option.tip then
					library.tooltip.Position = UDim2.new(0, input.Position.X + 26, 0, input.Position.Y + 36)
				end
			end
		end)

		inputvalue.InputEnded:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				if not inputvalue:IsFocused() then
					option.holder.BorderColor3 = Color3.new()
				end
				library.tooltip.Position = UDim2.new(2)
			end
		end)

		function option:SetValue(value, enter)
			if tostring(value) == "" then
				inputvalue.Text = self.value
			else
				library.flags[self.flag] = tostring(value)
				self.value = tostring(value)
				inputvalue.Text = self.value
				library:Invoke(self.callback, value, enter)
			end
		end
		task.defer(function()
			if library and not library.unloaded then
				option:SetValue(option.value)
			end
		end)
	end

	library.createColorPickerWindow = function(option)
		option.mainHolder = library:Create("TextButton", {
			ZIndex = 4,
			--Position = UDim2.new(1, -184, 1, 6),
			Size = UDim2.new(0, option.trans and 200 or 184, 0, 264),
			BackgroundColor3 = Color3.fromRGB(24, 28, 37),
			BorderColor3 = Color3.new(),
			AutoButtonColor = false,
			Visible = false,
			Parent = library.base
		})

		option.rgbBox = library:Create("Frame", {
			Position = UDim2.new(0, 6, 0, 214),
			Size = UDim2.new(0, (option.mainHolder.AbsoluteSize.X - 12), 0, 20),
			BackgroundColor3 = Color3.fromRGB(57, 57, 57),
			BorderColor3 = Color3.new(),
			ZIndex = 5;
			Parent = option.mainHolder
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2454009026",
			ImageColor3 = Color3.new(),
			ImageTransparency = 0.8,
			ZIndex = 6;
			Parent = option.rgbBox
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.fromRGB(44, 50, 65),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			ZIndex = 6;
			Parent = option.rgbBox
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, -2, 1, -2),
			Position = UDim2.new(0, 1, 0, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.new(),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			ZIndex = 6;
			Parent = option.rgbBox
		})

		option.rgbInput = library:Create("TextBox", {
			Position = UDim2.new(0, 4, 0, 0),
			Size = UDim2.new(1, -4, 1, 0),
			BackgroundTransparency = 1,
			Text = tostring(option.color),
			TextSize = 14,
			Font = Enum.Font.Code,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			ClearTextOnFocus = false,
			ZIndex = 6;
			Parent = option.rgbBox
		})

		option.hexBox = option.rgbBox:Clone()
		option.hexBox.Position = UDim2.new(0, 6, 0, 238)
		-- option.hexBox.Size = UDim2.new(0, (option.mainHolder.AbsoluteSize.X/2 - 10), 0, 20)
		option.hexBox.Parent = option.mainHolder
		option.hexInput = option.hexBox.TextBox;

		library:Create("ImageLabel", {
			ZIndex = 4,
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.fromRGB(44, 50, 65),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.mainHolder
		})

		library:Create("ImageLabel", {
			ZIndex = 4,
			Size = UDim2.new(1, -2, 1, -2),
			Position = UDim2.new(0, 1, 0, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.new(),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.mainHolder
		})

		local hue, sat, val = Color3.toHSV(option.color)
		hue, sat, val = hue == 0 and 1 or hue, sat + 0.005, val - 0.005
		local editinghue
		local editingsatval
		local editingtrans

		local transMain
		if option.trans then
			transMain = library:Create("ImageLabel", {
				ZIndex = 5,
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Image = "rbxassetid://2454009026",
				ImageColor3 = Color3.fromHSV(hue, 1, 1),
				Rotation = 180,
				Parent = library:Create("ImageLabel", {
					ZIndex = 4,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -6, 0, 6),
					Size = UDim2.new(0, 10, 1, -60),
					BorderColor3 = Color3.new(),
					Image = "rbxassetid://4632082392",
					ScaleType = Enum.ScaleType.Tile,
					TileSize = UDim2.new(0, 5, 0, 5),
					Parent = option.mainHolder
				})
			})

			option.transSlider = library:Create("Frame", {
				ZIndex = 5,
				Position = UDim2.new(0, 0, option.trans, 0),
				Size = UDim2.new(1, 0, 0, 2),
				BackgroundColor3 = Color3.fromRGB(38, 41, 65),
				BorderColor3 = Color3.fromRGB(255, 255, 255),
				Parent = transMain
			})

			transMain.InputBegan:Connect(function(Input)
				if Input.UserInputType.Name == "MouseButton1" then
					editingtrans = true
					option:SetTrans(1 - ((Input.Position.Y - transMain.AbsolutePosition.Y) / transMain.AbsoluteSize.Y))
				end
			end)

			transMain.InputEnded:Connect(function(Input)
				if Input.UserInputType.Name == "MouseButton1" then
					editingtrans = false
				end
			end)
		end

		local hueMain = library:Create("Frame", {
			ZIndex = 4,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 6, 1, -54),
			Size = UDim2.new(1, option.trans and -28 or -12, 0, 10),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderColor3 = Color3.new(),
			Parent = option.mainHolder
		})

		local Gradient = library:Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 0, 255)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 0, 255)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 255, 0)),
				ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
			}),
			Parent = hueMain
		})

		local hueSlider = library:Create("Frame", {
			ZIndex = 4,
			Position = UDim2.new(1 - hue, 0, 0, 0),
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = Color3.fromRGB(38, 41, 65),
			BorderColor3 = Color3.fromRGB(255, 255, 255),
			Parent = hueMain
		})

		hueMain.InputBegan:Connect(function(Input)
			if Input.UserInputType.Name == "MouseButton1" then
				editinghue = true
				local width = math.max(hueMain.AbsoluteSize.X, 1)
				local x = math.clamp((Input.Position.X - hueMain.AbsolutePosition.X) / width, 0, 0.995)
				option:SetColor(Color3.fromHSV(1 - x, sat, val))
			end
		end)

		hueMain.InputEnded:Connect(function(Input)
			if Input.UserInputType.Name == "MouseButton1" then
				editinghue = false
			end
		end)

		local satval = library:Create("ImageLabel", {
			ZIndex = 4,
			Position = UDim2.new(0, 6, 0, 6),
			Size = UDim2.new(1, option.trans and -28 or -12, 1, -74),
			BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
			BorderColor3 = Color3.new(),
			Image = "rbxassetid://4155801252",
			ClipsDescendants = true,
			Parent = option.mainHolder
		})

		local satvalSlider = library:Create("Frame", {
			ZIndex = 4,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(sat, 0, 1 - val, 0),
			Size = UDim2.new(0, 4, 0, 4),
			Rotation = 45,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			Parent = satval
		})

		satval.InputBegan:Connect(function(Input)
			if Input.UserInputType.Name == "MouseButton1" then
				editingsatval = true
				local width = math.max(satval.AbsoluteSize.X, 1)
				local height = math.max(satval.AbsoluteSize.Y, 1)
				local x = math.clamp((Input.Position.X - satval.AbsolutePosition.X) / width, 0.005, 1)
				local y = math.clamp((Input.Position.Y - satval.AbsolutePosition.Y) / height, 0, 0.995)
				option:SetColor(Color3.fromHSV(hue, x, 1 - y))
			end
		end)

		library:AddConnection(inputService.InputChanged, function(Input)
			if Input.UserInputType.Name == "MouseMovement" then
				if editingsatval then
					local width = math.max(satval.AbsoluteSize.X, 1)
					local height = math.max(satval.AbsoluteSize.Y, 1)
					local x = math.clamp((Input.Position.X - satval.AbsolutePosition.X) / width, 0.005, 1)
					local y = math.clamp((Input.Position.Y - satval.AbsolutePosition.Y) / height, 0, 0.995)
					option:SetColor(Color3.fromHSV(hue, x, 1 - y))
				elseif editinghue then
					local width = math.max(hueMain.AbsoluteSize.X, 1)
					local x = math.clamp((Input.Position.X - hueMain.AbsolutePosition.X) / width, 0, 0.995)
					option:SetColor(Color3.fromHSV(1 - x, sat, val))
				elseif editingtrans and transMain then
					local height = math.max(transMain.AbsoluteSize.Y, 1)
					option:SetTrans(1 - ((Input.Position.Y - transMain.AbsolutePosition.Y) / height))
				end
			end
		end)

		satval.InputEnded:Connect(function(Input)
			if Input.UserInputType.Name == "MouseButton1" then
				editingsatval = false
			end
		end)

		local r, g, b = library.round(option.color)
		option.hexInput.Text = string.format("#%02x%02x%02x", r, g, b)
		option.rgbInput.Text = table.concat({r, g, b}, ",")

		option.rgbInput.FocusLost:Connect(function()
			local r, g, b = option.rgbInput.Text:gsub("%s+", ""):match("(%d+),(%d+),(%d+)")
			if r and g and b then
				local red = math.clamp(tonumber(r) or 0, 0, 255)
				local green = math.clamp(tonumber(g) or 0, 0, 255)
				local blue = math.clamp(tonumber(b) or 0, 0, 255)
				return option:SetColor(Color3.fromRGB(red, green, blue))
			end

			local r, g, b = library.round(option.color)
			option.rgbInput.Text = table.concat({r, g, b}, ",")
		end)

		option.hexInput.FocusLost:Connect(function()
			local r, g, b = option.hexInput.Text:match("#?(..)(..)(..)")
			if r and g and b then
				local red = tonumber(r, 16)
				local green = tonumber(g, 16)
				local blue = tonumber(b, 16)
				if red and green and blue then
					return option:SetColor(Color3.fromRGB(red, green, blue))
				end
			end

			local r, g, b = library.round(option.color)
			option.hexInput.Text = string.format("#%02x%02x%02x", r, g, b)
		end)

		function option:updateVisuals(Color)
			hue, sat, val = Color3.toHSV(Color)
			hue = hue == 0 and 1 or hue
			satval.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
			if option.trans then
				transMain.ImageColor3 = Color3.fromHSV(hue, 1, 1)
			end
			hueSlider.Position = UDim2.new(1 - hue, 0, 0, 0)
			satvalSlider.Position = UDim2.new(sat, 0, 1 - val, 0)

			local r, g, b = library.round(Color3.fromHSV(hue, sat, val))

			option.hexInput.Text = string.format("#%02x%02x%02x", r, g, b)
			option.rgbInput.Text = table.concat({r, g, b}, ",")
		end

		return option
	end

	library.createColor = function(option, parent)
		option.hasInit = true

		if option.sub then
			option.main = option:getMain()
		else
			option.main = library:Create("Frame", {
				LayoutOrder = option.position,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Parent = parent
			})

			option.title = library:Create("TextLabel", {
				Position = UDim2.new(0, 6, 0, 0),
				Size = UDim2.new(1, -12, 1, 0),
				BackgroundTransparency = 1,
				Text = option.text,
				TextSize = 15,
				Font = Enum.Font.Code,
				TextColor3 = Color3.fromRGB(210, 210, 210),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = option.main
			})
		end

		option.visualize = library:Create(option.sub and "TextButton" or "Frame", {
			Position = UDim2.new(1, -(option.subpos or 0) - 24, 0, 4),
			Size = UDim2.new(0, 18, 0, 12),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			BackgroundColor3 = option.color,
			BorderColor3 = Color3.new(),
			Parent = option.main
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2454009026",
			ImageColor3 = Color3.new(),
			ImageTransparency = 0.6,
			Parent = option.visualize
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.fromRGB(44, 50, 65),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.visualize
		})

		library:Create("ImageLabel", {
			Size = UDim2.new(1, -2, 1, -2),
			Position = UDim2.new(0, 1, 0, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2592362371",
			ImageColor3 = Color3.new(),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(2, 2, 62, 62),
			Parent = option.visualize
		})

		local interest = option.sub and option.visualize or option.main

		if option.sub then
			option.visualize.Text = ""
			option.visualize.AutoButtonColor = false
		end

		interest.InputBegan:Connect(function(input)
			if input.UserInputType.Name == "MouseButton1" then
				if not option.mainHolder then library.createColorPickerWindow(option) end
				if library.popup == option then library.popup:Close() return end
				if library.popup then library.popup:Close() end
				option.open = true
				local pos = option.main.AbsolutePosition
				option.mainHolder.Position = UDim2.new(0, pos.X + 36 + (option.trans and -16 or 0), 0, pos.Y + 56)
				option.mainHolder.Visible = true
				library.popup = option
				option.visualize.BorderColor3 = library.flags["Menu Accent Color"]
			end
			if input.UserInputType.Name == "MouseMovement" then
				if not library.warning and not library.slider then
					option.visualize.BorderColor3 = library.flags["Menu Accent Color"]
				end
				if option.tip then
					library.tooltip.Text = option.tip
					library.tooltip.Size = UDim2.new(0, textService:GetTextSize(option.tip, 15, Enum.Font.Code, Vector2.new(9e9, 9e9)).X, 0, 20)
				end
			end
		end)

		interest.InputChanged:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				if option.tip then
					library.tooltip.Position = UDim2.new(0, input.Position.X + 26, 0, input.Position.Y + 36)
				end
			end
		end)

		interest.InputEnded:Connect(function(input)
			if input.UserInputType.Name == "MouseMovement" then
				if not option.open then
					option.visualize.BorderColor3 = Color3.new()
				end
				library.tooltip.Position = UDim2.new(2)
			end
		end)

		function option:SetColor(newColor, nocallback)
			if typeof(newColor) == "table" then
				local red = tonumber(newColor[1]) or 1
				local green = tonumber(newColor[2]) or 1
				local blue = tonumber(newColor[3]) or 1
				newColor = Color3.new(math.clamp(red, 0, 1), math.clamp(green, 0, 1), math.clamp(blue, 0, 1))
			end
			if typeof(newColor) ~= "Color3" then
				newColor = Color3.new(1, 1, 1)
			end
			if self.mainHolder then
				self:updateVisuals(newColor)
			end
			option.visualize.BackgroundColor3 = newColor
			library.flags[self.flag] = newColor
			self.color = newColor
			if not nocallback then
				library:Invoke(self.callback, newColor)
			end
		end

		if option.trans then
			function option:SetTrans(value, manual)
				value = math.clamp(tonumber(value) or 0, 0, 1)
				if self.transSlider then
					self.transSlider.Position = UDim2.new(0, 0, value, 0)
				end
				self.trans = value
				library.flags[self.flag .. " Transparency"] = 1 - value
				library:Invoke(self.calltrans, value)
			end
			option:SetTrans(option.trans)
		end

		task.defer(function()
			if library and not library.unloaded then
				option:SetColor(option.color)
			end
		end)

		function option:Close()
			library.popup = nil
			self.open = false
			self.mainHolder.Visible = false
			option.visualize.BorderColor3 = Color3.new()
		end
	end

	function library:AddTab(title, pos)
		local order = tonumber(pos) or (#self.tabs + 1)
		local tab = {canInit = true, tabs = {}, columns = {}, title = tostring(title), order = order}
		local insertIndex = #self.tabs + 1
		for index, existing in ipairs(self.tabs) do
			if order < (tonumber(existing.order) or index) then
				insertIndex = index
				break
			end
		end
		table.insert(self.tabs, insertIndex, tab)

		function tab:AddColumn()
			local column = {sections = {}, position = #self.columns, canInit = true, tab = self}
			table.insert(self.columns, column)

			function column:AddSection(title)
				local section = {title = tostring(title), options = {}, canInit = true, column = self}
				table.insert(self.sections, section)

				function section:AddLabel(text)
					local option = {text = text}
					option.section = self
					option.type = "label"
					option.position = #self.options
					option.canInit = true
					table.insert(self.options, option)

					if library.hasInit and self.hasInit then
						library.createLabel(option, self.content)
					else
						option.Init = library.createLabel
					end

					return option
				end

				function section:AddDivider(text)
					local option = {text = text}
					option.section = self
					option.type = "divider"
					option.position = #self.options
					option.canInit = true
					table.insert(self.options, option)

					if library.hasInit and self.hasInit then
						library.createDivider(option, self.content)
					else
						option.Init = library.createDivider
					end

					return option
				end

				function section:AddToggle(option)
					option = typeof(option) == "table" and option or {}
					option.section = self
					option.text = tostring(option.text)
					option.state = option.state == nil and nil or (typeof(option.state) == "boolean" and option.state or false)
					option.callback = typeof(option.callback) == "function" and option.callback or function() end
					option.type = "toggle"
					option.position = #self.options
					option.flag = (library.flagprefix and library.flagprefix .. " " or "") .. (option.flag or option.text)
					option.subcount = 0
					option.canInit = option.canInit ~= false
					option.tip = option.tip and tostring(option.tip)
					option.style = option.style == 2
					library.flags[option.flag] = option.state
					table.insert(self.options, option)
					library.options[option.flag] = option

					function option:AddColor(subOption)
						subOption = typeof(subOption) == "table" and subOption or {}
						subOption.sub = true
						subOption.subpos = self.subcount * 24
						function subOption:getMain() return option.main end
						self.subcount = self.subcount + 1
						return section:AddColor(subOption)
					end

					function option:AddBind(subOption)
						subOption = typeof(subOption) == "table" and subOption or {}
						subOption.sub = true
						subOption.subpos = self.subcount * 24
						function subOption:getMain() return option.main end
						self.subcount = self.subcount + 1
						return section:AddBind(subOption)
					end

					function option:AddList(subOption)
						subOption = typeof(subOption) == "table" and subOption or {}
						subOption.sub = true
						function subOption:getMain() return option.main end
						self.subcount = self.subcount + 1
						return section:AddList(subOption)
					end

					function option:AddSlider(subOption)
						subOption = typeof(subOption) == "table" and subOption or {}
						subOption.sub = true
						function subOption:getMain() return option.main end
						self.subcount = self.subcount + 1
						return section:AddSlider(subOption)
					end

					if library.hasInit and self.hasInit then
						library.createToggle(option, self.content)
					else
						option.Init = library.createToggle
					end

					return option
				end

				function section:AddButton(option)
					option = typeof(option) == "table" and option or {}
					option.section = self
					option.text = tostring(option.text)
					option.callback = typeof(option.callback) == "function" and option.callback or function() end
					option.type = "button"
					option.position = #self.options
					option.flag = (library.flagprefix and library.flagprefix .. " " or "") .. (option.flag or option.text)
					option.subcount = 0
					option.canInit = option.canInit ~= false
					option.tip = option.tip and tostring(option.tip)
					table.insert(self.options, option)
					library.options[option.flag] = option

					function option:AddBind(subOption)
						subOption = typeof(subOption) == "table" and subOption or {}
						subOption.sub = true
						subOption.subpos = self.subcount * 24
						function subOption:getMain() option.main.Size = UDim2.new(1, 0, 0, 40) return option.main end
						self.subcount = self.subcount + 1
						return section:AddBind(subOption)
					end

					function option:AddColor(subOption)
						subOption = typeof(subOption) == "table" and subOption or {}
						subOption.sub = true
						subOption.subpos = self.subcount * 24
						function subOption:getMain() option.main.Size = UDim2.new(1, 0, 0, 40) return option.main end
						self.subcount = self.subcount + 1
						return section:AddColor(subOption)
					end

					if library.hasInit and self.hasInit then
						library.createButton(option, self.content)
					else
						option.Init = library.createButton
					end

					return option
				end

				function section:AddBind(option)
					option = typeof(option) == "table" and option or {}
					option.section = self
					option.text = tostring(option.text)
					local requestedKey = (option.key and option.key.Name) or option.key or "none"
					option.key = type(requestedKey) == "string" and requestedKey or "none"
					option.nomouse = option.nomouse == true
					option.mode = option.mode == "hold" and "hold" or "toggle"
					option.callback = typeof(option.callback) == "function" and option.callback or function() end
					option.type = "bind"
					option.position = #self.options
					option.flag = (library.flagprefix and library.flagprefix .. " " or "") .. (option.flag or option.text)
					option.canInit = option.canInit ~= false
					option.tip = option.tip and tostring(option.tip)
					library.flags[option.flag] = false
					table.insert(self.options, option)
					library.options[option.flag] = option

					if library.hasInit and self.hasInit then
						library.createBind(option, self.content)
					else
						option.Init = library.createBind
					end

					return option
				end

				function section:AddSlider(option)
					option = typeof(option) == "table" and option or {}
					option.section = self
					option.text = tostring(option.text)
					option.min = typeof(option.min) == "number" and option.min or 0
					option.max = typeof(option.max) == "number" and option.max or (option.min + 100)
					if option.max <= option.min then
						option.max = option.min + 1
					end
					local requestedValue = typeof(option.value) == "number" and option.value or option.min
					option.value = math.clamp(requestedValue, option.min, option.max)
					option.callback = typeof(option.callback) == "function" and option.callback or function() end
					option.float = typeof(option.float) == "number" and math.abs(option.float) or 1
					if option.float == 0 then
						option.float = 1
					end
					option.suffix = option.suffix and tostring(option.suffix) or ""
					option.textpos = option.textpos == 2
					option.type = "slider"
					option.position = #self.options
					option.flag = (library.flagprefix and library.flagprefix .. " " or "") .. (option.flag or option.text)
					option.subcount = 0
					option.canInit = option.canInit ~= false
					option.tip = option.tip and tostring(option.tip)
					library.flags[option.flag] = option.value
					table.insert(self.options, option)
					library.options[option.flag] = option

					function option:AddColor(subOption)
						subOption = typeof(subOption) == "table" and subOption or {}
						subOption.sub = true
						subOption.subpos = self.subcount * 24
						function subOption:getMain() return option.main end
						self.subcount = self.subcount + 1
						return section:AddColor(subOption)
					end

					function option:AddBind(subOption)
						subOption = typeof(subOption) == "table" and subOption or {}
						subOption.sub = true
						subOption.subpos = self.subcount * 24
						function subOption:getMain() return option.main end
						self.subcount = self.subcount + 1
						return section:AddBind(subOption)
					end

					if library.hasInit and self.hasInit then
						library.createSlider(option, self.content)
					else
						option.Init = library.createSlider
					end

					return option
				end

				function section:AddList(option)
					option = typeof(option) == "table" and option or {}
					option.section = self
					option.text = tostring(option.text)
					option.values = typeof(option.values) == "table" and option.values or {}
					option.callback = typeof(option.callback) == "function" and option.callback or function() end
					option.multiselect = typeof(option.multiselect) == "boolean" and option.multiselect or false
					--option.groupbox = (not option.multiselect) and (typeof(option.groupbox) == "boolean" and option.groupbox or false)
					option.value = option.multiselect and (typeof(option.value) == "table" and option.value or {}) or tostring(option.value or option.values[1] or "")
					if option.multiselect then
						for _, value in next, option.values do
							local key = tostring(value)
							option.value[key] = option.value[key] == true
						end
					end
					option.max = math.max(1, math.floor(tonumber(option.max) or 4))
					option.open = false
					option.type = "list"
					option.position = #self.options
					option.labels = {}
					option.flag = (library.flagprefix and library.flagprefix .. " " or "") .. (option.flag or option.text)
					option.subcount = 0
					option.canInit = option.canInit ~= false
					option.tip = option.tip and tostring(option.tip)
					library.flags[option.flag] = option.value
					table.insert(self.options, option)
					library.options[option.flag] = option

					function option:AddValue(value, state)
						value = tostring(value)
						if not table.find(self.values, value) then
							table.insert(self.values, value)
						end
						if self.multiselect and self.value[value] == nil then
							self.value[value] = state == true
						end
					end

					function option:AddColor(subOption)
						subOption = typeof(subOption) == "table" and subOption or {}
						subOption.sub = true
						subOption.subpos = self.subcount * 24
						function subOption:getMain() return option.main end
						self.subcount = self.subcount + 1
						return section:AddColor(subOption)
					end

					function option:AddBind(subOption)
						subOption = typeof(subOption) == "table" and subOption or {}
						subOption.sub = true
						subOption.subpos = self.subcount * 24
						function subOption:getMain() return option.main end
						self.subcount = self.subcount + 1
						return section:AddBind(subOption)
					end

					if library.hasInit and self.hasInit then
						library.createList(option, self.content)
					else
						option.Init = library.createList
					end

					return option
				end

				function section:AddBox(option)
					option = typeof(option) == "table" and option or {}
					option.section = self
					option.text = tostring(option.text)
					option.value = tostring(option.value or "")
					option.callback = typeof(option.callback) == "function" and option.callback or function() end
					option.type = "box"
					option.position = #self.options
					option.flag = (library.flagprefix and library.flagprefix .. " " or "") .. (option.flag or option.text)
					option.canInit = option.canInit ~= false
					option.tip = option.tip and tostring(option.tip)
					library.flags[option.flag] = option.value
					table.insert(self.options, option)
					library.options[option.flag] = option

					if library.hasInit and self.hasInit then
						library.createBox(option, self.content)
					else
						option.Init = library.createBox
					end

					return option
				end

				function section:AddColor(option)
					option = typeof(option) == "table" and option or {}
					option.section = self
					option.text = tostring(option.text)
					if typeof(option.color) == "table" then
						option.color = Color3.new(
							math.clamp(tonumber(option.color[1]) or 1, 0, 1),
							math.clamp(tonumber(option.color[2]) or 1, 0, 1),
							math.clamp(tonumber(option.color[3]) or 1, 0, 1)
						)
					elseif typeof(option.color) ~= "Color3" then
						option.color = Color3.new(1, 1, 1)
					end
					option.callback = typeof(option.callback) == "function" and option.callback or function() end
					option.calltrans = typeof(option.calltrans) == "function" and option.calltrans or (option.calltrans == 1 and option.callback) or function() end
					option.open = false
					option.trans = option.trans ~= nil and math.clamp(tonumber(option.trans) or 0, 0, 1) or nil
					option.subcount = 1
					option.type = "color"
					option.position = #self.options
					option.flag = (library.flagprefix and library.flagprefix .. " " or "") .. (option.flag or option.text)
					option.canInit = option.canInit ~= false
					option.tip = option.tip and tostring(option.tip)
					library.flags[option.flag] = option.color
					table.insert(self.options, option)
					library.options[option.flag] = option

					function option:AddColor(subOption)
						subOption = typeof(subOption) == "table" and subOption or {}
						subOption.sub = true
						subOption.subpos = self.subcount * 24
						function subOption:getMain() return option.main end
						self.subcount = self.subcount + 1
						return section:AddColor(subOption)
					end

					if option.trans then
						library.flags[option.flag .. " Transparency"] = option.trans
					end

					if library.hasInit and self.hasInit then
						library.createColor(option, self.content)
					else
						option.Init = library.createColor
					end

					return option
				end

				function section:SetTitle(newTitle)
					self.title = tostring(newTitle)
					if self.titleText then
						self.titleText.Text = tostring(newTitle)
					end
				end

				function section:Init()
					if self.hasInit then return end
					self.hasInit = true

					self.main = library:Create("Frame", {
						BackgroundColor3 = Color3.fromRGB(18, 21, 28),
						BorderColor3 = Color3.new(),
						Parent = column.main
					})

					self.content = library:Create("Frame", {
						Size = UDim2.new(1, 0, 1, 0),
						BackgroundColor3 = Color3.fromRGB(18, 21, 28),
						BorderColor3 = Color3.fromRGB(44, 50, 65),
						BorderMode = Enum.BorderMode.Inset,
						Parent = self.main
					})

					library:Create("ImageLabel", {
						Size = UDim2.new(1, -2, 1, -2),
						Position = UDim2.new(0, 1, 0, 1),
						BackgroundTransparency = 1,
						Image = "rbxassetid://2592362371",
						ImageColor3 = Color3.new(),
						ScaleType = Enum.ScaleType.Slice,
						SliceCenter = Rect.new(2, 2, 62, 62),
						Parent = self.main
					})

					library:AddThemeObject(library:Create("Frame", {
						Size = UDim2.new(1, 0, 0, 1),
						BackgroundColor3 = library.flags["Menu Accent Color"],
						BorderSizePixel = 0,
						BorderMode = Enum.BorderMode.Inset,
						Parent = self.main
					}))

					local layout = library:Create("UIListLayout", {
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 2),
						Parent = self.content
					})

					library:Create("UIPadding", {
						PaddingTop = UDim.new(0, 12),
						Parent = self.content
					})

					self.titleText = library:Create("TextLabel", {
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, 12, 0, 0),
						Size = UDim2.new(0, textService:GetTextSize(self.title, 15, Enum.Font.Code, Vector2.new(9e9, 9e9)).X + 10, 0, 3),
						BackgroundColor3 = Color3.fromRGB(18, 21, 28),
						BorderSizePixel = 0,
						Text = self.title,
						TextSize = 15,
						Font = Enum.Font.Code,
						TextColor3 = Color3.new(1, 1, 1),
						Parent = self.main
					})

					library:AddConnection(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
						if self.main then
							self.main.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y + 16)
						end
					end)

					for _, option in next, self.options do
						if option.canInit and type(option.Init) == "function" then
							local ok, err = pcall(option.Init, option, self.content)
							if not ok then
								warn("[xanhub] Failed to initialize " .. tostring(option.type) .. " '" .. tostring(option.text or option.flag) .. "': " .. tostring(err))
							end
						end
					end
				end

				if library.hasInit and self.hasInit then
					section:Init()
				end

				return section
			end

			function column:Init()
				if self.hasInit then return end
				self.hasInit = true

				self.main = library:Create("ScrollingFrame", {
					ZIndex = 2,
					Position = UDim2.new(0, 6 + (self.position * 239), 0, 2),
					Size = UDim2.new(0, 233, 1, -4),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ScrollBarImageColor3 = Color3.new(),
					ScrollBarThickness = 4,	
					VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
					ScrollingDirection = Enum.ScrollingDirection.Y,
					Visible = false,
					Parent = library.columnHolder
				})

				local layout = library:Create("UIListLayout", {
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 12),
					Parent = self.main
				})

				library:Create("UIPadding", {
					PaddingTop = UDim.new(0, 8),
					PaddingLeft = UDim.new(0, 2),
					PaddingRight = UDim.new(0, 2),
					Parent = self.main
				})

				library:AddConnection(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
					if self.main then
						self.main.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 14)
					end
				end)

				for _, section in next, self.sections do
					if section.canInit and #section.options > 0 then
						local ok, err = pcall(function() section:Init() end)
						if not ok then
							warn("[xanhub] Failed to initialize section '" .. tostring(section.title) .. "': " .. tostring(err))
						end
					end
				end
			end

			if library.hasInit and self.hasInit then
				column:Init()
			end

			return column
		end

		function tab:Init()
			if self.hasInit then return end
			self.hasInit = true
			local size = textService:GetTextSize(self.title, 18, Enum.Font.Code, Vector2.new(9e9, 9e9)).X + 10

			self.button = library:Create("TextLabel", {
				Position = UDim2.new(0, library.tabSize, 0, 22),
				Size = UDim2.new(0, size, 0, 30),
				BackgroundTransparency = 1,
				Text = self.title,
				TextColor3 = Color3.new(1, 1, 1),
				TextSize = 15,
				Font = Enum.Font.Code,
				TextWrapped = true,
				ClipsDescendants = true,
				Parent = library.main
			})
			library.tabSize = library.tabSize + size

			self.button.InputBegan:Connect(function(input)
				if input.UserInputType.Name == "MouseButton1" then
					library:selectTab(self)
				end
			end)

			for _, column in next, self.columns do
				if column.canInit then
					local ok, err = pcall(function()
						column:Init()
					end)
					if not ok then
						warn("[xanhub] Failed to initialize a column in tab '" .. tostring(self.title) .. "': " .. tostring(err))
					end
				end
			end
		end

		if self.hasInit then
			tab:Init()
		end

		return tab
	end

	function library:AddWarning(warning)
		warning = typeof(warning) == "table" and warning or {}
		warning.text = tostring(warning.text) 
		warning.type = warning.type == "confirm" and "confirm" or ""

		local answer
		function warning:Show()
			library.warning = warning
			if warning.main and warning.type == "" then return end
			if library.popup then library.popup:Close() end
			if not warning.main then
				warning.main = library:Create("TextButton", {
					ZIndex = 2,
					Size = UDim2.new(1, 0, 1, 0),
					BackgroundTransparency = 0.6,
					BackgroundColor3 = Color3.new(),
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = false,
					Parent = library.main
				})

				warning.message = library:Create("TextLabel", {
					ZIndex = 2,
					Position = UDim2.new(0, 20, 0.5, -60),
					Size = UDim2.new(1, -40, 0, 40),
					BackgroundTransparency = 1,
					TextSize = 16,
					Font = Enum.Font.Code,
					TextColor3 = Color3.new(1, 1, 1),
					TextWrapped = true,
					RichText = true,
					Parent = warning.main
				})

				if warning.type == "confirm" then
					local button = library:Create("TextLabel", {
						ZIndex = 2,
						Position = UDim2.new(0.5, -105, 0.5, -10),
						Size = UDim2.new(0, 100, 0, 20),
						BackgroundColor3 = Color3.fromRGB(24, 28, 37),
						BorderColor3 = Color3.new(),
						Text = "Yes",
						TextSize = 16,
						Font = Enum.Font.Code,
						TextColor3 = Color3.new(1, 1, 1),
						Parent = warning.main
					})

					library:Create("ImageLabel", {
						ZIndex = 2,
						Size = UDim2.new(1, 0, 1, 0),
						BackgroundTransparency = 1,
						Image = "rbxassetid://2454009026",
						ImageColor3 = Color3.new(),
						ImageTransparency = 0.8,
						Parent = button
					})

					library:Create("ImageLabel", {
						ZIndex = 2,
						Size = UDim2.new(1, 0, 1, 0),
						BackgroundTransparency = 1,
						Image = "rbxassetid://2592362371",
						ImageColor3 = Color3.fromRGB(44, 50, 65),
						ScaleType = Enum.ScaleType.Slice,
						SliceCenter = Rect.new(2, 2, 62, 62),
						Parent = button
					})

					local button1 = library:Create("TextLabel", {
						ZIndex = 2,
						Position = UDim2.new(0.5, 5, 0.5, -10),
						Size = UDim2.new(0, 100, 0, 20),
						BackgroundColor3 = Color3.fromRGB(24, 28, 37),
						BorderColor3 = Color3.new(),
						Text = "No",
						TextSize = 16,
						Font = Enum.Font.Code,
						TextColor3 = Color3.new(1, 1, 1),
						Parent = warning.main
					})

					library:Create("ImageLabel", {
						ZIndex = 2,
						Size = UDim2.new(1, 0, 1, 0),
						BackgroundTransparency = 1,
						Image = "rbxassetid://2454009026",
						ImageColor3 = Color3.new(),
						ImageTransparency = 0.8,
						Parent = button1
					})

					library:Create("ImageLabel", {
						ZIndex = 2,
						Size = UDim2.new(1, 0, 1, 0),
						BackgroundTransparency = 1,
						Image = "rbxassetid://2592362371",
						ImageColor3 = Color3.fromRGB(44, 50, 65),
						ScaleType = Enum.ScaleType.Slice,
						SliceCenter = Rect.new(2, 2, 62, 62),
						Parent = button1
					})

					button.InputBegan:Connect(function(input)
						if input.UserInputType.Name == "MouseButton1" then
							answer = true
						end
					end)

					button1.InputBegan:Connect(function(input)
						if input.UserInputType.Name == "MouseButton1" then
							answer = false
						end
					end)
				else
					local button = library:Create("TextLabel", {
						ZIndex = 2,
						Position = UDim2.new(0.5, -50, 0.5, -10),
						Size = UDim2.new(0, 100, 0, 20),
						BackgroundColor3 = Color3.fromRGB(18, 21, 28),
						BorderColor3 = Color3.new(),
						Text = "OK",
						TextSize = 16,
						Font = Enum.Font.Code,
						TextColor3 = Color3.new(1, 1, 1),
						Parent = warning.main
					})

					library:Create("ImageLabel", {
						ZIndex = 2,
						Size = UDim2.new(1, 0, 1, 0),
						BackgroundTransparency = 1,
						Image = "rbxassetid://2454009026",
						ImageColor3 = Color3.new(),
						ImageTransparency = 0.8,
						Parent = button
					})

					library:Create("ImageLabel", {
						ZIndex = 2,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, 0, 0.5, 0),
						Size = UDim2.new(1, -2, 1, -2),
						BackgroundTransparency = 1,
						Image = "rbxassetid://3570695787",
						ImageColor3 = Color3.fromRGB(30, 35, 46),
						Parent = button
					})

					button.InputBegan:Connect(function(input)
						if input.UserInputType.Name == "MouseButton1" then
							answer = true
						end
					end)
				end
			end
			warning.main.Visible = true
			warning.message.Text = warning.text

			repeat task.wait()
			until answer ~= nil or library.unloaded
			if library.unloaded and answer == nil then
				answer = false
			end
			task.spawn(warning.Close)
			library.warning = nil
			return answer
		end

		function warning:Close()
			answer = nil
			if not warning.main then return end
			warning.main.Visible = false
		end

		return warning
	end

	function library:SetOpen(state)
		if self.unloaded then return false end
		state = state == true
		self.open = state

		if not state then
			dragging = false
			dragInput = nil
			dragObject = nil
			if self.slider then
				pcall(function() self.slider.slider.BorderColor3 = Color3.new() end)
				self.slider = nil
			end
			if self.popup then
				pcall(function() self.popup:Close() end)
			end
			if self.tooltip then
				pcall(function() self.tooltip.Position = UDim2.new(2, 0, 2, 0) end)
			end
		end

		if self.main then
			self.main.Visible = state
		end
		if self.base then
			-- Keep the ScreenGui enabled so keybind listeners and notifications can
			-- continue working while only the main window is hidden.
			self.base.Enabled = true
		end

		-- Use Roblox's normal cursor. Drawing cursors vary heavily by executor.
		pcall(function()
			inputService.MouseIconEnabled = self.mousestate
		end)
		if self.cursor then pcall(function() self.cursor.Visible = false end) end
		if self.cursor1 then pcall(function() self.cursor1.Visible = false end) end
		return self.open
	end

	function library:Close()
		return self:SetOpen(not self.open)
	end

	function library:Toggle()
		return self:Close()
	end

	function library:IsInitialized()
		if self.initialized ~= true or not self.base or not self.main then
			return false
		end
		local ok, parent = pcall(function() return self.base.Parent end)
		return ok and parent ~= nil
	end

	function library:GetStatus()
		return {
			brand = self.brand,
			version = self.version,
			initialized = self:IsInitialized(),
			open = self.open == true,
			unloaded = self.unloaded == true,
			parent = self.uiParent,
			lastInitError = self.lastInitError,
		}
	end

	function library:GetViewportSize()
		local camera = workspace.CurrentCamera
		if camera then
			local ok, viewport = pcall(function()
				return camera.ViewportSize
			end)
			if ok and typeof(viewport) == "Vector2" and viewport.X > 0 and viewport.Y > 0 then
				return viewport
			end
		end
		return Vector2.new(1920, 1080)
	end

	function library:GetRequiredWindowSize(tab)
		local columnCount = math.max(2, tab and #tab.columns or 2)
		local contentWidth = 16 + (columnCount * 239)
		local tabWidth = math.max(self.minimumWindowWidth or 494, (self.tabSize or 0) + 14)
		return Vector2.new(math.max(contentWidth, tabWidth), self.windowHeight or 600)
	end

	function library:UpdateWindowLayout(tab)
		if not self.main then
			return false
		end

		tab = tab or self.currentTab
		local required = self:GetRequiredWindowSize(tab)
		self.main.Size = UDim2.fromOffset(required.X, required.Y)

		local viewport = self:GetViewportSize()
		local margin = 28
		local availableX = math.max(1, viewport.X - margin * 2)
		local availableY = math.max(1, viewport.Y - margin * 2)
		local fitScale = math.min(availableX / required.X, availableY / required.Y)
		local requestedScale = math.clamp(tonumber(self.userScale) or 1, 0.55, 1.25)
		local finalScale = math.clamp(math.min(requestedScale, fitScale), 0.35, 1.25)

		self.autoScale = finalScale
		if self.uiScale then
			self.uiScale.Scale = finalScale
		end
		return true
	end

	function library:SetMenuScale(scale)
		self.userScale = math.clamp(tonumber(scale) or 1, 0.55, 1.25)
		self:UpdateWindowLayout(self.currentTab)
		return self.userScale
	end

	function library:GetMenuScale()
		return self.userScale or 1
	end

	function library:Init()
		if self.unloaded then
			return nil, "xanhub has already been unloaded"
		end
		if self:IsInitialized() then
			return self
		end
		if self.initializing then
			return self
		end

		self.initializing = true
		self.lastInitError = nil

		local function traceback(message)
			if type(debug) == "table" and type(debug.traceback) == "function" then
				return debug.traceback(tostring(message), 2)
			end
			return tostring(message)
		end

		local success, initError = xpcall(function()
			self.base = library:Create("ScreenGui", {
				Name = "xanhub_ui",
				Enabled = true,
				IgnoreGuiInset = true,
				ResetOnSpawn = false,
				DisplayOrder = 999999,
				ZIndexBehavior = Enum.ZIndexBehavior.Global,
			})
			assert(self.base, "failed to create ScreenGui")

			local possibleParents = {}
			local function addParent(parent)
				if typeof(parent) == "Instance" and not table.find(possibleParents, parent) then
					table.insert(possibleParents, parent)
				end
			end
			local function addGetter(getter)
				if type(getter) == "function" then
					local ok, parent = pcall(getter)
					if ok then
						addParent(parent)
					end
				end
			end
			local function addService(name)
				local ok, service = pcall(function()
					return game:GetService(name)
				end)
				if ok and type(cloneref) == "function" then
					local cloneOk, cloned = pcall(cloneref, service)
					if cloneOk and cloned then
						service = cloned
					end
				end
				if ok then
					addParent(service)
				end
			end

			addGetter(gethui)
			addGetter(get_hidden_gui)
			addGetter(gethiddengui)
			addService("CoreGui")
			pcall(function()
				local player = playersService.LocalPlayer
				if player then
					addParent(player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5))
				end
			end)

			for _, parent in ipairs(possibleParents) do
				pcall(function()
					for _, child in ipairs(parent:GetChildren()) do
						if child:IsA("ScreenGui") and (child.Name == "xanhub_ui" or child.Name == "uwuware_ui") then
							child:Destroy()
						end
					end
				end)
			end

			if type(syn) == "table" and type(syn.protect_gui) == "function" then
				pcall(function()
					syn.protect_gui(self.base)
				end)
			elseif type(protectgui) == "function" then
				pcall(function()
					protectgui(self.base)
				end)
			end

			local parented = false
			local lastParentError = "no valid GUI parent was found"
			for _, parent in ipairs(possibleParents) do
				local ok, err = pcall(function()
					self.base.Parent = parent
				end)
				if ok and self.base.Parent ~= nil then
					parented = true
					break
				end
				lastParentError = tostring(err)
			end
			assert(parented, "failed to parent ScreenGui: " .. lastParentError)

			self.main = self:Create("ImageButton", {
				AutoButtonColor = false,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(0, 494, 0, 600),
				BackgroundColor3 = self.palette.background,
				BorderColor3 = self.palette.border,
				ScaleType = Enum.ScaleType.Tile,
				Modal = true,
				Visible = true,
				Parent = self.base,
			})
			assert(self.main, "failed to create main window")

			self.uiScale = self:Create("UIScale", {
				Scale = 1,
				Parent = self.main,
			})

			self.top = self:Create("Frame", {
				Size = UDim2.new(1, 0, 0, 50),
				BackgroundColor3 = self.palette.surfaceRaised,
				BorderColor3 = self.palette.border,
				Parent = self.main,
			})

			self.titleLabel = self:Create("TextLabel", {
				ZIndex = 3,
				Position = UDim2.new(0, 7, 0, -1),
				Size = UDim2.new(1, -14, 0, 21),
				BackgroundTransparency = 1,
				Text = self:FormatTitle(self.title),
				RichText = true,
				Font = Enum.Font.GothamSemibold,
				TextSize = 17,
				TextColor3 = Color3.new(1, 1, 1),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = self.main,
			})
			self:RegisterBrandLabel(self.titleLabel, self.title, true)

			self:AddThemeObject(self:Create("Frame", {
				ZIndex = 3,
				Size = UDim2.new(1, 0, 0, 1),
				Position = UDim2.new(0, 0, 0, 24),
				BackgroundColor3 = self.flags["Menu Accent Color"] or self.defaultAccent,
				BorderSizePixel = 0,
				Parent = self.main,
			}))

			self:Create("ImageLabel", {
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Image = "rbxassetid://2454009026",
				ImageColor3 = Color3.new(),
				ImageTransparency = 0.45,
				Parent = self.top,
			})

			self.tabHighlight = self:Create("Frame", {
				ZIndex = 3,
				BackgroundColor3 = self.flags["Menu Accent Color"] or self.defaultAccent,
				BorderSizePixel = 0,
				Parent = self.main,
			})
			self:AddThemeObject(self.tabHighlight)

			self.columnHolder = self:Create("Frame", {
				Position = UDim2.new(0, 5, 0, 55),
				Size = UDim2.new(1, -10, 1, -60),
				BackgroundTransparency = 1,
				Parent = self.main,
			})

			self.cursor = nil
			self.cursor1 = nil

			self.tooltip = self:Create("TextLabel", {
				ZIndex = 20,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				TextSize = 15,
				Font = Enum.Font.Code,
				TextColor3 = Color3.new(1, 1, 1),
				Visible = true,
				Parent = self.base,
			})

			self:Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 0),
				Size = UDim2.new(1, 10, 1, 0),
				Style = Enum.FrameStyle.RobloxRound,
				Parent = self.tooltip,
			})

			self:Create("ImageLabel", {
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Image = "rbxassetid://2592362371",
				ImageColor3 = Color3.fromRGB(44, 50, 65),
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = Rect.new(2, 2, 62, 62),
				Parent = self.main,
			})

			self:Create("ImageLabel", {
				Size = UDim2.new(1, -2, 1, -2),
				Position = UDim2.new(0, 1, 0, 1),
				BackgroundTransparency = 1,
				Image = "rbxassetid://2592362371",
				ImageColor3 = Color3.new(),
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = Rect.new(2, 2, 62, 62),
				Parent = self.main,
			})

			self:AddConnection(self.top.InputBegan, function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					dragObject = self.main
					dragging = true
					dragStart = input.Position
					startPos = dragObject.Position
					if self.popup then
						self.popup:Close()
					end
				end
			end)
			self:AddConnection(self.top.InputChanged, function(input)
				if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
					dragInput = input
				end
			end)
			self:AddConnection(self.top.InputEnded, function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					dragging = false
				end
			end)

			function self:selectTab(tab)
				if not tab or not tab.button or self.currentTab == tab then
					return false
				end
				if self.popup then
					self.popup:Close()
				end
				if self.currentTab then
					pcall(function()
						self.currentTab.button.TextColor3 = Color3.fromRGB(235, 235, 235)
					end)
					for _, column in next, self.currentTab.columns do
						if column.main then
							column.main.Visible = false
						end
					end
				end
				self.currentTab = tab
				self:UpdateWindowLayout(tab)
				tab.button.TextColor3 = self.flags["Menu Accent Color"] or self.defaultAccent
				local tabWidth = tab.button.AbsoluteSize.X
				if tabWidth <= 0 then
					tabWidth = tab.button.Size.X.Offset
				end
				self:SafeTween(self.tabHighlight, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.new(0, tab.button.Position.X.Offset, 0, 50),
					Size = UDim2.new(0, tabWidth, 0, 1),
				})
				for _, column in next, tab.columns do
					if column.main then
						column.main.Visible = true
					end
				end
				return true
			end

			local firstTab
			for _, tab in next, self.tabs do
				if tab.canInit then
					local ok, err = pcall(function()
						tab:Init()
					end)
					if ok and tab.button then
						firstTab = firstTab or tab
					else
						warn("[xanhub] Failed to initialize tab '" .. tostring(tab.title) .. "': " .. tostring(err))
					end
				end
			end
			if firstTab then
				self:selectTab(firstTab)
			else
				self:UpdateWindowLayout(nil)
			end

			local function connectViewportWatcher()
				local camera = workspace.CurrentCamera
				if camera then
					self:AddConnection(camera:GetPropertyChangedSignal("ViewportSize"), "ViewportScale", function()
						self:UpdateWindowLayout(self.currentTab)
					end)
				end
			end
			connectViewportWatcher()
			self:AddConnection(workspace:GetPropertyChangedSignal("CurrentCamera"), "CameraScaleWatcher", function()
				task.defer(function()
					connectViewportWatcher()
					self:UpdateWindowLayout(self.currentTab)
				end)
			end)

			self:AddConnection(inputService.InputEnded, function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 and self.slider then
					pcall(function()
						self.slider.slider.BorderColor3 = Color3.new()
					end)
					self.slider = nil
				end
			end)

			self:AddConnection(inputService.InputChanged, function(input)
				if not self.open or self.unloaded then
					return
				end
				if input.UserInputType == Enum.UserInputType.MouseMovement and self.slider then
					local width = self.slider.slider.AbsoluteSize.X
					if width > 0 then
						self.slider:SetValue(self.slider.min + ((input.Position.X - self.slider.slider.AbsolutePosition.X) / width) * (self.slider.max - self.slider.min))
					end
				end
				if input == dragInput and dragging and self.draggable and dragObject then
					local scale = (self.uiScale and self.uiScale.Scale) or 1
					local delta = (input.Position - dragStart) / math.max(scale, 0.01)
					local yPos = math.max(-36, startPos.Y.Offset + delta.Y)
					self:SafeTween(dragObject, TweenInfo.new(0.08, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
						Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, yPos),
					})
				end
			end)

			if self.capabilities.filesystem and self.options["Config List"] then
				task.spawn(function()
					while not self.unloaded and self.base and self.base.Parent do
						task.wait(5)
						if self.unloaded then
							break
						end
						local configOption = self.options["Config List"]
						if configOption then
							local configs = self:GetConfigs()
							for _, config in next, configs do
								if not table.find(configOption.values, config) then
									configOption:AddValue(config)
								end
							end
							for index = #configOption.values, 1, -1 do
								local config = configOption.values[index]
								if not table.find(configs, config) then
									configOption:RemoveValue(config)
								end
							end
						end
					end
				end)
			end

			self.open = true
			self.base.Enabled = true
			self.main.Visible = true
			self.uiParent = self.base.Parent
			pcall(function()
				inputService.MouseIconEnabled = self.mousestate
			end)
		end, traceback)

		self.initializing = false
		if not success then
			self.lastInitError = initError
			warn("[xanhub] Initialization warning: " .. tostring(initError))
			-- A noncritical control can fail after the window is already usable. Return
			-- the library in that case so caller assertions do not report a false failure.
			if self.base and self.main and self.base.Parent then
				self.hasInit = true
				self.initialized = true
				self.ready = true
				self:SetOpen(true)
				return self
			end
			self.hasInit = false
			self.initialized = false
			self.ready = false
			pcall(function()
				if self.base then
					self.base:Destroy()
				end
			end)
			self.base = nil
			self.main = nil
			return nil, initError
		end

		self.hasInit = true
		self.initialized = true
		self.ready = true
		self:SetAccent(self.flags["Menu Accent Color"] or self.defaultAccent)
		self:UpdateWindowLayout(self.currentTab)
		print("[xanhub " .. tostring(self.version) .. "] UI initialized | parent: " .. (self.uiParent and self.uiParent:GetFullName() or "unknown"))
		return self
	end

	library.Initialize = library.Init
	library.Start = library.Init
	library.Ready = function(self)
		return self:IsInitialized()
	end

	library.SettingsTab = library:AddTab("Settings", 100)
	library.SettingsColumn = library.SettingsTab:AddColumn()
	library.SettingsColumn1 = library.SettingsTab:AddColumn()

	library.SettingsMain = library.SettingsColumn:AddSection"Main"
	library.SettingsMain:AddButton({text = "Unload xanhub", nomouse = true, callback = function()
		library:Unload()
		env.xanhub = nil
	end})
	library.SettingsMain:AddBind({text = "Panic Key", callback = library.options["Unload xanhub"].callback})

	library.SettingsMenu = library.SettingsColumn:AddSection"Menu"
	library.SettingsMenu:AddBind({text = "Open / Close", flag = "UI Toggle", nomouse = true, key = "Insert", callback = function() library:Close() end})
	library.SettingsMenu:AddColor({text = "Accent Color", flag = "Menu Accent Color", color = DEFAULT_ACCENT, callback = function(Color)
		library:SetAccent(Color)
	end})
	local Backgrounds = {
		["None"] = false,
		["Floral"] = 5553946656,
		["Flowers"] = 6071575925,
		["Circles"] = 6071579801,
		["Hearts"] = 6073763717,
		["Polka dots"] = 6214418014,
		["Mountains"] = 6214412460,
		["Zigzag"] = 6214416834,
		["Zigzag 2"] = 6214375242,
		["Tartan"] = 6214404863,
		["Roses"] = 6214374619,
		["Hexagons"] = 6214320051,
		["Leopard print"] = 6214318622
	}
	library.SettingsMenu:AddList({text = "Background", flag = "UI Background", max = 6, value = "None", values = {"None", "Floral", "Flowers", "Circles", "Hearts", "Polka dots", "Mountains", "Zigzag", "Zigzag 2", "Tartan", "Roses", "Hexagons", "Leopard print"}, callback = function(Value)
		if Value == "None" then
			library.main.Image = ""
		elseif Backgrounds[Value] then
			library.main.Image = "rbxassetid://" .. Backgrounds[Value]
		end
	end}):AddColor({flag = "Menu Background Color", color = Color3.new(), callback = function(Color)
		library.main.ImageColor3 = Color
	end, trans = 1, calltrans = function(Value)
		library.main.ImageTransparency = 1 - Value
	end})
	library.SettingsMenu:AddSlider({text = "Menu Scale", flag = "Menu Scale", value = 100, min = 55, max = 125, suffix = "%", callback = function(Value)
		library:SetMenuScale((tonumber(Value) or 100) / 100)
	end})
	library.SettingsMenu:AddSlider({text = "Tile Size", value = 90, min = 50, max = 500, callback = function(Value)
		library.main.TileSize = UDim2.new(0, Value, 0, Value)
	end})

	library.ConfigSection = library.SettingsColumn1:AddSection"Configs"
	if library.capabilities.filesystem then
		library.ConfigSection:AddBox({text = "Config Name", skipflag = true})
		library.ConfigSection:AddButton({text = "Create", callback = function()
			local name = library.flags["Config Name"]
			local ok = library:CreateConfig(name)
			if ok and not table.find(library.options["Config List"].values, name) then
				library.options["Config List"]:AddValue(name)
			end
		end})
		library.ConfigWarning = library:AddWarning({type = "confirm"})
		library.ConfigSection:AddList({text = "Configs", skipflag = true, value = "", flag = "Config List", values = library:GetConfigs()})
		library.ConfigSection:AddButton({text = "Save", callback = function()
			local r, g, b = library.round(library.flags["Menu Accent Color"])
			library.ConfigWarning.text = "Are you sure you want to save the current settings to config <font color='rgb(" .. r .. "," .. g .. "," .. b .. ")'>" .. library.flags["Config List"] .. "</font>?"
			if library.ConfigWarning:Show() then
				library:SaveConfig(library.flags["Config List"])
			end
		end})
		library.ConfigSection:AddButton({text = "Load", callback = function()
			local r, g, b = library.round(library.flags["Menu Accent Color"])
			library.ConfigWarning.text = "Are you sure you want to load config <font color='rgb(" .. r .. "," .. g .. "," .. b .. ")'>" .. library.flags["Config List"] .. "</font>?"
			if library.ConfigWarning:Show() then
				library:LoadConfig(library.flags["Config List"])
			end
		end})
		library.ConfigSection:AddButton({text = "Delete", callback = function()
			local r, g, b = library.round(library.flags["Menu Accent Color"])
			library.ConfigWarning.text = "Are you sure you want to delete config <font color='rgb(" .. r .. "," .. g .. "," .. b .. ")'>" .. library.flags["Config List"] .. "</font>?"
			if library.ConfigWarning:Show() then
				local Config = library.flags["Config List"]
				if table.find(library:GetConfigs(), Config) then
					library:DeleteConfig(Config)
					library.options["Config List"]:RemoveValue(Config)
				end
			end
		end})
	else
		library.ConfigSection:AddLabel("Config saving is unavailable in this executor")
	end

	--LIBRARY END
	
	--custom notification thing, library required for this to work
	local LastNotification = 0
	function library:SendNotification(duration, message)
		local now = tick()
		if library.unloaded or now - LastNotification < 0.2 or not library.base then return nil end
		LastNotification = now
		if message == nil and type(duration) == "string" then
			message = duration
			duration = 2
		else
			duration = math.max(tonumber(duration) or 2, 2)
			message = message and tostring(message) or "Empty"
		end

		--create the thing
		local notification = library:Create("Frame", {
			AnchorPoint = Vector2.new(1, 1),
			Size = UDim2.new(0, 0, 0, 80),
			Position = UDim2.new(1, -5, 1, -5),
			BackgroundTransparency = 1,
			BackgroundColor3 = library.palette.surfaceRaised,
			BorderColor3 = library.palette.border,
			Parent = library.base
		})
		library:SafeTween(notification, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, 240, 0, 80), BackgroundTransparency = 0})

		library:SafeTween(library:Create("TextLabel", {
			Position = UDim2.new(0, 5, 0, 25),
			Size = UDim2.new(1, -10, 0, 40),
			BackgroundTransparency = 1,
			Text = tostring(message),
			Font = Enum.Font.SourceSans,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 18,
			TextTransparency = 1,
			TextWrapped = true,
			Parent = notification
		}), TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.3), {TextTransparency = 0})

		--bump existing notifications
		for _,notification in next, library.notifications do
			library:SafeTween(notification, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(1, -5, 1, notification.Position.Y.Offset - 85)})
		end
		library.notifications[notification] = notification

		-- Create the remaining elements immediately. SafeTween handles either
		-- animated or instant rendering without yielding the caller.
		--create other things
		local progressBar = library:Create("Frame", {
			Position = UDim2.new(0, 0, 0, 20),
			Size = UDim2.new(0, 0, 0, 1),
			BackgroundColor3 = library.flags["Menu Accent Color"] or library.defaultAccent,
			BorderSizePixel = 0,
			Parent = notification
		})
		if progressBar then
			library:AddThemeObject(progressBar)
		end
		library:SafeTween(progressBar, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, 1)})

		local notificationBrand = library:Create("TextLabel", {
			Position = UDim2.new(0, 4, 0, 0),
			Size = UDim2.new(0, 90, 0, 16),
			BackgroundTransparency = 1,
			Text = library:FormatBrand(library.brand),
			RichText = true,
			Font = Enum.Font.GothamSemibold,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 16,
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = notification
		})
		library:RegisterBrandLabel(notificationBrand, library.brand)
		library:SafeTween(notificationBrand, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0})

		--remove
		task.delay(duration, function()
			if not library or library.unloaded or not notification or notification.Parent == nil then return end
			library.notifications[notification] = nil
			--bump existing notifications down
			for _,otherNotif in next, library.notifications do
				if otherNotif.Position.Y.Offset < notification.Position.Y.Offset then
					library:SafeTween(otherNotif, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(1, -5, 1, otherNotif.Position.Y.Offset + 85)})
				end
			end
			notification:Destroy()
		end)
		return notification
	end

	print("[xanhub " .. tostring(library.version) .. "] library loaded")
	return library
