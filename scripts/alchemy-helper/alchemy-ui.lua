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
        relativeSize = v2(1, 1),
    }
end

local function flexPropH()
    return {
        horizontal = true,
        autoSize = false,
        align = ui.ALIGNMENT.Center,
        arrange = ui.ALIGNMENT.Center,
        relativeSize = v2(1, 0),
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

-- Track whether we own the Interface mode (prevents conflicts with other mods).
local ownsMode = false
local applyingMode = false

local panelState = {
    panel = nil,
    contentPanel = nil,
    visible = false,
    currentId = nil,
}

-- ---------------------------------------------------------------------------
-- UI Construction — all types use ui.TYPE values.
-- ---------------------------------------------------------------------------

-- Build the inner UI content (the panel body, separate from the
-- border frame).  Returns ui.content — ready to pass as the
-- 'content' slot of the root Container.
local function buildPanelContent()
    return ui.content {
        -- Outer vertical Flex
        {
            type = ui.TYPE.Flex,
            props = flexProp(),
            content = ui.content {
                -- Title bar row (horizontal, fixed height)
                {
                    type = ui.TYPE.Flex,
                    props = {
                        horizontal = true,
                        autoSize = false,
                        align = ui.ALIGNMENT.Center,
                        arrange = ui.ALIGNMENT.Center,
                        relativeSize = v2(1, 0),
                    },
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
                        -- Close button (Widget with mouseRelease event + Text child)
                        {
                            type = ui.TYPE.Widget,
                            props = {
                                size = v2(30, 30),
                            },
                            events = {
                                mouseRelease = closeCallback,
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
                -- Scrollable content area (fills remaining height)
                {
                    type = ui.TYPE.Container,
                    name = 'scrollArea',
                    props = {
                        relativeSize = v2(1, 1),
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
                                    props = {
                                        horizontal = false,
                                        autoSize = false,
                                        align = ui.ALIGNMENT.Start,
                                        arrange = ui.ALIGNMENT.Start,
                                        relativeSize = v2(0, 1),
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


local auxUi = require('openmw_aux.ui')

local function frameTemplate()
    local base = interfaces.MWUI.templates.boxThick
        or interfaces.MWUI.templates.box
        or interfaces.MWUI.templates.borders
    local tpl = auxUi.deepLayoutCopy(base)
    tpl.type = ui.TYPE.Container

    local background = {
        name = 'background',
        type = ui.TYPE.Image,
            props = {
                resource = ui.texture { path = 'white' },
                color = util.color.rgb(0.3, 0.3, 0.3),
                alpha = 0.5,
                relativeSize = v2(1, 1),
                size = v2(0, 0),
            },
    }

    local rebuilt = { background }
    for _, child in ipairs(tpl.content) do
        rebuilt[#rebuilt + 1] = child
    end
    tpl.content = ui.content(rebuilt)
    return tpl
end

-- (Re)build the window.  Destroys existing, creates fresh.
-- Sets panelState.panel and panelState.contentPanel.
local function rebuildWindow()
    if panelState.panel then
        panelState.panel:destroy()
        panelState.panel = nil
    end

    local pos = CONFIG and CONFIG.positioning
    local ox = (pos and pos.offsetX) or 50
    local oy = (pos and pos.offsetY) or 50
    local corner = pos and pos.corner or 'bottom-right'
    local px = calcPosition(corner, 400, 500, ox, oy)

    local layout = {
        type = ui.TYPE.Container,
        template = frameTemplate(),
        props = {
            size = v2(500,400),
            anchor = v2(0.5, 0.5),
            relativePosition = v2(0.5, 0.5),
        },
        content = buildPanelContent(),
        layer = 'Windows',
    }

    local panel = ui.create(layout)
    if not panel then
        ui.showMessage('Failed to init window')
        return nil
    end

    panelState.panel = panel

    -- Walk the layout content.  Structure:
    --   Container -> [outerFlex] -> [titleBar, scrollArea]
    if layout.content and layout.content[1] then
        local outerFlex = layout.content[1]
        if outerFlex and outerFlex.content and outerFlex.content[2] then
            local scrollContainer = outerFlex.content[2]
            if scrollContainer and scrollContainer.content and scrollContainer.content[1] then
                panelState.contentPanel = scrollContainer.content[1]
            end
        end
    end
    return panel
end

-- Create (or reuse) the panel.  Sets panelState references.
local function createPanel()
    if panelState.panel then
        return panelState.panel
    end
    return rebuildWindow()
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

-- Reconcile Interface mode ownership.  Must be called BEFORE the
-- window element is built (window mode intent is checked, not the
-- element itself).
local function reconcilePause()
    if applyingMode then return end
    local want = panelState.visible
    if want == ownsMode then return end

    local mode = interfaces.UI.getMode()
    applyingMode = true
    if want then
        if mode == nil then
            interfaces.UI.setMode('Interface', { windows = {} })
            ownsMode = true
        end
    else
        if mode == 'Interface' then
            interfaces.UI.removeMode('Interface')
        end
        ownsMode = false
    end
    applyingMode = false
end

function AlchemyUI.isVisible()
    return panelState.visible
end

function AlchemyUI.create()
    if panelState.panel then
        return panelState.panel
    end
    return rebuildWindow()
end

function AlchemyUI.show()
    if panelState.visible then
        return
    end
    -- Set mode BEFORE building the window (matches DailyTraining order).
    panelState.visible = true
    reconcilePause()
    if not panelState.panel then
        AlchemyUI.create()
    end
    if not panelState.panel then
        return
    end
end

function AlchemyUI.hide()
    if not panelState.visible then
        return
    end
    if panelState.panel then
        panelState.panel:destroy()
        panelState.panel = nil
    end
    panelState.visible = false
    panelState.contentPanel = nil
    reconcilePause()
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
