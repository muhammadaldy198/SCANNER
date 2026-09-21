--[[
    LFAMILIA Fish It - Variant + Color Scanner
    One-shot / weekly scanner for Delta Android

    OUTPUT ONLY:
    return {
        [1] = { Name = "Corrupt", Colors = {{165,20,255}, {83,3,223}} },
        ...
    }

    Notes:
      - Scans client-visible ModuleScripts / loaded modules only.
      - Keeps variants whose Colors table is intentionally empty.
      - Supports Color3, ColorSequence, RGB tables, and nested color tables.
      - Does NOT export Chance, SellMultiplier, source paths, or other metadata.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local CONFIG = {
    UI_NAME = "LFAMILIA_VariantColorScanner",
    SAVE_FOLDER = "LFAMILIA_FishIt",
    SAVE_NAME = "VariantDatabase_NEW.lua",

    REQUIRE_TIMEOUT = 2.0,
    MAX_MODULES = 2500,
    MAX_DEPTH = 12,
}

--==============================================================
-- HELPERS
--==============================================================

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function contains(text, needle)
    return string.find(lower(text), lower(needle), 1, true) ~= nil
end

local function getPath(obj)
    local ok, result = pcall(function()
        return obj:GetFullName()
    end)

    return ok and result or tostring(obj.Name)
end

local function luaEscape(text)
    text = tostring(text or "")
    text = text:gsub("\\", "\\\\")
    text = text:gsub("\"", "\\\"")
    text = text:gsub("\r", "\\r")
    text = text:gsub("\n", "\\n")
    return text
end

local function asInteger(v)
    if type(v) == "number" then
        return math.floor(v)
    end

    if type(v) == "string" then
        local n = tonumber(v)
        if n then
            return math.floor(n)
        end
    end

    return nil
end

local function tableGetCI(tbl, wanted)
    if type(tbl) ~= "table" then
        return nil
    end

    local wantedLower = lower(wanted)

    for k, v in pairs(tbl) do
        if type(k) == "string" and lower(k) == wantedLower then
            return v
        end
    end

    return nil
end

local function hasKeyCI(tbl, wanted)
    if type(tbl) ~= "table" then
        return false
    end

    local wantedLower = lower(wanted)

    for k in pairs(tbl) do
        if type(k) == "string" and lower(k) == wantedLower then
            return true
        end
    end

    return false
end

local function getFirstCI(tbl, names)
    for _, name in ipairs(names) do
        local value = tableGetCI(tbl, name)
        if value ~= nil then
            return value
        end
    end

    return nil
end

local NAME_KEYS = {
    "Name",
    "DisplayName",
    "VariantName",
    "MutationName",
    "Title",
}

local ID_KEYS = {
    "Id",
    "ID",
    "Index",
    "VariantId",
    "VariantID",
    "MutationId",
    "MutationID",
}

local TYPE_KEYS = {
    "Type",
    "ItemType",
    "Category",
    "Kind",
}

local COLOR_KEYS = {
    "Colors",
    "Colours",
    "Color",
    "Colour",
    "Gradient",
    "GradientColors",
    "GradientColours",
    "ColorSequence",
    "ColourSequence",
    "PrimaryColor",
    "SecondaryColor",
    "TertiaryColor",
    "Color1",
    "Color2",
    "Color3",
}

local function isVariantWord(value)
    local s = lower(value)
    return s == "variant"
        or s == "variants"
        or s == "mutation"
        or s == "mutations"
        or contains(s, "variant")
        or contains(s, "mutation")
end

local function sourceLooksVariant(source)
    local s = lower(source)
    return contains(s, "variant") or contains(s, "mutation")
end

local function keyLooksVariant(key)
    if type(key) ~= "string" then
        return false
    end

    return isVariantWord(key)
end

--==============================================================
-- COLOR NORMALIZATION
--==============================================================

local function clamp255(n)
    n = tonumber(n)
    if not n or n ~= n then
        return nil
    end

    if n < 0 then n = 0 end
    if n > 255 then n = 255 end

    return math.floor(n + 0.5)
end

local function rgbTriplet(r, g, b)
    r, g, b = tonumber(r), tonumber(g), tonumber(b)

    if not r or not g or not b then
        return nil
    end

    -- Color3-style normalized triplets.
    if r >= 0 and r <= 1
    and g >= 0 and g <= 1
    and b >= 0 and b <= 1 then
        r, g, b = r * 255, g * 255, b * 255
    end

    r, g, b = clamp255(r), clamp255(g), clamp255(b)

    if not r or not g or not b then
        return nil
    end

    return {r, g, b}
end

local function addColor(out, dedupe, rgb)
    if not rgb then
        return
    end

    local key = tostring(rgb[1]) .. "," .. tostring(rgb[2]) .. "," .. tostring(rgb[3])

    if dedupe[key] then
        return
    end

    dedupe[key] = true
    out[#out + 1] = rgb
end

local function collectColors(value, out, dedupe, seen, depth)
    out = out or {}
    dedupe = dedupe or {}
    seen = seen or {}
    depth = depth or 0

    if depth > 6 or value == nil then
        return out
    end

    local valueType = typeof(value)

    if valueType == "Color3" then
        addColor(out, dedupe, rgbTriplet(value.R, value.G, value.B))
        return out
    end

    if valueType == "BrickColor" then
        addColor(out, dedupe, rgbTriplet(value.Color.R, value.Color.G, value.Color.B))
        return out
    end

    if valueType == "ColorSequence" then
        for _, keypoint in ipairs(value.Keypoints) do
            local c = keypoint.Value
            addColor(out, dedupe, rgbTriplet(c.R, c.G, c.B))
        end

        return out
    end

    if type(value) == "string" then
        local hex = value:match("#?(%x%x%x%x%x%x)")
        if hex and #hex == 6 then
            addColor(
                out,
                dedupe,
                rgbTriplet(
                    tonumber(hex:sub(1, 2), 16),
                    tonumber(hex:sub(3, 4), 16),
                    tonumber(hex:sub(5, 6), 16)
                )
            )
            return out
        end

        local rr, gg, bb = value:match("(%d+)%s*[,;]%s*(%d+)%s*[,;]%s*(%d+)")
        if rr and gg and bb then
            addColor(out, dedupe, rgbTriplet(rr, gg, bb))
        end

        return out
    end

    if type(value) ~= "table" then
        return out
    end

    if seen[value] then
        return out
    end
    seen[value] = true

    -- {R=..., G=..., B=...} or {r=..., g=..., b=...}
    local r = tableGetCI(value, "R")
    local g = tableGetCI(value, "G")
    local b = tableGetCI(value, "B")

    if r ~= nil and g ~= nil and b ~= nil then
        addColor(out, dedupe, rgbTriplet(r, g, b))
        return out
    end

    -- Plain RGB tuple: {255, 120, 30}
    if type(value[1]) == "number"
    and type(value[2]) == "number"
    and type(value[3]) == "number" then
        addColor(out, dedupe, rgbTriplet(value[1], value[2], value[3]))

        -- A strict three-number tuple is already a complete color.
        if value[4] == nil then
            return out
        end
    end

    for _, child in pairs(value) do
        if type(child) == "table" then
            collectColors(child, out, dedupe, seen, depth + 1)
        else
            local childType = typeof(child)

            if childType == "Color3"
            or childType == "BrickColor"
            or childType == "ColorSequence" then
                collectColors(child, out, dedupe, seen, depth + 1)
            end
        end
    end

    return out
end

local function extractRecordColors(tbl)
    local colors = {}
    local dedupe = {}
    local hasColorField = false

    for _, keyName in ipairs(COLOR_KEYS) do
        if hasKeyCI(tbl, keyName) then
            hasColorField = true
            local value = tableGetCI(tbl, keyName)
            collectColors(value, colors, dedupe)
        end
    end

    return colors, hasColorField
end

--==============================================================
-- UI
--==============================================================

pcall(function()
    if gethui then
        local old = gethui():FindFirstChild(CONFIG.UI_NAME)
        if old then old:Destroy() end
    end
end)

pcall(function()
    local old = CoreGui:FindFirstChild(CONFIG.UI_NAME)
    if old then old:Destroy() end
end)

local Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.UI_NAME
Gui.ResetOnSpawn = false

local parented = false

pcall(function()
    if gethui then
        Gui.Parent = gethui()
        parented = true
    end
end)

if not parented then
    Gui.Parent = CoreGui
end

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0.95, 0, 0.78, 0)
Main.Position = UDim2.new(0.025, 0, 0.11, 0)
Main.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
Main.BorderSizePixel = 0
Main.Parent = Gui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(65, 65, 85)
Stroke.Thickness = 1
Stroke.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 56)
Header.BackgroundColor3 = Color3.fromRGB(22, 22, 29)
Header.BorderSizePixel = 0
Header.Parent = Main

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 12)
HeaderCorner.Parent = Header

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.new(0, 13, 0, 5)
Title.Size = UDim2.new(1, -60, 0, 24)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextColor3 = Color3.fromRGB(245, 245, 250)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "LFAMILIA • VARIANT + COLOR SCANNER"
Title.Parent = Header

