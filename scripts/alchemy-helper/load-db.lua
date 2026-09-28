-- Alchemist's Almanac — Alchemy Effect Database + Settings Registration (LOAD context)
--
-- Runs once during content load. Builds the complete effect lookup database
-- in `scripts.alchemy-helper.shared.db`. The `AlchemyHelper` interface
-- (queryByEffect / querySharedWith / queryEffects / getDiscovered) is
-- exposed by init.lua over this shared database.
--
-- Also registers the Settings page / group / keybind field so users can
-- view and change the alchemy-helper keybind in-game.  Settings
-- persistence is handled by `openmw.interfaces.Settings` — no custom
-- config files or ad-hoc storage.
--
-- All tables live at module scope. `queryEffects` is a live closure over them
-- — nothing is serialized. Database is fully rebuilt from scratch on every
-- LOAD event.
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
                db.ingredientEffects[ing.id] = effList
            end
        end
    end)
    if not success and type(logError) == 'function' then logError('ingredientEffects build: ' .. tostring(err)) end

    local success, err = pcall(db.rebuildIndexes)
    if not success and type(logError) == 'function' then logError('effect index build: ' .. tostring(err)) end

end

return {
    engineHandlers = {
        onContentFilesLoaded = loadDB
    }
}
