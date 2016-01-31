-- Libraries
local constants = require('constants')
local network = require('network')
local OptionManager = require('optionmanager')
local SkillManager = require('skillmanager')

--[[
    Main pregame, selection related handler
]]

local Pregame = class({})

-- Init pregame stuff
function Pregame:init()
    -- Set it to the loading phase
    self:setPhase(constants.PHASE_LOADING)

    -- Init thinker
    GameRules:GetGameModeEntity():SetThink('onThink', self, 'PregameThink', 0.25)
    GameRules:SetHeroSelectionTime(0)   -- Hero selection is done elsewhere, hero selection should be instant

    -- Store for options
    self.optionStore = {}

    -- Store for selected heroes and skills
    self.selectedHeroes = {}
    self.selectedSkills = {}

    -- Init options
    self:initOptionSelector()

    -- Grab a reference to self
    local this = self

    --[[
        Listen to events
    ]]

    -- Options are locked
    CustomGameEventManager:RegisterListener('lodOptionsLocked', function(eventSourceIndex, args)
        this:onOptionsLocked(eventSourceIndex, args)
    end)

    -- Host looks at a different tab
    CustomGameEventManager:RegisterListener('lodOptionsMenu', function(eventSourceIndex, args)
        this:onOptionsMenuChanged(eventSourceIndex, args)
    end)

    -- Host wants to set an option
    CustomGameEventManager:RegisterListener('lodOptionSet', function(eventSourceIndex, args)
        this:onOptionChanged(eventSourceIndex, args)
    end)

    -- Player wants to set their hero
    CustomGameEventManager:RegisterListener('lodChooseHero', function(eventSourceIndex, args)
        this:onPlayerSelectHero(eventSourceIndex, args)
    end)

    -- Player wants to change which ability is in a slot
    CustomGameEventManager:RegisterListener('lodChooseAbility', function(eventSourceIndex, args)
        this:onPlayerSelectAbility(eventSourceIndex, args)
    end)

    -- Network heroes
    self:networkHeroes()

    -- Setup default option related stuff
    network:setActiveOptionsTab('presets')
    self:setOption('lodOptionBanning', 1)
    self:setOption('lodOptionSlots', 6)
    self:setOption('lodOptionUlts', 2)
    self:setOption('lodOptionGamemode', 1)
end

-- Thinker function to handle logic
function Pregame:onThink()
    -- Grab the phase
    local ourPhase = self:getPhase()

    --[[
        LOADING PHASE
    ]]
    if ourPhase == constants.PHASE_LOADING then
        -- Are we in the custom game setup phase?
        if GameRules:State_Get() >= DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP then
            self:setPhase(constants.PHASE_OPTION_SELECTION)
        end

        -- Wait for time to pass
        return 0.1
    end

    --[[
        OPTION SELECTION PHASE
    ]]
    if ourPhase == constants.PHASE_OPTION_SELECTION then
        return 0.1
    end

    --[[
        BANNING PHASE
    ]]
    if ourPhase == constants.PHASE_BANNING then
        -- Is it over?
        if Time() >= self:getEndOfPhase() then
            -- Change to picking phase
            self:setPhase(constants.PHASE_SELECTION)
            self:setEndOfPhase(Time() + OptionManager:GetOption('pickingTime'))
        end

        return 0.1
    end

    -- Selection phase
    if ourPhase == constants.PHASE_SELECTION then
        -- Is it over?
        if Time() >= self:getEndOfPhase() then
            -- Change to picking phase
            self:setPhase(constants.PHASE_REVIEW)
            self:setEndOfPhase(Time() + OptionManager:GetOption('reviewTime'))
        end

        return 0.1
    end

    -- Review
    if ourPhase == constants.PHASE_REVIEW then
        -- Is it over?
        if Time() >= self:getEndOfPhase() then
            -- Change to picking phase
            self:setPhase(constants.PHASE_INGAME)

            -- Kill the selection screen
            GameRules:FinishCustomGameSetup()
        end

        return 0.1
    end

    -- Once we get to this point, we will not fire again

    -- Game is starting, spawn heroes
    if ourPhase == constants.PHASE_INGAME then
        self:spawnAllHeroes()
    end
end

