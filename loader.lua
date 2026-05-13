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

if env.Voidra and type(env.Voidra.Cleanup) == "function" then
    pcall(env.Voidra.Cleanup)
end

if env.Voidra and env.Voidra.Library and type(env.Voidra.Library.Unload) == "function" then
    pcall(function()
        env.Voidra.Library:Unload()
    end)
end

local Library = run("Library.lua")

local Loading = Library:CreateLoading({
    Title = "voidra",
    CurrentStep = 1,
    TotalSteps = 5,
    AutoResizeHeight = true,
    WindowWidth = 430,
    WindowHeight = 250,
})

Loading:SetMessage("Loading voidra")
Loading:SetDescription("made by zz.tonho")

local ThemeManagerOk, ThemeManager = pcall(run, "addons/ThemeManager.lua")
if not ThemeManagerOk then
    warn("[voidra] ThemeManager failed to load: " .. tostring(ThemeManager))
    ThemeManager = nil
end

Loading:SetMessage("Loading theme manager")
Loading:SetCurrentStep(2)

local SaveManagerOk, SaveManager = pcall(run, "addons/SaveManager.lua")
if not SaveManagerOk then
    warn("[voidra] SaveManager failed to load: " .. tostring(SaveManager))
    SaveManager = nil
end

Loading:SetMessage("Loading save manager")
Loading:SetCurrentStep(3)

local Options = Library.Options
local Toggles = Library.Toggles

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

Loading:SetMessage("Creating window")
Loading:SetCurrentStep(4)

local Window = Library:CreateWindow({
    Title = "voidra",
    Footer = "voidra",
    Icon = "rbxthumb://type=Asset&id=72568647036813&w=150&h=150",
    IconSize = UDim2.fromOffset(20, 20),
    Font = Enum.Font.RobotoMono,
    AutoShow = true,
    Center = true,
    Resizable = false,
    EnableSidebarResize = false,
    EnableCompacting = false,
    NotifySide = "Left",
    ShowCustomCursor = true,
})

local Tabs = {
    Main = Window:AddTab("Main", "house"),
    Player = Window:AddTab("Player", "user"),
    Mining = Window:AddTab("Ores", "pickaxe"),
    Settings = Window:AddTab("UI Settings", "settings"),
}

local State = {
    Loaded = true,
    Mining = {
        SelectedOre = "Copper",
        AutoFarm = false,
        StopRequested = false,
    },
    Movement = {
        Coordinates = "",
        SelectedPlayer = nil,
        SpeedEnabled = false,
        Speed = 50,
        InfJump = false,
        JumpPower = 50,
        Noclip = false,
        Fly = false,
        FlySpeed = 100,
        DefaultWalkSpeed = nil,
        WalkSpeedConnection = nil,
        InfJumpConnection = nil,
        NoclipConnection = nil,
        FlyConnection = nil,
        NoclipOriginal = {},
        FlyVelocity = nil,
        FlyGyro = nil,
        FlyRoot = nil,
    },
}

local MenuBox = Tabs.Settings:AddLeftGroupbox("Menu", "settings")

MenuBox:AddLabel("Menu keybind"):AddKeyPicker("MenuKeybind", {
    Text = "Menu keybind",
    Default = "RightControl",
    Mode = "Toggle",
    SyncToggleState = false,
})

Library.ToggleKeybind = Options.MenuKeybind

local cleanup = function() end

