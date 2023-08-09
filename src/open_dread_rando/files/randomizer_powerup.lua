Game.LogWarn(0, "Loading randomizer_powerup.lua...")

RandomizerPowerup = {}
function RandomizerPowerup.main()
end

RandomizerPowerup.tProgressiveModels = {}

RandomizerPowerup.Self = nil

function RandomizerPowerup.SetItemAmount(item_id, quantity)
    if type(quantity) == "string" then
        quantity = RandomizerPowerup.GetItemAmount(quantity)
    end
    Game.SetItemAmount(Game.GetPlayerName(), item_id, quantity)
end
function RandomizerPowerup.GetItemAmount(item_id)
    return Game.GetItemAmount(Game.GetPlayerName(), item_id)
end
function RandomizerPowerup.HasItem(item_id)
    return RandomizerPowerup.GetItemAmount(item_id) > 0
end
function RandomizerPowerup.IncreaseItemAmount(item_id, quantity, capacity)
    local target = RandomizerPowerup.GetItemAmount(item_id) + quantity
    if capacity ~= nil then
        if type(capacity) == "string" then
            capacity = RandomizerPowerup.GetItemAmount(capacity)
        end
        target = math.min(target, capacity)
    end
    target = math.max(target, 0)
    RandomizerPowerup.SetItemAmount(item_id, target)
end

function RandomizerPowerup.PropertyForLocation(locationIdentifier)
    return "Location_Collected_" .. locationIdentifier
end

function RandomizerPowerup.MarkLocationCollected(locationIdentifier)
    local playerSection = Game.GetPlayerBlackboardSectionName()
    local propName = RandomizerPowerup.PropertyForLocation(locationIdentifier)
    Game.LogWarn(0, propName)
    Blackboard.SetProp(playerSection, propName, "b", true)
end

function RandomizerPowerup.IncrementInventoryIndex()
    local playerSection = Game.GetPlayerBlackboardSectionName()
    local propName = "InventoryIndex"
    local currentIndex = Blackboard.GetProp(playerSection, propName) or 0
    currentIndex = currentIndex + 1
    Blackboard.SetProp(playerSection, propName, "f", currentIndex)
end

function RandomizerPowerup.OnPickedUp(actor, resources)
    RandomizerPowerup.Self = actor
    local name = "Boss"
    if actor ~= nil then
        name = actor.sName
        RandomizerPowerup.MarkLocationCollected(string.format("%s_%s", Scenario.CurrentScenarioID, name))
    end

    Game.LogWarn(0, "Collected pickup: " .. name)
    local granted = RandomizerPowerup.HandlePickupResources(resources)

    -- RandomizerPowerup.ChangeSuit()

    for _, resource in ipairs(granted) do
        RandomizerPowerup.IncreaseEnergy(resource)
        RandomizerPowerup.IncreaseAmmo(resource)

        RandomizerPowerup.CheckArtifacts(resource)
    end

    RandomizerPowerup.ApplyTunableChanges()
    Scenario.UpdateProgressiveItemModels()
    RandomizerPowerup.IncrementInventoryIndex()
    RL.UpdateRDVClient(false)
    return granted
end

function RandomizerPowerup.DisableInput()
    -- items with unique inputs (Speed Booster, Phantom Cloak) require disabling and re-enabling inputs to work properly
    local oPlayer = Game.GetPlayer()
    if oPlayer ~= nil then
        oPlayer.INPUT:IgnoreInput(true, false, "PickupObtained")
    end
    Game.AddSF(0.1, "RandomizerPowerup.RecoverInput", "")
end
function RandomizerPowerup.RecoverInput()
    local oPlayer = Game.GetPlayer()
    if oPlayer ~= nil then
        oPlayer.INPUT:IgnoreInput(false, false, "PickupObtained")
    end
end

function RandomizerPowerup.HandlePickupResources(progression)
    progression = progression or {}

    local alwaysGrant = false

    if #progression == 0 then
        return {}
    elseif #progression == 1 then
        alwaysGrant = true
    end

    Game.LogWarn(0, "Resources:")
    for _, resource_list in ipairs(progression) do
        local data = "  - "
        for _, resource in ipairs(resource_list) do
            data = data .. resource.item_id .. " (" .. resource.quantity .. ") / "
        end
        Game.LogWarn(0, data)
    end

    -- For each progression stage, if the player does not have the FIRST item in that stage, the whole stage is granted
    for _, resource_list in ipairs(progression) do
        -- Check if we need to grant anything from this progression stage

        if #resource_list > 0 then
            local current = RandomizerPowerup.GetItemAmount(resource_list[1].item_id)
            local shouldGrant = alwaysGrant or current < resource_list[1].quantity

            if shouldGrant then
                for _, resource in ipairs(resource_list) do
                    Game.LogWarn(0, "Granting " .. resource.quantity .. " " .. resource.item_id)
                    RandomizerPowerup.IncreaseItemAmount(resource.item_id, resource.quantity)
                end

                return resource_list
            end
        end

        -- Otherwise, loop to next progression stage (or fall out of loop)
    end

    return {} -- nothing granted after final stage of progression is reached