local Status = Instance.new("TextLabel")
Status.BackgroundTransparency = 1
Status.Position = UDim2.new(0, 13, 0, 30)
Status.Size = UDim2.new(1, -60, 0, 18)
Status.Font = Enum.Font.Code
Status.TextSize = 10
Status.TextColor3 = Color3.fromRGB(165, 170, 190)
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Text = "Ready"
Status.Parent = Header

local CloseButton = Instance.new("TextButton")
CloseButton.Size = UDim2.new(0, 38, 0, 34)
CloseButton.Position = UDim2.new(1, -46, 0, 10)
CloseButton.BackgroundColor3 = Color3.fromRGB(52, 25, 30)
CloseButton.TextColor3 = Color3.fromRGB(255, 125, 135)
CloseButton.BorderSizePixel = 0
CloseButton.Font = Enum.Font.GothamBold
CloseButton.TextSize = 14
CloseButton.Text = "X"
CloseButton.Parent = Header

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 8)
CloseCorner.Parent = CloseButton

local ButtonHolder = Instance.new("Frame")
ButtonHolder.BackgroundTransparency = 1
ButtonHolder.Position = UDim2.new(0, 8, 0, 63)
ButtonHolder.Size = UDim2.new(1, -16, 0, 38)
ButtonHolder.Parent = Main

