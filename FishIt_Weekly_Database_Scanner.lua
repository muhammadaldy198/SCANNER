--[[
    LFAMILIA Fish It Database Scanner - Weekly Edition
    One-shot scanner for Delta Android / mobile executors.

    Purpose:
      - Scan client-visible Fish It data after weekly updates
      - Find Ruby
      - Find Withering Core
      - Find fish names / IDs / icons / image asset IDs
      - Scan ReplicatedStorage objects, attributes, ValueObjects
      - Scan accessible ModuleScript return tables
      - Copy / Save / Clear results from a mobile-friendly UI

    Notes:
      - This does NOT decompile server-only code or inaccessible data.
      - writefile() saves to the executor's workspace when supported.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local CONFIG = {
    UIName = "LFAMILIA_FishIt_WeeklyScanner",
    SaveFolder = "LFAMILIA_FishIt",
    ModuleTimeout = 2,
    MaxModules = 1800,
    MaxTableDepth = 14,
    MaxConsoleLines = 1800,
    RefreshEvery = 30,
}

--==============================================================
-- CLEAN OLD UI
--==============================================================

pcall(function()
    if gethui then
        local old = gethui():FindFirstChild(CONFIG.UIName)
        if old then old:Destroy() end
    end
end)

pcall(function()
    local old = CoreGui:FindFirstChild(CONFIG.UIName)
    if old then old:Destroy() end
end)

--==============================================================
-- UI
--==============================================================

local Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.UIName
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false

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

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(70, 70, 90)
MainStroke.Thickness = 1
MainStroke.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 54)
Header.BackgroundColor3 = Color3.fromRGB(22, 22, 29)
Header.BorderSizePixel = 0
Header.Parent = Main

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 12)
HeaderCorner.Parent = Header

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.new(0, 14, 0, 5)
Title.Size = UDim2.new(1, -65, 0, 23)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 15
Title.TextColor3 = Color3.fromRGB(245, 245, 250)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "LFAMILIA • FISH IT WEEKLY SCANNER"
Title.Parent = Header

local Status = Instance.new("TextLabel")
Status.BackgroundTransparency = 1
Status.Position = UDim2.new(0, 14, 0, 29)
Status.Size = UDim2.new(1, -70, 0, 18)
Status.Font = Enum.Font.Code
Status.TextSize = 10
Status.TextColor3 = Color3.fromRGB(160, 165, 185)
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Text = "Ready"
Status.Parent = Header

local Close = Instance.new("TextButton")
Close.Size = UDim2.new(0, 38, 0, 34)
Close.Position = UDim2.new(1, -46, 0, 10)
Close.BackgroundColor3 = Color3.fromRGB(52, 25, 30)
Close.TextColor3 = Color3.fromRGB(255, 125, 135)
Close.Text = "X"
Close.Font = Enum.Font.GothamBold
Close.TextSize = 14
Close.BorderSizePixel = 0
Close.Parent = Header

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 8)
CloseCorner.Parent = Close

local ButtonHolder = Instance.new("Frame")
ButtonHolder.BackgroundTransparency = 1
ButtonHolder.Position = UDim2.new(0, 8, 0, 61)
ButtonHolder.Size = UDim2.new(1, -16, 0, 78)
ButtonHolder.Parent = Main

local Grid = Instance.new("UIGridLayout")
Grid.CellSize = UDim2.new(0.32, -3, 0, 34)
Grid.CellPadding = UDim2.new(0.02, 0, 0, 6)
Grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
Grid.Parent = ButtonHolder

local function newButton(text)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = Color3.fromRGB(31, 31, 42)
    b.TextColor3 = Color3.fromRGB(235, 235, 245)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.Text = text

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = b

    b.Parent = ButtonHolder
    return b
end

local ScanButton = newButton("FULL SCAN")
local TargetButton = newButton("TARGETS")
local FishButton = newButton("FISH/ASSETS")
local CopyButton = newButton("COPY")
local SaveButton = newButton("SAVE")
local ClearButton = newButton("CLEAR")