local MovementOk, MovementError = pcall(function()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local MovementState = State.Movement
local ZeroVector = Vector3.new(0, 0, 0)
local UpVector = Vector3.new(0, 1, 0)

local function notify(description)
    Library:Notify({
        Title = "voidra",
        Description = description,
        Time = 3,
    })
end

local function getCharacter()
    return LocalPlayer.Character
end

local function getHumanoid()
    local character = getCharacter()
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(model)
    model = model or getCharacter()
    return model
        and (
            model:FindFirstChild("HumanoidRootPart")
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart")
        )
end

local function parseCoordinates(text)
    local numbers = {}

    for value in tostring(text):gmatch("[-+]?%d*%.?%d+") do
        numbers[#numbers + 1] = tonumber(value)
    end

    if #numbers < 3 then
        return nil
    end

    return Vector3.new(numbers[1], numbers[2], numbers[3])
end

local function teleportToCFrame(cframe)
    local root = getRoot()

    if not root then
        notify("Character root was not found.")
        return false
    end

    root.CFrame = cframe
    return true
end

local function applyWalkSpeed()
    local humanoid = getHumanoid()

    if humanoid and MovementState.SpeedEnabled then
        humanoid.WalkSpeed = MovementState.Speed
    end
end

local function setWalkSpeedEnabled(enabled)
    MovementState.SpeedEnabled = enabled

    if MovementState.WalkSpeedConnection then
        MovementState.WalkSpeedConnection:Disconnect()
        MovementState.WalkSpeedConnection = nil
    end

    local humanoid = getHumanoid()

    if enabled then
        if humanoid and not MovementState.DefaultWalkSpeed then
            MovementState.DefaultWalkSpeed = humanoid.WalkSpeed
        end

        applyWalkSpeed()
        MovementState.WalkSpeedConnection = RunService.Heartbeat:Connect(applyWalkSpeed)
    elseif humanoid and MovementState.DefaultWalkSpeed then
        humanoid.WalkSpeed = MovementState.DefaultWalkSpeed
    end
end

local function applyJumpPower()
    local humanoid = getHumanoid()

    if not humanoid then
        return
    end

    pcall(function()
        humanoid.JumpPower = MovementState.JumpPower
    end)

    pcall(function()
        humanoid.JumpHeight = MovementState.JumpPower
    end)
end

local function setInfJumpEnabled(enabled)
    MovementState.InfJump = enabled

    if MovementState.InfJumpConnection then
        MovementState.InfJumpConnection:Disconnect()
        MovementState.InfJumpConnection = nil
    end

    if enabled then
        applyJumpPower()
        MovementState.InfJumpConnection = UserInputService.JumpRequest:Connect(function()
            local humanoid = getHumanoid()

            if humanoid then
                applyJumpPower()
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    end
end

local function restoreNoclip()
    for part, canCollide in pairs(MovementState.NoclipOriginal) do
        if part and part.Parent then
            part.CanCollide = canCollide
        end

        MovementState.NoclipOriginal[part] = nil
    end
end

local function applyNoclip()
    local character = getCharacter()

    if not character then
        return
    end

    for _, object in ipairs(character:GetDescendants()) do
        if object:IsA("BasePart") then
            if MovementState.NoclipOriginal[object] == nil then
                MovementState.NoclipOriginal[object] = object.CanCollide
            end

            object.CanCollide = false
        end
    end
end

local function setNoclipEnabled(enabled)
    MovementState.Noclip = enabled

    if MovementState.NoclipConnection then
        MovementState.NoclipConnection:Disconnect()
        MovementState.NoclipConnection = nil
    end

    if enabled then
        MovementState.NoclipConnection = RunService.Stepped:Connect(applyNoclip)
    else
        restoreNoclip()
    end
end

local function cleanupFly()
    if MovementState.FlyConnection then
        MovementState.FlyConnection:Disconnect()
        MovementState.FlyConnection = nil
    end

    if MovementState.FlyVelocity then
        MovementState.FlyVelocity:Destroy()
        MovementState.FlyVelocity = nil
    end

    if MovementState.FlyGyro then
        MovementState.FlyGyro:Destroy()
        MovementState.FlyGyro = nil
    end

    MovementState.FlyRoot = nil

    local humanoid = getHumanoid()
    if humanoid then
        humanoid.PlatformStand = false
    end
end

local function ensureFlyMovers()
    local root = getRoot()

    if not root then
        return nil, nil
    end

    if MovementState.FlyRoot ~= root then
        if MovementState.FlyVelocity then
            MovementState.FlyVelocity:Destroy()
        end

        if MovementState.FlyGyro then
            MovementState.FlyGyro:Destroy()
        end

        MovementState.FlyRoot = root

        local velocity = Instance.new("BodyVelocity")
        velocity.Name = "VoidraFlyVelocity"
        velocity.MaxForce = Vector3.new(1, 1, 1) * 1000000
        velocity.Velocity = ZeroVector
        velocity.Parent = root

        local gyro = Instance.new("BodyGyro")
        gyro.Name = "VoidraFlyGyro"
        gyro.MaxTorque = Vector3.new(1, 1, 1) * 1000000
        gyro.P = 90000
        gyro.CFrame = root.CFrame
        gyro.Parent = root

        MovementState.FlyVelocity = velocity
        MovementState.FlyGyro = gyro
    end

    return MovementState.FlyVelocity, MovementState.FlyGyro
end

local function getFlyDirection()
    local camera = workspace.CurrentCamera

    if not camera then
        return ZeroVector
    end

    local direction = ZeroVector

    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
        direction = direction + camera.CFrame.LookVector
    end

    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        direction = direction - camera.CFrame.LookVector
    end

    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        direction = direction - camera.CFrame.RightVector
    end

    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        direction = direction + camera.CFrame.RightVector
    end

    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        direction = direction + UpVector
    end

    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        direction = direction - UpVector
    end

    if direction.Magnitude > 0 then
        return direction.Unit
    end

    return ZeroVector
end

local function setFlyEnabled(enabled)
    MovementState.Fly = enabled
    cleanupFly()

    if not enabled then
        return
    end

    MovementState.FlyConnection = RunService.RenderStepped:Connect(function()
        local velocity, gyro = ensureFlyMovers()
        local humanoid = getHumanoid()
        local camera = workspace.CurrentCamera

        if not velocity or not gyro or not camera then
            return
        end

        if humanoid then
            humanoid.PlatformStand = true
        end

        velocity.Velocity = getFlyDirection() * MovementState.FlySpeed
        gyro.CFrame = camera.CFrame
    end)
end

local CharacterAddedConnection = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)

    if MovementState.SpeedEnabled then
        setWalkSpeedEnabled(true)
    end

    if MovementState.Noclip then
        setNoclipEnabled(true)
    end

    if MovementState.Fly then
        setFlyEnabled(true)
    end
end)

cleanup = function()
    setWalkSpeedEnabled(false)
    setInfJumpEnabled(false)
    setNoclipEnabled(false)
    setFlyEnabled(false)

    if CharacterAddedConnection then
        CharacterAddedConnection:Disconnect()
        CharacterAddedConnection = nil
    end
end

local MovementBox = Tabs.Player:AddLeftGroupbox("Movement", "move")

MovementBox:AddDivider("Teleport")
MovementBox:AddInput("PlayerCoordinates", {
    Text = "Coordinates",
    Placeholder = "X, Y, Z",
    Default = "",
    Finished = false,
    ClearTextOnFocus = false,
})

MovementBox:AddButton({
    Text = "TP To",
    Func = function()
        local position = parseCoordinates(MovementState.Coordinates)

        if not position then
            notify("Use coordinates like: X, Y, Z")
            return
        end

        if teleportToCFrame(CFrame.new(position)) then
            notify("Teleported to coordinates.")
        end
    end,
})

MovementBox:AddButton({
    Text = "Copy Position",
    Func = function()
        local root = getRoot()

        if not root then
            notify("Character root was not found.")
            return
        end

        local position = root.Position
        local text = string.format("%.2f, %.2f, %.2f", position.X, position.Y, position.Z)
        Options.PlayerCoordinates:SetValue(text)

        if type(setclipboard) == "function" and pcall(setclipboard, text) then
            notify("Position copied.")
        else
            notify(text)
        end
    end,
})

MovementBox:AddDivider("TP to Player")
MovementBox:AddDropdown("MovementTargetPlayer", {
    Text = "Select Player",
    Values = {},
    SpecialType = "Player",
    ExcludeLocalPlayer = true,
    EnablePlayerImages = true,
    AllowNull = true,
    Searchable = true,
})

MovementBox:AddButton({
    Text = "Teleport",
    Func = function()
        local player = MovementState.SelectedPlayer

        if not player or not player.Character then
            notify("Select a valid player.")
            return
        end

        local targetRoot = getRoot(player.Character)

        if not targetRoot then
            notify("Target root was not found.")
            return
        end

        if teleportToCFrame(targetRoot.CFrame * CFrame.new(0, 0, 3)) then
            notify("Teleported to " .. player.Name .. ".")
        end
    end,
})

MovementBox:AddDivider("Movement")
MovementBox:AddToggle("MovementSpeedEnabled", {
    Text = "Speed",
    Default = false,
}):AddKeyPicker("MovementSpeedKey", {
    Text = "Speed",
    Default = "N",
    Mode = "Toggle",
    SyncToggleState = true,
})

MovementBox:AddSlider("MovementSpeed", {
    Text = "Speed",
    Default = 50,
    Min = 16,
    Max = 250,
    Rounding = 0,
    Compact = true,
})

MovementBox:AddToggle("MovementInfJump", {
    Text = "Inf Jump",
    Default = false,
}):AddKeyPicker("MovementInfJumpKey", {
    Text = "Inf Jump",
    Default = "H",
    Mode = "Toggle",
    SyncToggleState = true,
})

MovementBox:AddSlider("MovementJumpPower", {
    Text = "Jump Height",
    Default = 50,
    Min = 20,
    Max = 250,
    Rounding = 0,
    Compact = true,
})

MovementBox:AddToggle("MovementNoclip", {
    Text = "Noclip",
    Default = false,
}):AddKeyPicker("MovementNoclipKey", {
    Text = "Noclip",
    Default = "None",
    Mode = "Toggle",
    SyncToggleState = true,
})

MovementBox:AddToggle("MovementFly", {
    Text = "Fly",
    Default = false,
}):AddKeyPicker("MovementFlyKey", {
    Text = "Fly",
    Default = "None",
    Mode = "Toggle",
    SyncToggleState = true,
})

MovementBox:AddSlider("MovementFlySpeed", {
    Text = "Fly Speed",
    Default = 100,
    Min = 25,
    Max = 300,
    Rounding = 0,
    Compact = true,
})

Options.PlayerCoordinates:OnChanged(function(value)
    MovementState.Coordinates = value
end)

Options.MovementTargetPlayer:OnChanged(function(value)
    MovementState.SelectedPlayer = value
end)

Toggles.MovementSpeedEnabled:OnChanged(setWalkSpeedEnabled)

Options.MovementSpeed:OnChanged(function(value)
    MovementState.Speed = value
    applyWalkSpeed()
end)

Toggles.MovementInfJump:OnChanged(setInfJumpEnabled)

Options.MovementJumpPower:OnChanged(function(value)
    MovementState.JumpPower = value

    if MovementState.InfJump then
        applyJumpPower()
    end
end)

Toggles.MovementNoclip:OnChanged(setNoclipEnabled)
Toggles.MovementFly:OnChanged(setFlyEnabled)

Options.MovementFlySpeed:OnChanged(function(value)
    MovementState.FlySpeed = value
end)
end)