local Grid = Instance.new("UIGridLayout")
Grid.CellSize = UDim2.new(0.24, -3, 0, 34)
Grid.CellPadding = UDim2.new(0.013, 0, 0, 0)
Grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
Grid.Parent = ButtonHolder

local function makeButton(text)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = Color3.fromRGB(31, 31, 42)
    b.TextColor3 = Color3.fromRGB(235, 235, 245)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.Text = text
    b.Parent = ButtonHolder

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = b

    return b
end

local ScanButton = makeButton("SCAN")
local CopyButton = makeButton("COPY LUA")
local SaveButton = makeButton("SAVE LUA")
local AllButton = makeButton("ALL RESULTS")

local ConsoleFrame = Instance.new("ScrollingFrame")
ConsoleFrame.Position = UDim2.new(0, 8, 0, 108)
ConsoleFrame.Size = UDim2.new(1, -16, 1, -116)
ConsoleFrame.BackgroundColor3 = Color3.fromRGB(7, 7, 10)
ConsoleFrame.BorderSizePixel = 0
ConsoleFrame.ScrollBarThickness = 5
ConsoleFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
ConsoleFrame.CanvasSize = UDim2.new()
ConsoleFrame.Parent = Main

local ConsoleCorner = Instance.new("UICorner")
ConsoleCorner.CornerRadius = UDim.new(0, 8)
ConsoleCorner.Parent = ConsoleFrame