local ConsoleFrame = Instance.new("ScrollingFrame")
ConsoleFrame.Position = UDim2.new(0, 8, 0, 146)
ConsoleFrame.Size = UDim2.new(1, -16, 1, -154)
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
Console.Text = "LFAMILIA Weekly Scanner\nStarting...\n"
Console.Parent = ConsoleFrame

--==============================================================
-- MOBILE DRAG
--==============================================================

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

--==============================================================
-- OUTPUT
--==============================================================

local Output = {}
local TargetLines = {}
local FishAssetLines = {}
local SeenOutput = {}
local SeenTables = {}

local function refreshConsole(lines)
    lines = lines or Output
    local count = #lines
    local first = math.max(1, count - CONFIG.MaxConsoleLines + 1)

    local visible = {}
    for i = first, count do
        visible[#visible + 1] = lines[i]
    end

    Console.Text = table.concat(visible, "\n")

    task.defer(function()
        ConsoleFrame.CanvasPosition = Vector2.new(0, math.max(0, Console.AbsoluteSize.Y))
    end)
end

local function add(line)
    line = tostring(line or "")
    Output[#Output + 1] = line

    if #Output % CONFIG.RefreshEvery == 0 then
        refreshConsole()
    end
end

local function addUnique(line)
    line = tostring(line)
    if SeenOutput[line] then return end
    SeenOutput[line] = true
    add(line)
end

local function addTarget(line)
    line = tostring(line)
    if not table.find(TargetLines, line) then
        TargetLines[#TargetLines + 1] = line
    end
    addUnique(line)
end

local function addFishAsset(line)
    line = tostring(line)
    if not table.find(FishAssetLines, line) then
        FishAssetLines[#FishAssetLines + 1] = line
    end
    addUnique(line)
end

local function section(name)
    add("")
    add("==================================================")
    add(name)
    add("==================================================")
end

--==============================================================
-- HELPERS
--==============================================================

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function contains(text, search)
    return string.find(lower(text), lower(search), 1, true) ~= nil
end

local function containsAny(text, words)
    text = lower(text)
    for _, word in ipairs(words) do
        if string.find(text, lower(word), 1, true) then
            return true
        end
    end
    return false
end

local TARGET_WORDS = {
    "ruby",
    "withering core",
    "withering"
}

local DATABASE_WORDS = {
    "fish", "fishes", "fishing",
    "item", "items",
    "variant", "variants",
    "mutation", "mutations",
    "tier", "tiers", "rarity",
    "index", "catalog", "database", "data",
    "icon", "image", "thumbnail", "texture", "asset"
}

local ASSET_KEYS = {
    "asset", "assetid",
    "icon", "iconid",
    "image", "imageid",
    "thumbnail", "thumbnailid",
    "texture", "textureid",
    "decal"
}

local NAME_KEYS = {
    "name", "displayname", "itemname", "fishname", "title"
}

local function isTarget(value)
    local text = lower(value)
    for _, word in ipairs(TARGET_WORDS) do
        if string.find(text, word, 1, true) then
            return true
        end
    end
    return false
end

local function isAssetKey(key)
    return containsAny(key, ASSET_KEYS)
end

local function isNameKey(key)
    local k = lower(key)
    for _, name in ipairs(NAME_KEYS) do
        if k == name then return true end
    end
    return false
end

local function getPath(obj)
    local ok, path = pcall(function()
        return obj:GetFullName()
    end)

    if ok then
        return path
    end

    return tostring(obj.Name)
end

local function formatValue(value)
    local valueType = typeof(value)

    if valueType == "Color3" then
        return string.format(
            "Color3(%d,%d,%d)",
            math.floor(value.R * 255),
            math.floor(value.G * 255),
            math.floor(value.B * 255)
        )
    elseif valueType == "ColorSequence" then
        return "ColorSequence"
    end

    return tostring(value)
end

--==============================================================
-- ASSET ID EXTRACTION
--==============================================================

local function extractAssetIDs(value, key)
    local found = {}
    local dup = {}

    local function push(id)
        id = tostring(id)
        if id ~= "" and not dup[id] then
            dup[id] = true
            found[#found + 1] = id
        end
    end

    if type(value) == "number" then
        if isAssetKey(key) and value > 1000 then
            push(math.floor(value))
        end
        return found
    end

    if type(value) ~= "string" then
        return found
    end

    for id in string.gmatch(value, "rbxassetid://(%d+)") do
        push(id)
    end

    for id in string.gmatch(
        value,
        "[Aa][Ss][Ss][Ee][Tt][Ii][Dd][^%d]*(%d+)"
    ) do
        push(id)
    end

    if isAssetKey(key) then
        for id in string.gmatch(value, "(%d%d%d%d%d%d+)") do
            push(id)
        end
    end

    return found
end

--==============================================================
-- TABLE SCANNER
--==============================================================

local function identifyEntity(tbl)
    local name =
        rawget(tbl, "Name")
        or rawget(tbl, "name")
        or rawget(tbl, "DisplayName")
        or rawget(tbl, "displayName")
        or rawget(tbl, "ItemName")
        or rawget(tbl, "FishName")
        or rawget(tbl, "Title")

    local entityType =
        rawget(tbl, "Type")
        or rawget(tbl, "type")
        or rawget(tbl, "ItemType")
        or rawget(tbl, "Category")

    local id =
        rawget(tbl, "Id")
        or rawget(tbl, "ID")
        or rawget(tbl, "id")
        or rawget(tbl, "Index")

    return name, entityType, id
end

local function scanTable(tbl, source, path, depth)
    if type(tbl) ~= "table" then return end

    depth = depth or 0
    if depth > CONFIG.MaxTableDepth then return end
    if SeenTables[tbl] then return end
    SeenTables[tbl] = true

    local entityName, entityType, databaseId = identifyEntity(tbl)

    if entityName ~= nil then
        local entityLine =
            "[ENTITY]"
            .. " Name=" .. tostring(entityName)
            .. " | Type=" .. tostring(entityType or "?")
            .. " | DB_ID=" .. tostring(databaseId or "?")
            .. " | Source=" .. tostring(source)
            .. " | Path=" .. tostring(path)

        if containsAny(
            tostring(source) .. " " .. tostring(path) .. " "
            .. tostring(entityName) .. " " .. tostring(entityType or ""),
            DATABASE_WORDS
        ) then
            addFishAsset(entityLine)
        else
            addUnique(entityLine)
        end

        if isTarget(entityName) then
            addTarget(
                "[!!! TARGET ENTITY !!!]"
                .. " Name=" .. tostring(entityName)
                .. " | Type=" .. tostring(entityType or "?")
                .. " | DB_ID=" .. tostring(databaseId or "?")
                .. " | Source=" .. tostring(source)
                .. " | Path=" .. tostring(path)
            )
        end
    end

    for key, value in pairs(tbl) do
        local keyString = tostring(key)
        local valueType = type(value)
        local nextPath = tostring(path) .. "." .. keyString

        if valueType == "table" then
            scanTable(value, source, nextPath, depth + 1)

        elseif valueType == "string"
        or valueType == "number"
        or valueType == "boolean" then

            local valueString = formatValue(value)

            if isNameKey(keyString)
            or isAssetKey(keyString)
            or containsAny(keyString, DATABASE_WORDS) then
                addFishAsset(
                    "[FIELD]"
                    .. " Key=" .. keyString
                    .. " | Value=" .. valueString
                    .. " | Source=" .. tostring(source)
                    .. " | Path=" .. nextPath
                )
            end

            local ids = extractAssetIDs(value, keyString)

            for _, assetId in ipairs(ids) do
                local line =
                    "[ASSET]"
                    .. " ID=" .. assetId
                    .. " | Key=" .. keyString
                    .. " | Value=" .. valueString
                    .. " | Source=" .. tostring(source)
                    .. " | Path=" .. nextPath

                addFishAsset(line)

                if isTarget(
                    tostring(entityName or "") .. " "
                    .. tostring(path) .. " "
                    .. keyString .. " "
                    .. valueString
                ) then
                    addTarget("[!!! TARGET ASSET !!!] " .. line)
                end
            end

            if isTarget(keyString)
            or isTarget(valueString) then
                addTarget(
                    "[!!! TARGET MATCH !!!]"
                    .. " Key=" .. keyString
                    .. " | Value=" .. valueString
                    .. " | Source=" .. tostring(source)
                    .. " | Path=" .. nextPath
                )
            end
        end
    end
end

--==============================================================
-- SAFE REQUIRE
--==============================================================

local function safeRequire(module)
    local finished = false
    local success = false
    local returned

    local thread = task.spawn(function()
        success, returned = pcall(require, module)
        finished = true
    end)

    local started = os.clock()

    while not finished
    and os.clock() - started < CONFIG.ModuleTimeout do
        task.wait(0.03)
    end

    if not finished then
        pcall(function()
            task.cancel(thread)
        end)
        return false, "TIMEOUT"
    end

    return success, returned
end

local function modulePriority(module)
    local path = lower(getPath(module))

    if isTarget(path) then return 100 end
    if containsAny(path, {"fish", "fishes"}) then return 95 end
    if containsAny(path, {"variant", "mutation"}) then return 90 end
    if containsAny(path, {"item", "index", "catalog", "database"}) then return 85 end
    if containsAny(path, {"tier", "rarity"}) then return 80 end
    if contains(path, "data") then return 60 end

    return 0
end

local function scanModule(module)
    if not module or not module:IsA("ModuleScript") then return end

    local source = getPath(module)
    local priority = modulePriority(module)

    if priority > 0 then
        addUnique(
            "[MODULE]"
            .. " Priority=" .. tostring(priority)
            .. " | " .. source
        )
    end

    local success, data = safeRequire(module)

    if not success then
        if priority > 0 then
            addUnique(
                "[MODULE FAILED]"
                .. " " .. source
                .. " | Reason=" .. tostring(data)
            )
        end
        return
    end

    if type(data) == "table" then
        scanTable(data, source, "ROOT", 0)

    elseif type(data) == "string"
    or type(data) == "number" then
        if isTarget(data) then
            addTarget(
                "[!!! TARGET MODULE VALUE !!!]"
                .. " Module=" .. source
                .. " | Value=" .. tostring(data)
            )
        end
    end
end

--==============================================================
-- OBJECT SCANNER
--==============================================================

local function scanObject(obj)
    if not obj then return end

    local path = getPath(obj)

    if isTarget(obj.Name)
    or isTarget(path) then
        addTarget(
            "[!!! TARGET OBJECT !!!]"
            .. " Name=" .. tostring(obj.Name)
            .. " | Class=" .. tostring(obj.ClassName)
            .. " | Path=" .. path
        )
    end

    local okAttributes, attributes = pcall(function()
        return obj:GetAttributes()
    end)

    if okAttributes and attributes then
        for key, value in pairs(attributes) do
            local valueString = formatValue(value)

            if isNameKey(key)
            or isAssetKey(key)
            or containsAny(key, DATABASE_WORDS) then
                addFishAsset(
                    "[ATTRIBUTE]"
                    .. " " .. tostring(key)
                    .. "=" .. valueString
                    .. " | Object=" .. path
                )
            end

            for _, assetId in ipairs(extractAssetIDs(value, tostring(key))) do
                local line =
                    "[ATTRIBUTE ASSET]"
                    .. " ID=" .. assetId
                    .. " | Key=" .. tostring(key)
                    .. " | Value=" .. valueString
                    .. " | Object=" .. path

                addFishAsset(line)

                if isTarget(
                    path .. " "
                    .. tostring(key) .. " "
                    .. valueString
                ) then
                    addTarget("[!!! TARGET ASSET !!!] " .. line)
                end
            end

            if isTarget(key)
            or isTarget(valueString) then
                addTarget(
                    "[!!! TARGET ATTRIBUTE !!!]"
                    .. " Object=" .. path
                    .. " | " .. tostring(key)
                    .. "=" .. valueString
                )
            end
        end
    end

    if obj:IsA("StringValue")
    or obj:IsA("IntValue")
    or obj:IsA("NumberValue") then
        local ok, value = pcall(function()
            return obj.Value
        end)

        if ok then
            local valueString = formatValue(value)

            if isNameKey(obj.Name)
            or isAssetKey(obj.Name)
            or containsAny(obj.Name, DATABASE_WORDS) then
                addFishAsset(
                    "[VALUE]"
                    .. " Name=" .. obj.Name
                    .. " | Value=" .. valueString
                    .. " | Object=" .. path
                )
            end

            for _, assetId in ipairs(extractAssetIDs(value, obj.Name)) do
                addFishAsset(
                    "[VALUE ASSET]"
                    .. " ID=" .. assetId
                    .. " | Object=" .. path
                    .. " | Value=" .. valueString
                )
            end

            if isTarget(obj.Name)
            or isTarget(valueString) then
                addTarget(
                    "[!!! TARGET VALUE !!!]"
                    .. " Object=" .. path
                    .. " | Value=" .. valueString
                )
            end
        end
    end

    local propertyName
    local propertyValue

    if obj:IsA("ImageLabel")
    or obj:IsA("ImageButton") then
        propertyName = "Image"
        propertyValue = obj.Image

    elseif obj:IsA("Decal")
    or obj:IsA("Texture") then
        propertyName = "Texture"
        propertyValue = obj.Texture
    end

    if propertyName and propertyValue then
        for _, assetId in ipairs(extractAssetIDs(propertyValue, propertyName)) do
            local line =
                "[OBJECT ASSET]"
                .. " ID=" .. assetId
                .. " | Property=" .. propertyName
                .. " | Value=" .. tostring(propertyValue)
                .. " | Object=" .. path

            addFishAsset(line)

            if isTarget(path) then
                addTarget("[!!! TARGET ASSET !!!] " .. line)
            end
        end
    end
end

--==============================================================
-- SAVE
--==============================================================

local function saveResults(auto)
    if not writefile then
        Status.Text = "writefile() unavailable • use COPY"
        return false
    end

    local folder = CONFIG.SaveFolder

    if makefolder then
        pcall(function()
            local exists = false

            if isfolder then
                exists = isfolder(folder)
            end

            if not exists then
                makefolder(folder)
            end
        end)
    end

    local filename =
        folder
        .. "/FishIt_Weekly_"
        .. tostring(os.time())
        .. ".txt"

    local ok, err = pcall(function()
        writefile(filename, table.concat(Output, "\n"))
    end)

    if ok then
        add("")
        add("[SAVED] " .. filename)
        refreshConsole()

        if auto then
            Status.Text = "DONE • Auto-saved: " .. filename
        else
            Status.Text = "Saved: " .. filename
        end

        return true
    end

    Status.Text = "Save failed: " .. tostring(err)
    return false
end

--==============================================================
-- FULL ONE-SHOT SCAN
--==============================================================

local Scanning = false

local function fullScan()
    if Scanning then return end

    Scanning = true
    ScanButton.Text = "SCANNING..."

    Output = {}
    TargetLines = {}
    FishAssetLines = {}
    SeenOutput = {}
    SeenTables = {}

    section("LFAMILIA FISH IT WEEKLY SCAN")

    add("PlaceId: " .. tostring(game.PlaceId))
    add("GameId : " .. tostring(game.GameId))
    add("Mode   : ONE-SHOT / WEEKLY")
    add("")
    add("Main targets:")
    add(" - Ruby")
    add(" - Withering Core")
    add(" - All fish visible to client")
    add(" - New fish")
    add(" - Icon / Image / AssetId / Thumbnail")
    add("")

    -- Pass 1: ReplicatedStorage objects
    local descendants = ReplicatedStorage:GetDescendants()

    section("PASS 1 • REPLICATED OBJECTS")
    add("Objects found: " .. tostring(#descendants))

    for i, obj in ipairs(descendants) do
        pcall(scanObject, obj)

        if i % 250 == 0 then
            Status.Text =
                "Objects "
                .. tostring(i)
                .. "/"
                .. tostring(#descendants)
            refreshConsole()
            task.wait()
        end
    end

    -- Pass 2: ModuleScripts in ReplicatedStorage
    section("PASS 2 • MODULES")

    local modules = {}
    local moduleSeen = {}

    local function addModule(module)
        if not module
        or not module:IsA("ModuleScript")
        or moduleSeen[module] then
            return
        end

        moduleSeen[module] = true
        modules[#modules + 1] = module
    end

    for _, obj in ipairs(descendants) do
        if obj:IsA("ModuleScript") then
            addModule(obj)
        end
    end

    -- Optional: already-loaded modules exposed by executor
    if getloadedmodules then
        local ok, loaded = pcall(getloadedmodules)

        if ok and type(loaded) == "table" then
            for _, module in ipairs(loaded) do
                if typeof(module) == "Instance"
                and module:IsA("ModuleScript") then
                    addModule(module)
                end
            end
        end
    end

    table.sort(modules, function(a, b)
        return modulePriority(a) > modulePriority(b)
    end)

    add("Modules found: " .. tostring(#modules))

    local maxModules = math.min(#modules, CONFIG.MaxModules)

    for i = 1, maxModules do
        local module = modules[i]

        Status.Text =
            "Modules "
            .. tostring(i)
            .. "/"
            .. tostring(maxModules)

        pcall(scanModule, module)

        if i % 20 == 0 then
            refreshConsole()
            task.wait()
        end
    end

    section("SCAN COMPLETE")

    add("Total output lines : " .. tostring(#Output))
    add("Target lines       : " .. tostring(#TargetLines))
    add("Fish/asset lines   : " .. tostring(#FishAssetLines))
    add("")
    add("Press TARGETS for Ruby / Withering Core only.")
    add("Press FISH/ASSETS for fish + asset-related results.")
    add("Press COPY if Delta cannot save files.")

    refreshConsole()

    ScanButton.Text = "FULL SCAN"
    Status.Text =
        "DONE • "
        .. tostring(#TargetLines)
        .. " target matches"

    Scanning = false

    -- Auto-save once after scan
    saveResults(true)
end

--==============================================================
-- BUTTONS
--==============================================================

ScanButton.MouseButton1Click:Connect(function()
    task.spawn(fullScan)
end)

TargetButton.MouseButton1Click:Connect(function()
    local lines = {
        "LFAMILIA • TARGET RESULTS",
        "Ruby / Withering Core",
        "============================================"
    }

    if #TargetLines == 0 then
        lines[#lines + 1] = "No target match found."
    else
        for _, line in ipairs(TargetLines) do
            lines[#lines + 1] = line
        end
    end

    refreshConsole(lines)
    Status.Text = "Targets: " .. tostring(#TargetLines)
end)

FishButton.MouseButton1Click:Connect(function()
    local lines = {
        "LFAMILIA • FISH / ASSET RESULTS",
        "============================================"
    }

    if #FishAssetLines == 0 then
        lines[#lines + 1] = "No fish/asset result found."
    else
        for _, line in ipairs(FishAssetLines) do
            lines[#lines + 1] = line
        end
    end

    refreshConsole(lines)
    Status.Text = "Fish/asset lines: " .. tostring(#FishAssetLines)
end)

CopyButton.MouseButton1Click:Connect(function()
    local copier = setclipboard or toclipboard

    if not copier then
        Status.Text = "setclipboard() unavailable"
        return
    end

    local ok = pcall(function()
        copier(table.concat(Output, "\n"))
    end)

    Status.Text = ok and "All results copied" or "Copy failed"
end)

SaveButton.MouseButton1Click:Connect(function()
    saveResults(false)
end)

ClearButton.MouseButton1Click:Connect(function()
    Output = {}
    TargetLines = {}
    FishAssetLines = {}
    SeenOutput = {}
    SeenTables = {}

    Console.Text = ""
    Status.Text = "Console cleared"
end)

Close.MouseButton1Click:Connect(function()
    Gui:Destroy()
end)

--==============================================================
-- AUTO START ON EXECUTE
--==============================================================

task.delay(0.5, function()
    fullScan()
end)
