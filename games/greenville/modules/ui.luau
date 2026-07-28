--[[
    xanhub | Greenville | UI

    Tuning tab layout shared by the Greenville control modules.
]]

return function(ctx)
	local tuningTab = ctx.library:AddTab("Tuning", 1)

	return {
		tabs = {
			tuning = tuningTab,
		},
		columns = {
			engine = tuningTab:AddColumn(),
			boost = tuningTab:AddColumn(),
		},
	}
end