local Console = Instance.new("TextLabel")
Console.BackgroundTransparency = 1
Console.Position = UDim2.new(0, 8, 0, 8)
Console.Size = UDim2.new(1, -16, 0, 0)
Console.AutomaticSize = Enum.AutomaticSize.Y
Console.Font = Enum.Font.Code
Console.TextSize = 10
Console.TextColor3 = Color3.fromRGB(205, 215, 210)
Console.TextXAlignment = Enum.TextXAlignment.Left
Console.TextYAlignment = Enum.TextYAlignment.Top
Console.TextWrapped = true
Console.Text = "Ready.\nSCAN will generate VariantDatabase_NEW.lua with Name + Colors only."
Console.Parent = ConsoleFrame

-- Mobile drag
do
    local dragging = false
    local dragStart
    local startPos

    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position
        end
    end)

    Header.InputChanged:Connect(function(input)
        if not dragging then return end

        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart

            Main.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)

    Header.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

local function showText(text)
    Console.Text = tostring(text or "")

    task.defer(function()
        ConsoleFrame.CanvasPosition = Vector2.new(0, 0)
    end)
end

--==============================================================
-- SCANNER STATE
--==============================================================

local EntriesByName = {}
local ColorHintsById = {}
local ColorHintsByName = {}
local DatabaseText = ""
local Scanning = false
local DiscoveryOrder = 0

local function resetState()
    EntriesByName = {}
    ColorHintsById = {}
    ColorHintsByName = {}
    DatabaseText = ""
    DiscoveryOrder = 0
end

local function rememberColorHint(key, colors)
    if type(colors) ~= "table" or #colors == 0 then
        return
    end

    if type(key) == "number" then
        local id = asInteger(key)
        if id and not ColorHintsById[id] then
            ColorHintsById[id] = colors
        end
        return
    end

    if type(key) == "string" then
        local numeric = asInteger(key)
        if numeric and not ColorHintsById[numeric] then
            ColorHintsById[numeric] = colors
        end

        local nameKey = lower(key)
        if nameKey ~= ""
        and nameKey ~= "colors"
        and nameKey ~= "colours"
        and not ColorHintsByName[nameKey] then
            ColorHintsByName[nameKey] = colors
        end
    end
end

local function harvestColorMap(tbl, contextKey, source)
    if type(tbl) ~= "table" then
        return
    end

    local contextText = lower(contextKey)
    local sourceText = lower(source)

    local colorContext =
        contains(contextText, "color")
        or contains(contextText, "colour")
        or contains(sourceText, "variant")
        or contains(sourceText, "mutation")

    if not colorContext then
        return
    end

    for key, value in pairs(tbl) do
        local colors = collectColors(value)

        if #colors > 0 then
            rememberColorHint(key, colors)

            if type(value) == "table" then
                local embeddedName = getFirstCI(value, NAME_KEYS)
                local embeddedId = getFirstCI(value, ID_KEYS)

                if embeddedName then
                    rememberColorHint(tostring(embeddedName), colors)
                end

                if embeddedId then
                    rememberColorHint(asInteger(embeddedId), colors)
                end
            end
        end
    end
end

