
local M = {}

M.ingredientEffects = {}
M.effectIngredients = {}
M.discoveredIngredients = {}

--- Discover a single ingredient ID.
--- Deduplicates (checks discoveredMap), inserts if new.
function M.discoverIngredient(ingredientId)
    if not ingredientId or type(ingredientId) ~= 'string' or ingredientId == '' then
        return
    end
    if M.discoveredIngredients[ingredientId] then
        return
    end
    M.discoveredIngredients[ingredientId] = true
end


return M