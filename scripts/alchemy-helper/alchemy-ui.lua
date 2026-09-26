-- Alchemist's Almanac — Alchemy Effects UI Panel
-- Self-contained UI module for displaying ingredient/potion effects.
-- Runs in PLAYER context as a standalone overlay.
--
-- Public API:  create(), show(), hide(), destroy(), update(id)
-- All UI built with openmw.ui primitives and openmw_aux.ui utilities.
-- No MWUI XML templates. No keybind wiring. No save/load. No menu detection.

local core = require('openmw.core')
local interfaces = require('openmw.interfaces')
local ui = require('openmw.ui')

local db = require('scripts.alchemy-helper.shared.db')

-- ---------------------------------------------------------------------------
-- Configuration — plain Lua table, no metatables, no classes.
-- Modders copy/paste/edit this table directly.
-- ---------------------------------------------------------------------------
local CONFIG = {
    positioning = {
        -- Screen corner to anchor the panel to.
        -- Valid values: "top-left", "top-right", "bottom-left", "bottom-right".
        -- Defaults to "bottom-right".
        corner = "bottom-right",
        -- Pixel offset inward from the selected corner.
        offsetX = 50,
        offsetY = 50,
    },
    theme = {
        -- Color overrides (number or nil). nil = leave buildPanelLayout default.
        -- Values are packed ARGB integers (e.g. 0xFF123456).
        backgroundColor = nil,
        borderColor = nil,
        titleColor = nil,
        textColor = nil,
        buttonColor = nil,
        -- Font sizes (number).
        fontSizeTitle = 16,
        fontSizeBody = 12,
        -- Spacing (number).
        padding = 5,
        margin = 2,
        -- Visual toggle.
        border = true,
    },
}

-- Resolve screen dimensions from openmw.core or use a reasonable default.
local function getScreenSize()
    local width = 1920
    local height = 1080
    local s = core.screen
    if type(s) == 'table' and s.width and s.height then
        width = s.width
        height = s.height
    end
    return width, height
end

-- Map a corner string to (x, y) placement for a panel of given dimensions.
-- Unrecognized corners fall back to "bottom-right".
local function calcPosition(corner, panelWidth, panelHeight, ox, oy)
    local w, h = getScreenSize()
    local dx = ox or 50
    local dy = oy or 50

    if type(corner) ~= 'string' or corner ~= 'top-left' and corner ~= 'top-right' and corner ~= 'bottom-left' and corner ~= 'bottom-right' then
        return { x = w - panelWidth - dx, y = h - panelHeight - dy }
    end

    if corner == 'top-left' then
        return { x = dx, y = dy }
    elseif corner == 'top-right' then
        return { x = w - panelWidth - dx, y = dy }
    elseif corner == 'bottom-left' then
        return { x = dx, y = h - panelHeight - dy }
    else
        return { x = w - panelWidth - dx, y = h - panelHeight - dy }
    end
end

-- Merge CONFIG into a layout table returned by buildPanelLayout().
-- Modifies props in-place (with nil-safety for theme values).
-- Returns the layout for convenience.
local function applyConfigToLayout(layout, config)
    local pos = config and config.positioning
    local theme = config and config.theme

    if pos then
        local pw = layout.props and layout.props.width or 400
        local ph = layout.props and layout.props.height or 500
        local valid = pos.corner == 'bottom-right' or pos.corner == 'bottom-left' or pos.corner == 'top-right' or pos.corner == 'top-left'
        local px = valid and calcPosition(pos.corner, pw, ph, pos.offsetX, pos.offsetY) or calcPosition('bottom-right', pw, ph, 50, 50)
        layout.props.x = px.x
        layout.props.y = px.y
    end

    if theme then
        if theme.fontSizeTitle ~= nil then layout.props.fontSizeTitle = theme.fontSizeTitle end
        if theme.fontSizeBody ~= nil then layout.props.fontSize = theme.fontSizeBody end
        if theme.padding ~= nil then layout.props.padding = theme.padding end
        if theme.margin ~= nil then layout.props.margin = theme.margin end
        if theme.backgroundColor ~= nil then layout.props.backgroundColor = theme.backgroundColor end
        if theme.borderColor ~= nil then layout.props.borderColor = theme.borderColor end
        if theme.titleColor ~= nil then layout.props.titleColor = theme.titleColor end
        if theme.textColor ~= nil then layout.props.textColor = theme.textColor end
        if theme.buttonColor ~= nil then layout.props.buttonColor = theme.buttonColor end
        if theme.border ~= nil then layout.props.border = theme.border end
    end

    return layout
