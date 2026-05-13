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
        SelectedOre = "All",
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
local MiningActionDelay = 0.2
local MiningTeleportOffset = 5
local MiningIdleDelay = 1

local OreNames = {
    "All",
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
OreLookup.All = nil

local EventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
if not EventsFolder then
    error("ReplicatedStorage.Events was not found.")
end

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

local function getPosition(instance)
    if not instance then
        return nil
    end

    if instance:IsA("BasePart") then
        return instance.Position
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
    local containers = {
        getCharacter(),
        LocalPlayer:FindFirstChildOfClass("Backpack"),
        LocalPlayer,
    }

    for _, container in ipairs(containers) do
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

local function setToolInput(active)
    if not ToolInputChangedRemote then
        return
    end

    local pickaxe = getPickaxe()
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

    return ore:FindFirstChildWhichIsA("BasePart", true)
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

        if oreName and (oreFilter == "All" or oreName == oreFilter) then
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

local function teleportNear(position)
    local root = getRoot()

    if not root then
        return false
    end

    root.CFrame = CFrame.new(position + Vector3.new(0, MiningTeleportOffset, 0))
    return true
end

local function mineTarget(entry)
    if not entry or not entry.Target or not entry.Target.Parent then
        return false
    end

    if not teleportNear(entry.HitPosition) then
        miningNotify("Character root was not found.")
        return false
    end

    task.wait(0.1)

    setToolInput(true)

    ChargeRemote:FireServer({
        Target = entry.Target,
        HitPosition = entry.HitPosition,
    })

    task.wait(MiningChargeTime)

    AttackRemote:FireServer({
        Alpha = 1,
        ResponseTime = MiningChargeTime,
    })

    setToolInput(false)
    task.wait(MiningActionDelay)

    return true
end

local function mineRoute(stopWhenToggleOff)
    local targets = getOreTargets(MiningState.SelectedOre)

    if #targets == 0 then
        miningNotify("No ore target found.")
        return false
    end

    local minedAny = false

    for _, entry in ipairs(targets) do
        if MiningState.StopRequested then
            break
        end

        if stopWhenToggleOff and Toggles.MiningAutoFarm and not Toggles.MiningAutoFarm.Value then
            break
        end

        minedAny = mineTarget(entry) or minedAny
    end

    return minedAny
end

local MiningBox = Tabs.Mining:AddLeftGroupbox("Autofarm", "pickaxe")

MiningBox:AddDropdown("MiningOreFilter", {
    Text = "Ore",
    Values = OreNames,
    Default = "All",
    Searchable = true,
})

MiningBox:AddButton({
    Text = "Mine route once",
    Func = function()
        task.spawn(function()
            MiningState.StopRequested = false
            mineRoute(false)
        end)
    end,
})

MiningBox:AddToggle("MiningAutoFarm", {
    Text = "Auto farm",
    Default = false,
})

MiningBox:AddButton({
    Text = "Stop",
    Func = function()
        MiningState.StopRequested = true

        if Toggles.MiningAutoFarm then
            Toggles.MiningAutoFarm:SetValue(false)
        end
    end,
})

Options.MiningOreFilter:OnChanged(function(value)
    MiningState.SelectedOre = value or "All"
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
            local mined = mineRoute(true)

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