if not MovementOk then
    warn("[voidra] Movement setup failed: " .. tostring(MovementError))
    Library:Notify({
        Title = "voidra",
        Description = "Movement setup failed. Check console.",
        Time = 5,
    })
end

local MiningOk, MiningError = pcall(function()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local MiningState = State.Mining
local MiningChargeTime = 0.63
local MiningActionDelay = 0.04
local MiningTeleportOffset = 5
local MiningIdleDelay = 0.35
local MiningMaxHitsPerOre = 60
local MiningChargeUiTimeout = 0.5
local MiningCooldownDelay = 0.65
local MiningDropScanRadius = 14
local MiningGrabSteps = 8
local MiningGrabStepDelay = 0.015
local MiningFinalGrabRepeats = 5
local MiningDropSettleDelay = 0.12
local MiningFastGrabRepeats = 2
local MiningFastGrabDelay = 0.002
local MiningStorageBatchDelay = 0.004
local MiningAutoGrabRepeats = 2
local MiningAutoGrabDelay = 0.002
local MiningAutoLiftHeight = 85
local MiningAutoBatchDelay = 0.004
local MiningDropWaitTimeout = 0.25
local MiningDropPollDelay = 0.02
local MiningTargetSettleDelay = 0.03
local MiningAttackResultDelay = 0.08
local MiningTeleportRefreshDistance = 12
local MiningOreSpotLoadDelay = 4
local MiningOreSpotLoadCooldown = 20
local MiningBaseDropHeight = 1.75
local MiningDropSpacing = 5
local MiningDropMaxColumns = 7
local MiningPlotInset = 5
local MiningBringRadius = 18
local MiningSellDropSpacing = 4
local MiningTierWarningScanRadius = 45
local MiningMaxChargeMisses = 20
local LastMiningWarning = 0
local LastMiningOreSpotLoad = {}

local OreNames = {
    "Abyssalite",
    "Amber",
    "Ancient Rune",
    "Bauxite",
    "Blastshard",
    "Blazing Star",
    "BlueFlower",
    "Chocolate",
    "Clay",
    "Cloudnite",
    "Coal",
    "Cobalt",
    "Copper",
    "Crimson",
    "Deepslate",
    "Diamond",
    "Dirt",
    "Dumortierite",
    "Emerald",
    "Fallen Star",
    "Flower Grass",
    "Giftium",
    "Gingerbread",
    "Gold",
    "Granite",
    "Hallow",
    "Ice",
    "Iron",
    "Jade",
    "Limestone",
    "Lithium",
    "Magma",
    "Marble",
    "Meteorite",
    "Moonstone",
    "Mud",
    "Mushroom",
    "Noir",
    "Null",
    "Obsidian",
    "Old Stone",
    "Pink Diamond",
    "Pumpkin",
    "Quartz",
    "Ruby",
    "Salt",
    "Sand",
    "Sapphire",
    "Scarlet",
    "Silver",
    "Snow",
    "Soulstone",
    "Sphalerite",
    "Stone",
    "Sulfur",
    "Sunstone",
    "Tall Grass",
    "Tin",
    "Titanium",
    "Tolmedit",
    "Topaz",
    "Volcanium",
    "Voltshard",
    "Wildcore",
}

local OreLookup = {}
for _, oreName in ipairs(OreNames) do
    OreLookup[oreName] = true
end

local OreLoadSpots = {
    Marble = { Vector3.new(-595.55, 78.75, -240.07) },
    Granite = { Vector3.new(-595.55, 78.75, -240.07) },
    Lithium = { Vector3.new(-595.55, 78.75, -240.07) },
    Dirt = { Vector3.new(1234.13, 2.70, 2458.88) },
    Mud = { Vector3.new(1234.13, 2.70, 2458.88) },
    Clay = { Vector3.new(1234.13, 2.70, 2458.88) },
    Bauxite = { Vector3.new(-1182.11, -6.12, 1293.27) },
    Iron = { Vector3.new(-1182.11, -6.12, 1293.27) },
    Stone = { Vector3.new(-1182.11, -6.12, 1293.27) },
    Copper = { Vector3.new(-1182.11, -6.12, 1293.27) },
    Cobalt = { Vector3.new(332.95, -96.18, 3327.90) },
    Amber = { Vector3.new(332.95, -96.18, 3327.90) },
    Salt = { Vector3.new(-5952.75, -174.50, -2017.67) },
}

local EventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
if not EventsFolder then
    error("ReplicatedStorage.Events was not found.")
end

local GrabHandlerRemote = EventsFolder:FindFirstChild("GrabHandler")

local ToolEvents = EventsFolder:WaitForChild("Tools", 10)
if not ToolEvents then
    error("ReplicatedStorage.Events.Tools was not found.")
end

local ChargeRemote = ToolEvents:WaitForChild("Charge", 10)
local AttackRemote = ToolEvents:WaitForChild("Attack", 10)
if not ChargeRemote or not AttackRemote then
    error("Charge or Attack remote was not found.")
end

local ToolInputChangedRemote = ToolEvents:FindFirstChild("ToolInputChanged")

local function miningNotify(description)
    Library:Notify({
        Title = "voidra",
        Description = description,
        Time = 3,
    })
end

local function miningWarn(description)
    local now = os.clock()

    if now - LastMiningWarning < 3 then
        return
    end

    LastMiningWarning = now
    miningNotify(description)
end

local function getCharacter()
    return LocalPlayer.Character
end

local function getRoot()
    local character = getCharacter()
    return character
        and (
            character:FindFirstChild("HumanoidRootPart")
            or character.PrimaryPart
            or character:FindFirstChildWhichIsA("BasePart")
        )
end

local function getHumanoid()
    local character = getCharacter()
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function getPlayerGui()
    return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function isVisibleGui(object)
    if not object:IsA("GuiObject") or not object.Visible then
        return false
    end

    local parent = object.Parent
    while parent and parent:IsA("GuiObject") do
        if not parent.Visible then
            return false
        end

        parent = parent.Parent
    end

    return true
end

local function guiText(object)
    local ok, text = pcall(function()
        return object.Text
    end)

    if ok and type(text) == "string" then
        return text
    end

    return ""
end

local function getPosition(instance)
    if not instance then
        return nil
    end

    if instance:IsA("BasePart") then
        return instance.Position
    end

    if instance:IsA("Attachment") then
        return instance.WorldPosition
    end

    if instance:IsA("Model") then
        local ok, pivot = pcall(function()
            return instance:GetPivot()
        end)

        if ok then
            return pivot.Position
        end
    end

    local part = instance:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local function isLikelyChargeGui(object)
    if not isVisibleGui(object) then
        return false
    end

    local value = (object.Name .. " " .. guiText(object)):lower()
    return value:find("charge", 1, true) ~= nil
        or value:find("power", 1, true) ~= nil
        or value:find("strength", 1, true) ~= nil
end

local function isTierWarningText(value)
    value = tostring(value):lower()

    return value:find("too sturdy", 1, true) ~= nil
        or value:find("sturdy", 1, true) ~= nil
        or value:find("too high", 1, true) ~= nil
        or value:find("too weak", 1, true) ~= nil
        or (
            value:find("tier", 1, true) ~= nil
            and (
                value:find("too", 1, true) ~= nil
                or value:find("weak", 1, true) ~= nil
                or value:find("high", 1, true) ~= nil
                or value:find("low", 1, true) ~= nil
            )
        )
end

local function getGuiWorldPosition(object)
    local current = object

    while current and current ~= workspace and current ~= game do
        if current:IsA("BillboardGui") or current:IsA("SurfaceGui") then
            local adornee = current.Adornee
            local adorneePosition = getPosition(adornee)

            if adorneePosition then
                return adorneePosition
            end
        end

        local position = getPosition(current)

        if position then
            return position
        end

        current = current.Parent
    end

    return nil
end

local function hasTierWarningInContainer(container, nearPosition)
    if not container then
        return false
    end

    for _, object in ipairs(container:GetDescendants()) do
        if isVisibleGui(object) then
            local value = (object.Name .. " " .. guiText(object)):lower()

            if isTierWarningText(value) then
                if not nearPosition then
                    return true
                end

                local position = getGuiWorldPosition(object)

                if position and (position - nearPosition).Magnitude <= MiningTierWarningScanRadius then
                    return true
                end
            end
        end
    end

    return false
end

local function hasTierWarningGui(nearPosition, ore)
    if hasTierWarningInContainer(getPlayerGui(), nil) then
        return true
    end

    return ore and hasTierWarningInContainer(ore, nearPosition) or false
end

local function waitForChargeGui()
    local playerGui = getPlayerGui()

    if not playerGui then
        return true
    end

    local startedAt = os.clock()

    while os.clock() - startedAt < MiningChargeUiTimeout do
        for _, object in ipairs(playerGui:GetDescendants()) do
            if isLikelyChargeGui(object) then
                return true
            end
        end

        task.wait(0.05)
    end

    return false
end

local function getAreaData(target, fallbackSize)
    local position = getPosition(target)

    if not position then
        return nil, nil, nil
    end

    local size = fallbackSize or Vector3.new(36, 1, 36)
    local topY = position.Y

    if target:IsA("BasePart") then
        size = target.Size
        topY = target.Position.Y + (target.Size.Y / 2)
    elseif target:IsA("Model") then
        local ok, boundsCFrame, boundsSize = pcall(function()
            return target:GetBoundingBox()
        end)

        if ok and boundsCFrame and boundsSize then
            position = boundsCFrame.Position
            size = boundsSize
            topY = boundsCFrame.Position.Y + (boundsSize.Y / 2)
        end
    end

    return position, size, topY
end

local function getGridDropPosition(position, size, topY, slot, part, spacing, maxColumns, inset, baseHeight)
    if not position or not size or not topY then
        return nil
    end

    slot = math.max(1, tonumber(slot) or 1)
    spacing = spacing or MiningDropSpacing
    maxColumns = maxColumns or MiningDropMaxColumns
    inset = inset or MiningPlotInset
    baseHeight = baseHeight or MiningBaseDropHeight

    local usableX = math.max(spacing, size.X - (inset * 2))
    local usableZ = math.max(spacing, size.Z - (inset * 2))
    local columns = math.max(1, math.floor(usableX / spacing))
    local rows = math.max(1, math.floor(usableZ / spacing))

    columns = math.min(columns, maxColumns)

    local totalSlots = math.max(1, columns * rows)
    local index = (slot - 1) % totalSlots
    local column = index % columns
    local row = math.floor(index / columns)
    local dropHeight = baseHeight

    if part and part:IsA("BasePart") then
        dropHeight = math.max(dropHeight, (part.Size.Y / 2) + 0.35)
    end

    local xOffset = (column - ((columns - 1) / 2)) * spacing
    local zOffset = (row - ((rows - 1) / 2)) * spacing

    return Vector3.new(position.X + xOffset, topY + dropHeight, position.Z + zOffset)
end

local function ownerMatchesLocalPlayer(owner)
    if not owner then
        return false
    end

    if owner:IsA("ObjectValue") then
        return owner.Value == LocalPlayer
            or (owner.Value and owner.Value.Name == LocalPlayer.Name)
            or (owner.Value and tostring(owner.Value) == LocalPlayer.Name)
    end

    if owner:IsA("StringValue") then
        return owner.Value == LocalPlayer.Name
            or owner.Value == tostring(LocalPlayer.UserId)
    end

    if owner:IsA("IntValue") or owner:IsA("NumberValue") then
        return owner.Value == LocalPlayer.UserId
    end

    if owner:IsA("BoolValue") then
        return owner.Value == true and owner.Name == LocalPlayer.Name
    end

    return owner:GetAttribute("UserId") == LocalPlayer.UserId
        or owner:GetAttribute("Owner") == LocalPlayer.Name
end

local function getLocalPlot()
    local plots = workspace:FindFirstChild("Plots")

    if not plots then
        return nil
    end

    for _, plot in ipairs(plots:GetChildren()) do
        local owner = plot:FindFirstChild("Owner", true) or plot:FindFirstChild("owner", true)

        if ownerMatchesLocalPlayer(owner) then
            return plot
        end
    end

    return nil
end

local function getPlotDropData()
    local plot = getLocalPlot()

    if not plot then
        return nil, nil, nil
    end

    local target = plot:FindFirstChild("Plot")
        or plot:FindFirstChild("ProjectionZone")
        or plot:FindFirstChild("Objects")
        or plot

    return getAreaData(target, Vector3.new(36, 1, 36))
end

local function getPlotDropPosition(slot, part)
    local position, size, topY = getPlotDropData()

    return getGridDropPosition(position, size, topY, slot, part)
end

local function getPlotStandPosition()
    local position, _, topY = getPlotDropData()

    if not position then
        return nil
    end

    return Vector3.new(position.X, topY + MiningTeleportOffset, position.Z)
end

local function isInsideArea(position, areaPosition, areaSize, padding)
    if not position or not areaPosition or not areaSize then
        return false
    end

    padding = padding or 0

    return math.abs(position.X - areaPosition.X) <= (areaSize.X / 2) + padding
        and math.abs(position.Z - areaPosition.Z) <= (areaSize.Z / 2) + padding
        and math.abs(position.Y - areaPosition.Y) <= math.max(120, areaSize.Y + padding)
end

local function isInsideLocalPlot(position, padding)
    local plotPosition, plotSize = getPlotDropData()
    return isInsideArea(position, plotPosition, plotSize, padding or 4)
end

local function getNovaSellary()
    local map = workspace:FindFirstChild("Map")
    local structures = map and map:FindFirstChild("Structures")

    if not structures then
        return nil
    end

    return structures:FindFirstChild("Nova_Sellary")
        or structures:FindFirstChild("Nova_Sellary", true)
end

local function getSellZone()
    local sellary = getNovaSellary()
    return sellary and (sellary:FindFirstChild("SellZone") or sellary:FindFirstChild("SellZone", true)) or nil
end

local function getSellTalkPart()
    local sellary = getNovaSellary()
    return sellary and (sellary:FindFirstChild("TalkPart") or sellary:FindFirstChild("TalkPart", true)) or nil
end

local function getSellZoneData()
    local sellZone = getSellZone()

    if not sellZone then
        return nil, nil, nil
    end

    local target = sellZone:IsA("Model") and sellZone.PrimaryPart or nil
    target = target
        or sellZone:FindFirstChild("Area", true)
        or sellZone:FindFirstChildWhichIsA("BasePart", true)
        or sellZone

    return getAreaData(target, Vector3.new(28, 1, 28))
end

local function getSellZoneDropPosition(slot, part)
    local position, size, topY = getSellZoneData()
    return getGridDropPosition(position, size, topY, slot, part, MiningSellDropSpacing, 8, 2, 1.5)
end

local function getPlayerDropPosition(slot, part)
    local root = getRoot()

    if not root then
        return nil
    end

    local center = root.Position + (root.CFrame.LookVector * 5)
    return getGridDropPosition(center, Vector3.new(18, 1, 18), root.Position.Y - 3, slot, part, 4, 5, 1, 1.5)
end

local function callSellaryInteract(...)
    local talkPart = getSellTalkPart()
    local interact = talkPart and talkPart:FindFirstChild("Interact")
    local args = { ... }

    if not interact then
        return false
    end

    local ok = pcall(function()
        if interact:IsA("RemoteFunction") then
            interact:InvokeServer(unpack(args))
        else
            interact:FireServer(unpack(args))
        end
    end)

    return ok
end

local function getOresFolder()
    local worldSpawn = workspace:FindFirstChild("WorldSpawn")

    if worldSpawn then
        local ores = worldSpawn:FindFirstChild("Ores")
        if ores then
            return ores
        end
    end

    return workspace:FindFirstChild("Ores")
end

local function getPickaxe()
    local character = getCharacter()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

    for _, container in ipairs({ LocalPlayer, character, backpack }) do
        if container then
            for _, object in ipairs(container:GetChildren()) do
                if object.Name:lower():find("pickaxe", 1, true) then
                    return object
                end
            end
        end
    end

    return nil
end

local function getEquippablePickaxe()
    local character = getCharacter()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

    for _, container in ipairs({ character, backpack }) do
        if container then
            for _, object in ipairs(container:GetChildren()) do
                if object:IsA("Tool") and object.Name:lower():find("pickaxe", 1, true) then
                    return object
                end
            end
        end
    end

    return nil
end

local function getEquippedPickaxe()
    local character = getCharacter()

    if not character then
        return nil
    end

    for _, object in ipairs(character:GetChildren()) do
        if object:IsA("Tool") and object.Name:lower():find("pickaxe", 1, true) then
            return object
        end
    end

    return nil
end

local function equipPickaxe()
    local humanoid = getHumanoid()
    local character = getCharacter()
    local tool = getEquippablePickaxe()

    if humanoid and character and tool and tool.Parent ~= character then
        pcall(function()
            humanoid:EquipTool(tool)
        end)

        task.wait(0.2)
    end

    local pickaxe = getEquippedPickaxe() or getPickaxe()
    if not pickaxe then
        miningNotify("No pickaxe found.")
        return nil
    end

    return pickaxe
end

local function setToolInput(active, pickaxe)
    if not ToolInputChangedRemote then
        return
    end

    pickaxe = pickaxe or getPickaxe()
    if pickaxe then
        pcall(function()
            ToolInputChangedRemote:FireServer(pickaxe, active)
        end)
    end
end

local function addOreTarget(targets, ore, target)
    if targets.Seen and targets.Seen[target] then
        return
    end

    local position = getPosition(target)

    if not position then
        return
    end

    if targets.Seen then
        targets.Seen[target] = true
    end

    targets[#targets + 1] = {
        Ore = ore,
        Target = target,
        HitPosition = position,
    }
end

local function findOreTarget(ore)
    local hittable = ore:FindFirstChild("Hittable")

    if hittable then
        for _, child in ipairs(hittable:GetDescendants()) do
            if child:IsA("BasePart") and child.Name == "Part" then
                return child
            end
        end

        for _, descendant in ipairs(hittable:GetDescendants()) do
            if descendant:IsA("BasePart") then
                return descendant
            end
        end
    end

    if ore:IsA("BasePart") then
        return ore
    end

    return nil
end

local function isOreAlive(ore)
    return ore and ore.Parent == getOresFolder() and findOreTarget(ore) ~= nil
end

local function collectTargetsFromOre(targets, ore)
    local target = findOreTarget(ore)

    if target then
        addOreTarget(targets, ore, target)
    end
end

local function normalizeOreName(name)
    name = tostring(name)

    if OreLookup[name] then
        return name
    end

    name = name:gsub("%s*%(%d+%)$", "")
    name = name:gsub("%s*_%d+$", "")
    name = name:gsub("%s*%-?%d+$", "")

    if OreLookup[name] then
        return name
    end

    return nil
end

local function getOreTargets(oreFilter)
    local oresFolder = getOresFolder()
    local targets = {
        Seen = {},
    }

    if not oresFolder then
        miningNotify("workspace.WorldSpawn.Ores was not found.")
        return targets
    end

    for _, ore in ipairs(oresFolder:GetChildren()) do
        local oreName = normalizeOreName(ore.Name)

        if oreName and oreName == oreFilter then
            collectTargetsFromOre(targets, ore)
        end
    end

    targets.Seen = nil

    local root = getRoot()
    local rootPosition = root and root.Position

    if rootPosition then
        table.sort(targets, function(a, b)
            return (a.HitPosition - rootPosition).Magnitude < (b.HitPosition - rootPosition).Magnitude
        end)
    end

    return targets
end

local function getNearestOreTarget(oreFilter)
    local targets = getOreTargets(oreFilter)
    return targets[1]
end

local function getGrabPart(object)
    if not object then
        return nil
    end

    if object:IsA("BasePart") then
        if object.Parent and object.Parent.Name == "MaterialPart" then
            return object
        end

        return nil
    end

    if object.Name == "MaterialPart" then
        return object:FindFirstChild("Part") or object:FindFirstChildWhichIsA("BasePart", true)
    end

    return nil
end

local function getGrabContainer(part)
    if not part then
        return nil
    end

    local current = part

    while current and current ~= workspace do
        if current.Name == "MaterialPart" then
            return current
        end

        current = current.Parent
    end

    return nil
end

local function isLocalOwnedGrabPart(part)
    local container = getGrabContainer(part)
    local owner = container and (container:FindFirstChild("Owner") or container:FindFirstChild("owner"))

    return ownerMatchesLocalPlayer(owner)
end

local function getDroppedOrePartsWhere(predicate, sortPosition)
    local grabFolder = workspace:FindFirstChild("Grab")
    local parts = {}
    local seen = {}

    if not grabFolder then
        return parts
    end

    for _, object in ipairs(grabFolder:GetDescendants()) do
        local part = getGrabPart(object)

        if part and part.Parent and not seen[part] then
            local position = getPosition(part)

            if position and isLocalOwnedGrabPart(part) and (not predicate or predicate(part, position)) then
                seen[part] = true
                parts[#parts + 1] = part
            end
        end
    end

    if sortPosition then
        table.sort(parts, function(a, b)
            return (a.Position - sortPosition).Magnitude < (b.Position - sortPosition).Magnitude
        end)
    end

    return parts
end

local function getDroppedOreParts(origin)
    return getDroppedOrePartsWhere(function(_, position)
        return not origin or (position - origin).Magnitude <= MiningDropScanRadius
    end, origin)
end

local function waitForDroppedOreParts(origin)
    local startedAt = os.clock()
    local parts = getDroppedOreParts(origin)

    while #parts == 0 and os.clock() - startedAt < MiningDropWaitTimeout do
        task.wait(MiningDropPollDelay)
        parts = getDroppedOreParts(origin)
    end

    return parts
end

local function getBaseDroppedOreParts()
    local plotPosition = getPlotStandPosition()

    return getDroppedOrePartsWhere(function(_, position)
        return isInsideLocalPlot(position, 5)
    end, plotPosition)
end

local function getOwnedDroppedOreParts()
    local root = getRoot()
    local plotPosition = getPlotStandPosition()
    local sortPosition = plotPosition or (root and root.Position) or nil

    return getDroppedOrePartsWhere(nil, sortPosition)
end

local function getSafePlayerDroppedOreParts()
    local root = getRoot()
    local rootPosition = root and root.Position

    return getDroppedOrePartsWhere(function(_, position)
        if isInsideLocalPlot(position, 5) then
            return true
        end

        return rootPosition and (position - rootPosition).Magnitude <= MiningBringRadius
    end, rootPosition)
end

local function callGrabHandler(part, action, position)
    if not GrabHandlerRemote or not part or not part.Parent then
        return false
    end

    local ok = pcall(function()
        if GrabHandlerRemote:IsA("RemoteFunction") then
            if position then
                GrabHandlerRemote:InvokeServer(part, action, position)
            else
                GrabHandlerRemote:InvokeServer(part, action)
            end
        else
            if position then
                GrabHandlerRemote:FireServer(part, action, position)
            else
                GrabHandlerRemote:FireServer(part, action)
            end
        end
    end)

    return ok
end

local function moveGrabPartToBase(part, destination)
    if not part or not part.Parent or not destination then
        return false
    end

    local startPosition = getPosition(part)

    if not startPosition then
        return false
    end

    local moved = false

    for i = 1, MiningGrabSteps do
        if not part.Parent then
            break
        end

        local alpha = i / MiningGrabSteps
        local position = startPosition:Lerp(destination, alpha)

        pcall(function()
            part.CFrame = CFrame.new(position)
            part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)

        moved = callGrabHandler(part, "Grab", position) or moved
        task.wait(MiningGrabStepDelay)
    end

    for _ = 1, MiningFinalGrabRepeats do
        if not part.Parent then
            break
        end

        pcall(function()
            part.CFrame = CFrame.new(destination)
            part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)

        moved = callGrabHandler(part, "Grab", destination) or moved
        task.wait(MiningGrabStepDelay)
    end

    callGrabHandler(part, "Ungrab")
    task.wait(MiningDropSettleDelay)

    return moved
end

local function moveGrabPartFast(part, destination, repeats, delay, liftHeight)
    if not part or not part.Parent or not destination then
        return false
    end

    local startPosition = getPosition(part)

    if not startPosition then
        return false
    end

    repeats = repeats or MiningFastGrabRepeats
    delay = delay or MiningFastGrabDelay

    local moved = callGrabHandler(part, "Grab", startPosition)
    task.wait(delay)

    local waypoints = {}

    if liftHeight and liftHeight > 0 then
        waypoints[#waypoints + 1] = startPosition + Vector3.new(0, liftHeight, 0)
        waypoints[#waypoints + 1] = Vector3.new(destination.X, destination.Y + liftHeight, destination.Z)
    end

    waypoints[#waypoints + 1] = destination

    for _, waypoint in ipairs(waypoints) do
        for _ = 1, repeats do
            if not part.Parent then
                break
            end

            pcall(function()
                part.CFrame = CFrame.new(waypoint)
                part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end)

            moved = callGrabHandler(part, "Grab", waypoint) or moved
            task.wait(delay)
        end
    end

    callGrabHandler(part, "Ungrab")
    return moved
end

local function moveDroppedOresToBase(origin)
    if not GrabHandlerRemote then
        miningWarn("GrabHandler remote was not found.")
        return 0
    end

    local destination = getPlotDropPosition(1)

    if not destination then
        miningWarn("Your plot was not found.")
        return 0
    end

    local moved = 0

    for _, part in ipairs(waitForDroppedOreParts(origin)) do
        local partDestination = getPlotDropPosition(moved + 1, part)

        if partDestination and moveGrabPartFast(part, partDestination, MiningAutoGrabRepeats, MiningAutoGrabDelay, MiningAutoLiftHeight) then
            moved = moved + 1

            if moved % 10 == 0 then
                task.wait(MiningAutoBatchDelay)
            end
        end
    end

    local standPosition = getPlotStandPosition()
    local root = getRoot()
    if root and standPosition then
        root.CFrame = CFrame.new(standPosition)
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end

    return moved
end

local function talkToSellary()
    if not getSellTalkPart() then
        miningWarn("Nova Sellary talk part was not found.")
        return false
    end

    if not callSellaryInteract() then
        return false
    end

    task.wait(0.1)
    return callSellaryInteract("Deal", 1)
end

local function sellBaseOres()
    if not GrabHandlerRemote then
        miningWarn("GrabHandler remote was not found.")
        return 0
    end

    if not getSellZoneDropPosition(1) then
        miningWarn("Nova Sellary sell zone was not found.")
        return 0
    end

    local parts = getOwnedDroppedOreParts()

    if #parts == 0 then
        miningNotify("No owned ores found.")
        return 0
    end

    local moved = 0

    for _, part in ipairs(parts) do
        local destination = getSellZoneDropPosition(moved + 1, part)

        if destination and moveGrabPartFast(part, destination) then
            moved = moved + 1

            if moved % 10 == 0 then
                task.wait(MiningStorageBatchDelay)
            end
        end
    end

    if moved == 0 then
        miningNotify("No ores were moved.")
        return 0
    end

    task.wait(0.08)

    if talkToSellary() then
        miningNotify("Ore sold successfully.")
    else
        miningWarn("Could not talk to Nova Sellary.")
    end

    return moved
end

local function bringSafeOresToPlayer()
    if not GrabHandlerRemote then
        miningWarn("GrabHandler remote was not found.")
        return 0
    end

    if not getRoot() then
        miningNotify("Character root was not found.")
        return 0
    end

    local parts = getSafePlayerDroppedOreParts()

    if #parts == 0 then
        miningNotify("No safe ores found near you or in your base.")
        return 0
    end

    local moved = 0

    for _, part in ipairs(parts) do
        local destination = getPlayerDropPosition(moved + 1, part)

        if destination and moveGrabPartFast(part, destination) then
            moved = moved + 1

            if moved % 10 == 0 then
                task.wait(MiningStorageBatchDelay)
            end
        end
    end

    if moved > 0 then
        miningNotify(("Brought %d ore blocks."):format(moved))
    else
        miningNotify("No ores were moved.")
    end

    return moved
end

local function teleportNear(position, force)
    local root = getRoot()

    if not root then
        return false
    end

    if force or (root.Position - position).Magnitude > MiningTeleportRefreshDistance then
        root.CFrame = CFrame.new(position + Vector3.new(0, MiningTeleportOffset, 0))
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end

    return true
end

local function teleportToExact(position)
    local root = getRoot()

    if not root or not position then
        return false
    end

    root.CFrame = CFrame.new(position)
    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    return true
end

local function canContinueMining(stopWhenToggleOff)
    if MiningState.StopRequested then
        return false
    end

    if stopWhenToggleOff and Toggles.MiningAutoFarm and not Toggles.MiningAutoFarm.Value then
        return false
    end

    return true
end

local function loadOreSpots(oreFilter, stopWhenToggleOff, force)
    local spots = OreLoadSpots[oreFilter]

    if not spots or #spots == 0 then
        return false
    end

    local now = os.clock()
    if not force and LastMiningOreSpotLoad[oreFilter] and now - LastMiningOreSpotLoad[oreFilter] < MiningOreSpotLoadCooldown then
        return false
    end

    LastMiningOreSpotLoad[oreFilter] = now
    miningNotify("Loading ores...")

    for _, position in ipairs(spots) do
        if not canContinueMining(stopWhenToggleOff) then
            return false
        end

        if not teleportToExact(position) then
            return false
        end

        local startedAt = os.clock()
        while os.clock() - startedAt < MiningOreSpotLoadDelay do
            if not canContinueMining(stopWhenToggleOff) then
                return false
            end

            task.wait(0.1)
        end
    end

    miningNotify("Ores loaded.")
    return true
end

local function refreshOreEntry(entry)
    if not entry or not entry.Ore or not entry.Ore.Parent then
        return false
    end

    local target = findOreTarget(entry.Ore)
    if target and target.Parent then
        local position = getPosition(target)

        if position then
            entry.Target = target
            entry.HitPosition = position
            return true
        end
    end

    return false
end

local function mineTarget(entry, stopWhenToggleOff, stopOnUnequip)
    if not refreshOreEntry(entry) then
        return false
    end

    local pickaxe = equipPickaxe()
    if not pickaxe then
        return false
    end

    local unequipped = false
    local unequipConnection = nil
    local trackedPickaxe = stopOnUnequip and getEquippedPickaxe() or pickaxe
    local maxChargeMisses = stopOnUnequip and 3 or MiningMaxChargeMisses

    if stopOnUnequip and not trackedPickaxe then
        miningNotify("Get ore stopped: pickaxe unequipped.")
        return false
    end

    if not teleportNear(entry.HitPosition, true) then
        miningNotify("Character root was not found.")
        return false
    end

    setToolInput(true, pickaxe)

    if stopOnUnequip and trackedPickaxe and trackedPickaxe:IsA("Tool") then
        unequipConnection = trackedPickaxe.Unequipped:Connect(function()
            unequipped = true
        end)
    end

    local function shouldStopForUnequip()
        if not stopOnUnequip then
            return false
        end

        if unequipped then
            return true
        end

        if not getEquippedPickaxe() then
            return true
        end

        if trackedPickaxe and trackedPickaxe.Parent ~= getCharacter() then
            return true
        end

        return false
    end

    local hits = 0
    local dropOrigin = entry.HitPosition
    local chargeMisses = 0
    local lastTarget = nil

    while canContinueMining(stopWhenToggleOff) and hits < MiningMaxHitsPerOre and isOreAlive(entry.Ore) and refreshOreEntry(entry) do
        if shouldStopForUnequip() then
            miningNotify("Get ore stopped: pickaxe unequipped.")
            break
        end

        local targetChanged = entry.Target ~= lastTarget
        teleportNear(entry.HitPosition, targetChanged)
        lastTarget = entry.Target
        dropOrigin = entry.HitPosition
        task.wait(MiningTargetSettleDelay)

        if shouldStopForUnequip() then
            miningNotify("Get ore stopped: pickaxe unequipped.")
            break
        end

        ChargeRemote:FireServer({
            Target = entry.Target,
            HitPosition = entry.HitPosition,
        })

        if not waitForChargeGui() then
            miningWarn("Charge did not start. Pickaxe may be on cooldown.")
            task.wait(MiningCooldownDelay)
            chargeMisses = chargeMisses + 1

            if chargeMisses >= maxChargeMisses then
                if stopOnUnequip then
                    miningNotify("Get ore stopped: charge did not start.")
                end

                break
            end
        else
            chargeMisses = 0

            task.wait(MiningChargeTime)

            if shouldStopForUnequip() then
                miningNotify("Get ore stopped: pickaxe unequipped.")
                break
            end

            AttackRemote:FireServer({
                Alpha = 1,
                ResponseTime = MiningChargeTime,
            })

            task.wait(MiningAttackResultDelay)

            if hasTierWarningGui(entry.HitPosition, entry.Ore) then
                miningNotify("Pickaxe is too weak for this ore.")
                break
            end

            hits = hits + 1
            task.wait(MiningActionDelay)
        end
    end

    if unequipConnection then
        unequipConnection:Disconnect()
    end

    setToolInput(false, pickaxe)

    if hits >= MiningMaxHitsPerOre and isOreAlive(entry.Ore) then
        miningNotify("Skipped ore: pickaxe tier may be too low.")
    end

    return hits > 0 and not isOreAlive(entry.Ore), dropOrigin
end

local function mineOneOre(stopWhenToggleOff, stopOnUnequip)
    local entry = getNearestOreTarget(MiningState.SelectedOre)

    if not entry and loadOreSpots(MiningState.SelectedOre, stopWhenToggleOff, not stopWhenToggleOff) then
        entry = getNearestOreTarget(MiningState.SelectedOre)
    end

    if not entry then
        if not stopWhenToggleOff then
            miningNotify("No ore target found.")
        end

        return false
    end

    local mined, dropOrigin = mineTarget(entry, stopWhenToggleOff, stopOnUnequip)

    if mined then
        moveDroppedOresToBase(dropOrigin)
        miningNotify("Ore collected successfully.")
    end

    return mined
end

local MiningBox = Tabs.Mining:AddLeftGroupbox("Autofarm", "pickaxe")

MiningBox:AddDropdown("MiningOreFilter", {
    Text = "Ore",
    Values = OreNames,
    Default = "Copper",
    Searchable = true,
})

MiningBox:AddButton({
    Text = "Get ore",
    Func = function()
        task.spawn(function()
            MiningState.StopRequested = false
            mineOneOre(false, true)
        end)
    end,
})

MiningBox:AddToggle("MiningAutoFarm", {
    Text = "Auto farm",
    Default = false,
})

local OreStorageBox = Tabs.Mining:AddRightGroupbox("Ore storage", "package")

OreStorageBox:AddButton({
    Text = "Bring ores",
    Func = function()
        task.spawn(bringSafeOresToPlayer)
    end,
})

OreStorageBox:AddButton({
    Text = "Sell all ore",
    Func = function()
        task.spawn(sellBaseOres)
    end,
})

Options.MiningOreFilter:OnChanged(function(value)
    MiningState.SelectedOre = value or "Copper"
end)

local miningLoopRunning = false

Toggles.MiningAutoFarm:OnChanged(function(enabled)
    MiningState.AutoFarm = enabled
    MiningState.StopRequested = not enabled

    if not enabled or miningLoopRunning then
        return
    end

    miningLoopRunning = true

    task.spawn(function()
        while Toggles.MiningAutoFarm and Toggles.MiningAutoFarm.Value and not MiningState.StopRequested do
            local mined = mineOneOre(true, false)

            if not mined then
                task.wait(MiningIdleDelay)
            end
        end

        miningLoopRunning = false
    end)
end)

local previousCleanup = cleanup
cleanup = function()
    previousCleanup()
    MiningState.StopRequested = true
end
end)

if not MiningOk then
    warn("[voidra] Mining setup failed: " .. tostring(MiningError))
    Library:Notify({
        Title = "voidra",
        Description = "Mining setup failed. Check console.",
        Time = 5,
    })
end

-- Add your own game services/remotes here.
-- local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local Events = ReplicatedStorage:WaitForChild("Events")

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
    SaveManager:SetIgnoreIndexes({ "MenuKeybind", "MiningAutoFarm" })
    SaveManager:SetFolder("voidra")
    SaveManager:SetSubFolder(tostring(game.PlaceId))
    SaveManager:BuildConfigSection(Tabs.Settings)

    pcall(function()
        SaveManager:LoadAutoloadConfig()
    end)
end

pcall(function()
    Library:SetFont(Enum.Font.RobotoMono)

    if Options.FontFace then
        Options.FontFace:SetValue("RobotoMono")
    end
end)

Loading:SetMessage("Finalizing")
Loading:SetCurrentStep(5)
task.wait(0.25)
Loading:Destroy()

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
    Cleanup = cleanup,
}

return env.Voidra