local function addEntry(name, id, colors, source, confidence)
    if type(name) ~= "string" then
        return
    end

    name = name:gsub("^%s+", ""):gsub("%s+$", "")

    if name == "" then
        return
    end

    local lname = lower(name)

    if lname == "variant"
    or lname == "variants"
    or lname == "mutation"
    or lname == "mutations"
    or lname == "color"
    or lname == "colors" then
        return
    end

    id = asInteger(id)
    colors = type(colors) == "table" and colors or {}

    DiscoveryOrder = DiscoveryOrder + 1

    local candidate = {
        Name = name,
        Id = id,
        Colors = colors,
        Source = tostring(source or "?"),
        Confidence = tonumber(confidence) or 0,
        Order = DiscoveryOrder,
    }

    local existing = EntriesByName[lname]

    if not existing then
        EntriesByName[lname] = candidate
        return
    end

    local existingScore =
        (existing.Confidence or 0) * 100
        + (#existing.Colors * 10)
        + (existing.Id and 2 or 0)

    local candidateScore =
        (candidate.Confidence or 0) * 100
        + (#candidate.Colors * 10)
        + (candidate.Id and 2 or 0)

    if candidateScore > existingScore then
        candidate.Order = existing.Order
        EntriesByName[lname] = candidate
    end
end

--==============================================================
-- RECORD EXTRACTION
--==============================================================

local function inspectRecord(tbl, source, currentKey, contextHint)
    if type(tbl) ~= "table" then
        return
    end

    local colors, hasColorField = extractRecordColors(tbl)

    -- Some Fish It builds keep the visible Colors field empty while the
    -- real Color3/ColorSequence lives deeper in the same variant record.
    if hasColorField and #colors == 0 then
        collectColors(tbl, colors, {})
    end

    -- IMPORTANT: Colors = {} is still a valid known variant record.
    if not hasColorField then
        return
    end

    local typeValue = getFirstCI(tbl, TYPE_KEYS)
    local sourceHint = sourceLooksVariant(source)
    local typeHint = typeValue ~= nil and isVariantWord(typeValue)
    local strongSignature =
        hasKeyCI(tbl, "SellMultiplier")
        and hasKeyCI(tbl, "Chance")

    local variantId =
        getFirstCI(tbl, ID_KEYS)
        or (type(currentKey) == "number" and currentKey or nil)

    local confidence = 0

    if contextHint then confidence = confidence + 5 end
    if sourceHint then confidence = confidence + 4 end
    if typeHint then confidence = confidence + 4 end
    if strongSignature then confidence = confidence + 3 end
    if variantId ~= nil then confidence = confidence + 1 end

    if confidence < 3 then
        return
    end

    local name = getFirstCI(tbl, NAME_KEYS)

    if name == nil
    and type(currentKey) == "string"
    and (contextHint or sourceHint) then
        name = currentKey
    end

    if type(name) ~= "string" then
        return
    end

    addEntry(name, variantId, colors, source, confidence)
end

local function walkTable(root, source)
    local seen = {}
    local rootHint = sourceLooksVariant(source)

    local function walk(tbl, depth, currentKey, contextHint)
        if type(tbl) ~= "table" then
            return
        end

        if depth > CONFIG.MAX_DEPTH then
            return
        end

        if seen[tbl] then
            return
        end
        seen[tbl] = true

        local localHint = contextHint or keyLooksVariant(currentKey)

        inspectRecord(tbl, source, currentKey, localHint)

        -- Second pass source: many versions keep variant colors in a
        -- separate map (by numeric VariantId or by variant name).
        harvestColorMap(tbl, currentKey, source)

        for key, value in pairs(tbl) do
            if type(value) == "table" then
                local childHint = localHint or keyLooksVariant(key)
                walk(value, depth + 1, key, childHint)
            end
        end
    end

    walk(root, 0, nil, rootHint)
end

--==============================================================
-- SAFE MODULE REQUIRE
--==============================================================

local function safeRequire(module)
    local done = false
    local ok = false
    local result

    local thread = task.spawn(function()
        ok, result = pcall(require, module)
        done = true
    end)

    local started = os.clock()

    while not done and (os.clock() - started) < CONFIG.REQUIRE_TIMEOUT do
        task.wait(0.03)
    end

    if not done then
        pcall(function()
            task.cancel(thread)
        end)

        return false, "TIMEOUT"
    end

    return ok, result
end

local function modulePriority(module)
    local path = lower(getPath(module))
    local score = 0

    if contains(path, "variant") then score = score + 250 end
    if contains(path, "mutation") then score = score + 230 end
    if contains(path, "tier") then score = score + 130 end
    if contains(path, "database") then score = score + 100 end
    if contains(path, "config") then score = score + 80 end
    if contains(path, "data") then score = score + 60 end
    if contains(path, "fish") then score = score + 30 end

    return score
end

local function shouldTryModule(module)
    local path = getPath(module)

    if contains(path, "Packages")
    or contains(path, "._Index.") then
        return modulePriority(module) >= 100
    end

    return true
end

--==============================================================
-- BUILD OUTPUT
--==============================================================

local function sortedEntries()
    local list = {}

    for _, entry in pairs(EntriesByName) do
        list[#list + 1] = entry
    end

    table.sort(list, function(a, b)
        if a.Id and b.Id and a.Id ~= b.Id then
            return a.Id < b.Id
        end

        if a.Id and not b.Id then
            return true
        end

        if b.Id and not a.Id then
            return false
        end

        if lower(a.Name) ~= lower(b.Name) then
            return lower(a.Name) < lower(b.Name)
        end

        return a.Order < b.Order
    end)

    return list
end

local function formatColors(colors)
    if type(colors) ~= "table" or #colors == 0 then
        return "{}"
    end

    local out = {}

    for _, rgb in ipairs(colors) do
        out[#out + 1] = string.format(
            "{%d,%d,%d}",
            rgb[1],
            rgb[2],
            rgb[3]
        )
    end

    return "{" .. table.concat(out, ", ") .. "}"
end

local function buildDatabase()
    local list = sortedEntries()

    -- Merge color tables discovered separately from variant records.
    for _, entry in ipairs(list) do
        if #entry.Colors == 0 then
            local hinted = nil

            if entry.Id then
                hinted = ColorHintsById[entry.Id]
            end

            if not hinted then
                hinted = ColorHintsByName[lower(entry.Name)]
            end

            if hinted and #hinted > 0 then
                entry.Colors = hinted
            end
        end
    end

    -- Preserve real IDs when available. Missing/duplicate IDs receive
    -- a stable free numeric slot so the output stays VariantDatabase-compatible.
    local usedIds = {}
    local nextFree = 1

    for _, entry in ipairs(list) do
        local id = asInteger(entry.Id)

        if id and id > 0 and not usedIds[id] then
            entry.OutputId = id
            usedIds[id] = true
        end
    end

    for _, entry in ipairs(list) do
        if not entry.OutputId then
            while usedIds[nextFree] do
                nextFree = nextFree + 1
            end

            entry.OutputId = nextFree
            usedIds[nextFree] = true
            nextFree = nextFree + 1
        end
    end

    table.sort(list, function(a, b)
        return a.OutputId < b.OutputId
    end)

    local out = {
        "-- LFAMILIA Fish It - VariantDatabase.lua",
        "-- Generated by LFAMILIA Variant + Color Scanner",
        "-- Contains ONLY variant Name + Colors",
        "-- Variants found: " .. tostring(#list),
        "",
        "return {",
    }

    for _, entry in ipairs(list) do
        out[#out + 1] = string.format(
            '    [%d] = { Name = "%s", Colors = %s },',
            entry.OutputId,
            luaEscape(entry.Name),
            formatColors(entry.Colors)
        )
    end

    out[#out + 1] = "}"

    DatabaseText = table.concat(out, "\n")
    return list
end

--==============================================================
-- SAVE
--==============================================================

local function ensureFolder()
    if not makefolder then
        return false
    end

    local ok = pcall(function()
        if isfolder then
            if not isfolder(CONFIG.SAVE_FOLDER) then
                makefolder(CONFIG.SAVE_FOLDER)
            end
        else
            makefolder(CONFIG.SAVE_FOLDER)
        end
    end)

    return ok
end

local function saveDatabase()
    if not writefile then
        Status.Text = "writefile() unavailable • use COPY LUA"
        return false
    end

    ensureFolder()

    local path = CONFIG.SAVE_FOLDER .. "/" .. CONFIG.SAVE_NAME

    local ok, err = pcall(function()
        writefile(path, DatabaseText)
    end)

    if not ok then
        Status.Text = "Save failed: " .. tostring(err)
        return false
    end

    Status.Text = "Saved: " .. path
    return true
end

--==============================================================
-- FULL SCAN
--==============================================================

local function runScan()
    if Scanning then
        return
    end

    Scanning = true
    ScanButton.Text = "SCANNING..."
    resetState()

    showText(
        "Scanning client-visible Fish It variant data...\n\n"
        .. "Output is restricted to Variant Name + RGB Colors.\n"
        .. "Chance / SellMultiplier / debug metadata are excluded.\n"
    )

    local modules = {}
    local seenModule = {}

    local function pushModule(module)
        if typeof(module) ~= "Instance"
        or not module:IsA("ModuleScript")
        or seenModule[module]
        or not shouldTryModule(module) then
            return
        end

        seenModule[module] = true
        modules[#modules + 1] = module
    end

    local descendants = ReplicatedStorage:GetDescendants()

    for _, obj in ipairs(descendants) do
        if obj:IsA("ModuleScript") then
            pushModule(obj)
        end
    end

    if getloadedmodules then
        local ok, loaded = pcall(getloadedmodules)

        if ok and type(loaded) == "table" then
            for _, module in ipairs(loaded) do
                pushModule(module)
            end
        end
    end

    table.sort(modules, function(a, b)
        local ap = modulePriority(a)
        local bp = modulePriority(b)

        if ap == bp then
            return getPath(a) < getPath(b)
        end

        return ap > bp
    end)

    local moduleLimit = math.min(#modules, CONFIG.MAX_MODULES)
    local required = 0
    local failed = 0
    local timeout = 0

    for i = 1, moduleLimit do
        local module = modules[i]

        Status.Text =
            "Modules "
            .. tostring(i)
            .. "/"
            .. tostring(moduleLimit)
            .. " • Variants "
            .. tostring(#sortedEntries())

        local ok, data = safeRequire(module)

        if ok then
            required = required + 1

            if type(data) == "table" then
                pcall(walkTable, data, getPath(module))
            end
        else
            if data == "TIMEOUT" then
                timeout = timeout + 1
            else
                failed = failed + 1
            end
        end

        if i % 20 == 0 then
            task.wait()
        end
    end

    local list = buildDatabase()

    local summary = {
        "LFAMILIA VARIANT + COLOR SCAN COMPLETE",
        "==================================================",
        "Variants found   : " .. tostring(#list),
        "Color maps found : " .. tostring((function()
            local n = 0
            for _ in pairs(ColorHintsById) do n = n + 1 end
            for _ in pairs(ColorHintsByName) do n = n + 1 end
            return n
        end)()),
        "Modules required : " .. tostring(required),
        "Modules failed   : " .. tostring(failed),
        "Modules timeout  : " .. tostring(timeout),
        "",
        "Output: Name + Colors ONLY",
        "Saved file: " .. CONFIG.SAVE_FOLDER .. "/" .. CONFIG.SAVE_NAME,
        "",
        "Preview:",
        "==================================================",
    }

    local previewCount = math.min(#list, 30)

    for i = 1, previewCount do
        local e = list[i]

        summary[#summary + 1] = string.format(
            '[%d] = { Name = "%s", Colors = %s },',
            e.OutputId,
            e.Name,
            formatColors(e.Colors)
        )
    end

    if #list > previewCount then
        summary[#summary + 1] =
            "... +" .. tostring(#list - previewCount) .. " more variants"
    end

    showText(table.concat(summary, "\n"))

    Status.Text =
        "DONE • "
        .. tostring(#list)
        .. " variants"

    ScanButton.Text = "SCAN"
    Scanning = false

    if writefile and DatabaseText ~= "" then
        saveDatabase()
    end
end

--==============================================================
-- BUTTONS
--==============================================================

ScanButton.MouseButton1Click:Connect(function()
    task.spawn(runScan)
end)

CopyButton.MouseButton1Click:Connect(function()
    if DatabaseText == "" then
        Status.Text = "Run SCAN first"
        return
    end

    local copy = setclipboard or toclipboard

    if not copy then
        Status.Text = "Clipboard unavailable"
        return
    end

    local ok = pcall(function()
        copy(DatabaseText)
    end)

    Status.Text = ok and "VariantDatabase.lua copied" or "Copy failed"
end)

SaveButton.MouseButton1Click:Connect(function()
    if DatabaseText == "" then
        Status.Text = "Run SCAN first"
        return
    end

    saveDatabase()
end)

AllButton.MouseButton1Click:Connect(function()
    if DatabaseText == "" then
        Status.Text = "Run SCAN first"
        return
    end

    showText(DatabaseText)
end)

CloseButton.MouseButton1Click:Connect(function()
    Gui:Destroy()
end)

--==============================================================
-- AUTO START
--==============================================================

task.delay(0.8, function()
    runScan()
end)
