local Repo = "https://raw.githubusercontent.com/zTonho/voidra-bridgerwestern/refs/heads/dev-test/"
local ObsidianRepo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/"
local ScriptFolderName = "voidra"
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

    if path == "addons/SaveManager.lua" or path == "addons/ThemeManager.lua" then
        source = source:gsub('Folder%s*=%s*"ObsidianLibSettings"', 'Folder = "' .. ScriptFolderName .. '"')
    end

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
    Mining = Window:AddTab("Ores", "pickaxe"),
    Teleports = Window:AddTab("Teleports", "map-pin"),
    Autobuy = Window:AddTab("Autobuy", "shopping-cart"),
    Player = Window:AddTab("Player", "user"),
    Settings = Window:AddTab("UI Settings", "settings"),
}

local State = {
    Loaded = true,
    Fishing = {
        AutoFish = false,
        AutoSell = false,
        UseHotspots = true,
        StopRequested = false,
    },
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
local unloadVoidra

MenuBox:AddButton({
    Text = "Unload",
    Func = function()
        if unloadVoidra then
            unloadVoidra()
        end
    end,
})

local MainOk, MainError = pcall(function()
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local FishingState = State.Fishing
local FishingSpotPosition = Vector3.new(1768.35, 3.03, -1398.29)
local FishingCastCFrame = CFrame.new(1743.9234619140625, -5.975002288818359, -1410.97705078125, -0, 1, -0, -0, 0, -1, -1, 0, -0)
local FishingCastRotation = CFrame.new(0, 0, 0, -0, 1, -0, -0, 0, -1, -1, 0, -0)
local FishingAttackAlpha = 1
local FishingAttackResponseTime = 0
local FishingCastAttackDelay = 0
local FishingAutoCastInterval = 1
local FishingAutoCatchPollDelay = 0.02
local FishingPreCastRecallDelay = 0
local FishingPostCatchCastDelay = 0.65
local FishingLineLandDelay = 0.48
local FishingReelWaitTimeout = 6
local FishingReelPollDelay = 0.04
local FishingReelHitRepeats = 64
local FishingReelHitBatchSize = 16
local FishingReelEndRepeats = 2
local FishingCatchingSettleDelay = 0.015
local FishingPostReelDelay = 0.005
local FishingCycleDelay = 0.005
local FishingIdleDelay = 0.2
local FishingBaseTeleportOffset = 5
local FishingBaseDropSpacing = 4
local FishingBaseDropHeight = 1.25
local FishingOwnedGrabScanRadius = 90
local FishingHeldDropDelay = 0.12
local FishingSellAfterCatchDelay = 0.02
local FishingSellDropSpacing = 1.35
local FishingSellDropHeight = 0.7
local FishingSellCenterBiasScale = 0.18
local FishingSellMaxGridOffset = 1.8
local FishingSellMoveRepeats = 12
local FishingSellStepDelay = 0.004
local FishingSellSettleDelay = 0.12
local FishingSellDealRepeats = 3
local FishingHoverMover = nil
local getCatchParts
local LastFishingCatchAt = 0
local LastFishingHotspotWarning = 0
local FishingHotspotWarningCooldown = 4

local function mainNotify(description)
    Library:Notify({
        Title = "voidra",
        Description = description,
        Time = 3,
    })
end

local function getQuestRewardRemote()
    local events = ReplicatedStorage:FindFirstChild("Events")
    local quests = events and events:FindFirstChild("Quests")
    local v2 = quests and quests:FindFirstChild("V2")

    return v2 and v2:FindFirstChild("ClaimQuestReward") or nil
end

local function claimQuestReward(questName, rewardName)
    local remote = getQuestRewardRemote()

    if not remote then
        mainNotify("ClaimQuestReward remote was not found.")
        return
    end

    local ok, result = pcall(function()
        if remote:IsA("RemoteFunction") then
            return remote:InvokeServer(questName)
        end

        remote:FireServer(questName)
        return true
    end)

    if ok then
        mainNotify(("%s claim requested."):format(rewardName))
    else
        warn("[voidra] Quest reward claim failed: " .. tostring(result))
        mainNotify("Quest reward claim failed. Check console.")
    end
end

local function mainCallRemote(remote, ...)
    if not remote then
        return false
    end

    local args = { ... }
    local ok = pcall(function()
        if remote:IsA("RemoteFunction") then
            remote:InvokeServer(unpack(args))
        else
            remote:FireServer(unpack(args))
        end
    end)

    return ok
end

local function getMainCharacter()
    return LocalPlayer.Character
end

local function getMainHumanoid()
    local character = getMainCharacter()
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function getMainRoot()
    local character = getMainCharacter()
    return character
        and (
            character:FindFirstChild("HumanoidRootPart")
            or character.PrimaryPart
            or character:FindFirstChildWhichIsA("BasePart")
        )
end

local function setMainCharacterAt(position)
    local root = getMainRoot()

    if not root then
        return false
    end

    root.CFrame = CFrame.new(position)
    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    return true
end

local function getMainPosition(instance)
    if not instance then
        return nil
    end

    if instance:IsA("BasePart") then
        return instance.Position
    end

    if instance:IsA("Model") then
        return instance:GetPivot().Position
    end

    local part = instance:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local function ownerMatchesMainPlayer(owner)
    if not owner then
        return false
    end

    if owner:IsA("ObjectValue") then
        local value = owner.Value
        return value == LocalPlayer
            or value == LocalPlayer.Character
            or value == LocalPlayer.Name
            or tostring(value) == LocalPlayer.Name
    end

    if owner:IsA("StringValue") then
        return owner.Value == LocalPlayer.Name
            or owner.Value == tostring(LocalPlayer.UserId)
    end

    if owner:IsA("IntValue") or owner:IsA("NumberValue") then
        return owner.Value == LocalPlayer.UserId
    end

    return owner:GetAttribute("UserId") == LocalPlayer.UserId
        or owner:GetAttribute("Owner") == LocalPlayer.Name
end

local function getMainAreaData(target, fallbackSize)
    if not target then
        return nil, nil, nil
    end

    if target:IsA("BasePart") then
        return target.Position, target.Size, target.Position.Y + (target.Size.Y / 2)
    end

    if target:IsA("Model") then
        local cframe, size = target:GetBoundingBox()
        return cframe.Position, size, cframe.Position.Y + (size.Y / 2)
    end

    local part = target:FindFirstChildWhichIsA("BasePart", true)
    if part then
        return part.Position, fallbackSize or part.Size, part.Position.Y + (part.Size.Y / 2)
    end

    return nil, nil, nil
end

local function getMainLocalPlot()
    local plots = workspace:FindFirstChild("Plots")

    if not plots then
        return nil
    end

    for _, plot in ipairs(plots:GetChildren()) do
        local owner = plot:FindFirstChild("Owner", true) or plot:FindFirstChild("owner", true)

        if ownerMatchesMainPlayer(owner) then
            return plot
        end
    end

    return nil
end

local function getMainPlotTarget()
    local plot = getMainLocalPlot()

    if not plot then
        return nil
    end

    return plot:FindFirstChild("Plot")
        or plot:FindFirstChild("ProjectionZone")
        or plot:FindFirstChild("Objects")
        or plot
end

local function getMainPlotAreaData()
    return getMainAreaData(getMainPlotTarget(), Vector3.new(36, 1, 36))
end

local function isPositionInsideMainPlot(position, margin)
    local center, size = getMainPlotAreaData()

    if not position or not center or not size then
        return false
    end

    margin = margin or 4

    return math.abs(position.X - center.X) <= (size.X / 2) + margin
        and math.abs(position.Z - center.Z) <= (size.Z / 2) + margin
end

local function getMainPlotStandPosition()
    local position, _, topY = getMainPlotAreaData()

    if not position then
        return nil
    end

    return Vector3.new(position.X, topY + FishingBaseTeleportOffset, position.Z)
end

local function getMainPlotDropPosition(slot)
    local position, size, topY = getMainPlotAreaData()

    if not position then
        return nil
    end

    local columns = math.max(1, math.min(6, math.floor(size.X / FishingBaseDropSpacing)))
    local index = slot - 1
    local column = index % columns
    local row = math.floor(index / columns)
    local xLimit = math.max(1, (size.X / 2) - 2)
    local zLimit = math.max(1, (size.Z / 2) - 2)
    local xOffset = math.clamp((column - ((columns - 1) / 2)) * FishingBaseDropSpacing, -xLimit, xLimit)
    local zOffset = math.clamp(row * FishingBaseDropSpacing, -zLimit, zLimit)

    return Vector3.new(position.X + xOffset, topY + FishingBaseDropHeight, position.Z + zOffset)
end

local function stopFishingHover()
    if FishingHoverMover then
        FishingHoverMover:Destroy()
        FishingHoverMover = nil
    end
end

local function finishFishingAtBase()
    stopFishingHover()

    local position = getMainPlotStandPosition()

    if position then
        setMainCharacterAt(position)
    end
end

local function holdFishingPosition(position)
    local root = getMainRoot()

    if not root or not position then
        return false
    end

    setMainCharacterAt(position)

    if not FishingHoverMover or FishingHoverMover.Parent ~= root then
        stopFishingHover()

        local bodyPosition = Instance.new("BodyPosition")
        bodyPosition.Name = "VoidraFishingHover"
        bodyPosition.MaxForce = Vector3.new(1000000, 1000000, 1000000)
        bodyPosition.P = 35000
        bodyPosition.D = 1600
        bodyPosition.Parent = root
        FishingHoverMover = bodyPosition
    end

    FishingHoverMover.Position = position
    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    return true
end

local function getEventsChild(...)
    local current = ReplicatedStorage:FindFirstChild("Events")

    for _, name in ipairs({ ... }) do
        current = current and current:FindFirstChild(name)
    end

    return current
end

local function isFishingRod(tool)
    if not tool or not tool:IsA("Tool") then
        return false
    end

    local name = tool.Name:lower()
    return name:find("fishing", 1, true) ~= nil or name:find("rod", 1, true) ~= nil
end

local function getFishingRod()
    local character = getMainCharacter()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

    for _, container in ipairs({ character, backpack, LocalPlayer }) do
        if container then
            for _, object in ipairs(container:GetChildren()) do
                if isFishingRod(object) then
                    return object
                end
            end
        end
    end

    return nil
end

local function equipFishingRod()
    local humanoid = getMainHumanoid()
    local character = getMainCharacter()
    local rod = getFishingRod()

    if not rod then
        return nil
    end

    if humanoid and character and rod.Parent ~= character then
        pcall(function()
            humanoid:EquipTool(rod)
        end)

        task.wait(0.15)
    end

    return getFishingRod() or rod
end

local function canContinueFishing(singleRun)
    if singleRun then
        return not FishingState.StopRequested
    end

    return Toggles.FishingAutoFish
        and Toggles.FishingAutoFish.Value
        and not FishingState.StopRequested
end

local function getFishingHotspotFolder()
    local mouseIgnore = workspace:FindFirstChild("MouseIgnore")
        or workspace:FindFirstChild("Mouseignore")
        or workspace:FindFirstChild("Mouseignore", true)
        or workspace:FindFirstChild("MouseIgnore", true)

    return mouseIgnore and mouseIgnore:FindFirstChild("FishHotspots") or nil
end

local function getFishingHotspotPosition(hotspot)
    if not hotspot then
        return nil
    end

    if hotspot:IsA("BasePart") then
        return hotspot.Position
    end

    local hitbox = hotspot:FindFirstChild("Hitbox", true)
    if hitbox and hitbox:IsA("BasePart") then
        return hitbox.Position
    end

    local part = hotspot:FindFirstChildWhichIsA("BasePart", true)
    if part then
        return part.Position
    end

    return getMainPosition(hotspot)
end

local function getBestFishingHotspot()
    local folder = getFishingHotspotFolder()

    if not folder then
        return nil
    end

    local root = getMainRoot()
    local rootPosition = root and root.Position
    local bestHotspot = nil
    local bestPosition = nil
    local bestDistance = math.huge

    for _, hotspot in ipairs(folder:GetChildren()) do
        local position = getFishingHotspotPosition(hotspot)

        if position then
            local distance = rootPosition and (position - rootPosition).Magnitude or 0

            if distance < bestDistance then
                bestDistance = distance
                bestHotspot = hotspot
                bestPosition = position
            end
        end
    end

    return bestHotspot, bestPosition
end

local function getFishingCastData()
    local _, hotspotPosition = nil, nil

    if FishingState.UseHotspots then
        _, hotspotPosition = getBestFishingHotspot()
    end

    if hotspotPosition then
        return FishingSpotPosition,
            CFrame.new(hotspotPosition) * FishingCastRotation,
            true
    end

    return FishingSpotPosition, FishingCastCFrame, false
end

local function warnNoFishingHotspot()
    local now = os.clock()

    if now - LastFishingHotspotWarning < FishingHotspotWarningCooldown then
        return
    end

    LastFishingHotspotWarning = now
    mainNotify("No fish hotspot found.")
end

local function isFishingCatchingActive()
    local character = getMainCharacter()
    return character and character:GetAttribute("Catching") == true
end

local function waitForFishingReel(singleRun)
    local startedAt = os.clock()

    while canContinueFishing(singleRun) and os.clock() - startedAt < FishingReelWaitTimeout do
        if isFishingCatchingActive() then
            return true
        end

        task.wait(FishingReelPollDelay)
    end

    return false
end

local function recallFishingLine()
    local chargeRemote = getEventsChild("Tools", "Charge")

    if chargeRemote then
        mainCallRemote(chargeRemote, {})
        task.wait(0.12)
    end
end

local function triggerFishingCatchFromAttribute(reelHitRemote, reelEndRemote, singleRun)
    if not isFishingCatchingActive() then
        return false
    end

    local hits = 0

    while canContinueFishing(singleRun) and hits < FishingReelHitRepeats do
        for _ = 1, FishingReelHitBatchSize do
            if not canContinueFishing(singleRun) or hits >= FishingReelHitRepeats then
                break
            end

            mainCallRemote(reelHitRemote)
            hits = hits + 1
        end

        task.wait()
    end

    task.wait(FishingCatchingSettleDelay)

    for _ = 1, FishingReelEndRepeats do
        if not canContinueFishing(singleRun) then
            return false
        end

        mainCallRemote(reelEndRemote)
        task.wait(FishingCatchingSettleDelay)
    end

    task.wait(FishingPostReelDelay)
    if hits > 0 then
        LastFishingCatchAt = os.clock()
        return true
    end

    return false
end

local function castFishingLine(forceRecall)
    local chargeRemote = getEventsChild("Tools", "Charge")
    local attackRemote = getEventsChild("Tools", "Attack")

    if not chargeRemote or not attackRemote then
        mainNotify("Fishing remotes were not found.")
        return false
    end

    if isFishingCatchingActive() or os.clock() - LastFishingCatchAt < FishingPostCatchCastDelay then
        return false
    end

    local standPosition, castCFrame = getFishingCastData()

    if not standPosition or not castCFrame then
        warnNoFishingHotspot()
        stopFishingHover()
        return false
    end

    if not holdFishingPosition(standPosition) then
        mainNotify("Character root was not found.")
        return false
    end

    if not equipFishingRod() then
        mainNotify("Fishing rod was not found.")
        return false
    end

    if forceRecall then
        mainCallRemote(chargeRemote, {})
        task.wait(FishingPreCastRecallDelay)
    end

    mainCallRemote(chargeRemote, {
        HitPosition = castCFrame,
    })

    if FishingCastAttackDelay > 0 then
        task.wait(FishingCastAttackDelay)
    end

    mainCallRemote(attackRemote, {
        Alpha = FishingAttackAlpha,
        ResponseTime = FishingAttackResponseTime,
    })

    return true
end

local function runFishingCycle(singleRun)
    local reelHitRemote = getEventsChild("Fish", "ReelSessionHit")
    local reelEndRemote = getEventsChild("Fish", "ReelSessionEnd")

    if not reelHitRemote or not reelEndRemote then
        mainNotify("Fishing remotes were not found.")
        return false
    end

    if not castFishingLine(false) then
        return false
    end

    task.wait(FishingLineLandDelay)

    if not waitForFishingReel(singleRun) then
        recallFishingLine()
        return false
    end

    return triggerFishingCatchFromAttribute(reelHitRemote, reelEndRemote, singleRun)
end

local function getNauticSellary()
    local map = workspace:FindFirstChild("Map")
    local structures = map and map:FindFirstChild("Structures")
    return structures and (structures:FindFirstChild("Nautic_Sellary") or structures:FindFirstChild("Nautic_Sellary", true)) or nil
end

local function getFishSellZoneData()
    local sellary = getNauticSellary()
    local sellZone = sellary and (sellary:FindFirstChild("SellZone") or sellary:FindFirstChild("SellZone", true))

    if not sellZone then
        return nil, nil, nil
    end

    local function biasInsideSellZone(position, size)
        local talkPart = sellary and (sellary:FindFirstChild("TalkPart") or sellary:FindFirstChild("TalkPart", true))

        if not talkPart or not talkPart:IsA("BasePart") then
            return position
        end

        local direction = Vector3.new(talkPart.Position.X - position.X, 0, talkPart.Position.Z - position.Z)

        if direction.Magnitude <= 0.01 then
            return position
        end

        local biasDistance = math.min(size.X, size.Z) * FishingSellCenterBiasScale
        return position + direction.Unit * biasDistance
    end

    local target = sellZone:FindFirstChild("Area", true)

    if target and target:IsA("BasePart") then
        return biasInsideSellZone(target.Position, target.Size), target.Size, target.Position.Y + (target.Size.Y / 2) + 0.5
    end

    if sellZone:IsA("Model") then
        local cframe, size = sellZone:GetBoundingBox()
        return biasInsideSellZone(cframe.Position, size), size, cframe.Position.Y - (size.Y / 2) + FishingSellDropHeight
    end

    if sellZone:IsA("BasePart") then
        return biasInsideSellZone(sellZone.Position, sellZone.Size), sellZone.Size, sellZone.Position.Y + (sellZone.Size.Y / 2) + 0.5
    end

    return nil, nil, nil
end

local function getFishSellDropPosition(slot)
    local position, size, dropY = getFishSellZoneData()

    if not position then
        return nil
    end

    local index = slot - 1
    local gridSize = 3
    local column = (index % gridSize) - 1
    local row = (math.floor(index / gridSize) % gridSize) - 1
    local layer = math.floor(index / (gridSize * gridSize))
    local xLimit = math.min(FishingSellMaxGridOffset, math.max(0.5, (size.X / 2) - 3))
    local zLimit = math.min(FishingSellMaxGridOffset, math.max(0.5, (size.Z / 2) - 3))
    local xOffset = math.clamp(column * FishingSellDropSpacing, -xLimit, xLimit)
    local zOffset = math.clamp(row * FishingSellDropSpacing, -zLimit, zLimit)

    return Vector3.new(position.X + xOffset, dropY + math.min(layer * 0.35, 1.5), position.Z + zOffset)
end

local function getNauticSellaryInteract()
    local sellary = getNauticSellary()
    local talkPart = sellary and (sellary:FindFirstChild("TalkPart") or sellary:FindFirstChild("TalkPart", true))
    return talkPart and talkPart:FindFirstChild("Interact") or nil
end

local function getGrabHandlerRemote()
    return getEventsChild("GrabHandler")
end

local function hasCatchTag(instance)
    if not instance then
        return false
    end

    local ok, tagged = pcall(function()
        return CollectionService:HasTag(instance, "_IsCatch")
    end)

    return ok and tagged == true
end

local function getCatchMarkerRoot(marker)
    if not marker then
        return nil
    end

    if hasCatchTag(marker) then
        return marker
    end

    if marker.Name == "_CatchWeld" or marker.Name == "_CatchAttachment" then
        local root = marker:FindFirstAncestorWhichIsA("Model")

        if root and root ~= getMainCharacter() then
            return root
        end
    end

    return nil
end

local function getOwnedGrabRootOwner(root)
    if not root then
        return nil
    end

    return root:FindFirstChild("Owner")
        or root:FindFirstChild("owner")
        or root:FindFirstChild("Owner", true)
        or root:FindFirstChild("owner", true)
end

local function isOwnedGrabLootRoot(root)
    local grab = workspace:FindFirstChild("Grab")

    if not root or not grab or root.Parent ~= grab then
        return false
    end

    if not ownerMatchesMainPlayer(getOwnedGrabRootOwner(root)) then
        return false
    end

    local characterRoot = getMainRoot()
    local lootPosition = getMainPosition(root)

    if characterRoot and lootPosition then
        return (lootPosition - characterRoot.Position).Magnitude <= FishingOwnedGrabScanRadius
    end

    return true
end

local function getCatchMoveRoot(instance)
    local current = instance
    local best = instance

    while current and current ~= workspace do
        if hasCatchTag(current) then
            best = current
        end

        if current.Parent == workspace:FindFirstChild("Grab") then
            return current
        end

        current = current.Parent
    end

    return best
end

local function getCatchMovePart(instance)
    local root = getCatchMoveRoot(instance)

    if root:IsA("BasePart") then
        return root, root
    end

    if root:IsA("Model") then
        local part = root.PrimaryPart or root:FindFirstChildWhichIsA("BasePart", true)
        return part, root
    end

    local part = root:FindFirstChildWhichIsA("BasePart", true)
    return part, root
end

local function setCatchAt(part, root, position)
    pcall(function()
        if root and root:IsA("Model") then
            root:PivotTo(CFrame.new(position))
        elseif part then
            part.CFrame = CFrame.new(position)
        end

        if part then
            part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end
    end)
end

local function detachCatchLocal(root)
    if not root then
        return
    end

    pcall(function()
        for _, object in ipairs(root:GetDescendants()) do
            if object.Name == "_CatchWeld" or object.Name == "_CatchAttachment" then
                object:Destroy()
            elseif object:IsA("BasePart") then
                object.Anchored = false
                object.Massless = false
                object.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                object.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end
        end

        root:SetAttribute("Grabbed", nil)
    end)
end

function getCatchParts(includeOwnedGrabLoot)
    if includeOwnedGrabLoot == nil then
        includeOwnedGrabLoot = true
    end

    local parts = {}
    local seen = {}

    local function addCatch(catch)
        if catch and (catch:IsDescendantOf(workspace) or catch:IsDescendantOf(LocalPlayer)) then
            local part, root = getCatchMovePart(catch)

            if part and root and not seen[root] then
                seen[root] = true
                parts[#parts + 1] = {
                    Part = part,
                    Root = root,
                }
            end
        end
    end

    for _, catch in ipairs(CollectionService:GetTagged("_IsCatch")) do
        addCatch(catch)
    end

    local character = getMainCharacter()

    if character then
        for _, object in ipairs(character:GetDescendants()) do
            local root = getCatchMarkerRoot(object)

            if root then
                addCatch(root)
            end
        end
    end

    local grab = includeOwnedGrabLoot and workspace:FindFirstChild("Grab") or nil

    if grab then
        for _, object in ipairs(grab:GetChildren()) do
            if isOwnedGrabLootRoot(object) then
                addCatch(object)
            end
        end
    end

    return parts
end

local function isCatchHeld(entry)
    local character = getMainCharacter()

    return character
        and entry
        and (
            (entry.Root and entry.Root:IsDescendantOf(character))
            or (entry.Part and entry.Part:IsDescendantOf(character))
        )
end

local function isCatchInsideMainPlot(entry)
    if not entry then
        return false
    end

    local plot = getMainLocalPlot()

    if plot and (
        (entry.Root and entry.Root:IsDescendantOf(plot))
        or (entry.Part and entry.Part:IsDescendantOf(plot))
    ) then
        return true
    end

    local position = getMainPosition(entry.Root) or getMainPosition(entry.Part)
    return isPositionInsideMainPlot(position, 5)
end

local function hasHeldFishingCatch()
    for _, entry in ipairs(getCatchParts()) do
        if isCatchHeld(entry) then
            return true
        end
    end

    return false
end

local function moveCatchToSell(entry, destination)
    local grabHandler = getGrabHandlerRemote()

    if not grabHandler or not entry or not entry.Part or not destination then
        return false
    end

    local part = entry.Part
    local root = entry.Root
    detachCatchLocal(root)

    local startPosition = getMainPosition(root) or getMainPosition(part)

    if not startPosition then
        return false
    end

    local moved = mainCallRemote(grabHandler, part, "Grab", startPosition)

    for _ = 1, FishingSellMoveRepeats do
        setCatchAt(part, root, destination)
        moved = mainCallRemote(grabHandler, part, "Grab", destination) or moved
        task.wait(FishingSellStepDelay)
    end

    mainCallRemote(grabHandler, part, "Ungrab")
    setCatchAt(part, root, destination)
    return moved
end

local function dropHeldFishCatchAt(position)
    local chargeRemote = getEventsChild("Tools", "Charge")

    if not chargeRemote or not position or not hasHeldFishingCatch() then
        return false
    end

    stopFishingHover()
    setMainCharacterAt(position)
    task.wait(0.08)
    mainCallRemote(chargeRemote, {})
    task.wait(FishingHeldDropDelay)
    return true
end

local function getLootNameCandidates(entry)
    local names = {}

    local function addName(value)
        if type(value) == "string" and value ~= "" and not names[value] then
            names[value] = true
        end
    end

    if entry then
        if entry.Root then
            addName(entry.Root.Name)
            addName(entry.Root:GetAttribute("MaterialString"))
            addName(entry.Root:GetAttribute("ItemName"))
            addName(entry.Root:GetAttribute("FishName"))
        end

        if entry.Part then
            addName(entry.Part.Name)
            addName(entry.Part:GetAttribute("MaterialString"))
            addName(entry.Part:GetAttribute("ItemName"))
            addName(entry.Part:GetAttribute("FishName"))
        end
    end

    return names
end

local FishingValuableLootNames = {
    ["Bronze Key"] = true,
    ["Silver Key"] = true,
    ["Gold Key"] = true,
    ["Rusty Chest"] = true,
    ["Silver Chest"] = true,
    ["Golden Chest"] = true,
}

local function isFishingValuableLoot(entry)
    for name in pairs(getLootNameCandidates(entry)) do
        if FishingValuableLootNames[name] then
            return true
        end
    end

    return false
end

local function storeFishCatchesAtBase(filterFn)
    if not getMainPlotDropPosition(1) then
        finishFishingAtBase()
        return false
    end

    local catches = getCatchParts()

    if #catches == 0 then
        return false
    end

    local moved = 0

    for _, entry in ipairs(catches) do
        if filterFn and filterFn(entry) then
            local destination = getMainPlotDropPosition(moved + 1)

            if destination and moveCatchToSell(entry, destination) then
                moved = moved + 1
            end
        end
    end

    return moved > 0
end

local function sellFishCatches()
    local firstDropPosition = getFishSellDropPosition(1)

    if not firstDropPosition then
        mainNotify("Nautic sell zone was not found.")
        return 0
    end

    local catches = getCatchParts(false)

    if #catches == 0 then
        mainNotify("No caught fish found.")
        return 0
    end

    local moved = 0

    for _, entry in ipairs(catches) do
        if not isCatchInsideMainPlot(entry) then
            local destination = getFishSellDropPosition(moved + 1)

            if destination and moveCatchToSell(entry, destination) then
                moved = moved + 1
            end
        end
    end

    if moved <= 0 then
        mainNotify("No fish were moved.")
        return 0
    end

    task.wait(FishingSellSettleDelay)

    local interact = getNauticSellaryInteract()

    if interact then
        for _ = 1, FishingSellDealRepeats do
            mainCallRemote(interact, "Deal", 1)
            task.wait(0.08)
        end

        mainNotify("Fish sold successfully.")
    else
        mainNotify("Nautic Sellary was not found.")
    end

    return moved
end

local TalentsBox = Tabs.Main:AddRightGroupbox("Talents", "sparkles")

TalentsBox:AddButton({
    Text = "Get Tool Reaper",
    Func = function()
        claimQuestReward("MaroonsQuest", "Tool Reaper")
    end,
})

local FishingBox = Tabs.Main:AddLeftGroupbox("Fishing", "fish")

FishingBox:AddButton({
    Text = "Fish once",
    Func = function()
        task.spawn(function()
            FishingState.StopRequested = false
            local ok, result = pcall(runFishingCycle, true)

            if not ok then
                warn("[voidra] Fish once failed: " .. tostring(result))
                mainNotify("Fish once failed. Check console.")
            end

            local cycleOk = ok and result == true

            if cycleOk and FishingState.AutoSell then
                sellFishCatches()
            end

            finishFishingAtBase()
        end)
    end,
})

FishingBox:AddToggle("FishingAutoFish", {
    Text = "Auto fish",
    Default = false,
})

FishingBox:AddToggle("FishingUseHotspots", {
    Text = "Use hotspots",
    Default = true,
})

FishingBox:AddDivider("Storage")
FishingBox:AddButton({
    Text = "Sell fish",
    Func = function()
        task.spawn(sellFishCatches)
    end,
})

FishingBox:AddButton({
    Text = "Store keys/chests",
    Func = function()
        task.spawn(function()
            local moved = storeFishCatchesAtBase(isFishingValuableLoot)

            if moved then
                mainNotify("Keys/chests stored at base.")
            else
                mainNotify("No keys/chests found.")
            end
        end)
    end,
})

FishingBox:AddToggle("FishingAutoSell", {
    Text = "Auto sell fish",
    Default = false,
})

local fishingLoopRunning = false
local fishingCatchLoopRunning = false

Toggles.FishingUseHotspots:OnChanged(function(enabled)
    FishingState.UseHotspots = enabled
end)

Toggles.FishingAutoSell:OnChanged(function(enabled)
    FishingState.AutoSell = enabled
end)

Toggles.FishingAutoFish:OnChanged(function(enabled)
    FishingState.AutoFish = enabled
    FishingState.StopRequested = not enabled

    if not enabled then
        task.spawn(finishFishingAtBase)
        return
    end

    if fishingLoopRunning then
        return
    end

    fishingLoopRunning = true

    if not fishingCatchLoopRunning then
        fishingCatchLoopRunning = true

        task.spawn(function()
            local reelHitRemote = getEventsChild("Fish", "ReelSessionHit")
            local reelEndRemote = getEventsChild("Fish", "ReelSessionEnd")

            while canContinueFishing() do
                if reelHitRemote and reelEndRemote and isFishingCatchingActive() then
                    local caught = triggerFishingCatchFromAttribute(reelHitRemote, reelEndRemote, false)

                    if caught and FishingState.AutoSell then
                        task.spawn(function()
                            task.wait(FishingSellAfterCatchDelay)
                            sellFishCatches()
                        end)
                    end
                end

                task.wait(FishingAutoCatchPollDelay)
            end

            fishingCatchLoopRunning = false
        end)
    end

    task.spawn(function()
        while canContinueFishing() do
            if isFishingCatchingActive() or os.clock() - LastFishingCatchAt < FishingPostCatchCastDelay then
                task.wait(FishingAutoCatchPollDelay)
            else
                local ok, result = pcall(castFishingLine, true)

                if not ok then
                    warn("[voidra] Auto fish failed: " .. tostring(result))
                    mainNotify("Auto fish failed. Check console.")
                end

                local cycleOk = ok and result == true
                task.wait(cycleOk and FishingAutoCastInterval or FishingIdleDelay)
            end
        end

        finishFishingAtBase()
        fishingLoopRunning = false
    end)
end)

local previousCleanup = cleanup
cleanup = function()
    previousCleanup()
    FishingState.StopRequested = true
    stopFishingHover()
end
end)

if not MainOk then
    warn("[voidra] Main setup failed: " .. tostring(MainError))
    Library:Notify({
        Title = "voidra",
        Description = "Main setup failed. Check console.",
        Time = 5,
    })
end

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
local MiningChargeAlpha = 1
local MiningSensitiveChargeAlpha = 0.55
local MiningSensitiveChargeTime = 0.55
local MiningSensitiveChargeDelay = 0
local MiningSensitiveAttackBurstCount = 1
local MiningNormalActionDelay = 0.006
local MiningNormalAttackResultDelay = 0.012
local MiningNormalAttackBurstCount = 8
local MiningNormalAttackBurstDelay = 0.012
local MiningActionDelay = 0.015
local MiningTeleportOffset = 5
local MiningIdleDelay = 0.35
local MiningMaxHitsPerOre = 3600
local MiningChargeUiTimeout = 0.3
local MiningChargeUiPollDelay = 0.015
local MiningCooldownDelay = 0.25
local MiningGetOreMaxChargeMisses = 8
local MiningDropScanRadius = 30
local MiningGrabSteps = 8
local MiningGrabStepDelay = 0.015
local MiningFinalGrabRepeats = 5
local MiningDropSettleDelay = 0.12
local MiningFastGrabRepeats = 2
local MiningFastGrabDelay = 0.002
local MiningStorageBatchDelay = 0.004
local MiningAutoGrabRepeats = 2
local MiningAutoGrabDelay = 0.002
local MiningAutoLiftHeight = 180
local MiningAutoRouteStepDistance = 650
local MiningAutoRouteDelay = 0.012
local MiningAutoRouteFinalRepeats = 4
local MiningAutoBatchDelay = 0.004
local MiningBagCapacity = 5
local MiningBagStoreDelay = 0.04
local MiningBagStorePositionDelay = 0.055
local MiningBagStoreConfirmTimeout = 0.24
local MiningBagStoreConfirmPollDelay = 0.025
local MiningBagDropDelay = 0.09
local MiningBagStoreHeight = 3
local MiningBagCollectionPasses = 12
local MiningBagCollectionPassDelay = 0.1
local MiningBagEmptyPassLimit = 5
local MiningBagPostFlushScanDelay = 0.16
local MiningBagDropExtraCalls = 6
local MiningBagFinalDropCalls = 4
local MiningBagReturnDelay = 0.08
local MiningGrabReleaseRepeats = 6
local MiningGrabReleaseDelay = 0.04
local MiningDropWaitTimeout = 0.25
local MiningDropPollDelay = 0.02
local MiningTargetSettleDelay = 0.02
local MiningAttackResultDelay = 0.025
local MiningAttackBurstCount = 5
local MiningAttackBurstDelay = 0.025
local MiningAttackBurstYieldEvery = 1
local MiningTeleportRefreshDistance = 12
local MiningOreSpotDetectTimeout = 2.5
local MiningOreSpotPollDelay = 0.05
local MiningOreSpotLoadCooldown = 20
local MiningTargetRefreshTimeout = 1.2
local MiningTargetRefreshPollDelay = 0.05
local MiningUnequipStopDelay = 0.85
local MiningBaseDropHeight = 1.75
local MiningDropSpacing = 5
local MiningDropMaxColumns = 7
local MiningPlotInset = 5
local MiningBringRadius = 18
local MiningSellDropSpacing = 4
local MiningSellMoveSteps = 4
local MiningSellStepDelay = 0.006
local MiningSellFinalRepeats = 14
local MiningSellReleaseRepeats = 6
local MiningSellRetryDistance = 10
local MiningSellBatchDelay = 0.001
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

local ChargeSensitiveOres = {
    Blastshard = true,
    Voltshard = true,
}

local OreLoadSpots = {
    Abyssalite = { Vector3.new(-7066.40, -534.32, -2874.44) },
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
    Blastshard = { Vector3.new(-6563.19, -535.76, 1122.95) },
    Deepslate = { Vector3.new(-7836.77, 7.10, -3635.81) },
    Magma = { Vector3.new(-7066.40, -534.32, -2874.44) },
    Obsidian = { Vector3.new(-7066.40, -534.32, -2874.44) },
    Quartz = { Vector3.new(-5546.61, -90.25, -1807.21) },
    Salt = {
        Vector3.new(-5952.75, -174.50, -2017.67),
        Vector3.new(-6563.19, -535.76, 1122.95),
    },
    Sulfur = { Vector3.new(-29.43, 156.68, 3755.94) },
    Volcanium = { Vector3.new(-7066.40, -534.32, -2874.44) },
    Voltshard = { Vector3.new(-6563.19, -535.76, 1122.95) },
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

        task.wait(MiningChargeUiPollDelay)
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

local function getSellZoneStandPosition()
    local position, _, topY = getSellZoneData()

    if not position then
        return nil
    end

    return Vector3.new(position.X, topY + MiningTeleportOffset, position.Z)
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

local function isChargeSensitiveOre(ore)
    local oreName = ore and normalizeOreName(ore.Name)
    return oreName and ChargeSensitiveOres[oreName] == true
end

local function getNumericValue(object)
    if not object then
        return nil
    end

    local ok, value = pcall(function()
        return object.Value
    end)

    if ok then
        return tonumber(value)
    end

    return nil
end

local function findNumericConfigValue(object, valueName)
    if not object then
        return nil
    end

    local config = object:FindFirstChild("Configuration")
        or object:FindFirstChild("Configuration", true)

    if not config then
        return nil
    end

    local wanted = valueName:lower()
    local direct = config:FindFirstChild(valueName)

    if direct then
        local value = getNumericValue(direct)

        if value then
            return value
        end
    end

    for _, descendant in ipairs(config:GetDescendants()) do
        if descendant.Name:lower() == wanted then
            local value = getNumericValue(descendant)

            if value then
                return value
            end
        end
    end

    return nil
end

local function findContentTemplate(folderName, objectName)
    local content = ReplicatedStorage:FindFirstChild("Content")
    local folder = content and content:FindFirstChild(folderName)

    if not folder or not objectName then
        return nil
    end

    local exact = folder:FindFirstChild(objectName)

    if exact then
        return exact
    end

    local lowered = tostring(objectName):lower()

    for _, child in ipairs(folder:GetChildren()) do
        if child.Name:lower() == lowered then
            return child
        end
    end

    return nil
end

local function getOreTier(ore)
    local tier = findNumericConfigValue(ore, "Tier")

    if tier then
        return tier
    end

    local oreName = ore and (normalizeOreName(ore.Name) or ore.Name)
    local template = findContentTemplate("Ores", oreName)

    return findNumericConfigValue(template, "Tier")
end

local function getPickaxeTier(pickaxe)
    local tier = findNumericConfigValue(pickaxe, "Tier")

    if tier then
        return tier
    end

    local template = pickaxe and findContentTemplate("Tools", pickaxe.Name)

    return findNumericConfigValue(template, "Tier")
end

local function canPickaxeMineOre(pickaxe, ore)
    local pickaxeTier = getPickaxeTier(pickaxe)
    local oreTier = getOreTier(ore)

    if pickaxeTier and oreTier and pickaxeTier < oreTier then
        return false, pickaxeTier, oreTier
    end

    return true, pickaxeTier, oreTier
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

local function getDroppedOrePartsNearCharacter(origin)
    local root = getRoot()
    local rootPosition = root and root.Position

    return getDroppedOrePartsWhere(function(_, position)
        local nearOrigin = origin and (position - origin).Magnitude <= MiningDropScanRadius
        local nearCharacter = rootPosition and (position - rootPosition).Magnitude <= MiningDropScanRadius

        return nearCharacter or nearOrigin
    end, rootPosition or origin)
end

local function waitForDroppedOrePartsNearCharacter(origin)
    local startedAt = os.clock()
    local parts = getDroppedOrePartsNearCharacter(origin)

    while #parts == 0 and os.clock() - startedAt < MiningDropWaitTimeout do
        task.wait(MiningDropPollDelay)
        parts = getDroppedOrePartsNearCharacter(origin)
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

local function callRemote(remote, ...)
    if not remote then
        return false
    end

    local args = { ... }
    local ok = pcall(function()
        if remote:IsA("RemoteFunction") then
            remote:InvokeServer(unpack(args))
        else
            remote:FireServer(unpack(args))
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

local function moveGrabPartToSell(part, destination)
    if not part or not part.Parent or not destination then
        return false
    end

    local startPosition = getPosition(part)

    if not startPosition then
        return false
    end

    local moved = false
    local function setSellPartAt(position)
        pcall(function()
            part.CFrame = CFrame.new(position)
            part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)
    end

    moved = callGrabHandler(part, "Grab", startPosition) or moved
    task.wait(MiningSellStepDelay)

    for i = 1, MiningSellMoveSteps do
        if not part.Parent then
            break
        end

        local alpha = i / MiningSellMoveSteps
        local position = startPosition:Lerp(destination, alpha)

        setSellPartAt(position)
        moved = callGrabHandler(part, "Grab", position) or moved
        task.wait(MiningSellStepDelay)
    end

    for _ = 1, MiningSellFinalRepeats do
        if not part.Parent then
            break
        end

        setSellPartAt(destination)
        moved = callGrabHandler(part, "Grab", destination) or moved
        task.wait(MiningSellStepDelay)
    end

    for _ = 1, MiningSellReleaseRepeats do
        if not part.Parent then
            break
        end

        setSellPartAt(destination)
        callGrabHandler(part, "Ungrab")
        task.wait(MiningSellStepDelay)
    end

    local finalPosition = getPosition(part)

    if finalPosition and (finalPosition - destination).Magnitude > MiningSellRetryDistance then
        for _ = 1, MiningSellFinalRepeats do
            if not part.Parent then
                break
            end

            setSellPartAt(destination)
            moved = callGrabHandler(part, "Grab", destination) or moved
            task.wait(MiningSellStepDelay)
        end

        for _ = 1, MiningSellReleaseRepeats do
            if not part.Parent then
                break
            end

            setSellPartAt(destination)
            callGrabHandler(part, "Ungrab")
            task.wait(MiningSellStepDelay)
        end
    end

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

local function setCharacterAt(position)
    local root = getRoot()

    if not root or not position then
        return false
    end

    root.CFrame = CFrame.new(position + Vector3.new(0, MiningTeleportOffset, 0))
    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    return true
end

local function setCharacterExactAt(position)
    local root = getRoot()

    if not root or not position then
        return false
    end

    root.CFrame = CFrame.new(position)
    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    return true
end

local function setGrabPartAt(part, position)
    pcall(function()
        part.CFrame = CFrame.new(position)
        part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end)
end

local function getPlayerActionRemote(timeout)
    return LocalPlayer:FindFirstChild("Action") or LocalPlayer:WaitForChild("Action", timeout or 2)
end

local function getItemBag()
    local character = getCharacter()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

    local function isItemBagObject(object)
        local name = object.Name:lower()
        return object.Name == "Item Bag"
            or (name:find("item", 1, true) ~= nil and name:find("bag", 1, true) ~= nil)
    end

    for _, container in ipairs({ character, backpack, LocalPlayer }) do
        if container then
            local bag = container:FindFirstChild("Item Bag")

            if bag and (bag:IsA("Tool") or bag:FindFirstChild("Action", true)) then
                return bag
            end

            for _, object in ipairs(container:GetDescendants()) do
                if isItemBagObject(object) and (object:IsA("Tool") or object:FindFirstChild("Action", true)) then
                    return object
                end
            end
        end
    end

    return nil
end

local function equipItemBag()
    local humanoid = getHumanoid()
    local character = getCharacter()
    local bag = getItemBag()

    if humanoid and character and bag and bag:IsA("Tool") and bag.Parent ~= character then
        pcall(function()
            humanoid:EquipTool(bag)
        end)

        task.wait(0.25)
        bag = character:FindFirstChild("Item Bag") or character:FindFirstChild("Item Bag", true) or bag
    end

    return bag
end

local function getItemBagDropRemote()
    local bag = equipItemBag()
    local action = bag and (bag:FindFirstChild("Action") or bag:FindFirstChild("Action", true))

    return action
end

local function getEquippedItemBagAction()
    local character = getCharacter()
    local bag = character and character:FindFirstChild("Item Bag")

    if not bag then
        bag = equipItemBag()
    end

    if bag and bag.Parent ~= character then
        bag = character and character:FindFirstChild("Item Bag") or bag
    end

    return bag and (bag:FindFirstChild("Action") or bag:FindFirstChild("Action", true)) or nil
end

local function canUseItemBagTransport()
    local bagAction = getEquippedItemBagAction()

    return bagAction ~= nil
end

local function isDroppedPartActive(part)
    local container = getGrabContainer(part)
    return part
        and part.Parent
        and container
        and container.Parent
        and container:IsDescendantOf(workspace)
end

local function waitForItemBagStore(part)
    local startedAt = os.clock()

    repeat
        if not isDroppedPartActive(part) then
            return true
        end

        task.wait(MiningBagStoreConfirmPollDelay)
    until os.clock() - startedAt >= MiningBagStoreConfirmTimeout

    return not isDroppedPartActive(part)
end

local function storePartInItemBag(part, playerAction, bagAction)
    if not part or not part.Parent then
        return false
    end

    if not playerAction and not bagAction then
        equipItemBag()
        playerAction = getPlayerActionRemote(0.75)
        bagAction = getEquippedItemBagAction()
    end

    if not playerAction and not bagAction then
        return false
    end

    local position = getPosition(part)

    if position then
        setCharacterExactAt(position + Vector3.new(0, MiningBagStoreHeight, 0))
        task.wait(MiningBagStorePositionDelay)
    end

    local stored = false

    if playerAction then
        stored = callRemote(playerAction, "Store", part)
    end

    if not stored and bagAction then
        stored = callRemote(bagAction, "Store", part)
    end

    if not stored then
        return false
    end

    task.wait(MiningBagStoreDelay)
    return waitForItemBagStore(part)
end

local function dropItemBagAtBase(startSlot, amount)
    if amount <= 0 then
        return 0
    end

    local attempts = math.max(amount, MiningBagCapacity) + MiningBagDropExtraCalls

    for i = 1, attempts do
        local slotOffset = (i - 1) % math.max(amount, 1)
        local destination = getPlotDropPosition(startSlot + slotOffset)

        if not destination then
            break
        end

        setCharacterExactAt(destination + Vector3.new(0, 2.5, 0))
        task.wait(MiningBagDropDelay)

        local action = getEquippedItemBagAction()

        if action then
            callRemote(action, "Drop")
        end

        task.wait(MiningBagDropDelay)
    end

    return amount
end

local function clearItemBagAtBase(startSlot)
    local destination = getPlotDropPosition(startSlot)

    if not destination then
        return
    end

    setCharacterExactAt(destination + Vector3.new(0, 2.5, 0))
    task.wait(MiningBagDropDelay)

    for _ = 1, MiningBagFinalDropCalls do
        local action = getEquippedItemBagAction()

        if action then
            callRemote(action, "Drop")
        end

        task.wait(MiningBagDropDelay)
    end
end

local function moveGrabPartToBaseRouted(part, destination)
    if not part or not part.Parent or not destination then
        return false
    end

    local startPosition = getPosition(part)

    if not startPosition then
        return false
    end

    local liftY = math.max(startPosition.Y, destination.Y) + MiningAutoLiftHeight
    local liftedStart = Vector3.new(startPosition.X, liftY, startPosition.Z)
    local liftedDestination = Vector3.new(destination.X, liftY, destination.Z)
    local route = {
        liftedStart,
        liftedDestination,
        destination,
    }
    local moved = false
    local current = startPosition

    setCharacterAt(startPosition)
    moved = callGrabHandler(part, "Grab", startPosition) or moved
    task.wait(MiningAutoRouteDelay)

    for _, waypoint in ipairs(route) do
        local distance = (waypoint - current).Magnitude
        local steps = math.max(2, math.ceil(distance / MiningAutoRouteStepDistance))

        for i = 1, steps do
            if not part.Parent then
                break
            end

            local position = current:Lerp(waypoint, i / steps)

            setCharacterAt(position)
            setGrabPartAt(part, position)
            moved = callGrabHandler(part, "Grab", position) or moved
            task.wait(MiningAutoRouteDelay)
        end

        current = waypoint
    end

    for _ = 1, MiningAutoRouteFinalRepeats do
        if not part.Parent then
            break
        end

        setCharacterAt(destination)
        setGrabPartAt(part, destination)
        moved = callGrabHandler(part, "Grab", destination) or moved
        task.wait(MiningAutoRouteDelay)
    end

    for _ = 1, MiningGrabReleaseRepeats do
        if not part.Parent then
            break
        end

        setCharacterAt(destination)
        setGrabPartAt(part, destination)
        callGrabHandler(part, "Ungrab")
        task.wait(MiningGrabReleaseDelay)
    end

    task.wait(MiningDropSettleDelay)
    return moved
end

local function moveDroppedOresToBase(origin, flushPartialAtEnd)
    local destination = getPlotDropPosition(1)

    if not destination then
        miningWarn("Your plot was not found.")
        return 0
    end

    local useItemBag = canUseItemBagTransport()
    local moved = 0

    if not useItemBag then
        miningWarn("Item Bag was not found. Ore transport skipped.")
        return 0
    end

    MiningState.BagStoredCount = MiningState.BagStoredCount or 0

    local playerAction = getPlayerActionRemote(0.75)
    local bagAction = getEquippedItemBagAction()
    local storeAttempts = 0
    local storedParts = {}

    local function flushItemBag(forcePartial)
        if MiningState.BagStoredCount <= 0 then
            return false
        end

        if MiningState.BagStoredCount < MiningBagCapacity and not forcePartial then
            return false
        end

        local nextSlot = moved + 1
        local dropAmount = forcePartial and MiningState.BagStoredCount or MiningBagCapacity
        moved = moved + dropItemBagAtBase(nextSlot, dropAmount)
        clearItemBagAtBase(moved + 1)
        MiningState.BagStoredCount = 0
        task.wait(MiningAutoBatchDelay)

        if origin then
            setCharacterExactAt(origin + Vector3.new(0, MiningBagStoreHeight, 0))
            task.wait(MiningBagReturnDelay)
        end

        task.wait(MiningBagPostFlushScanDelay)
        return true
    end

    local emptyPasses = 0

    for pass = 1, MiningBagCollectionPasses do
        local parts = pass == 1 and waitForDroppedOrePartsNearCharacter(origin) or getDroppedOrePartsNearCharacter(origin)
        local storedThisPass = 0

        for _, part in ipairs(parts) do
            if not storedParts[part] then
                storeAttempts = storeAttempts + 1

                if storePartInItemBag(part, playerAction, bagAction) then
                    storedParts[part] = true
                    MiningState.BagStoredCount = MiningState.BagStoredCount + 1
                    storedThisPass = storedThisPass + 1

                    if MiningState.BagStoredCount >= MiningBagCapacity then
                        flushItemBag()
                        emptyPasses = 0
                    end
                end
            end
        end

        if storedThisPass == 0 then
            emptyPasses = emptyPasses + 1
        else
            emptyPasses = 0
        end

        if emptyPasses >= MiningBagEmptyPassLimit then
            break
        end

        task.wait(MiningBagCollectionPassDelay)
    end

    if flushPartialAtEnd then
        flushItemBag(true)
    end

    if storeAttempts > 0 and moved <= 0 then
        if MiningState.BagStoredCount > 0 then
            miningNotify(("Item Bag stored %d/%d ores."):format(MiningState.BagStoredCount, MiningBagCapacity))
        else
            miningWarn("Item Bag did not store any ore.")
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
    local talkPart = getSellTalkPart()

    if not talkPart then
        miningWarn("Nova Sellary talk part was not found.")
        return false
    end

    if not callSellaryInteract() then
        return false
    end

    task.wait(0.2)

    local sold = false

    for _ = 1, 3 do
        sold = callSellaryInteract("Deal", 1) or sold
        task.wait(0.15)
    end

    return sold
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

        if destination and moveGrabPartToSell(part, destination) then
            moved = moved + 1

            if moved % 10 == 0 then
                task.wait(MiningSellBatchDelay)
            end
        end
    end

    if moved == 0 then
        miningNotify("No ores were moved.")
        return 0
    end

    task.wait(0.5)

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

local TeleportsBox = Tabs.Teleports:AddLeftGroupbox("Locations", "map-pin")

local function teleportToLocation(position, name)
    if not position then
        miningNotify(name .. " was not found.")
        return
    end

    if setCharacterExactAt(position) then
        miningNotify("Teleported to " .. name .. ".")
    else
        miningNotify("Character root was not found.")
    end
end

TeleportsBox:AddButton({
    Text = "Base",
    Func = function()
        teleportToLocation(getPlotStandPosition(), "base")
    end,
})

TeleportsBox:AddButton({
    Text = "Sell Zone",
    Func = function()
        teleportToLocation(getSellZoneStandPosition(), "sell zone")
    end,
})

TeleportsBox:AddButton({
    Text = "Vi's Lab",
    Func = function()
        teleportToLocation(Vector3.new(-4446.63, -195.77, -2029.90), "Vi's Lab")
    end,
})

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
        while os.clock() - startedAt < MiningOreSpotDetectTimeout do
            if not canContinueMining(stopWhenToggleOff) then
                return false
            end

            if getNearestOreTarget(oreFilter) then
                miningNotify("Ores loaded.")
                return true
            end

            task.wait(MiningOreSpotPollDelay)
        end
    end

    return getNearestOreTarget(oreFilter) ~= nil
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

local function waitForOreEntry(entry, timeout)
    timeout = timeout or 0

    local startedAt = os.clock()

    repeat
        if refreshOreEntry(entry) then
            return true
        end

        if not entry or not entry.Ore or entry.Ore.Parent ~= getOresFolder() then
            return false
        end

        if timeout <= 0 then
            return false
        end

        task.wait(MiningTargetRefreshPollDelay)
    until os.clock() - startedAt >= timeout

    return refreshOreEntry(entry)
end

local function mineTarget(entry, stopWhenToggleOff, stopOnUnequip)
    if not refreshOreEntry(entry) then
        return false
    end

    local pickaxe = equipPickaxe()
    if not pickaxe then
        return false
    end

    local unequippedAt = nil
    local unequipConnection = nil
    local trackedPickaxe = stopOnUnequip and getEquippedPickaxe() or pickaxe
    local maxChargeMisses = stopOnUnequip and MiningGetOreMaxChargeMisses or MiningMaxChargeMisses
    local canMine, pickaxeTier, oreTier = canPickaxeMineOre(pickaxe, entry.Ore)
    local chargeSensitiveOre = isChargeSensitiveOre(entry.Ore)

    if not canMine then
        miningWarn(("Pickaxe tier too low. Pickaxe: %s | Ore: %s."):format(
            tostring(pickaxeTier or "?"),
            tostring(oreTier or "?")
        ))
        return false
    end

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
            unequippedAt = os.clock()
        end)
    end

    local function shouldStopForUnequip()
        if not stopOnUnequip then
            return false
        end

        local equippedPickaxe = getEquippedPickaxe()

        if equippedPickaxe then
            trackedPickaxe = equippedPickaxe
            unequippedAt = nil
            return false
        end

        unequippedAt = unequippedAt or os.clock()

        if os.clock() - unequippedAt >= MiningUnequipStopDelay then
            return true
        end

        return false
    end

    local hits = 0
    local dropOrigin = entry.HitPosition
    local chargeMisses = 0
    local lastTarget = nil

    while canContinueMining(stopWhenToggleOff) and hits < MiningMaxHitsPerOre and entry.Ore and entry.Ore.Parent == getOresFolder() do
        if not waitForOreEntry(entry, hits > 0 and MiningTargetRefreshTimeout or 0) then
            break
        end

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

            local attacksFired = 0
            local attackBurstCount = chargeSensitiveOre and MiningSensitiveAttackBurstCount or MiningNormalAttackBurstCount
            local attackBurstDelay = chargeSensitiveOre and MiningAttackBurstDelay or MiningNormalAttackBurstDelay
            local attackResultDelay = chargeSensitiveOre and MiningAttackResultDelay or MiningNormalAttackResultDelay
            local actionDelay = chargeSensitiveOre and MiningActionDelay or MiningNormalActionDelay
            local attackAlpha = chargeSensitiveOre and MiningSensitiveChargeAlpha or MiningChargeAlpha
            local attackResponseTime = chargeSensitiveOre and MiningSensitiveChargeTime or MiningChargeTime

            if chargeSensitiveOre then
                task.wait(MiningSensitiveChargeDelay)
            end

            for burstIndex = 1, attackBurstCount do
                if shouldStopForUnequip() then
                    miningNotify("Get ore stopped: pickaxe unequipped.")
                    break
                end

                if not entry.Ore or entry.Ore.Parent ~= getOresFolder() then
                    break
                end

                local attacked = pcall(function()
                    AttackRemote:FireServer({
                        Alpha = attackAlpha,
                        ResponseTime = attackResponseTime,
                    })
                end)

                if attacked then
                    attacksFired = attacksFired + 1
                end

                if attackBurstDelay > 0 then
                    task.wait(attackBurstDelay)
                elseif burstIndex % MiningAttackBurstYieldEvery == 0 then
                    task.wait()
                end
            end

            task.wait(attackResultDelay)

            hits = hits + attacksFired
            task.wait(actionDelay)
        end
    end

    if unequipConnection then
        unequipConnection:Disconnect()
    end

    setToolInput(false, pickaxe)

    if hits >= MiningMaxHitsPerOre and isOreAlive(entry.Ore) then
        miningNotify("Skipped ore: safety hit limit reached.")
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
        moveDroppedOresToBase(dropOrigin, stopWhenToggleOff)
        miningNotify("Ore collected successfully.")
    end

    return mined
end

local MiningBox = Tabs.Mining:AddLeftGroupbox("Autofarm", "pickaxe")

MiningBox:AddLabel("⚠ High ping may affect farm.")

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
    SaveManager:SetIgnoreIndexes({ "MenuKeybind", "MiningAutoFarm", "FishingAutoFish", "FishingAutoSell" })
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

unloadVoidra = function()
    cleanup()

    if Library and type(Library.Unload) == "function" then
        Library:Unload()
    end

    if env.Voidra then
        env.Voidra = nil
    end
end

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
