-- Alchemist's Almanac — Alchemy Effects UI Panel
-- Self-contained UI module for displaying ingredient/potion effects.
-- Runs in PLAYER context as a standalone overlay.
--
-- Public API:  create(), show(), hide(), destroy(), update(id)
-- All UI built with openmw.ui.TYPE (Flex, Text, Container, Window, Widget).
-- No MWUI XML templates. No keybind wiring. No save/load. No menu detection.

local ui = require('openmw.ui')
local interfaces = require('openmw.interfaces')
local async = require('openmw.async')
local util = require('openmw.util')

local db = require('scripts.alchemy-helper.shared.db')

local function v2(x, y)
    return util.vector2(x or 0, y or 0)
end

-- ---------------------------------------------------------------------------
-- Configuration — plain Lua table.
-- Modders copy/paste/edit this table directly.
-- ---------------------------------------------------------------------------
local CONFIG = {
    positioning = {
        corner = "bottom-right",
        offsetX = 50,
        offsetY = 50,
    },
    theme = {
        backgroundColor = nil,
        borderColor = nil,
        titleColor = nil,
        textColor = nil,
        buttonColor = nil,
        fontSizeTitle = 16,
        fontSizeBody = 12,
        border = true,
    },
}

-- Map a corner string to (x, y) placement for a panel of given dimensions.
local function calcPosition(corner, panelWidth, panelHeight, ox, oy)
    local sz = ui.screenSize()
    local w = sz and sz.x or 1920
    local h = sz and sz.y or 1080
    local dx = ox or 50
    local dy = oy or 50

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

local function textProp(txt, sz)
    return {
        text = txt,
        textSize = sz or 12,
        autoSize = false,
    }
end

local function flexProp()
    return {
        horizontal = false,
        autoSize = false,
        align = ui.ALIGNMENT.Start,
        arrange = ui.ALIGNMENT.Start,
        size = v2(0, 0),
    }
end

local function fixedSize()
    return { size = v2(0, 0) }
end

-- Merge CONFIG into a layout table.  Modifies in-place.
local function applyConfigToLayout(layout, config)
    local pos = config and config.positioning
    local theme = config and config.theme

    if pos then
        local pw = (layout.props and layout.props.size and layout.props.size.x) or 400
        local ph = (layout.props and layout.props.size and layout.props.size.y) or 500
        local valid = pos.corner == 'bottom-right' or pos.corner == 'bottom-left'
            or pos.corner == 'top-right' or pos.corner == 'top-left'
        local px = valid
            and calcPosition(pos.corner, pw, ph, pos.offsetX, pos.offsetY)
            or calcPosition('bottom-right', pw, ph, 50, 50)
        layout.props.position = v2(px.x, px.y)
    end

    return layout
end

-- ---------------------------------------------------------------------------
-- Module state
-- ---------------------------------------------------------------------------
local AlchemyUI = {}

-- Close button callback userdata.
local closeCallback = async:callback(function()
    AlchemyUI.hide()
end)

local panelState = {
    panel = nil,
    contentPanel = nil,
    visible = false,
    currentId = nil,
}

-- ---------------------------------------------------------------------------
-- UI Construction — all types use ui.TYPE values.
-- ---------------------------------------------------------------------------