end

-- ---------------------------------------------------------------------------
-- Module state — plain table, no custom metatables.
-- ---------------------------------------------------------------------------
local AlchemyUI = {}

local panelState = {
    panel = nil,
    contentPanel = nil,
    visible = false,
    currentId = nil,
}

-- ---------------------------------------------------------------------------
-- UI Construction — TODO stubs where exact openmw.ui / openmw_aux.ui signatures
-- are not documented.  Replace stub calls with real API once OpenMW API is
-- confirmed.
-- ---------------------------------------------------------------------------

-- Build the panel layout table for ui.create().
local function buildPanelLayout()
    -- TODO: confirm exact ui.create signature and TYPE constants
    -- Expected structure: { type = ui.TYPE.Window, props = { ... }, content = { ... } }
    return {
        type = ui.TYPE and ui.TYPE.Window or 'Window',
        props = {
            x = 100,
            y = 100,
            width = 400,
            height = 500,
            -- TODO: confirm if titlebar is a prop or requires a separate widget
        },
        content = {
            type = ui.TYPE and ui.TYPE.VerticalLayout or 'VerticalLayout',
            props = {
                padding = 5,
            },
            content = {
                -- Title bar row
                {
                    type = ui.TYPE and ui.TYPE.HorizontalLayout or 'HorizontalLayout',
                    props = {
                        padding = 5,
                    },
                    content = {
                        -- Title label
                        {
                            type = ui.TYPE and ui.TYPE.Label or 'Label',
                            props = {
                                text = 'Alchemy Effects',
                                fontSize = 16,
                            },
                        },
                        -- Spacer
                        {
                            type = ui.TYPE and ui.TYPE.Spacer or 'Spacer',
                            props = {
                                expand = true,
                            },
                        },
                        -- Close button (btnClose)
                        {
                            type = ui.TYPE and ui.TYPE.Button or 'Button',
                            props = {
                                text = '\x2716',  -- close symbol
                                width = 30,
                            },
                            events = {
                                onClick = function()
                                    AlchemyUI.hide()
                                end,
                            },
                        },
                    },
                },
                -- Scrollable content area
                {
                    type = ui.TYPE and ui.TYPE.ScrollArea or 'ScrollArea',
                    props = {
                        expand = true,
                    },
                    content = {
                        -- Content container for effect detail blocks
                        {
                            type = ui.TYPE and ui.TYPE.VerticalLayout or 'VerticalLayout',
                            props = {
                                padding = 5,
                            },
                            content = {}, -- populated by populateEffects()
                        },
                    },
                },
            },
        },
    }
end

-- Create (or reuse) the main panel widget via ui.
-- Sets panelState.panel and panelState.contentPanel.
local function createPanel()
    if panelState.panel then
        return panelState.panel
    end
    -- TODO: confirm the exact ui.create() call and return value
    -- openmw_aux.ui may provide helper: openmw_aux.ui.createWindow(...)
    local layout = applyConfigToLayout(buildPanelLayout(), CONFIG)
    local panel = ui.create and ui.create(layout)
    -- Fallback stub if ui.create is not available:
    -- panel = openmw_aux.ui.createWindow and openmw_aux.ui.createWindow('AlchemyEffects')
    if not panel then
        panel = { _stub = true }
    end
    panelState.panel = panel
    -- Grab reference to the inner content VerticalLayout.
    -- Layout: window -> VLayout -> [titleRow, scrollArea]
    local scrollArea = layout.content and layout.content[2]
    local scrollInner = scrollArea and scrollArea.content
    local contentContainer = scrollInner and scrollInner.content
    if contentContainer then
        panelState.contentPanel = contentContainer[1]  -- inner VerticalLayout
    end
    return panel
