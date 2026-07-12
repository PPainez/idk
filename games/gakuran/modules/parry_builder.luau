--[[
    xanhub | gakuran | parry builder

    Parry profile builder UI integrated with dev animation logger/viewer.
    Profiles are stored in ctx.state.parry — logic wired later.
]]

return function(ctx)
	local library = ctx.library
	local columns = ctx.columns
	local state = ctx.state.parry

	state.profiles = type(state.profiles) == "table" and state.profiles or {}
	state.selected = state.selected

	local function devShared()
		local dev = ctx.devtools
		return dev and dev.shared
	end

	local function notifySoon(feature)
		ctx.notify(feature .. " — coming soon", 2)
	end

	local tools = columns.parryLeft:AddSection("Animation Tools")
	tools:AddLabel("Enable Dev Tools in Settings first")
	tools:AddButton({
		text = "Open Animation Logger",
		callback = function()
			local shared = devShared()
			if shared then
				shared.invokeApi("animationLogger", "Open")
			else
				ctx.notify("Enable Dev Tools in Settings", 3)
			end
		end,
	})
	tools:AddButton({
		text = "Open Animation Viewer",
		callback = function()
			local shared = devShared()
			if shared then
				shared.invokeApi("animationViewer", "Open")
			else
				ctx.notify("Enable Dev Tools in Settings", 3)
			end
		end,
	})
	tools:AddButton({
		text = "Use Logger Selection",
		callback = function()
			local dev = ctx.devtools
			local api = dev and dev.apis and dev.apis.animationLogger
			local selected = api and api.GetSelected and api:GetSelected()
			if not selected then
				ctx.notify("Select an animation in the logger first", 3)
				return
			end
			state.selected = {
				id = selected.id,
				name = selected.name or selected.id,
				source = selected.sourceName or selected.sourceType or "Unknown",
				path = selected.sourcePath or "",
			}
			if ctx.refs.parrySelectedLabel then
				ctx.refs.parrySelectedLabel.Text = string.format(
					"Selected: %s (%s)",
					tostring(state.selected.name),
					tostring(state.selected.id)
				)
			end
			ctx.notify("Animation linked to parry builder", 2)
		end,
	})
	tools:AddButton({
		text = "Preview Selection",
		callback = function()
			if not state.selected then
				ctx.notify("No animation selected for parry builder", 3)
				return
			end
			local shared = devShared()
			if shared then
				shared.invokeApi("animationViewer", "Open", state.selected)
			else
				ctx.notify("Enable Dev Tools in Settings", 3)
			end
		end,
	})

	local profiles = columns.parryRight:AddSection("Parry Profiles")
	ctx.refs.parrySelectedLabel = profiles:AddLabel("Selected: none")
	profiles:AddBox({ text = "Profile Name", flag = "Gakuran Parry Profile Name", value = "" })
	profiles:AddSlider({
		text = "Parry Window",
		flag = "Gakuran Parry Window",
		min = 50,
		max = 800,
		value = 220,
		float = 10,
		suffix = " ms",
	})
	profiles:AddSlider({
		text = "Startup Delay",
		flag = "Gakuran Parry Startup",
		min = 0,
		max = 400,
		value = 40,
		float = 5,
		suffix = " ms",
	})
	profiles:AddSlider({
		text = "Range",
		flag = "Gakuran Parry Range",
		min = 4,
		max = 30,
		value = 12,
		float = 1,
		suffix = " studs",
	})
	profiles:AddToggle({ text = "Enabled", flag = "Gakuran Parry Profile Enabled", state = true })

	profiles:AddButton({
		text = "Add Profile From Selection",
		callback = function()
			if not state.selected then
				ctx.notify("Link an animation first (Use Logger Selection)", 3)
				return
			end
			local name = library.flags["Gakuran Parry Profile Name"]
			if type(name) ~= "string" or name == "" then
				name = "Parry_" .. tostring(state.selected.id)
			end
			state.profiles[name] = {
				name = name,
				animationId = state.selected.id,
				animationName = state.selected.name,
				source = state.selected.source,
				path = state.selected.path,
				windowMs = library.flags["Gakuran Parry Window"] or 220,
				startupMs = library.flags["Gakuran Parry Startup"] or 40,
				rangeStuds = library.flags["Gakuran Parry Range"] or 12,
				enabled = library.flags["Gakuran Parry Profile Enabled"] == true,
			}
			local count = 0
			for _ in pairs(state.profiles) do
				count = count + 1
			end
			if ctx.refs.parryCountLabel then
				ctx.refs.parryCountLabel.Text = "Saved profiles: " .. tostring(count)
			end
			ctx.notify("Profile saved locally: " .. name, 2)
		end,
	})
	profiles:AddButton({
		text = "Export Profiles",
		callback = function()
			notifySoon("Export profiles")
		end,
	})
	profiles:AddButton({
		text = "Import Profiles",
		callback = function()
			notifySoon("Import profiles")
		end,
	})
	profiles:AddButton({
		text = "Clear All Profiles",
		callback = function()
			state.profiles = {}
			state.selected = nil
			if ctx.refs.parryCountLabel then
				ctx.refs.parryCountLabel.Text = "Saved profiles: 0"
			end
			if ctx.refs.parrySelectedLabel then
				ctx.refs.parrySelectedLabel.Text = "Selected: none"
			end
			ctx.notify("Parry profiles cleared", 2)
		end,
	})
	ctx.refs.parryCountLabel = profiles:AddLabel("Saved profiles: 0")

	local builder = columns.parryLeft:AddSection("Builder Notes")
	builder:AddLabel("1. Enable Dev Tools in Settings")
	builder:AddLabel("2. Open Animation Logger and capture hits")
	builder:AddLabel("3. Select an entry → Use Logger Selection")
	builder:AddLabel("4. Tune window/range → Add Profile")
	builder:AddLabel("5. Preview with Animation Viewer")
	builder:AddLabel("Parry execution logic will hook profiles later")

	local function setup()
		local count = 0
		for _ in pairs(state.profiles) do
			count = count + 1
		end
		if ctx.refs.parryCountLabel then
			ctx.refs.parryCountLabel.Text = "Saved profiles: " .. tostring(count)
		end
	end

	return { setup = setup }
end
