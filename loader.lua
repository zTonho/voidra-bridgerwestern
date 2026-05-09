local Repo = "https://raw.githubusercontent.com/zTonho/voidra-bridgerwestern/refs/heads/main/"
local ObsidianRepo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/"
local CacheToken = tostring(os.time())

local function fetchFrom(repo, path)
    local url = repo .. path .. "?v=" .. CacheToken
    local ok, result = pcall(function()
        return game:HttpGet(url)
    end)

    return ok, result, url
end

local function isBadResponse(result)
    return type(result) ~= "string"
        or result == ""
        or result:match("^404")
        or result:find("404: Not Found", 1, true) ~= nil
end

local function fetch(path)
    local ok, result, url = fetchFrom(Repo, path)

    if ok and not isBadResponse(result) then
        return result
    end

    local primaryError = ok and result or tostring(result)
    local fallbackOk, fallbackResult, fallbackUrl = fetchFrom(ObsidianRepo, path)

    if fallbackOk and not isBadResponse(fallbackResult) then
        warn(("[voidra] %s was not found in your repo. Loaded fallback from Obsidian official repo."):format(path))
        return fallbackResult
    end

    error(
        ("[voidra] Failed to fetch %s.\nPrimary: %s -> %s\nFallback: %s -> %s"):format(
            path,
            url,
            tostring(primaryError),
            fallbackUrl,
            tostring(fallbackResult)
        ),
        2
    )
end

local function run(path)
    local source = fetch(path)
    local chunk, compileError = loadstring(source)

    if not chunk then
        error(("[voidra] Failed to compile %s: %s"):format(path, tostring(compileError)), 2)
    end

    local ok, result = pcall(chunk)
    if not ok then
        error(("[voidra] Failed to run %s: %s"):format(path, tostring(result)), 2)
    end

    return result
end

local env = (getgenv and getgenv()) or shared or _G

if env.Voidra and env.Voidra.Library and type(env.Voidra.Library.Unload) == "function" then
    pcall(function()
        env.Voidra.Library:Unload()
    end)
end

local Library = run("Library.lua")

local ThemeManagerOk, ThemeManager = pcall(run, "addons/ThemeManager.lua")
if not ThemeManagerOk then
    warn("[voidra] ThemeManager failed to load: " .. tostring(ThemeManager))
    ThemeManager = nil
end

local SaveManagerOk, SaveManager = pcall(run, "addons/SaveManager.lua")
if not SaveManagerOk then
    warn("[voidra] SaveManager failed to load: " .. tostring(SaveManager))
    SaveManager = nil
end

local Options = Library.Options
local Toggles = Library.Toggles

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

local Window = Library:CreateWindow({
    Title = "voidra",
    Footer = "voidra",
    AutoShow = true,
    Center = true,
    Resizable = true,
    NotifySide = "Right",
    ShowCustomCursor = true,
})

local Tabs = {
    Main = Window:AddTab("Main", "house"),
    Players = Window:AddTab("Players", "users"),
    Settings = Window:AddTab("UI Settings", "settings"),
}

Tabs.Main:UpdateWarningBox({
    Visible = true,
    Title = "voidra",
    Text = "Executor template loaded.",
    IsNormal = true,
    LockSize = true,
})

local State = {
    Enabled = false,
    Amount = 50,
    Mode = "Default",
    Text = "",
    SelectedPlayer = nil,
}

local MainBox = Tabs.Main:AddLeftGroupbox("Controls", "sliders-horizontal")
local InfoBox = Tabs.Main:AddRightGroupbox("Status", "info")
local PlayerBox = Tabs.Players:AddLeftGroupbox("Players", "users")

InfoBox:AddLabel("Use this file as the base for your hub.", true)
InfoBox:AddLabel("Create UI first, then connect callbacks with Options/Toggles.", true)
InfoBox:AddLabel("Add your game remotes and systems inside loader.lua.", true)

MainBox:AddToggle("VoidraEnabled", {
    Text = "Enabled",
    Default = false,
    Tooltip = "Example toggle using Toggles.VoidraEnabled:OnChanged.",
})

MainBox:AddSlider("VoidraAmount", {
    Text = "Amount",
    Default = 50,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Suffix = "%",
})

MainBox:AddDropdown("VoidraMode", {
    Text = "Mode",
    Values = { "Default", "Safe", "Fast" },
    Default = 1,
    Multi = false,
    Searchable = false,
})

MainBox:AddInput("VoidraText", {
    Text = "Text value",
    Placeholder = "Type here",
    Default = "",
    Finished = false,
    ClearTextOnFocus = false,
})

MainBox:AddButton({
    Text = "Notify current state",
    Func = function()
        Library:Notify({
            Title = "voidra",
            Description = ("Enabled: %s | Amount: %s | Mode: %s"):format(
                tostring(State.Enabled),
                tostring(State.Amount),
                tostring(State.Mode)
            ),
            Time = 4,
        })
    end,
})

PlayerBox:AddDropdown("VoidraPlayer", {
    Text = "Target player",
    Values = {},
    SpecialType = "Player",
    ExcludeLocalPlayer = true,
    EnablePlayerImages = true,
    AllowNull = true,
    Searchable = true,
})

PlayerBox:AddButton({
    Text = "Print selected player",
    Func = function()
        local player = State.SelectedPlayer

        Library:Notify({
            Title = "voidra",
            Description = player and ("Selected: " .. player.Name) or "No player selected.",
            Time = 3,
        })
    end,
})

-- Add your own game services/remotes here.
-- local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local Events = ReplicatedStorage:WaitForChild("Events")

Toggles.VoidraEnabled:OnChanged(function(value)
    State.Enabled = value
end)

Options.VoidraAmount:OnChanged(function(value)
    State.Amount = value
end)

Options.VoidraMode:OnChanged(function(value)
    State.Mode = value
end)

Options.VoidraText:OnChanged(function(value)
    State.Text = value
end)

Options.VoidraPlayer:OnChanged(function(value)
    State.SelectedPlayer = value
end)

if ThemeManager then
    ThemeManager:SetLibrary(Library)
    ThemeManager:SetFolder("voidra")
    ThemeManager:ApplyToTab(Tabs.Settings)

    pcall(function()
        ThemeManager:ApplyTheme("Material")
        if Options.ThemeManager_ThemeList then
            Options.ThemeManager_ThemeList:SetValue("Material")
        end
    end)
end

if SaveManager then
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
    SaveManager:SetFolder("voidra")
    SaveManager:SetSubFolder(tostring(game.PlaceId))
    SaveManager:BuildConfigSection(Tabs.Settings)

    pcall(function()
        SaveManager:LoadAutoloadConfig()
    end)
end

Library:Notify({
    Title = "voidra",
    Description = "Loaded successfully.",
    Time = 4,
})

env.Voidra = {
    Library = Library,
    Window = Window,
    Tabs = Tabs,
    Options = Options,
    Toggles = Toggles,
    ThemeManager = ThemeManager,
    SaveManager = SaveManager,
    State = State,
}

return env.Voidra
