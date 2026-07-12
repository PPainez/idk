--[[
    xanhub | devmodules | module template

    Contract:
      return function(ctx) -> module
      module.setup() is called after library:Init()
      module.cleanup() is optional; also register with shared.addCleanup
]]

return function(ctx)
    local dev = assert(ctx.devtools, "[xanhub dev template] dev_shared missing")
    local shared = assert(dev.shared, "[xanhub dev template] dev_shared missing")

    local section = dev.left:AddSection("Example Dev Module")
    section:AddToggle({text = "Enabled", flag = "Dev Example Enabled", state = false})
    section:AddButton({
        text = "Run Example",
        callback = function()
            shared.notify("Example action", 2)
        end,
    })

    local state = {}
    local api = {}

    function api:GetState()
        return state
    end

    local function setup()
        -- Runtime connections belong here, after library:Init().
    end

    local function cleanup()
        -- Restore or destroy everything this module created.
    end

    local module = {
        name = "example_dev_module",
        setup = setup,
        cleanup = cleanup,
        api = api,
    }

    dev.apis.exampleDevModule = api
    dev.modules.example_dev_module = module
    shared.addCleanup(cleanup)
    return module
end