end

function RandomizerPowerup.ChangeSuit()
    -- ordered by priority
    local suits = {
        {item = "ITEM_HYPER_SUIT", model = "Hyper"},
        {item = "ITEM_GRAVITY_SUIT", model = "Gravity"},
        {item = "ITEM_VARIA_SUIT", model = "Varia"},
    }
    local model_updater = Game.GetPlayer().MODELUPDATER
    for _, suit in ipairs(suits) do
        if suit.model == model_updater.sModelAlias then break end
        if RandomizerPowerup.HasItem(suit.item) then
            Game.AddPSF(0.1, RandomizerPowerup.Delayed_ChangeSuit, "s", suit.model)
            break
        end
    end
end

function RandomizerPowerup.Delayed_ChangeSuit(model)
    if fxcallbacks == nil then
        Game.LogWarn(0, "No fxcallbacks")
    elseif #fxcallbacks.lfxenabled > 0 then
        Game.LogWarn(0, "FX active, try again")
        Game.AddPSF(0.1, RandomizerPowerup.Delayed_ChangeSuit, "s", model)
        return
    end
    -- updating the model while VFX are active on the old model will cause a nullptr
    local model_updater = Game.GetPlayer().MODELUPDATER
    Game.LogWarn(0, "Updating suit to " .. model)
    model_updater.sModelAlias = model
end

MAX_ENERGY = 1499
function RandomizerPowerup.IncreaseEnergy(resource)
    -- No resource, quit
    if not resource then return end

    local item_id = resource.item_id

    -- Not etank or epart, quit
    if item_id ~= "ITEM_ENERGY_TANKS" and item_id ~= "ITEM_LIFE_SHARDS" then return end

    local energy = Init.fEnergyPerTank

    if item_id == "ITEM_LIFE_SHARDS" then
        local shards_amount = RandomizerPowerup.GetItemAmount(item_id)
        if Init.bImmediateEnergyParts then
            energy = Init.fEnergyPerPart
        elseif (shards_amount % 4) ~= 0 then
            -- only change energy every 4 parts if not immediate but change internal amount
            Game.GetPlayer().LIFE.fLifeShards = shards_amount
            return
        end
        -- remove all life shards as energy will be increased by following code
        RandomizerPowerup.SetItemAmount("ITEM_LIFE_SHARDS", 0)
        Game.GetPlayer().LIFE.fLifeShards = 0
    end

    Game.LogWarn(0, "Increasing player energy.")

    local new_max = RandomizerPowerup.GetItemAmount("ITEM_MAX_LIFE") + energy
    new_max = math.min(new_max, MAX_ENERGY)

    local new_current = new_max
    if item_id == "ITEM_LIFE_SHARDS" and Init.bImmediateEnergyParts then
        new_current = RandomizerPowerup.GetItemAmount("ITEM_CURRENT_LIFE") + energy
        new_current = math.min(new_current, new_max)
    end

    RandomizerPowerup.SetItemAmount("ITEM_MAX_LIFE", new_max)
    RandomizerPowerup.SetItemAmount("ITEM_CURRENT_LIFE", new_current)

    local life = Game.GetPlayer().LIFE
    life.fMaxLife = new_max
    life.fCurrentLife = new_current
end

function RandomizerPowerup.IncreaseAmmo(resource)
    if not resource then return end

    local current_id = nil

    if resource.item_id == "ITEM_WEAPON_POWER_BOMB_MAX" then
        current_id = "ITEM_WEAPON_POWER_BOMB_CURRENT"
    elseif resource.item_id == "ITEM_WEAPON_MISSILE_MAX" then
        current_id = "ITEM_WEAPON_MISSILE_CURRENT"
    end

    if current_id == nil then return end

    RandomizerPowerup.IncreaseItemAmount(current_id, resource.quantity, resource.item_id)
end

function RandomizerPowerup.CheckArtifacts(resource)
    if not resource then return end
    if Init.iNumRequiredArtifacts == 0 then return end
    if RandomizerPowerup.HasItem("ITEM_METROIDNIZATION") then return end

    if resource.item_id:find("ITEM_RANDO_ARTIFACT", 1, true) then
        GUI.AddEmmyMissionLogEntry("#MLOG_" .. resource.item_id)
    end

    -- check for all artifact items, which are numbered. if all are collected, grant metroidnization
    for i=1, Init.iNumRequiredArtifacts do
        if RandomizerPowerup.GetItemAmount("ITEM_RANDO_ARTIFACT_"..i) == 0 then return end
    end

    RandomizerPowerup.SetItemAmount("ITEM_METROIDNIZATION", 1)

    -- popup currently disabled since it causes a softlock
    --Game.AddGUISF(0.1, "RandomizerPowerup.ShowArtifactMessage", "")
end

function RandomizerPowerup.ShowArtifactMessage()
    GUI.ShowMessage("#RANDO_ARTIFACTS_ALL", true, "")
