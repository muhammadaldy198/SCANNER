--[[
    LFAMILIA Fish It - Catchable Database Scanner
    Weekly / One-shot edition for Delta Android

    OUTPUT:
    return {
        ["Name"] = { Id = 123, AssetId = "rbxassetid://123456..." },
        ...
    }

    Designed to extract ALL client-visible catchable database entries,
    NOT only names containing "Fish".

    Examples of intended entries:
      - normal fish
      - Ruby
      - Withering Core
      - Runic Enchant Stone
      - other treasure / junk / event catchables

    It does NOT decompile server-only data.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local CONFIG = {
    UI_NAME = "LFAMILIA_CatchableScanner",
    SAVE_FOLDER = "LFAMILIA_FishIt",
    SAVE_NAME = "FishDatabase_NEW.lua",

    REQUIRE_TIMEOUT = 2.0,
    MAX_MODULES = 2500,
    MAX_DEPTH = 12,

    -- Explicit database branches that are NOT catchables.
    SKIP_PATH_WORDS = {
        ".variants.",
        ".tiers.",
        ".rarities.",
        ".rods.",
        ".baits.",
        ".boats.",
    },

    -- Explicit record types that are not catchable database entries.
    SKIP_TYPES = {
        variant = true,
        mutation = true,
        tier = true,
        rarity = true,
        rod = true,
        bait = true,
        boat = true,
        quest = true,
        gamepass = true,
        product = true,
    },

    IMPORTANT_TARGETS = {
        "Ruby",
        "Withering Core",
        "Runic Enchant Stone",
    }
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

    if ok then
        return result
    end

    return tostring(obj.Name)
end

local function luaEscape(text)
    text = tostring(text or "")
    text = text:gsub("\\", "\\\\")
    text = text:gsub("\"", "\\\"")
    text = text:gsub("\r", "\\r")
    text = text:gsub("\n", "\\n")
    return text
end

local function asNumber(v)
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

local function normalizeAsset(value)
    if value == nil then
        return nil
    end

    if type(value) == "number" then
        if value >= 1000 then
            return "rbxassetid://" .. tostring(math.floor(value))
        end
        return nil
    end

    local s = tostring(value)

    if s == "" then
        return nil
    end

    local id =
        s:match("rbxassetid://(%d+)")
        or s:match("[Aa]sset[Ii]d[^%d]*(%d+)")
        or s:match("rbxthumb://[^%d]*[Ii][Dd]=(%d+)")
        or s:match("[?&][Ii][Dd]=(%d+)")
        or s:match("^%s*(%d%d%d%d%d%d+)%s*$")

    if id then
        return "rbxassetid://" .. id
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
    "FishName",
    "ItemName",
    "Title",
}

local ID_KEYS = {
    "Id",
    "ID",
    "FishId",
    "FishID",
    "ItemId",
    "ItemID",
    "Index",
}

local TYPE_KEYS = {
    "Type",
    "ItemType",
    "Category",
    "Kind",
}

local ASSET_KEYS = {
    "AssetId",
    "AssetID",
    "Icon",
    "IconId",
    "IconID",
    "Image",
    "ImageId",
    "ImageID",
    "Thumbnail",
    "ThumbnailId",
    "ThumbnailID",
    "Texture",
    "TextureId",
    "TextureID",
}

local function findAssetInTable(tbl, depth, seen)
    if type(tbl) ~= "table" then
        return nil
    end

    depth = depth or 0
    if depth > 2 then
        return nil
    end

    seen = seen or {}
    if seen[tbl] then
        return nil
    end
    seen[tbl] = true

    -- Asset-like fields have highest priority.
    for _, keyName in ipairs(ASSET_KEYS) do
        local value = tableGetCI(tbl, keyName)
        local asset = normalizeAsset(value)

        if asset then
            return asset
        end
    end

    -- Some games wrap icon data inside one extra table.
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            local keyText = lower(k)

            if keyText:find("icon", 1, true)
            or keyText:find("image", 1, true)
            or keyText:find("thumbnail", 1, true)
            or keyText:find("asset", 1, true)
            or keyText == "data" then

                local asset = findAssetInTable(v, depth + 1, seen)
                if asset then
                    return asset
                end
            end
        end
    end

    return nil
end

local function isSkippedType(typeValue)
    if typeValue == nil then
        return false
    end

    local t = lower(typeValue)
    return CONFIG.SKIP_TYPES[t] == true
end

local function pathShouldBeSkipped(path)
    local p = lower(path)

    for _, word in ipairs(CONFIG.SKIP_PATH_WORDS) do
        if p:find(word, 1, true) then
            return true
        end
    end

    return false
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
Main.Size = UDim2.new(0.95, 0, 0.82, 0)
Main.Position = UDim2.new(0.025, 0, 0.09, 0)
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
Title.Text = "LFAMILIA • CATCHABLE DATABASE SCANNER"
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
ButtonHolder.Size = UDim2.new(1, -16, 0, 78)
ButtonHolder.Parent = Main

local Grid = Instance.new("UIGridLayout")
Grid.CellSize = UDim2.new(0.32, -3, 0, 34)
Grid.CellPadding = UDim2.new(0.02, 0, 0, 6)
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
local TargetsButton = makeButton("TARGETS")
local MissingButton = makeButton("MISSING")
local AllButton = makeButton("ALL RESULTS")

local ConsoleFrame = Instance.new("ScrollingFrame")
ConsoleFrame.Position = UDim2.new(0, 8, 0, 148)
ConsoleFrame.Size = UDim2.new(1, -16, 1, -156)
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
Console.Text = "Ready.\nSCAN will generate a clean FishDatabase.lua."
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
local MissingByKey = {}
local DuplicateNotes = {}

local DatabaseText = ""
local MissingText = ""
local TargetsText = ""

local Scanning = false

local function resetState()
    EntriesByName = {}
    MissingByKey = {}
    DuplicateNotes = {}
    DatabaseText = ""
    MissingText = ""
    TargetsText = ""
end

local function addMissing(name, id, typeValue, source)
    if not name or not id then
        return
    end

    if isSkippedType(typeValue) then
        return
    end

    local key = tostring(name) .. "|" .. tostring(id)

    if not MissingByKey[key] then
        MissingByKey[key] = {
            Name = tostring(name),
            Id = id,
            Type = tostring(typeValue or "?"),
            Source = tostring(source or "?"),
        }
    end
end

local function addEntry(name, id, assetId, typeValue, source)
    if type(name) ~= "string" then
        return
    end

    name = name:gsub("^%s+", ""):gsub("%s+$", "")

    if name == "" then
        return
    end

    id = asNumber(id)
    if not id then
        return
    end

    if isSkippedType(typeValue) then
        return
    end

    assetId = normalizeAsset(assetId)

    if not assetId then
        addMissing(name, id, typeValue, source)
        return
    end

    local existing = EntriesByName[name]

    local candidate = {
        Name = name,
        Id = id,
        AssetId = assetId,
        Type = tostring(typeValue or "?"),
        Source = tostring(source or "?"),
    }

    if not existing then
        EntriesByName[name] = candidate
        return
    end

    if existing.Id == id and existing.AssetId == assetId then
        return
    end

    -- If the same name appears twice, prefer the larger database Id.
    -- Keep a note so it is visible instead of silently hiding it.
    DuplicateNotes[#DuplicateNotes + 1] =
        string.format(
            "%s | old(Id=%s, Asset=%s) | new(Id=%s, Asset=%s)",
            name,
            tostring(existing.Id),
            tostring(existing.AssetId),
            tostring(id),
            tostring(assetId)
        )

    if id > existing.Id then
        EntriesByName[name] = candidate
    end
end

--==============================================================
-- RECORD EXTRACTION
--==============================================================

local function inspectRecord(tbl, parentTbl, source)
    if type(tbl) ~= "table" then
        return
    end

    local name = getFirstCI(tbl, NAME_KEYS)
    local id = getFirstCI(tbl, ID_KEYS)

    if name == nil or id == nil then
        return
    end

    if type(name) ~= "string" then
        return
    end

    id = asNumber(id)
    if not id then
        return
    end

    local typeValue = getFirstCI(tbl, TYPE_KEYS)

    if isSkippedType(typeValue) then
        return
    end

    local asset = findAssetInTable(tbl)

    -- Some modules keep Data.Name/Data.Id but keep Icon at the root.
    if not asset and type(parentTbl) == "table" then
        asset = findAssetInTable(parentTbl)
    end

    if asset then
        addEntry(name, id, asset, typeValue, source)
    else
        addMissing(name, id, typeValue, source)
    end
end

local function walkTable(root, source)
    local seen = {}

    local function walk(tbl, parentTbl, depth)
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

        inspectRecord(tbl, parentTbl, source)

        for _, value in pairs(tbl) do
            if type(value) == "table" then
                walk(value, tbl, depth + 1)
            end
        end
    end

    walk(root, nil, 0)
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

    if contains(path, "fish") then score = score + 100 end
    if contains(path, "catch") then score = score + 90 end
    if contains(path, "item") then score = score + 70 end
    if contains(path, "index") then score = score + 60 end
    if contains(path, "database") then score = score + 60 end
    if contains(path, "catalog") then score = score + 50 end
    if contains(path, "collect") then score = score + 40 end
    if contains(path, "loot") then score = score + 40 end

    return score
end

local function shouldTryModule(module)
    local path = getPath(module)

    if pathShouldBeSkipped(path) then
        return false
    end

    -- Avoid requiring huge dependency package trees unless their path
    -- specifically looks related to catchables/items/fish.
    if contains(path, "Packages")
    or contains(path, "._Index.") then
        return modulePriority(module) > 0
    end

    return true
end

--==============================================================
-- INSTANCE FALLBACK
--==============================================================

local function scanInstanceFallback(obj)
    local path = getPath(obj)

    if pathShouldBeSkipped(path) then
        return
    end

    local attrs

    pcall(function()
        attrs = obj:GetAttributes()
    end)

    if type(attrs) == "table" then
        local name =
            getFirstCI(attrs, NAME_KEYS)
            or (obj.Name ~= "" and obj.Name or nil)

        local id = getFirstCI(attrs, ID_KEYS)
        local typeValue = getFirstCI(attrs, TYPE_KEYS)

        if name and id and not isSkippedType(typeValue) then
            local asset

            for _, key in ipairs(ASSET_KEYS) do
                local value = tableGetCI(attrs, key)
                asset = normalizeAsset(value)

                if asset then
                    break
                end
            end

            if asset then
                addEntry(name, id, asset, typeValue, path)
            elseif id then
                addMissing(name, asNumber(id), typeValue, path)
            end
        end
    end

    if obj:IsA("StringValue")
    or obj:IsA("IntValue")
    or obj:IsA("NumberValue") then
        -- ValueObjects alone are not enough to confidently build a record.
        -- They are intentionally ignored unless attributes already formed one.
    end
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
        if a.Id == b.Id then
            return lower(a.Name) < lower(b.Name)
        end

        return a.Id < b.Id
    end)

    return list
end

local function buildDatabase()
    local list = sortedEntries()

    local out = {
        "-- LFAMILIA Fish It - FishDatabase.lua",
        "-- Generated by LFAMILIA Catchable Database Scanner",
        "-- Returns: { [CatchableName] = { Id = number, AssetId = string } }",
        "-- Entries found: " .. tostring(#list),
        "",
        "return {",
    }

    for _, entry in ipairs(list) do
        out[#out + 1] = string.format(
            '    ["%s"] = { Id = %d, AssetId = "%s" },',
            luaEscape(entry.Name),
            entry.Id,
            entry.AssetId
        )
    end

    out[#out + 1] = "}"

    DatabaseText = table.concat(out, "\n")

    return list
end

local function buildMissing()
    local list = {}

    for _, item in pairs(MissingByKey) do
        -- Do not show items that later received a valid asset entry.
        local existing = EntriesByName[item.Name]

        if not existing or existing.Id ~= item.Id then
            list[#list + 1] = item
        end
    end

    table.sort(list, function(a, b)
        if a.Id == b.Id then
            return lower(a.Name) < lower(b.Name)
        end

        return a.Id < b.Id
    end)

    local out = {
        "MISSING ASSET CANDIDATES",
        "These records had Name + Id but no usable AssetId/Icon.",
        "They are NOT inserted into FishDatabase_NEW.lua.",
        "==================================================",
    }

    if #list == 0 then
        out[#out + 1] = "None."
    else
        for _, item in ipairs(list) do
            out[#out + 1] = string.format(
                "Id=%s | Name=%s | Type=%s | Source=%s",
                tostring(item.Id),
                tostring(item.Name),
                tostring(item.Type),
                tostring(item.Source)
            )
        end
    end

    if #DuplicateNotes > 0 then
        out[#out + 1] = ""
        out[#out + 1] = "DUPLICATE NAME NOTES"
        out[#out + 1] = "=================================================="

        for _, note in ipairs(DuplicateNotes) do
            out[#out + 1] = note
        end
    end

    MissingText = table.concat(out, "\n")
end

local function buildTargets()
    local out = {
        "IMPORTANT TARGETS",
        "==================================================",
    }

    for _, target in ipairs(CONFIG.IMPORTANT_TARGETS) do
        local found = nil

        for name, entry in pairs(EntriesByName) do
            if lower(name) == lower(target) then
                found = entry
                break
            end
        end

        if found then
            out[#out + 1] = string.format(
                "[FOUND] %s | Id=%s | AssetId=%s",
                found.Name,
                tostring(found.Id),
                found.AssetId
            )
        else
            out[#out + 1] = "[NOT FOUND] " .. target
        end
    end

    TargetsText = table.concat(out, "\n")
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

    -- Save missing/debug separately.
    pcall(function()
        writefile(
            CONFIG.SAVE_FOLDER .. "/FishDatabase_MissingAssets.txt",
            MissingText
        )
    end)

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
        "Scanning client-visible Fish It database...\n\n"
        .. "This scanner does NOT filter names by the word Fish.\n"
        .. "Ruby / Withering Core / Runic Enchant Stone can be included.\n"
    )

    -- Collect modules.
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
        return modulePriority(a) > modulePriority(b)
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
            .. " • Entries "
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

    -- Attributes fallback.
    for i, obj in ipairs(descendants) do
        pcall(scanInstanceFallback, obj)

        if i % 400 == 0 then
            task.wait()
        end
    end

    local list = buildDatabase()
    buildMissing()
    buildTargets()

    local summary = {
        "LFAMILIA CATCHABLE DATABASE SCAN COMPLETE",
        "==================================================",
        "Database entries : " .. tostring(#list),
        "Modules required : " .. tostring(required),
        "Modules failed   : " .. tostring(failed),
        "Modules timeout  : " .. tostring(timeout),
        "",
        TargetsText,
        "",
        "Database output is ready.",
        "Use COPY LUA or SAVE LUA.",
        "",
        "Preview:",
        "==================================================",
    }

    local previewCount = math.min(#list, 20)

    for i = 1, previewCount do
        local e = list[i]

        summary[#summary + 1] = string.format(
            '["%s"] = { Id = %s, AssetId = "%s" },',
            e.Name,
            tostring(e.Id),
            e.AssetId
        )
    end

    if #list > previewCount then
        summary[#summary + 1] =
            "... +" .. tostring(#list - previewCount) .. " more entries"
    end

    showText(table.concat(summary, "\n"))

    Status.Text =
        "DONE • "
        .. tostring(#list)
        .. " clean entries"

    ScanButton.Text = "SCAN"
    Scanning = false

    -- Auto-save when supported.
    if writefile then
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

    Status.Text = ok and "FishDatabase.lua copied" or "Copy failed"
end)

SaveButton.MouseButton1Click:Connect(function()
    if DatabaseText == "" then
        Status.Text = "Run SCAN first"
        return
    end

    saveDatabase()
end)

TargetsButton.MouseButton1Click:Connect(function()
    if TargetsText == "" then
        Status.Text = "Run SCAN first"
        return
    end

    showText(TargetsText)
end)

MissingButton.MouseButton1Click:Connect(function()
    if MissingText == "" then
        Status.Text = "Run SCAN first"
        return
    end

    showText(MissingText)
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
