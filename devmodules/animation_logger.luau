--[[
    xanhub | devmodules | animation logger

    Captures Animator.AnimationPlayed from players, NPCs, and self.
    Includes filtering, dedupe, blacklist, export, and viewer integration.
]]

return function(ctx)
    local dev = assert(ctx.devtools, "[xanhub animation logger] dev_shared missing")
    local shared = assert(dev.shared, "[xanhub animation logger] dev_shared missing")
    local section = dev.left:AddSection("Animation Logger")

    section:AddToggle({text = "Enabled", flag = "Dev Animation Logger Enabled", state = false})
    section:AddToggle({text = "Limit Capture Range", flag = "Dev Animation Logger Range Limit", state = true})
    section:AddSlider({
        text = "Capture Range",
        flag = "Dev Animation Logger Range",
        min = 5,
        max = 1000,
        value = 150,
        float = 5,
        suffix = " studs",
    })
    section:AddList({
        text = "Source Filter",
        flag = "Dev Animation Logger Source",
        values = {"All", "Players", "NPCs", "Self"},
        value = "All",
    })
    section:AddSlider({
        text = "Dedupe Window",
        flag = "Dev Animation Logger Dedupe",
        min = 0,
        max = 10,
        value = 0.5,
        float = 0.1,
        suffix = "s",
    })
    section:AddSlider({
        text = "Maximum Entries",
        flag = "Dev Animation Logger Max Entries",
        min = 50,
        max = 1000,
        value = 300,
        float = 25,
    })
    section:AddButton({
        text = "Open Animation Logger",
        callback = function()
            shared.invokeApi("animationLogger", "Open")
        end,
    })
    section:AddButton({
        text = "View Animation DB",
        callback = function()
            shared.invokeApi("animationLogger", "OpenDb")
        end,
    })
    section:AddButton({
        text = "Clear Animation Log",
        callback = function()
            shared.invokeApi("animationLogger", "Clear")
        end,
    })
    section:AddLabel("Captures Animator.AnimationPlayed · View DB browses game folders for AP")

    local state = {
        entries = {},
        recent = {},
        blacklist = {},
        animatorConnections = setmetatable({}, {__mode = "k"}),
        trackConnections = setmetatable({}, {__mode = "k"}),
        selected = nil,
        window = nil,
        rows = {},
        dirty = true,
        entryEvent = Instance.new("BindableEvent"),
        scanConnection = nil,
        descendantConnection = nil,
        uiConnection = nil,
        -- View DB
        dbWindow = nil,
        dbCategories = {},
        dbSelectedCategory = nil,
        dbSelectedAnim = nil,
        dbMarked = {}, -- id -> true (user marked for export)
        dbCatRows = {},
        dbAnimRows = {},
        dbDirty = true,
    }

    local ui = {}
    local persistenceFolder = "xanhub_dev"
    local persistencePath = persistenceFolder .. "/animation_logger.json"

    local function enabled()
        return ctx.library.flags["Dev Animation Logger Enabled"] == true
    end

    local function normalizeId(value)
        return tostring(value or ""):match("%d+")
    end

    local function sourceInfo(animator)
        local model = animator:FindFirstAncestorOfClass("Model")
        if not model then
            return nil, "Unknown", "Unknown"
        end
        local player = ctx.Players:GetPlayerFromCharacter(model)
        if player == ctx.LocalPlayer then
            return model, "Self", player.DisplayName or player.Name
        elseif player then
            return model, "Player", player.DisplayName or player.Name
        end
        return model, "NPC", model.Name
    end

    local function passesSource(sourceType)
        local filter = ctx.library.flags["Dev Animation Logger Source"] or "All"
        if filter == "All" then return true end
        if filter == "Players" then return sourceType == "Player" end
        if filter == "NPCs" then return sourceType == "NPC" end
        if filter == "Self" then return sourceType == "Self" end
        return true
    end

    local function passesRange(model)
        if ctx.library.flags["Dev Animation Logger Range Limit"] == false then
            return true
        end
        local localRoot = ctx.getRoot and ctx.getRoot() or nil
        local root = ctx.getRoot and ctx.getRoot(model) or (model and model:FindFirstChild("HumanoidRootPart"))
        if not localRoot or not root then
            return true
        end
        local range = tonumber(ctx.library.flags["Dev Animation Logger Range"]) or 150
        return (localRoot.Position - root.Position).Magnitude <= range
    end

    local function saveSettings()
        if type(writefile) ~= "function" then
            return
        end
        local ok, payload = pcall(function()
            local encoded = game:GetService("HttpService"):JSONEncode({blacklist = state.blacklist})
            return encoded
        end)
        if not ok then return end
        pcall(function()
            if type(isfolder) == "function" and not isfolder(persistenceFolder) and type(makefolder) == "function" then
                makefolder(persistenceFolder)
            end
            writefile(persistencePath, payload)
        end)
    end

    local function loadSettings()
        if type(readfile) ~= "function" or type(isfile) ~= "function" or not isfile(persistencePath) then
            return
        end
        local ok, decoded = pcall(function()
            return game:GetService("HttpService"):JSONDecode(readfile(persistencePath))
        end)
        if ok and type(decoded) == "table" and type(decoded.blacklist) == "table" then
            for key, value in pairs(decoded.blacklist) do
                if value == true then
                    local id = normalizeId(key)
                    if id then state.blacklist[id] = true end
                end
            end
        end
    end

    loadSettings()

    local function markDirty()
        state.dirty = true
    end

    local function trimEntries()
        local maxEntries = math.clamp(tonumber(ctx.library.flags["Dev Animation Logger Max Entries"]) or 300, 50, 1000)
        while #state.entries > maxEntries do
            table.remove(state.entries)
        end
    end

    local function shouldDedupe(key)
        local now = os.clock()
        local window = math.max(0, tonumber(ctx.library.flags["Dev Animation Logger Dedupe"]) or 0.5)
        local last = state.recent[key]
        state.recent[key] = now
        return last ~= nil and now - last < window
    end

    local function trackMetadata(track, sourceModel, sourceType, sourceName)
        local animation = track.Animation
        local id = animation and normalizeId(animation.AnimationId)
        if not id then return nil end
        local animator = track.Parent
        local key = tostring(animator) .. ":" .. id
        if shouldDedupe(key) or state.blacklist[id] then
            return nil
        end
        return {
            id = id,
            animationId = "rbxassetid://" .. id,
            name = animation.Name ~= "" and animation.Name or track.Name,
            sourceName = sourceName,
            sourceType = sourceType,
            sourceModel = sourceModel,
            sourcePath = shared.instancePath(sourceModel),
            animatorPath = shared.instancePath(animator),
            speed = tonumber(track.Speed) or 1,
            weight = tonumber(track.WeightCurrent) or 0,
            looped = track.Looped == true,
            priority = tostring(track.Priority),
            length = tonumber(track.Length) or 0,
            startedAt = os.clock(),
            wallTime = os.time(),
            timePosition = tonumber(track.TimePosition) or 0,
            track = track,
            stopped = false,
        }
    end

    local function addEntry(entry)
        table.insert(state.entries, 1, entry)
        trimEntries()
        state.entryEvent:Fire(entry)
        markDirty()

        if entry.track and not state.trackConnections[entry.track] then
            local connection
            connection = entry.track.Stopped:Connect(function()
                entry.stopped = true
                entry.endedAt = os.clock()
                entry.durationPlayed = math.max(0, entry.endedAt - entry.startedAt)
                state.trackConnections[entry.track] = nil
                pcall(function() connection:Disconnect() end)
                markDirty()
            end)
            state.trackConnections[entry.track] = connection
        end
    end

    local function onAnimationPlayed(animator, track)
        if not enabled() then return end
        local model, sourceType, sourceName = sourceInfo(animator)
        if not model or not passesSource(sourceType) or not passesRange(model) then
            return
        end
        local ok, entry = pcall(trackMetadata, track, model, sourceType, sourceName)
        if ok and entry then
            addEntry(entry)
        end
    end

    local function attachAnimator(animator)
        if not animator:IsA("Animator") or state.animatorConnections[animator] then
            return
        end
        local connection = animator.AnimationPlayed:Connect(function(track)
            onAnimationPlayed(animator, track)
        end)
        state.animatorConnections[animator] = connection
        animator.AncestryChanged:Connect(function(_, parent)
            if not parent then
                local existing = state.animatorConnections[animator]
                if existing then pcall(function() existing:Disconnect() end) end
                state.animatorConnections[animator] = nil
            end
        end)
    end

    local function scanExisting()
        task.spawn(function()
            local count = 0
            for _, object in ipairs(ctx.Workspace:GetDescendants()) do
                if object:IsA("Animator") then
                    attachAnimator(object)
                end
                count = count + 1
                if count % 300 == 0 then task.wait() end
            end
        end)
    end

    local function exportEntries()
        local export = {}
        for _, entry in ipairs(state.entries) do
            table.insert(export, {
                id = entry.id,
                name = entry.name,
                sourceName = entry.sourceName,
                sourceType = entry.sourceType,
                sourcePath = entry.sourcePath,
                speed = entry.speed,
                looped = entry.looped,
                priority = entry.priority,
                length = entry.length,
                durationPlayed = entry.durationPlayed,
                wallTime = entry.wallTime,
            })
        end
        local ok, text = pcall(function()
            return game:GetService("HttpService"):JSONEncode(export)
        end)
        if ok then shared.copy(text) end
    end

    local function clearRows()
        for _, row in ipairs(state.rows) do
            shared.safeDestroy(row)
        end
        state.rows = {}
    end

    local function selectEntry(entry)
        state.selected = entry
        if not entry then
            ui.details.Text = "No entry selected"
            return
        end
        ui.details.Text = table.concat({
            "Animation: " .. tostring(entry.name),
            "ID: " .. tostring(entry.id),
            "Source: " .. tostring(entry.sourceName) .. " (" .. tostring(entry.sourceType) .. ")",
            "Path: " .. tostring(entry.sourcePath),
            string.format("Speed %.2f | Weight %.2f | Length %.3f", entry.speed, entry.weight, entry.length),
            "Priority: " .. tostring(entry.priority) .. " | Looped: " .. tostring(entry.looped),
            entry.stopped and string.format("Played for %.3fs", entry.durationPlayed or 0) or "Track currently active or stop not observed",
        }, "\n")
    end

    local function entryMatches(entry)
        local query = ui.search and string.lower(ui.search.Text) or ""
        if query == "" then return true end
        local haystack = string.lower(table.concat({entry.id, entry.name, entry.sourceName, entry.sourceType, entry.sourcePath}, " "))
        return string.find(haystack, query, 1, true) ~= nil
    end

    local function rebuildRows()
        if not ui.list then return end
        clearRows()
        local shown = 0
        for _, entry in ipairs(state.entries) do
            if entryMatches(entry) then
                shown = shown + 1
                if shown > 250 then break end
                local row = shared.create("TextButton", {
                    Size = UDim2.new(1, -4, 0, 34),
                    BackgroundColor3 = shared.theme.panel2,
                    BackgroundTransparency = 0.08,
                    BorderSizePixel = 0,
                    Text = "",
                    Parent = ui.list,
                })
                shared.round(row, 5)
                shared.stroke(row, shared.theme.border, 0.45, 1)
                local title = shared.create("TextLabel", {
                    Position = UDim2.fromOffset(8, 2),
                    Size = UDim2.new(1, -16, 0, 16),
                    BackgroundTransparency = 1,
                    Text = tostring(entry.sourceName) .. "  •  " .. tostring(entry.name),
                    TextColor3 = shared.theme.text,
                    TextSize = 11,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = row,
                })
                shared.create("TextLabel", {
                    Position = UDim2.fromOffset(8, 17),
                    Size = UDim2.new(1, -16, 0, 14),
                    BackgroundTransparency = 1,
                    Text = tostring(entry.id) .. "  |  " .. tostring(entry.sourceType) .. string.format("  |  %.2fx", entry.speed),
                    TextColor3 = shared.theme.muted,
                    TextSize = 10,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row,
                })
                shared.connect(row.MouseButton1Click, function()
                    selectEntry(entry)
                end)
                table.insert(state.rows, row)
            end
        end
        if ui.count then ui.count.Text = string.format("%d captured • %d shown", #state.entries, shown) end
        state.dirty = false
    end

    local function buildWindow()
        if state.window and state.window.root.Parent then return state.window end
        state.window = shared.makeWindow("Animation Logger", 840, 520)
        local content = state.window.content

        local left = shared.create("Frame", {
            Position = UDim2.fromOffset(10, 10),
            Size = UDim2.new(0.58, -15, 1, -20),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Parent = content,
        })
        shared.round(left, 8)
        shared.stroke(left, shared.theme.border, 0.25, 1)
        local leftPad = Instance.new("UIPadding")
        leftPad.PaddingTop = UDim.new(0, 8)
        leftPad.PaddingLeft = UDim.new(0, 8)
        leftPad.PaddingRight = UDim.new(0, 8)
        leftPad.PaddingBottom = UDim.new(0, 8)
        leftPad.Parent = left

        ui.search = shared.makeTextBox(left, "Search ID, source, name, path", "")
        ui.search.Position = UDim2.fromOffset(0, 0)
        ui.count = shared.create("TextLabel", {
            Position = UDim2.fromOffset(0, 34),
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1,
            Text = "0 captured",
            TextColor3 = shared.theme.muted,
            TextSize = 10,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = left,
        })
        ui.list = shared.create("ScrollingFrame", {
            Position = UDim2.fromOffset(0, 56),
            Size = UDim2.new(1, 0, 1, -56),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = left,
        })
        shared.round(ui.list, 6)
        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 4)
        layout.Parent = ui.list
        shared.connect(ui.search:GetPropertyChangedSignal("Text"), markDirty)

        local right = shared.create("Frame", {
            Position = UDim2.new(0.58, 5, 0, 10),
            Size = UDim2.new(0.42, -15, 1, -20),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Parent = content,
        })
        shared.round(right, 8)
        shared.stroke(right, shared.theme.border, 0.25, 1)
        local rightPad = Instance.new("UIPadding")
        rightPad.PaddingTop = UDim.new(0, 10)
        rightPad.PaddingLeft = UDim.new(0, 10)
        rightPad.PaddingRight = UDim.new(0, 10)
        rightPad.PaddingBottom = UDim.new(0, 10)
        rightPad.Parent = right

        ui.details = shared.create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 240),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            Text = "No entry selected",
            TextColor3 = shared.theme.text,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = right,
        })
        shared.round(ui.details, 6)
        local detailPad = Instance.new("UIPadding")
        detailPad.PaddingTop = UDim.new(0, 8)
        detailPad.PaddingLeft = UDim.new(0, 8)
        detailPad.PaddingRight = UDim.new(0, 8)
        detailPad.Parent = ui.details

        local buttons = shared.create("Frame", {
            Position = UDim2.fromOffset(0, 250),
            Size = UDim2.new(1, 0, 1, -250),
            BackgroundTransparency = 1,
            Parent = right,
        })
        local buttonLayout = Instance.new("UIGridLayout")
        buttonLayout.CellSize = UDim2.new(0.5, -4, 0, 30)
        buttonLayout.CellPadding = UDim2.fromOffset(6, 6)
        buttonLayout.Parent = buttons
        shared.makeButton(buttons, "Preview", function()
            if state.selected and dev.apis.animationViewer then
                dev.apis.animationViewer:Open(state.selected)
            else
                shared.notify("Select an animation first", 2)
            end
        end, 120)
        shared.makeButton(buttons, "Copy ID", function()
            if state.selected then shared.copy(state.selected.id) end
        end, 120)
        shared.makeButton(buttons, "Copy Source Path", function()
            if state.selected then shared.copy(state.selected.sourcePath) end
        end, 120)
        shared.makeButton(buttons, "Blacklist ID", function()
            if state.selected then
                state.blacklist[state.selected.id] = true
                saveSettings()
                shared.notify("Blacklisted " .. state.selected.id, 2)
            end
        end, 120)
        shared.makeButton(buttons, "Export JSON", exportEntries, 120)
        shared.makeButton(buttons, "Clear", function()
            state.entries = {}
            state.recent = {}
            state.selected = nil
            markDirty()
            selectEntry(nil)
        end, 120)

        shared.connect(ctx.RunService.Heartbeat, function()
            if state.window and state.window.root.Visible and state.dirty then
                rebuildRows()
            end
        end)
        markDirty()
        return state.window
    end

    -- View DB (game Animation folders + AP status) -------------------------

    local function classifyApNeed(animName, folderName)
        local n = tostring(animName or "")
        local f = tostring(folderName or "")
        if n:find("Idle") or n:find("Walk") or n:find("Run") or n:find("Dash") then
            return false, "locomotion"
        end
        if n:find("Block") and not n:find("Guardbreak") and not n:find("EHit") then
            return false, "block"
        end
        if n:find("M1") or n:find("M2") or n:find("EHit") or n:find("Crit")
            or n:find("Grapple") or n:find("Dirty") or n:find("Attacker")
            or n:find("Momentum") or n:find("Slam") or n:find("Grab")
        then
            return true, "attack"
        end
        if f:find("Combat") or f:find("Anims") or f:find("Grappl") then
            if n ~= "" and n ~= "Animation" then
                return false, "other-combat"
            end
        end
        return false, "other"
    end

    local function lookupAttackDb(id)
        id = normalizeId(id)
        if not id then
            return nil
        end
        local combat = ctx.state and ctx.state.combat
        local db = combat and combat.db
        if db and type(db.lookup) == "function" then
            local ok, entry = pcall(function()
                return db:lookup(id)
            end)
            if ok and type(entry) == "table" then
                return entry
            end
        end
        if db and type(db.byId) == "table" then
            return db.byId[id]
        end
        return nil
    end

    local function scrapeAnimationDb()
        local categories = {}
        local order = {}
        local function ensureCat(name)
            if not categories[name] then
                categories[name] = { name = name, anims = {} }
                table.insert(order, name)
            end
            return categories[name]
        end

        local function addAnim(folderLabel, anim)
            if not anim or not anim:IsA("Animation") then
                return
            end
            local id = normalizeId(anim.AnimationId)
            if not id then
                return
            end
            local name = anim.Name ~= "" and anim.Name or ("Animation_" .. id)
            local needed, reason = classifyApNeed(name, folderLabel)
            local ap = lookupAttackDb(id)
            if ap then
                needed = true
                reason = "in-ap-db"
            end
            local cat = ensureCat(folderLabel)
            table.insert(cat.anims, {
                id = id,
                animationId = "rbxassetid://" .. id,
                name = name,
                folder = folderLabel,
                needed = needed,
                reason = reason,
                ap = ap and {
                    kind = ap.kind,
                    hitDelay = ap.hitDelay,
                    window = ap.window,
                    dbName = ap.name,
                } or nil,
                instance = anim,
            })
        end

        local function scrapeFolder(folder, label)
            if not folder then
                return
            end
            for _, d in ipairs(folder:GetDescendants()) do
                if d:IsA("Animation") then
                    -- Prefer nearest named parent folder under Combat
                    local folderLabel = label
                    local p = d.Parent
                    while p and p ~= folder do
                        if p:IsA("Folder") or p:IsA("Configuration") then
                            folderLabel = label .. "/" .. p.Name
                            break
                        end
                        p = p.Parent
                    end
                    -- Group by top combat style folder when possible
                    local top = d:FindFirstAncestorWhichIsA("Folder")
                    if folder.Name == "Combat" and top and top.Parent == folder then
                        folderLabel = top.Name
                    elseif folder.Name == "BaseCombat" then
                        folderLabel = "BaseCombat"
                    end
                    addAnim(folderLabel, d)
                end
            end
        end

        local ok, anims = pcall(function()
            return game:GetService("ReplicatedStorage"):FindFirstChild("Animations")
        end)
        if ok and anims then
            scrapeFolder(anims:FindFirstChild("Combat"), "Combat")
            scrapeFolder(anims:FindFirstChild("BaseCombat"), "BaseCombat")
            scrapeFolder(anims:FindFirstChild("Movement"), "Movement")
            -- Also list any other top-level folders lightly
            for _, child in ipairs(anims:GetChildren()) do
                if child:IsA("Folder")
                    and child.Name ~= "Combat"
                    and child.Name ~= "BaseCombat"
                    and child.Name ~= "Movement"
                then
                    scrapeFolder(child, child.Name)
                end
            end
        end

        -- Sort categories + anims
        table.sort(order)
        for _, name in ipairs(order) do
            table.sort(categories[name].anims, function(a, b)
                if a.needed ~= b.needed then
                    return a.needed
                end
                return tostring(a.name) < tostring(b.name)
            end)
        end

        -- Prefer combat folders first in UI
        table.sort(order, function(a, b)
            local aCombat = a:find("Anim") or a == "BaseCombat" or a:find("Grappl")
            local bCombat = b:find("Anim") or b == "BaseCombat" or b:find("Grappl")
            if aCombat and not bCombat then
                return true
            end
            if bCombat and not aCombat then
                return false
            end
            return a < b
        end)

        state.dbCategories = categories
        state.dbOrder = order
        if not state.dbSelectedCategory and order[1] then
            state.dbSelectedCategory = order[1]
        end
        return categories, order
    end

    local function clearDbRows(list)
        for _, row in ipairs(list) do
            shared.safeDestroy(row)
        end
        table.clear(list)
    end

    local function formatAnimExport(anim)
        local ap = anim.ap
        local lines = {
            string.format("[%s] %s", anim.folder, anim.name),
            "id = " .. anim.id,
            "needed_ap = " .. tostring(anim.needed),
            "reason = " .. tostring(anim.reason),
        }
        if ap then
            table.insert(lines, string.format(
                "ap = { kind = %q, hitDelay = %.3f, window = %.3f, name = %q }",
                tostring(ap.kind or "?"),
                tonumber(ap.hitDelay) or 0,
                tonumber(ap.window) or 0.125,
                tostring(ap.dbName or anim.name)
            ))
        else
            table.insert(lines, "ap = nil -- not in current attack_db")
        end
        if state.dbMarked[anim.id] then
            table.insert(lines, "marked = true")
        end
        return table.concat(lines, "\n")
    end

    local function exportAnims(list, title)
        if type(list) ~= "table" or #list == 0 then
            shared.notify("Nothing to export", 2)
            return
        end
        local chunks = {
            "-- xanhub Animation DB export · " .. tostring(title or "selection"),
            "-- paste this to the agent for AP timing work",
            string.format("-- count %d · place %s", #list, tostring(game.PlaceId)),
            "",
        }
        for _, anim in ipairs(list) do
            table.insert(chunks, formatAnimExport(anim))
            table.insert(chunks, "")
        end
        local text = table.concat(chunks, "\n")
        shared.copy(text)
        shared.notify(string.format("Exported %d anims to clipboard", #list), 3)
    end

    local function collectCategoryAnims(catName, onlyNeeded, onlyMarked)
        local cat = state.dbCategories[catName]
        if not cat then
            return {}
        end
        local out = {}
        for _, anim in ipairs(cat.anims) do
            local marked = state.dbMarked[anim.id] == true
            if onlyMarked then
                if marked then
                    table.insert(out, anim)
                end
            elseif onlyNeeded then
                if anim.needed or marked then
                    table.insert(out, anim)
                end
            else
                table.insert(out, anim)
            end
        end
        return out
    end

    local function collectAll(filterFn)
        local out = {}
        for _, catName in ipairs(state.dbOrder or {}) do
            local cat = state.dbCategories[catName]
            if cat then
                for _, anim in ipairs(cat.anims) do
                    if not filterFn or filterFn(anim) then
                        table.insert(out, anim)
                    end
                end
            end
        end
        return out
    end

    local function selectDbAnim(anim)
        state.dbSelectedAnim = anim
        if not ui.dbDetails then
            return
        end
        if not anim then
            ui.dbDetails.Text = "Select an animation"
            return
        end
        local lines = {
            "Name: " .. tostring(anim.name),
            "ID: " .. tostring(anim.id),
            "Category: " .. tostring(anim.folder),
            "AP needed: " .. (anim.needed and "YES" or "no") .. " (" .. tostring(anim.reason) .. ")",
            "Marked: " .. (state.dbMarked[anim.id] and "YES" or "no"),
        }
        if anim.ap then
            table.insert(lines, string.format(
                "In attack_db: %s · hitDelay %.0fms · window %.0fms",
                tostring(anim.ap.kind),
                (tonumber(anim.ap.hitDelay) or 0) * 1000,
                (tonumber(anim.ap.window) or 0) * 1000
            ))
            table.insert(lines, "DB name: " .. tostring(anim.ap.dbName))
        else
            table.insert(lines, "In attack_db: no")
            if anim.needed then
                table.insert(lines, "→ export this if AP should handle it")
            end
        end
        ui.dbDetails.Text = table.concat(lines, "\n")
    end

    local function rebuildDbAnimList()
        if not ui.dbAnimList then
            return
        end
        clearDbRows(state.dbAnimRows)
        local catName = state.dbSelectedCategory
        local cat = catName and state.dbCategories[catName]
        if not cat then
            if ui.dbAnimCount then
                ui.dbAnimCount.Text = "No category"
            end
            return
        end
        local query = ui.dbSearch and string.lower(ui.dbSearch.Text) or ""
        local shown = 0
        for _, anim in ipairs(cat.anims) do
            if query == ""
                or string.find(string.lower(anim.name), query, 1, true)
                or string.find(anim.id, query, 1, true)
            then
                shown = shown + 1
                local needed = anim.needed
                local marked = state.dbMarked[anim.id] == true
                local row = shared.create("TextButton", {
                    Size = UDim2.new(1, -4, 0, 36),
                    BackgroundColor3 = shared.theme.panel2,
                    BackgroundTransparency = 0.06,
                    BorderSizePixel = 0,
                    Text = "",
                    Parent = ui.dbAnimList,
                })
                shared.round(row, 5)
                shared.stroke(
                    row,
                    needed and shared.theme.warning or shared.theme.border,
                    needed and 0.2 or 0.5,
                    1
                )
                shared.create("TextLabel", {
                    Position = UDim2.fromOffset(8, 2),
                    Size = UDim2.new(1, -90, 0, 16),
                    BackgroundTransparency = 1,
                    Text = anim.name,
                    TextColor3 = shared.theme.text,
                    TextSize = 11,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = row,
                })
                shared.create("TextLabel", {
                    Position = UDim2.fromOffset(8, 18),
                    Size = UDim2.new(1, -90, 0, 14),
                    BackgroundTransparency = 1,
                    Text = anim.id
                        .. (anim.ap and string.format("  ·  %s %.0fms", anim.ap.kind, (anim.ap.hitDelay or 0) * 1000) or "")
                        .. (marked and "  ·  MARKED" or ""),
                    TextColor3 = shared.theme.muted,
                    TextSize = 10,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row,
                })
                local badge = shared.create("TextLabel", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -8, 0.5, 0),
                    Size = UDim2.fromOffset(52, 20),
                    BackgroundColor3 = needed and shared.theme.warning or shared.theme.panel,
                    BackgroundTransparency = 0.15,
                    BorderSizePixel = 0,
                    Text = needed and "AP" or "—",
                    TextColor3 = needed and Color3.fromRGB(20, 16, 8) or shared.theme.muted,
                    TextSize = 10,
                    Font = Enum.Font.Code,
                    Parent = row,
                })
                shared.round(badge, 4)
                shared.connect(row.MouseButton1Click, function()
                    selectDbAnim(anim)
                end)
                table.insert(state.dbAnimRows, row)
            end
        end
        if ui.dbAnimCount then
            local needN = 0
            for _, a in ipairs(cat.anims) do
                if a.needed then
                    needN = needN + 1
                end
            end
            ui.dbAnimCount.Text = string.format(
                "%s · %d shown · %d AP · %d total",
                tostring(catName),
                shown,
                needN,
                #cat.anims
            )
        end
    end

    local function rebuildDbCategories()
        if not ui.dbCatList then
            return
        end
        clearDbRows(state.dbCatRows)
        for _, catName in ipairs(state.dbOrder or {}) do
            local cat = state.dbCategories[catName]
            if cat then
                local needN = 0
                for _, a in ipairs(cat.anims) do
                    if a.needed then
                        needN = needN + 1
                    end
                end
                local selected = state.dbSelectedCategory == catName
                local row = shared.create("TextButton", {
                    Size = UDim2.new(1, -4, 0, 30),
                    BackgroundColor3 = selected and shared.accent() or shared.theme.panel2,
                    BackgroundTransparency = selected and 0.35 or 0.08,
                    BorderSizePixel = 0,
                    Text = "",
                    Parent = ui.dbCatList,
                })
                shared.round(row, 5)
                shared.stroke(row, shared.theme.border, 0.4, 1)
                shared.create("TextLabel", {
                    Position = UDim2.fromOffset(8, 0),
                    Size = UDim2.new(1, -16, 1, 0),
                    BackgroundTransparency = 1,
                    Text = string.format("%s  (%d · AP %d)", catName, #cat.anims, needN),
                    TextColor3 = shared.theme.text,
                    TextSize = 11,
                    Font = Enum.Font.Code,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = row,
                })
                shared.connect(row.MouseButton1Click, function()
                    state.dbSelectedCategory = catName
                    state.dbSelectedAnim = nil
                    selectDbAnim(nil)
                    rebuildDbCategories()
                    rebuildDbAnimList()
                end)
                table.insert(state.dbCatRows, row)
            end
        end
    end

    local function refreshDb()
        scrapeAnimationDb()
        rebuildDbCategories()
        rebuildDbAnimList()
        if state.dbSelectedAnim then
            -- re-bind selected by id
            local id = state.dbSelectedAnim.id
            local cat = state.dbCategories[state.dbSelectedCategory]
            if cat then
                for _, a in ipairs(cat.anims) do
                    if a.id == id then
                        selectDbAnim(a)
                        break
                    end
                end
            end
        end
        if ui.dbStatus then
            local total, need = 0, 0
            for _, catName in ipairs(state.dbOrder or {}) do
                local cat = state.dbCategories[catName]
                if cat then
                    total = total + #cat.anims
                    for _, a in ipairs(cat.anims) do
                        if a.needed then
                            need = need + 1
                        end
                    end
                end
            end
            ui.dbStatus.Text = string.format(
                "%d categories · %d anims · %d flagged for AP",
                #(state.dbOrder or {}),
                total,
                need
            )
        end
    end

    local function buildDbWindow()
        if state.dbWindow and state.dbWindow.root and state.dbWindow.root.Parent then
            return state.dbWindow
        end
        state.dbWindow = shared.makeWindow("Animation DB", 920, 560)
        local content = state.dbWindow.content

        -- Top bar
        ui.dbStatus = shared.create("TextLabel", {
            Position = UDim2.fromOffset(10, 8),
            Size = UDim2.new(1, -200, 0, 20),
            BackgroundTransparency = 1,
            Text = "Loading…",
            TextColor3 = shared.theme.muted,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = content,
        })
        shared.makeButton(content, "Refresh", function()
            refreshDb()
            shared.notify("Animation DB refreshed", 2)
        end, 90).Position = UDim2.new(1, -100, 0, 6)

        -- Categories
        local catFrame = shared.create("Frame", {
            Position = UDim2.fromOffset(10, 34),
            Size = UDim2.new(0.28, -15, 1, -44),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Parent = content,
        })
        shared.round(catFrame, 8)
        shared.stroke(catFrame, shared.theme.border, 0.25, 1)
        shared.create("TextLabel", {
            Position = UDim2.fromOffset(10, 8),
            Size = UDim2.new(1, -20, 0, 18),
            BackgroundTransparency = 1,
            Text = "Categories",
            TextColor3 = shared.theme.text,
            TextSize = 12,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = catFrame,
        })
        ui.dbCatList = shared.create("ScrollingFrame", {
            Position = UDim2.fromOffset(8, 30),
            Size = UDim2.new(1, -16, 1, -38),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = catFrame,
        })
        shared.round(ui.dbCatList, 6)
        local catLayout = Instance.new("UIListLayout")
        catLayout.Padding = UDim.new(0, 3)
        catLayout.Parent = ui.dbCatList

        -- Animations
        local animFrame = shared.create("Frame", {
            Position = UDim2.new(0.28, 5, 0, 34),
            Size = UDim2.new(0.40, -15, 1, -44),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Parent = content,
        })
        shared.round(animFrame, 8)
        shared.stroke(animFrame, shared.theme.border, 0.25, 1)
        ui.dbSearch = shared.makeTextBox(animFrame, "Filter name / id", "")
        ui.dbSearch.Position = UDim2.fromOffset(8, 8)
        ui.dbSearch.Size = UDim2.new(1, -16, 0, 28)
        ui.dbAnimCount = shared.create("TextLabel", {
            Position = UDim2.fromOffset(10, 40),
            Size = UDim2.new(1, -20, 0, 16),
            BackgroundTransparency = 1,
            Text = "Anims",
            TextColor3 = shared.theme.muted,
            TextSize = 10,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = animFrame,
        })
        ui.dbAnimList = shared.create("ScrollingFrame", {
            Position = UDim2.fromOffset(8, 58),
            Size = UDim2.new(1, -16, 1, -66),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = animFrame,
        })
        shared.round(ui.dbAnimList, 6)
        local animLayout = Instance.new("UIListLayout")
        animLayout.Padding = UDim.new(0, 3)
        animLayout.Parent = ui.dbAnimList
        shared.connect(ui.dbSearch:GetPropertyChangedSignal("Text"), rebuildDbAnimList)

        -- Details + actions
        local detFrame = shared.create("Frame", {
            Position = UDim2.new(0.68, 0, 0, 34),
            Size = UDim2.new(0.32, -10, 1, -44),
            BackgroundColor3 = shared.theme.panel,
            BorderSizePixel = 0,
            Parent = content,
        })
        shared.round(detFrame, 8)
        shared.stroke(detFrame, shared.theme.border, 0.25, 1)
        shared.create("TextLabel", {
            Position = UDim2.fromOffset(10, 8),
            Size = UDim2.new(1, -20, 0, 18),
            BackgroundTransparency = 1,
            Text = "Details",
            TextColor3 = shared.theme.text,
            TextSize = 12,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = detFrame,
        })
        ui.dbDetails = shared.create("TextLabel", {
            Position = UDim2.fromOffset(8, 30),
            Size = UDim2.new(1, -16, 0, 170),
            BackgroundColor3 = shared.theme.background,
            BorderSizePixel = 0,
            Text = "Select an animation",
            TextColor3 = shared.theme.text,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = detFrame,
        })
        shared.round(ui.dbDetails, 6)
        local detPad = Instance.new("UIPadding")
        detPad.PaddingTop = UDim.new(0, 8)
        detPad.PaddingLeft = UDim.new(0, 8)
        detPad.PaddingRight = UDim.new(0, 8)
        detPad.Parent = ui.dbDetails

        local actions = shared.create("Frame", {
            Position = UDim2.fromOffset(8, 210),
            Size = UDim2.new(1, -16, 1, -218),
            BackgroundTransparency = 1,
            Parent = detFrame,
        })
        local grid = Instance.new("UIGridLayout")
        grid.CellSize = UDim2.new(1, 0, 0, 30)
        grid.CellPadding = UDim2.fromOffset(0, 6)
        grid.Parent = actions

        shared.makeButton(actions, "Preview in Viewer", function()
            local anim = state.dbSelectedAnim
            if not anim then
                shared.notify("Select an animation first", 2)
                return
            end
            if dev.apis.animationViewer then
                dev.apis.animationViewer:Open({
                    id = anim.id,
                    animationId = anim.animationId,
                    name = anim.name,
                    sourceName = anim.folder,
                    sourceType = "DB",
                })
            else
                shared.notify("Animation Viewer not loaded", 3)
            end
        end, 200)

        shared.makeButton(actions, "Copy ID", function()
            if state.dbSelectedAnim then
                shared.copy(state.dbSelectedAnim.id)
            end
        end, 200)

        shared.makeButton(actions, "Copy Entry (for agent)", function()
            if state.dbSelectedAnim then
                shared.copy(formatAnimExport(state.dbSelectedAnim))
                shared.notify("Entry copied — paste to chat", 2)
            end
        end, 200)

        shared.makeButton(actions, "Toggle Mark", function()
            local anim = state.dbSelectedAnim
            if not anim then
                return
            end
            if state.dbMarked[anim.id] then
                state.dbMarked[anim.id] = nil
            else
                state.dbMarked[anim.id] = true
            end
            selectDbAnim(anim)
            rebuildDbAnimList()
        end, 200)

        shared.makeButton(actions, "Export Category AP", function()
            local list = collectCategoryAnims(state.dbSelectedCategory, true, false)
            exportAnims(list, "category-ap:" .. tostring(state.dbSelectedCategory))
        end, 200)

        shared.makeButton(actions, "Export Marked", function()
            local list = collectAll(function(a)
                return state.dbMarked[a.id] == true
            end)
            exportAnims(list, "marked")
        end, 200)

        shared.makeButton(actions, "Export All AP Needed", function()
            local list = collectAll(function(a)
                return a.needed == true
            end)
            exportAnims(list, "all-ap-needed")
        end, 200)

        shared.makeButton(actions, "Export Full Category", function()
            local list = collectCategoryAnims(state.dbSelectedCategory, false, false)
            exportAnims(list, "category-full:" .. tostring(state.dbSelectedCategory))
        end, 200)

        refreshDb()
        return state.dbWindow
    end

    local api = {}
    function api:Open()
        buildWindow():Show()
        markDirty()
    end
    function api:OpenDb()
        buildDbWindow():Show()
        refreshDb()
    end
    function api:Clear()
        state.entries = {}
        state.recent = {}
        state.selected = nil
        markDirty()
        selectEntry(nil)
    end
    function api:GetEntries()
        return state.entries
    end
    function api:GetSelected()
        return state.selected
    end
    function api:Blacklist(id, value)
        id = normalizeId(id)
        if id then
            state.blacklist[id] = value ~= false
            saveSettings()
        end
    end
    function api:OnEntry(callback)
        return state.entryEvent.Event:Connect(callback)
    end
    function api:GetState()
        return state
    end
    function api:GetDb()
        scrapeAnimationDb()
        return state.dbCategories, state.dbOrder
    end

    dev.apis.animationLogger = api

    local function setup()
        scanExisting()
        state.descendantConnection = shared.connect(ctx.Workspace.DescendantAdded, function(object)
            if object:IsA("Animator") then attachAnimator(object) end
        end)
    end

    local function cleanup()
        for animator, connection in pairs(state.animatorConnections) do
            pcall(function() connection:Disconnect() end)
            state.animatorConnections[animator] = nil
        end
        for track, connection in pairs(state.trackConnections) do
            pcall(function() connection:Disconnect() end)
            state.trackConnections[track] = nil
        end
        shared.safeDestroy(state.entryEvent)
        if state.window then state.window:Destroy() end
        if state.dbWindow then state.dbWindow:Destroy() end
        saveSettings()
    end

    local module = {name = "animation_logger", setup = setup, cleanup = cleanup, api = api}
    dev.modules.animation_logger = module
    shared.addCleanup(cleanup)
    return module
end