end

local tItemTunableHandlers = {
    ["ITEM_UPGRADE_FLASH_SHIFT_CHAIN"] = function(quantity)
        -- # of chains after first - vanilla is 2. We set it to the number of items, and the "default" config starts with 2 items.
        Scenario.SetTunableValue("CTunableAbilityGhostAura", "iChainDashMax", quantity)
    end,
    ["ITEM_UPGRADE_SPEED_BOOST_CHARGE"] = function(quantity)
        -- Amount of time in seconds for SB to charge - vanilla is 1.5 seconds. Each upgrade reduces by 0.25 seconds.
        local chargeTime = math.max(0.25, 1.5 - quantity * 0.25)
        Scenario.SetTunableValue("CTunableAbilitySpeedBooster", "fTimeToActivate", chargeTime)
    end
}

function RandomizerPowerup.ApplyTunableChanges()
    Game.AddSF(0, "RandomizerPowerup._ApplyTunableChanges", "")
end

function RandomizerPowerup._ApplyTunableChanges()
    for item, handler in pairs(tItemTunableHandlers) do
        local totalQuantity = RandomizerPowerup.GetItemAmount(item)

        Game.LogWarn(0, "Calling tunable handler for " .. item .. " = " .. totalQuantity)

        handler(totalQuantity)
    end
end

-- Main PBs
RandomizerPowerBomb = {}
setmetatable(RandomizerPowerBomb, {__index = RandomizerPowerup})
function RandomizerPowerBomb.OnPickedUp(actor, progression)
    progression = progression or {{{ item_id = "ITEM_WEAPON_POWER_BOMB_MAX", quantity = 0 }}}
    RandomizerPowerup.OnPickedUp(actor, progression)
end

-- Flash Shift
RandomizerFlashShift = {}
setmetatable(RandomizerFlashShift, {__index = RandomizerPowerup})
function RandomizerFlashShift.OnPickedUp(actor, progression)
    progression = progression or {{{item_id = "ITEM_UPGRADE_FLASH_SHIFT_CHAIN", quantity = 0}}}

    local hasFlashShift = RandomizerPowerup.HasItem("ITEM_GHOST_AURA")

    for _, resource_list in ipairs(progression) do
        for _, resource in ipairs(resource_list) do
            if resource.item_id == "ITEM_UPGRADE_FLASH_SHIFT_CHAIN" and hasFlashShift then
                -- Subsequent Flash Shift main items do not grant additional chains
                resource.quantity = 0
            end
        end
    end

    RandomizerPowerup.OnPickedUp(actor, progression)
end

function RandomizerPowerup.ToggleInputsOnPickedUp(actor, progression, item, SFs)
    SFs = SFs or {}
    local has_item_already = RandomizerPowerup.HasItem(item)
    RandomizerPowerup.OnPickedUp(actor, progression)
    if not has_item_already then
        RandomizerPowerup.DisableInput()
        for _, SF in ipairs(SFs) do
            Game.AddSF(SF[1], SF[2], SF[3])
        end
    end
end

RandomizerPhantomCloak = {}
setmetatable(RandomizerPhantomCloak, {__index = RandomizerPowerup})
function RandomizerPhantomCloak.OnPickedUp(actor, progression)
    RandomizerPowerup.ToggleInputsOnPickedUp(
        actor, progression, "ITEM_OPTIC_CAMOUFLAGE", {
            {0.101, "RandomizerPhantomCloak.Deactivate", ""}
        }
    )
end

function RandomizerPhantomCloak.Deactivate()
    -- prevent the pickup from trying to kill you
    Game.GetPlayer().SPECIALENERGY:Fill()
end

RandomizerSpeedBooster = {}
setmetatable(RandomizerSpeedBooster, {__index = RandomizerPowerup})
function RandomizerSpeedBooster.OnPickedUp(actor, progression)
    RandomizerPowerup.ToggleInputsOnPickedUp(
        actor, progression, "ITEM_SPEED_BOOSTER"
    )
end

RandomizerStormMissile = {}
setmetatable(RandomizerStormMissile, {__index = RandomizerPowerup})
function RandomizerStormMissile.OnPickedUp(actor, progression)
    RandomizerPowerup.ToggleInputsOnPickedUp(
        actor, progression, "ITEM_MULTILOCKON"
    )
end

RandomizerEnergyPart = {}
setmetatable(RandomizerEnergyPart, {__index = RandomizerPowerup})
function RandomizerEnergyPart.OnPickedUp(actor, progression)
    Game.LogWarn(0, "RandomizerEnergyPart " .. type(progression))
    if not Init.bImmediateEnergyParts and actor then
        name = actor.sName
        RandomizerPowerup.MarkLocationCollected(string.format("%s_%s", Scenario.CurrentScenarioID, name))
    else
        progression = progression or {{{ item_id = "ITEM_LIFE_SHARDS", quantity = 1 }}}
        RandomizerPowerup.OnPickedUp(actor, progression)
    end
end