-- Build the root panel layout table.
local function buildPanelLayout()
    return {
        type = ui.TYPE.Window,
        props = {
            size = v2(400, 500),
        },
        content = ui.content {
            -- Outer vertical Flex
            {
                type = ui.TYPE.Flex,
                props = flexProp(),
                content = ui.content {
                    -- Title bar row (horizontal Flex)
                    {
                        type = ui.TYPE.Flex,
                        props = flexProp(),
                        content = ui.content {
                            {
                                type = ui.TYPE.Text,
                                props = textProp('Alchemy Effects', 16),
                            },
                            {
                                type = ui.TYPE.Flex,
                                external = { grow = 1 },
                                props = fixedSize(),
                            },
                            -- Close button (Flex with mouseClick event + Text child)
                            {
                                type = ui.TYPE.Flex,
                                props = {
                                    horizontal = false,
                                    autoSize = true,
                                    align = ui.ALIGNMENT.Center,
                                    size = v2(30, 30),
                                },
                                events = {
                                    mouseClick = closeCallback,
                                },
                                content = ui.content {
                                    {
                                        type = ui.TYPE.Text,
                                        props = textProp('✖', 14),
                                    },
                                },
                            },
                        },
                    },
                    -- Scrollable content area (Container with fixed size,
                    -- inner Flex that overflows)
                    {
                        type = ui.TYPE.Container,
                        name = 'scrollArea',
                        props = {
                            relativeSize = v2(1, 0),  -- fill remaining height
                            size = v2(0, 0),
                        },
                        content = ui.content {
                            -- Inner vertical Flex (populated by populateEffects)
                            {
                                type = ui.TYPE.Flex,
                                name = 'contentContainer',
                                props = flexProp(),
                                content = ui.content {
                                    {
                                        type = ui.TYPE.Flex,
                                        props = fixedSize(),
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- Create (or reuse) the panel.  Sets panelState references.
local function createPanel()
    if panelState.panel then
        return panelState.panel
    end

    local layout = applyConfigToLayout(buildPanelLayout(), CONFIG)
    local panel = ui.create(layout)

    if not panel then
        return nil
    end

    panelState.panel = panel

    -- Walk layout by index to find inner content Flex.
    -- Structure: Window -> VFlex -> [titleRow, scrollContainer]
    local outerFlex = layout.content and layout.content[1]
    if outerFlex then
        local scrollContainer = outerFlex.content and outerFlex.content[2]
        if scrollContainer then
            local innerContainer = scrollContainer.content and scrollContainer.content[1]
            if innerContainer then
                panelState.contentPanel = innerContainer
            end
        end
    end

    return panel
end

-- Populate the scrollable content area with effect blocks.
local function populateEffects(contentArea, effects)
    if not contentArea or not contentArea.content then
        return
    end

    -- Clear: replace content with a single spacer.
    contentArea.content = ui.content {
        {
            type = ui.TYPE.Flex,
            props = fixedSize(),
        },
    }

    if not effects or #effects == 0 then
        return
    end

    for _, effData in ipairs(effects) do
        local block = {
            type = ui.TYPE.Flex,
            props = {
                horizontal = false,
                autoSize = false,
                align = ui.ALIGNMENT.Start,
                size = v2(0, 0),
            },
            content = ui.content {
                -- Effect name
                {
                    type = ui.TYPE.Text,
                    props = {
                        text = effData.effName or effData.effId or '',
                        textSize = 14,
                    },
                },
                -- Ingredients
                {
                    type = ui.TYPE.Text,
                    props = textProp(
                        'Ingredients: ' .. (effData.ingredients and table.concat(effData.ingredients, ', ') or '—'),
                        11),
                },
                -- Shared ingredient
                {
                    type = ui.TYPE.Text,
                    props = textProp(
                        'Shared ingredient: ' .. (effData.sharedIngredient or '—'),
                        11),
                },
                -- Pairs
                {
                    type = ui.TYPE.Text,
                    props = textProp(
                        'Pairs: ' .. (effData.pairs and #effData.pairs > 0
                            and table.concat(effData.pairs, ', ')
                            or '—'),
                        11),
                },
                -- Triples
                {
                    type = ui.TYPE.Text,
                    props = textProp(
                        'Triples: ' .. (effData.triples and #effData.triples > 0
                            and table.concat(effData.triples, ', ')
                            or '—'),
                        11),
                },
                -- Recipes
                {
                    type = ui.TYPE.Text,
                    props = textProp(
                        'Recipes: ' .. (effData.recipes and #effData.recipes > 0
                            and table.concat(effData.recipes, ', ')
                            or '—'),
                        11),
                },
                -- Separator: thin Widget
                {
                    type = ui.TYPE.Widget,
                    props = { size = v2(0, 1) },
                },
            },
        }
        contentArea.content:add(block)
    end
end

-- ---------------------------------------------------------------------------
-- ID Resolution
-- ---------------------------------------------------------------------------

local function resolveIngredientEffects(ingredientId)
    local effList = db.ingredientEffects[ingredientId]
    if not effList then
        return {}
    end
    local result = {}
    for _, entry in ipairs(effList) do
        result[#result + 1] = entry[1]
    end
    return result
end

local function resolveIdToEffectIds(id)
    if not id or type(id) ~= 'string' or id == '' then
        return {}
    end

    if db.ingredientEffects[id] then
        return resolveIngredientEffects(id)
    end
    return {}
end

-- ---------------------------------------------------------------------------
-- Query Effects
-- ---------------------------------------------------------------------------

local function queryAndFormatEffects(effectIds)
    if #effectIds == 0 then
        return {}
    end

    local rawResults = require('openmw.interfaces').AlchemyHelper
        and require('openmw.interfaces').AlchemyHelper.queryEffects(effectIds)
    if not rawResults then
        return {}
    end

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

function AlchemyUI.create()
    if panelState.panel then
        return panelState.panel
    end
    return createPanel()
end

function AlchemyUI.show()
    if panelState.visible then
        return
    end
    ui.showMessage('Button pressed')
    interfaces.UI.addMode('AlchemyUI')
    interfaces.UI.setHudVisibility(false)
    if not panelState.panel then
        ui.showMessage('Init UI')
        AlchemyUI.create()
    end
    if panelState.panel then
        ui.showMessage('UI ready')
        panelState.panel.layout.layer = 'Windows'
        panelState.panel:update()
        panelState.visible = true
    end
end

function AlchemyUI.hide()
    if not panelState.visible then
        return
    end
    if panelState.panel then
        panelState.panel.layout.layer = nil
        panelState.panel:update()
    end
    panelState.visible = false
    interfaces.UI.removeMode('AlchemyUI')
    interfaces.UI.setHudVisibility(true)
end

function AlchemyUI.destroy()
    if not panelState.panel then
        return
    end
    panelState.panel:destroy()
    panelState.panel = nil
    panelState.visible = false
    panelState.currentId = nil
end

function AlchemyUI.update(id)
    if not id or type(id) ~= 'string' then
        return
    end
    panelState.currentId = id

    AlchemyUI.create()

    local effectIds = resolveIdToEffectIds(id)

    if #effectIds == 0 then
        if panelState.contentPanel then
            panelState.contentPanel.content = ui.content {
                { type = ui.TYPE.Text, props = textProp('', 12) },
            }
        end
        if not panelState.visible then
            AlchemyUI.show()
        end
        return
    end

    local formattedEffects = queryAndFormatEffects(effectIds)

    if panelState.contentPanel then
        populateEffects(panelState.contentPanel, formattedEffects)
    end

    if not panelState.visible then
        AlchemyUI.show()
    end
end

-- ---------------------------------------------------------------------------
-- Module return
-- ---------------------------------------------------------------------------
return AlchemyUI