-- Spawns all heroes (this should only be called once!)
function Pregame:spawnAllHeroes()
    local minPlayerID = 0
    local maxPlayerID = 24

    -- Loop over all playerIDs
    for playerID = minPlayerID,maxPlayerID do
        -- Is there a player in this slot?
        if PlayerResource:IsValidPlayerID(playerID) then
            -- There is, go ahead and build this player

            -- Grab their build
            local build = self.selectedSkills[playerID]

            -- Validate the player
            local player = PlayerResource:GetPlayer(playerID)
            if player ~= nil then
                local heroName = self.selectedHeroes[playerID] or self:getRandomHero()

                -- Attempt to precache their hero
                PrecacheUnitByNameAsync(heroName, function()
                    -- Create the hero and validate it
                    local hero = CreateHeroForPlayer(heroName, player)
                    if hero ~= nil and IsValidEntity(hero) then
                        SkillManager:ApplyBuild(hero, build)
                    end
                end, playerID)
            end
        end
    end
end

-- Returns a random hero [will be unique]
function Pregame:getRandomHero()
    -- Build a list of heroes that have already been taken
    local takenHeroes = {}
    for k,v in pairs(self.selectedHeroes) do
        takenHeroes[v] = true
    end

    local possibleHeroes = {}

    for k,v in pairs(self.allowedHeroes) do
        if not takenHeroes[k] then
            table.insert(possibleHeroes, k)
        end
    end

    -- If no heroes were found, just give them pudge
    -- This should never happen, but if it does, WTF mate?
    if #possibleHeroes == 0 then
        return 'npc_dota_hero_pudge'
    end

    return possibleHeroes[math.random(#possibleHeroes)]
end

-- Setup the selectable heroes
function Pregame:networkHeroes()
    local allHeroes = LoadKeyValues('scripts/npc/npc_heroes.txt')
    local flags = LoadKeyValues('scripts/kv/flags.kv')
    local oldAbList = LoadKeyValues('scripts/kv/abilities.kv')

    -- Prepare flags
    local flagsInverse = {}
    for flagName,abilityList in pairs(flags) do
        for abilityName,nothing in pairs(abilityList) do
            -- Ensure a store exists
            flagsInverse[abilityName] = flagsInverse[abilityName] or {}
            flagsInverse[abilityName][flagName] = true
        end
    end

    -- Load in the category data for abilities
    local oldSkillList = oldAbList.skills

    for tabName, tabList in pairs(oldSkillList) do
        for abilityName,uselessNumber in pairs(tabList) do
            flagsInverse[abilityName] = flagsInverse[abilityName] or {}
            flagsInverse[abilityName].category = tabName
        end
    end

    -- Push flags to clients
    for abilityName, flagData in pairs(flagsInverse) do
        network:setFlagData(abilityName, flagData)
    end

    local allowedHeroes = {}

    for heroName,heroValues in pairs(allHeroes) do
        -- Ensure it is enabled
        if heroName ~= 'Version' and heroName ~= 'npc_dota_hero_base' and heroValues.Enabled == 1 then
            -- Store all the useful information
            local theData = {
                AttributePrimary = heroValues.AttributePrimary,
                Role = heroValues.Role,
                Rolelevels = heroValues.Rolelevels,
                AttackCapabilities = heroValues.AttackCapabilities,
                AttackDamageMin = heroValues.AttackDamageMin,
                AttackDamageMax = heroValues.AttackDamageMax,
                AttackRate = heroValues.AttackRate,
                AttackRange = heroValues.AttackRange,
                MovementSpeed = heroValues.MovementSpeed,
                AttributeBaseStrength = heroValues.AttributeBaseStrength,
                AttributeStrengthGain = heroValues.AttributeStrengthGain,
                AttributeBaseIntelligence = heroValues.AttributeBaseIntelligence,
                AttributeIntelligenceGain = heroValues.AttributeIntelligenceGain,
                AttributeBaseAgility = heroValues.AttributeBaseAgility,
                AttributeAgilityGain = heroValues.AttributeAgilityGain
            }

            if heroName == 'npc_dota_hero_invoker' then
                theData.Ability1 = 'invoker_alacrity_lod'
                theData.Ability2 = 'invoker_chaos_meteor_lod'
                theData.Ability3 = 'invoker_cold_snap_lod'
                theData.Ability4 = 'invoker_emp_lod'
                theData.Ability5 = 'invoker_forge_spirit_lod'
                theData.Ability6 = 'invoker_ghost_walk_lod'
                theData.Ability7 = 'invoker_ice_wall_lod'
                theData.Ability8 = 'invoker_sun_strike_lod'
                theData.Ability9 = 'invoker_tornado_lod'
            else
                local sn = 1
                for i=1,16 do
                    local abName = heroValues['Ability' .. i]

                    if abName ~= 'attribute_bonus' then
                        theData['Ability' .. sn] = abName
                        sn = sn + 1
                    end
                end
            end

            network:setHeroData(heroName, theData)

            -- Store allowed heroes
            allowedHeroes[heroName] = true
        end
    end

    -- Store it locally
    self.allowedHeroes = allowedHeroes
end

-- Options Locked event was fired
function Pregame:onOptionsLocked(eventSourceIndex, args)
    -- Ensure we are in the options locking phase
    if self:getPhase() ~= constants.PHASE_OPTION_SELECTION then return end

    -- Grab data
    local playerID = args.PlayerID
    local player = PlayerResource:GetPlayer(playerID)

    -- Ensure they have hosting privileges
    if GameRules:PlayerHasCustomGameHostPrivileges(player) then
        -- Should verify if the teams are locked here, oh well

        -- Move onto the next phase
        if OptionManager:GetOption('banningTime') > 0 then
            -- There is banning
            self:setPhase(constants.PHASE_BANNING)
            self:setEndOfPhase(Time() + OptionManager:GetOption('banningTime'))

        else
            -- There is not banning
            self:setPhase(constants.PHASE_SELECTION)
            self:setEndOfPhase(Time() + OptionManager:GetOption('pickingTime'))

        end
    end
end

-- Options menu changed
function Pregame:onOptionsMenuChanged(eventSourceIndex, args)
    -- Ensure we are in the options locking phase
    if self:getPhase() ~= constants.PHASE_OPTION_SELECTION then return end

    -- Grab data
    local playerID = args.PlayerID
    local player = PlayerResource:GetPlayer(playerID)

    -- Ensure they have hosting privileges
    if GameRules:PlayerHasCustomGameHostPrivileges(player) then
        -- Grab and set which tab is active
        local newActiveTab = args.v
        network:setActiveOptionsTab(newActiveTab)
    end
end

-- An option was changed
function Pregame:onOptionChanged(eventSourceIndex, args)
    -- Ensure we are in the options locking phase
    if self:getPhase() ~= constants.PHASE_OPTION_SELECTION then return end

    -- Grab data
    local playerID = args.PlayerID
    local player = PlayerResource:GetPlayer(playerID)

    -- Ensure they have hosting privileges
    if GameRules:PlayerHasCustomGameHostPrivileges(player) then
        -- Grab options
        local optionName = args.k
        local optionValue = args.v

        -- TODO: Validate option name
        -- Option values are validated at a later stage

        self:setOption(optionName, optionValue)
    end
end

-- init option validator
function Pregame:initOptionSelector()
    -- Option validator can only init once
    if self.doneInitOptions then return end
    self.doneInitOptions = true

    self.validOptions = {
        -- Fast gamemode selection
        lodOptionGamemode = function(value)
            -- Ensure it is a number
            if type(value) ~= 'number' then return false end

            local validGamemodes = {
                [-1] = true,
                [1] = true,
                [2] = true,
                [3] = true,
                [4] = true
            }

            -- Ensure it is one of the above gamemodes
            if not validGamemodes[value] then return false end

            -- It must be valid
            return true
        end,

        -- Fast banning selection
        lodOptionBanning = function(value)
            return value == 1 or value == 2
        end,

        -- Fast slots selection
        lodOptionSlots = function(value)
            return value == 4 or value == 5 or value == 6
        end,

        -- Fast ult selection
        lodOptionUlts = function(value)
            local valid = {
                [0] = true,
                [1] = true,
                [2] = true,
                [3] = true,
                [4] = true,
                [5] = true,
                [6] = true
            }

            return valid[value] or false
        end,

        -- Common gamemode
        lodOptionCommonGamemode = function(value)
            -- Ensure gamemode is set to custom
            if self.optionStore['lodOptionGamemode'] ~= -1 then return false end

            return value == 1 or value == 2 or value == 3 or value == 4
        end,

        -- Common max slots
        lodOptionCommonMaxSlots = function(value)
            -- Ensure gamemode is set to custom
            if self.optionStore['lodOptionGamemode'] ~= -1 then return false end

            return value == 4 or value == 5 or value == 6
        end,

        -- Common max skills
        lodOptionCommonMaxSkills = function(value)
            -- Ensure gamemode is set to custom
            if self.optionStore['lodOptionGamemode'] ~= -1 then return false end

            local valid = {
                [0] = true,
                [1] = true,
                [2] = true,
                [3] = true,
                [4] = true,
                [5] = true,
                [6] = true
            }

            return valid[value] or false
        end,

        -- Common max ults
        lodOptionCommonMaxUlts = function(value)
            -- Ensure gamemode is set to custom
            if self.optionStore['lodOptionGamemode'] ~= -1 then return false end

            local valid = {
                [0] = true,
                [1] = true,
                [2] = true,
                [3] = true,
                [4] = true,
                [5] = true,
                [6] = true
            }

            return valid[value] or false
        end,

        -- Common max bans
        lodOptionBanningMaxBans = function(value)
            -- Ensure gamemode is set to custom
            if self.optionStore['lodOptionGamemode'] ~= -1 then return false end

            local valid = {
                [0] = true,
                [1] = true,
                [2] = true,
                [3] = true,
                [5] = true,
                [10] = true,
                [25] = true
            }

            return valid[value] or false
        end,

        -- Common block troll combos
        lodOptionBanningBlockTrollCombos = function(value)
            -- Ensure gamemode is set to custom
            if self.optionStore['lodOptionGamemode'] ~= -1 then return false end

            return value == 0 or value == 1
        end,

        -- Common use ban list
        lodOptionBanningUseBanList = function(value)
            -- Ensure gamemode is set to custom
            if self.optionStore['lodOptionGamemode'] ~= -1 then return false end

            return value == 0 or value == 1
        end,

        -- Common ban all invis
        lodOptionBanningBanInvis = function(value)
            -- Ensure gamemode is set to custom
            if self.optionStore['lodOptionGamemode'] ~= -1 then return false end

            return value == 0 or value == 1
        end,

        -- Game Speed -- Starting Level
        lodOptionGameSpeedStartingLevel = function(value)
            -- Ensure gamemode is set to custom
            if self.optionStore['lodOptionGamemode'] ~= -1 then return false end

            local valid = {
                [1] = true,
                [6] = true,
                [11] = true,
                [16] = true,
                [25] = true,
                [50] = true,
                [75] = true,
                [100] = true
            }

            return valid[value] or false
        end,

        -- Game Speed -- Max Level
        lodOptionGameSpeedMaxLevel = function(value)
            -- Ensure gamemode is set to custom
            if self.optionStore['lodOptionGamemode'] ~= -1 then return false end

            local valid = {
                [6] = true,
                [11] = true,
                [16] = true,
                [25] = true,
                [50] = true,
                [75] = true,
                [100] = true
            }

            return valid[value] or false
        end,

        -- Game Speed -- Starting Gold
        lodOptionGameSpeedStartingGold = function(value)
            -- Ensure gamemode is set to custom
            if self.optionStore['lodOptionGamemode'] ~= -1 then return false end

            local valid = {
                [0] = true,
                [250] = true,
                [500] = true,
                [1000] = true,
                [2500] = true,
                [5000] = true,
                [10000] = true,
                [25000] = true,
                [50000] = true,
                [100000] = true
            }

            return valid[value] or false
        end
    }

    -- Callbacks
    self.onOptionsChanged = {
        -- Fast Gamemode
        lodOptionGamemode = function(optionName, optionValue)
            -- If we are using a hard coded gamemode, then, set all options automatically
            if optionValue ~= -1 then
                -- Gamemode is copied
                self:setOption('lodOptionCommonGamemode', optionValue, true)

                -- Total slots is copied
                self:setOption('lodOptionCommonMaxSlots', self.optionStore['lodOptionSlots'], true)

                -- Max skills is always 6
                self:setOption('lodOptionCommonMaxSkills', 6, true)

                -- Max ults is copied
                self:setOption('lodOptionCommonMaxUlts', self.optionStore['lodOptionUlts'], true)

                -- Banning mode depends on the option, but is baically copied
                if self.optionStore['lodOptionBanning'] == 1 then
                    self:setOption('lodOptionBanningMaxBans', 0, true)
                    self:setOption('lodOptionBanningUseBanList', 1, true)
                else
                    self:setOption('lodOptionBanningMaxBans', self.fastBansTotalBans, true)
                    self:setOption('lodOptionBanningUseBanList', 0, true)
                end

                -- Block troll combos is always on
                self:setOption('lodOptionBanningBlockTrollCombos', 1, true)

                -- Default, we don't ban all invisiblity
                self:setOption('lodOptionBanningBanInvis', 0, true)

                -- Starting level is lvl 1
                self:setOption('lodOptionGameSpeedStartingLevel', 1, true)

                -- Max level is 25
                self:setOption('lodOptionGameSpeedMaxLevel', 25, true)

                -- No bonus starting gold
                self:setOption('lodOptionGameSpeedStartingGold', 0, true)
            end
        end,

        -- Fast Banning
        lodOptionBanning = function(optionName, optionValue)
            if self.optionStore['lodOptionBanning'] == 1 then
                self:setOption('lodOptionBanningMaxBans', 0, true)
                self:setOption('lodOptionBanningUseBanList', 1, true)
            else
                self:setOption('lodOptionBanningMaxBans', self.fastBansTotalBans, true)
                self:setOption('lodOptionBanningUseBanList', 0, true)
            end
        end,

        -- Fast max slots
        lodOptionSlots = function(optionName, optionValue)
            -- Copy max slots in
            self:setOption('lodOptionCommonMaxSlots', self.optionStore['lodOptionSlots'], true)
        end,

        -- Fast max ults
        lodOptionUlts = function(optionName, optionValue)
            self:setOption('lodOptionCommonMaxUlts', self.optionStore['lodOptionUlts'], true)
        end
    }

    -- Some default values
    self.fastBansTotalBans = 3
end

-- Validates, and then sets an option
function Pregame:setOption(optionName, optionValue, force)
    -- option validator

    if not self.validOptions[optionName] then
        -- TODO: Tell the user they tried to modify an invalid option
        return
    end

    if not force and not self.validOptions[optionName](optionValue) then
        -- TODO: Tell the user they gave an invalid value
        return
    end

    -- Set the option
    self.optionStore[optionName] = optionValue
    network:setOption(optionName, optionValue)

    -- Check for option changing callbacks
    if self.onOptionsChanged[optionName] then
        self.onOptionsChanged[optionName](optionName, optionValue)
    end
end

-- Player wants to select a hero
function Pregame:onPlayerSelectHero(eventSourceIndex, args)
    -- Ensure we are in the picking phase
    --if self:getPhase() ~= constants.PHASE_SELECTION then return end

    -- Grab data
    local playerID = args.PlayerID
    local player = PlayerResource:GetPlayer(playerID)

    local heroName = args.heroName

    -- Validate hero
    if not self.allowedHeroes[heroName] then
        print('Failed to find hero!')

        -- TODO: Show some kind of error
        return
    end

    -- Is there an actual change?
    if self.selectedHeroes[playerID] ~= heroName then
        -- Update local store
        self.selectedHeroes[playerID] = heroName

        -- Update the selected hero
        network:setSelectedHero(playerID, heroName)
    end
end

-- Player wants to select a new ability
function Pregame:onPlayerSelectAbility(eventSourceIndex, args)
    -- Ensure we are in the picking phase
    --if self:getPhase() ~= constants.PHASE_SELECTION then return end

    -- Grab data
    local playerID = args.PlayerID
    local player = PlayerResource:GetPlayer(playerID)

    local slot = args.slot
    local abilityName = args.abilityName

    -- TODO: Validate the slot is a valid slot index

    -- TODO: Validate ability is an actual ability

    -- TODO: Validate the ability isn't already banned

    -- TODO: Validate that the ability is allowed in this slot (ulty count)

    -- TODO: Validate that it isn't a troll build

    -- Ensure a container for this player exists
    self.selectedSkills[playerID] = self.selectedSkills[playerID] or {}

    -- Is there an actual change?
    if self.selectedSkills[playerID][slot] ~= abilityName then
        -- New ability in this slot
        self.selectedSkills[playerID][slot] = abilityName

        -- Network it
        network:setSelectedAbilities(playerID, self.selectedSkills[playerID])
    end
end

-- Sets the stage
function Pregame:setPhase(newPhaseNumber)
    -- Store the current phase
    self.currentPhase = newPhaseNumber

    -- Update the phase for the clients
    network:setPhase(newPhaseNumber)
end

-- Sets when the next phase is going to end
function Pregame:setEndOfPhase(endTime)
    -- Store the time
    self.endOfTimer = endTime

    -- Network it
    network:setEndOfPhase(endTime)
end

-- Returns when the current phase should end
function Pregame:getEndOfPhase()
    return self.endOfTimer
end

-- Returns the current phase
function Pregame:getPhase()
    return self.currentPhase
end

-- Return an instance of it
return Pregame()