end

-- Populate the scrollable content area with effect detail blocks.
-- Each effect gets its own block showing name, ingredients, pairs, triples.
local function populateEffects(panel, contentArea, effects)
    -- contentArea is the VerticalLayout inside the ScrollArea.
    -- TODO: confirm how to reference nested layout from the created panel.

    -- Clear existing content
    if contentArea and contentArea.content then
        contentArea.content = {}
    end

    if not effects or #effects == 0 then
        -- TODO: add a "no effects" label via ui.TYPE.Label
        return
    end

    for _, effData in ipairs(effects) do
        local effId = effData.effId
        local effName = effData.effName or effId

        -- Build a detail block for this effect
        local block = {
            type = ui.TYPE and ui.TYPE.VerticalLayout or 'VerticalLayout',
            props = {
                padding = 5,
                margin = 2,
            },
            content = {
                -- Effect name header
                {
                    type = ui.TYPE and ui.TYPE.Label or 'Label',
                    props = {
                        text = effName or effId,
                        fontSize = 14,
                        bold = true,
                    },
                },
                -- Matching ingredients list
                {
                    type = ui.TYPE and ui.TYPE.Label or 'Label',
                    props = {
                        text = 'Ingredients: ' .. (effData.ingredients and table.concat(effData.ingredients, ', ') or '—'),
                        fontSize = 11,
                    },
                },
                -- Shared ingredient note
                {
                    type = ui.TYPE and ui.TYPE.Label or 'Label',
                    props = {
                        text = 'Shared ingredient: ' .. (effData.sharedIngredient or '—'),
                        fontSize = 11,
                    },
                },
                -- Pair usage info
                {
                    type = ui.TYPE and ui.TYPE.Label or 'Label',
                    props = {
                        text = 'Pairs: ' .. (effData.pairs and #effData.pairs > 0
                            and table.concat(effData.pairs, ', ')
                            or '—'),
                        fontSize = 11,
                    },
                },
                -- Triple usage info
                {
                    type = ui.TYPE and ui.TYPE.Label or 'Label',
                    props = {
                        text = 'Triples: ' .. (effData.triples and #effData.triples > 0
                            and table.concat(effData.triples, ', ')
                            or '—'),
                        fontSize = 11,
                    },
                },
                -- Recipe links
                {
                    type = ui.TYPE and ui.TYPE.Label or 'Label',
                    props = {
                        text = 'Recipes: ' .. (effData.recipes and #effData.recipes > 0
                            and table.concat(effData.recipes, ', ')
                            or '—'),
                        fontSize = 11,
                    },
                },
                -- Separator line
                {
                    type = ui.TYPE and ui.TYPE.Separator or 'Separator',
                    props = {},
                },
            },
        }
        contentArea.content[#contentArea.content + 1] = block
    end
end

-- ---------------------------------------------------------------------------
-- ID Resolution — maps a single string ID to effect ID(s).
-- ---------------------------------------------------------------------------

-- Resolve an ingredient ID to a list of effect IDs using init.lua lookup tables.
local function resolveIngredientEffects(ingredientId)
    local effList = db.ingredientEffects[ingredientId]
    if not effList then
        return {}
    end
    local result = {}
    for _, entry in ipairs(effList) do
        -- entry format: { effId, [minMagMult, maxMagMult] }
        result[#result + 1] = entry[1]
    end
    return result
end


-- Resolve a single string ID to effect IDs.
-- Ingredient IDs come from init.lua lookup tables.
-- Potion IDs are resolved via the game's record system (types.Potion.record).
local function resolveIdToEffectIds(id)
    if not id or type(id) ~= 'string' or id == '' then
        return {}
    end

    -- Try ingredient lookup first (from init.lua tables).
    if db.ingredientEffects[id] then
        return resolveIngredientEffects(id)
    end
    -- ID not recognized as ingredient or potion.
    return {}
end

-- ---------------------------------------------------------------------------
-- Query Effects — calls interfaces.AlchemyHelper.queryEffects(effectIds).
-- ---------------------------------------------------------------------------

local function queryAndFormatEffects(effectIds)
    if #effectIds == 0 then
        return {}
    end

    -- Call the established interface.
    local rawResults = interfaces.AlchemyHelper and interfaces.AlchemyHelper.queryEffects(effectIds)
    if not rawResults then
        return {}
    end

    -- Transform queryResults into a flat list for rendering.
    local result = {}
    for effId, data in pairs(rawResults) do
        result[#result + 1] = {
            effId = effId,
            effName = data.effName or effId,
            ingredients = data.ingredients or {},
            sharedIngredient = data.sharedIngredient,
            pairs = data.pairs or {},
            triples = data.triples or {},
            recipes = data.recipes or {},
        }
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Create the panel if it does not exist yet.
--- Repeated calls return the existing panel instance.
function AlchemyUI.create()
    if panelState.panel then
        return panelState.panel
    end
    return createPanel()
end

--- Show the panel.  If not yet created, creates it first.
--- If already visible, reuses the existing instance (no-op).
function AlchemyUI.show()
    if panelState.visible then
        return
    end
    if not panelState.panel then
        AlchemyUI.create()
    end
    -- TODO: ui.show(panel) or equivalent
    -- panel = ui.show and ui.show(panelState.panel)
    -- panel = openmw_aux.ui.show and openmw_aux.ui.show(panel)
    panelState.visible = true
end

--- Hide the panel.  Does not destroy it.
function AlchemyUI.hide()
    if not panelState.visible then
        return
    end
    -- TODO: ui.hide(panel) or equivalent
    -- ui.hide and ui.hide(panelState.panel)
    -- openmw_aux.ui.hide and openmw_aux.ui.hide(panelState.panel)
    panelState.visible = false
end

--- Destroy the panel and free all resources.
--  After destroy, a new call to show() or update() recreates it.
function AlchemyUI.destroy()
    if not panelState.panel then
        return
    end
    -- TODO: ui.destroy(panel) or equivalent
    -- ui.destroy and ui.destroy(panelState.panel)
    -- openmw_aux.ui.destroy and openmw_aux.ui.destroy(panelState.panel)
    panelState.panel = nil
    panelState.visible = false
    panelState.currentId = nil
end

--- Update the panel content for a given ID.
--- Accepts a single string ID (ingredient or potion).
--- Resolves it to effect IDs, queries via interfaces.AlchemyHelper.queryEffects,
--- and renders each effect as a detail block in the scrollable list.
--  Creates the panel if needed, populates content, and shows it.
function AlchemyUI.update(id)
    if not id or type(id) ~= 'string' then
        return
    end
    panelState.currentId = id

    -- Ensure panel exists (creates and sets contentPanel reference).
    AlchemyUI.create()

    -- Resolve ID to effect IDs.
    local effectIds = resolveIdToEffectIds(id)

    if #effectIds == 0 then
        -- No effects found — clear content and show.
        if panelState.contentPanel then
            panelState.contentPanel.content = {}
        end
        if not panelState.visible then
            AlchemyUI.show()
        end
        return
    end

    -- Query effects via the established interface.
    local formattedEffects = queryAndFormatEffects(effectIds)

    -- Populate content.
    -- TODO: openmw_aux.ui.refresh or ui.update to repaint contentPanel
    if panelState.contentPanel then
        populateEffects(panelState.panel, panelState.contentPanel, formattedEffects)
    end

    -- Show panel if not already visible.
    if not panelState.visible then
        AlchemyUI.show()
    end
end

-- ---------------------------------------------------------------------------
-- Module return — AlchemyUI is the module table itself.
-- ---------------------------------------------------------------------------
return AlchemyUI
