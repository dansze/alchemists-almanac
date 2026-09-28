-- Alchemist's Almanac — Alchemy Effect Database (LOAD context)
--
-- Runs once during content load. Scans `content.ingredients.records` and
-- stores the complete effect lookup database in the openmw.storage global
-- section `AlchemyHelperIndex` (GameSession lifetime) via
-- `scripts.alchemy-helper.shared.db`. The `AlchemyHelper` interface
-- (queryByEffect / querySharedWith / queryEffects / getDiscovered) is
-- exposed by init.lua over that storage.
--
-- Database is fully rebuilt from scratch on every LOAD event, so the
-- GameSession lifetime matches its real validity.
--
-- Constraints: Lua 5.1 sandbox only. No `openmw.world.*` calls
-- (world not initialized in LOAD). No prohibited ops.

local content = require('openmw.content')
local db = require('scripts.alchemy-helper.shared.db')

local function logError(msg)
    if type(print) == 'function' then
        print('[AlchemyHelper] ' .. tostring(msg))
    end
end

local function loadDB()

    -- Built locally, then stored whole; storage sections are the only
    -- cross-context shared state (each script context has its own Lua state).
    local ingredientEffects = {}

    local success, err = pcall(function()
        for _, ing in ipairs(content.ingredients.records) do
            if ing and ing.id and ing.id ~= '' then
                local effList = {}
                if ing.effects then
                    for _, eff in ipairs(ing.effects) do
                        local effId = eff and eff.id
                        if effId and effId ~= '' then
                            -- Compound key "effId~attribute~skill"; the '~'
                            -- separator lets callers recover the bare effect ID.
                            local entry = effId
                            if eff.affectedAttribute then
                                entry = entry .. '~' .. eff.affectedAttribute
                            end
                            if eff.affectedSkill then
                                entry = entry .. '~' .. eff.affectedSkill
                            end
                            effList[#effList + 1] = entry
                        end
                    end
                end
                ingredientEffects[ing.id] = effList
            end
        end
    end)
    if not success and type(logError) == 'function' then logError('ingredientEffects build: ' .. tostring(err)) end

    local success, err = pcall(db.storeIndexes, ingredientEffects)
    if not success and type(logError) == 'function' then logError('index store: ' .. tostring(err)) end

end

return {
    engineHandlers = {
        onContentFilesLoaded = loadDB
    }
}
