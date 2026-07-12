--[[
    xanhub | universal | keybinds module

    Movement and visual keybind controls.
]]

return function(ctx)
	local movementBinds = ctx.columns.bindsLeft:AddSection("Movement")
	movementBinds:AddBind({
		text = "Toggle Fly",
		flag = "Universal Bind Fly",
		key = "X",
		mode = "toggle",
		nomouse = true,
		callback = function(enabled)
			ctx.setToggle("Universal Fly", enabled == true)
		end,
	})
	movementBinds:AddBind({
		text = "Toggle Noclip",
		flag = "Universal Bind Noclip",
		key = "N",
		mode = "toggle",
		nomouse = true,
		callback = function(enabled)
			ctx.setToggle("Universal Noclip", enabled == true)
		end,
	})

	local visualBinds = ctx.columns.bindsRight:AddSection("Visuals")
	visualBinds:AddBind({
		text = "Toggle ESP",
		flag = "Universal Bind ESP",
		key = "H",
		mode = "toggle",
		nomouse = true,
		callback = function(enabled)
			ctx.setToggle("Universal ESP", enabled == true)
		end,
	})
	visualBinds:AddBind({
		text = "Toggle Crosshair",
		flag = "Universal Bind Crosshair",
		key = "C",
		mode = "toggle",
		nomouse = true,
		callback = function(enabled)
			ctx.setToggle("Universal Crosshair", enabled == true)
		end,
	})
	visualBinds:AddBind({
		text = "Toggle Targeting",
		flag = "Universal Bind Aim Preview",
		key = "V",
		mode = "toggle",
		nomouse = true,
		callback = function(enabled)
			ctx.setToggle("Universal Aim Preview", enabled == true)
		end,
	})
	visualBinds:AddBind({
		text = "Toggle Aim Lock",
		flag = "Universal Bind Aim Lock",
		key = "Q",
		mode = "toggle",
		nomouse = true,
		callback = function(enabled)
			ctx.setToggle("Universal Combat Aim Lock", enabled == true)
		end,
	})
	visualBinds:AddLabel("Menu and panic binds are available in Settings")
end
