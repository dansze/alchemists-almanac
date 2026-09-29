-- Alchemist's Almanac — main UI window (PLAYER context).
--
-- Two-tab window per UI_SPEC.md:
--   1. Ingredients List — searchable; icon, name, effect display names and
--      the number of discovered merchants restocking each ingredient.
--   2. Shopping Planner — pick effects (AND semantics), see which discovered
--      merchants restock ingredients providing them; optional Strict Mode.
--
-- All data comes from shared/db.lua (storage-backed) — this script never
-- touches game records directly. Effect display names come from the static
-- table in shared/data/effects.lua.
--
-- lua_ui has no native scrolling/clipping, so lists are *windowed*: only the
-- visible rows exist as widgets; navigation is mouse wheel + page buttons.

local ui = require('openmw.ui')
local async = require('openmw.async')
local storage = require('openmw.storage')
local util = require('openmw.util')
local auxUi = require('openmw_aux.ui')
local interfaces = require('openmw.interfaces')

--- Vector2 for layout props (openmw.util.vector2 with nil-safe args).
local function v2(x, y)
    return util.vector2(x or 0, y or 0)
end

local db = require('scripts.alchemy-helper.shared.db')
local SETTINGS = require('scripts.alchemy-helper.shared.settings')
local effects = require('scripts.alchemy-helper.shared.data.effects')

-- Geometry (px). The boxThick frame insets content by 4px at top-left and
-- overflows 4px at bottom-right; INNER_W/BODY_H plus the 12px centering
-- offset below keep everything inside the window with even 16px margins.
local WIN_W, WIN_H = 800, 620
local FRAME = 16
local BAR_H = 34
local TAB_H = 32
local FIELD_H = 30
local PAGE_H = 26
local HEADER_H = 28
local GAP = 6

local INNER_W = WIN_W - 2 * FRAME
local BODY_H = WIN_H - 2 * FRAME - BAR_H - TAB_H
local LIST_H_ING = BODY_H - FIELD_H - PAGE_H - 2 * GAP
local COL_H = BODY_H - HEADER_H - GAP
local LIST_H_COL = COL_H - FIELD_H - PAGE_H - 2 * GAP
local LEFT_W = 350
local RIGHT_W = INNER_W - LEFT_W - GAP

local ROW_H_ING = 54
local ROW_H_EFF = 30
local ROW_H_MERCH = 74

local C_TEXT = 'rgb(230,230,230)'
local C_DIM = 'rgb(160,160,160)'
local C_SEL = 'rgb(255,215,90)'
local C_WHITE = 'rgb(255,255,255)'

--- Immersive Mode: filter UI to discovered ingredients. Read live so an
-- in-game settings toggle applies on the next refresh; nil (unset) = on.
local function immersiveMode()
    local section = storage.playerSection(SETTINGS.group)
    return section:get(SETTINGS.immersiveMode) ~= false
end

local api = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local state = {
    visible = false,
    tab = 'ingredients', -- 'ingredients' | 'planner'
    ingSearch = '',
    effSearch = '',
    merchFilter = '',
    merchSort = 'name', -- 'name' | 'location'
    strict = false, -- session-only per spec
    selectedEffects = {}, -- set: compoundKey -> true
}

-- Live references for the currently built tab; rebuilt on open/tab switch.
local views = {} -- { ing = view, eff = view, merch = view }
local nodes = {} -- { root, body, tabIng, tabPlanner, strict }

-- Forward declarations: event callbacks fire after load, but Lua resolves
-- names lexically at compile time.
local refreshIngredients, refreshEffects, refreshMerchants, setTab

--- UiElement from ui.create; nil until the window is built.
local element = nil

--- Push layout-table mutations to the engine (no-op before first create).
local function applyUpdate()
    if element then
        element:update()
    end
end

-- ---------------------------------------------------------------------------
-- Layout helpers
-- ---------------------------------------------------------------------------

local function text(str, size, color, width)
    local props = {
        text = str or '',
        textSize = size or 12,
        textColor = color or C_TEXT,
    }
    if width then
        props.size = v2(width, 0)
    end
    return { type = ui.TYPE.Text, props = props }
end

--- Windowed list view: only visible rows exist as widgets.
-- makeRow(item, index) -> row layout table.
local function listView(node, rowHeight, height, makeRow)
    local v = {
        node = node,
        items = {},
        offset = 0,
        rowsPerPage = math.max(1, math.floor(height / rowHeight)),
    }

    function v.render()
        local rows = {}
        for i = v.offset + 1, math.min(#v.items, v.offset + v.rowsPerPage) do
            rows[#rows + 1] = makeRow(v.items[i], i)
        end
        if #rows == 0 then
            rows[1] = text('(none)', 12, C_DIM)
        end
        node.content = ui.content(rows)
        applyUpdate()
    end

    function v.setItems(items)
        v.items = items or {}
        local maxOff = math.max(0, #v.items - v.rowsPerPage)
        if v.offset > maxOff then
            v.offset = 0
        end
        v.render()
    end

    function v.scroll(deltaRows)
        local maxOff = math.max(0, #v.items - v.rowsPerPage)
        v.offset = math.max(0, math.min(maxOff, v.offset + deltaRows))
        v.render()
    end

    return v
end

--- Page up/down buttons for a list view (looked up lazily via views).
local function pageBar(viewName)
    local function btn(label, dir)
        return {
            type = ui.TYPE.Widget,
            props = { size = v2(30, PAGE_H - 4) },
            content = ui.content{ text(label, 12, C_DIM, 30) },
            events = {
                mouseRelease = async:callback(function()
                    local v = views[viewName]
                    if v then
                        v.scroll(dir)
                    end
                end),
            },
        }
    end
    return {
        type = ui.TYPE.Flex,
        -- stretch: fill the width of the parent (vertical) flex.
        external = { stretch = 1 },
        props = { horizontal = true, autoSize = false, size = v2(0, PAGE_H) },
        content = ui.content{
            { type = ui.TYPE.Widget, external = { grow = 1 } },
            btn('▲', -1),
            btn('▼', 1),
        },
    }
end

--- Mouse wheel on a list container: one row per notch (UI_SPEC.md).
local function wheelEvent(viewName)
    return async:callback(function(e)
        local v = views[viewName]
        if v and e and e.delta and e.delta.y then
            v.scroll(e.delta.y > 0 and -1 or 1)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Ingredients tab
-- ---------------------------------------------------------------------------

local function merchantLabel(n)
    return n .. (n == 1 and ' merchant' or ' merchants')
end

local function makeIngredientRow(counts)
    return function(item)
        local effNames = {}
        for _, key in ipairs(item.effects or {}) do
            effNames[#effNames + 1] = effects.formatEffectName(key)
        end
        table.sort(effNames)
        local iconPart
        if item.icon then
            iconPart = {
                type = ui.TYPE.Image,
                props = { size = v2(40, 40), resource = ui.texture { path = item.icon } },
            }
        else
            iconPart = { type = ui.TYPE.Widget, props = { size = v2(40, 40) } }
        end
        return {
            type = ui.TYPE.Flex,
            props = { horizontal = true, autoSize = false, size = v2(INNER_W - 8, ROW_H_ING), gap = 8 },
            content = ui.content{
                iconPart,
                {
                    type = ui.TYPE.Flex,
                    external = { grow = 1 },
                    props = { horizontal = false, autoSize = false },
                    content = ui.content{
                        text(item.name, 13, C_WHITE),
                        text(table.concat(effNames, ', '), 11, C_DIM),
                    },
                },
                text(merchantLabel(counts[item.id] or 0), 11, C_DIM, 110),
            },
        }
    end
end

local function buildIngredientsTab()
    local counts = db.restockCounts()
    local listNode = {
        type = ui.TYPE.Flex,
        external = { stretch = 1 },
        props = { horizontal = false, autoSize = false, size = v2(0, LIST_H_ING) },
        content = ui.content{ text('(none)', 12, C_DIM) },
        events = { mouseWheel = wheelEvent('ing') },
    }
    local layout = {
        type = ui.TYPE.Flex,
        props = { horizontal = false, autoSize = false, size = v2(INNER_W, BODY_H), gap = GAP },
        content = ui.content{
            {
                type = ui.TYPE.TextEdit,
                external = { stretch = 1 },
                props = {
                    text = state.ingSearch,
                    textSize = 12,
                    textColor = C_TEXT,
                    size = v2(0, FIELD_H),
                },
                events = {
                    textChanged = async:callback(function(t)
                        state.ingSearch = t or ''
                        refreshIngredients()
                    end),
                },
            },
            listNode,
            pageBar('ing'),
        },
    }
    views.ing = listView(listNode, ROW_H_ING, LIST_H_ING, makeIngredientRow(counts))
    return layout
end

function refreshIngredients()
    if state.tab ~= 'ingredients' or not views.ing then
        return
    end
    local list = db.getIngredientList(immersiveMode())
    local q = state.ingSearch:lower()
    if q ~= '' then
        local filtered = {}
        for _, item in ipairs(list) do
            if (item.name or ''):lower():find(q, 1, true) then
                filtered[#filtered + 1] = item
            end
        end
        list = filtered
    end
    views.ing.setItems(list)
end

-- ---------------------------------------------------------------------------
-- Shopping Planner tab
-- ---------------------------------------------------------------------------

local function makeEffectRow()
    return function(item) -- { key, name }
        local sel = state.selectedEffects[item.key] and true or false
        return {
            type = ui.TYPE.Flex,
            props = { horizontal = true, autoSize = false, size = v2(LEFT_W - 8, ROW_H_EFF) },
            content = ui.content{
                text(sel and '•' or '', 13, C_SEL, 16),
                {
                    type = ui.TYPE.Text,
                    external = { grow = 1 },
                    props = {
                        text = item.name,
                        textSize = 12,
                        textColor = sel and C_SEL or C_TEXT,
                    },
                },
            },
            events = {
                mouseRelease = async:callback(function()
                    if state.selectedEffects[item.key] then
                        state.selectedEffects[item.key] = nil
                    else
                        state.selectedEffects[item.key] = true
                    end
                    refreshEffects()
                    refreshMerchants()
                end),
            },
        }
    end
end

local function makeMerchantRow()
    return function(m)
        local ingNames = m.ingredients or {}
        local shown = {}
        for i = 1, math.min(2, #ingNames) do
            shown[i] = ingNames[i]
        end
        local line = table.concat(shown, ', ')
        local extra = #ingNames - #shown
        if extra > 0 then
            line = line .. ' …+' .. extra .. ' more'
        end
        return {
            type = ui.TYPE.Flex,
            props = { horizontal = false, autoSize = false, size = v2(RIGHT_W - 8, ROW_H_MERCH), gap = 2 },
            content = ui.content{
                text(m.name, 13, C_WHITE),
                text(m.location or 'unknown location', 11, C_DIM),
                text(line ~= '' and line or '(no matching ingredients)', 10, C_DIM),
            },
        }
    end
end

local function buildPlannerTab()
    local effListNode = {
        type = ui.TYPE.Flex,
        external = { stretch = 1 },
        props = { horizontal = false, autoSize = false, size = v2(0, LIST_H_COL) },
        content = ui.content{ text('(none)', 12, C_DIM) },
        events = { mouseWheel = wheelEvent('eff') },
    }
    local merchListNode = {
        type = ui.TYPE.Flex,
        external = { stretch = 1 },
        props = { horizontal = false, autoSize = false, size = v2(0, LIST_H_COL) },
        content = ui.content{ text('(none)', 12, C_DIM) },
        events = { mouseWheel = wheelEvent('merch') },
    }

    local function strictLabel()
        return (state.strict and '☑' or '☐') .. ' Strict Mode'
    end

    local layout = {
        type = ui.TYPE.Flex,
        props = { horizontal = false, autoSize = false, size = v2(INNER_W, BODY_H), gap = GAP },
        content = ui.content{
            {
                type = ui.TYPE.Widget,
                props = { size = v2(180, HEADER_H) },
                content = ui.content{ text(strictLabel(), 12, C_TEXT, 180) },
                events = {
                    mouseRelease = async:callback(function()
                        state.strict = not state.strict
                        nodes.strict.content = ui.content{ text(strictLabel(), 12, C_TEXT, 180) }
                        applyUpdate()
                        refreshMerchants()
                    end),
                },
            },
            {
                type = ui.TYPE.Flex,
                external = { stretch = 1 },
                props = { horizontal = true, autoSize = false, size = v2(0, COL_H), gap = GAP },
                content = ui.content{
                    -- Effects column
                    {
                        type = ui.TYPE.Flex,
                        props = { horizontal = false, autoSize = false, size = v2(LEFT_W, COL_H), gap = GAP },
                        content = ui.content{
                            {
                                type = ui.TYPE.TextEdit,
                                external = { stretch = 1 },
                                props = {
                                    text = state.effSearch,
                                    textSize = 12,
                                    textColor = C_TEXT,
                                    size = v2(0, FIELD_H),
                                },
                                events = {
                                    textChanged = async:callback(function(t)
                                        state.effSearch = t or ''
                                        refreshEffects()
                                    end),
                                },
                            },
                            effListNode,
                            pageBar('eff'),
                        },
                    },
                    -- Merchants column
                    {
                        type = ui.TYPE.Flex,
                        external = { grow = 1 },
                        props = { horizontal = false, autoSize = false, size = v2(0, COL_H), gap = GAP },
                        content = ui.content{
                            {
                                type = ui.TYPE.Flex,
                                external = { stretch = 1 },
                                props = { horizontal = true, autoSize = false, size = v2(0, FIELD_H), gap = 4 },
                                content = ui.content{
                                    {
                                        type = ui.TYPE.TextEdit,
                                        external = { grow = 1 },
                                        props = { text = state.merchFilter, textSize = 12, textColor = C_TEXT },
                                        events = {
                                            textChanged = async:callback(function(t)
                                                state.merchFilter = t or ''
                                                refreshMerchants()
                                            end),
                                        },
                                    },
                                    {
                                        type = ui.TYPE.Widget,
                                        props = { size = v2(56, FIELD_H - 4) },
                                        content = ui.content{ text('Name', 11, C_TEXT, 56) },
                                        events = {
                                            mouseRelease = async:callback(function()
                                                state.merchSort = 'name'
                                                refreshMerchants()
                                            end),
                                        },
                                    },
                                    {
                                        type = ui.TYPE.Widget,
                                        props = { size = v2(56, FIELD_H - 4) },
                                        content = ui.content{ text('Loc', 11, C_TEXT, 56) },
                                        events = {
                                            mouseRelease = async:callback(function()
                                                state.merchSort = 'location'
                                                refreshMerchants()
                                            end),
                                        },
                                    },
                                },
                            },
                            merchListNode,
                            pageBar('merch'),
                        },
                    },
                },
            },
        },
    }

    -- Strict toggle widget (for in-place label re-render).
    nodes.strict = layout.content[1]

    views.eff = listView(effListNode, ROW_H_EFF, LIST_H_COL, makeEffectRow())
    views.merch = listView(merchListNode, ROW_H_MERCH, LIST_H_COL, makeMerchantRow())
    return layout
end

function refreshEffects()
    if state.tab ~= 'planner' or not views.eff then
        return
    end
    local items = {}
    for _, key in ipairs(db.getEffectList(immersiveMode())) do
        items[#items + 1] = { key = key, name = effects.formatEffectName(key) }
    end
    table.sort(items, function(a, b)
        local la, lb = a.name:lower(), b.name:lower()
        if la == lb then
            return a.key < b.key
        end
        return la < lb
    end)
    local q = state.effSearch:lower()
    if q ~= '' then
        local filtered = {}
        for _, it in ipairs(items) do
            if it.name:lower():find(q, 1, true) then
                filtered[#filtered + 1] = it
            end
        end
        items = filtered
    end
    views.eff.setItems(items)
end

function refreshMerchants()
    if state.tab ~= 'planner' or not views.merch then
        return
    end
    local keys = {}
    for k in pairs(state.selectedEffects) do
        keys[#keys + 1] = k
    end
    local merchants = db.queryMerchantsForEffects(keys, state.strict)

    local f = state.merchFilter:lower()
    if f ~= '' then
        local filtered = {}
        for _, m in ipairs(merchants) do
            local hay = ((m.name or '') .. ' ' .. (m.location or '')):lower()
            if hay:find(f, 1, true) then
                filtered[#filtered + 1] = m
            end
        end
        merchants = filtered
    end

    table.sort(merchants, function(a, b)
        local ka = (state.merchSort == 'name' and a.name or a.location or ''):lower()
        local kb = (state.merchSort == 'name' and b.name or b.location or ''):lower()
        if ka == kb then
            return (a.id or '') < (b.id or '')
        end
        return ka < kb
    end)

    views.merch.setItems(merchants)
end

-- ---------------------------------------------------------------------------
-- Window chrome (title bar, tabs)
-- ---------------------------------------------------------------------------

local TAB_W = 170

local function tabButton(label, tabName)
    return {
        type = ui.TYPE.Widget,
        props = { size = v2(TAB_W, TAB_H - 4) },
        content = ui.content{ text(label, 13, C_DIM, TAB_W) },
        events = {
            mouseRelease = async:callback(function()
                if state.tab ~= tabName then
                    setTab(tabName)
                end
            end),
        },
    }
end

-- Root frame: deep copy of the MWUI boxThick template (the raw shared
-- table must not be mutated), plus a translucent background so the game
-- world does not show through the panel interior.
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
    for _, child in ipairs(tpl.content or {}) do
        rebuilt[#rebuilt + 1] = child
    end
    tpl.content = ui.content(rebuilt)
    return tpl
end

function setTab(tabName)
    state.tab = tabName
    nodes.tabIng.content = ui.content{
        text('Ingredients', 13, tabName == 'ingredients' and C_SEL or C_DIM, TAB_W),
    }
    nodes.tabPlanner.content = ui.content{
        text('Shopping Planner', 13, tabName == 'planner' and C_SEL or C_DIM, TAB_W),
    }
    -- Rebuild the active tab (spec: refresh on open + tab switch), then
    -- populate it with current data.
    local panel = (tabName == 'ingredients') and buildIngredientsTab() or buildPlannerTab()
    nodes.body.content = ui.content{ panel }
    if tabName == 'ingredients' then
        refreshIngredients()
    else
        refreshEffects()
        refreshMerchants()
    end
    applyUpdate()
end

local function buildWindow()
    -- Centered in the window: boxThick's slot starts at (4,4) with full
    -- parent size, so (12,12) inside it lands content at (16,16).
    local innerFlex = {
        type = ui.TYPE.Flex,
        props = { horizontal = false, autoSize = true, size = v2(0, 0), position = v2(12, 12) },
        content = ui.content{
                    -- Title bar
                    {
                        type = ui.TYPE.Flex,
                        props = { horizontal = true, autoSize = false, size = v2(INNER_W, BAR_H) },
                        content = ui.content{
                            text('Alchemist\'s Almanac', 15, C_WHITE),
                            { type = ui.TYPE.Widget, external = { grow = 1 } },
                            {
                                type = ui.TYPE.Widget,
                                props = { size = v2(24, 24) },
                                content = ui.content{ text('✕', 13, C_DIM, 24) },
                                events = { mouseRelease = async:callback(function() api.hide() end) },
                            },
                        },
                    },
                    -- Tab bar
                    {
                        type = ui.TYPE.Flex,
                        props = { horizontal = true, autoSize = false, size = v2(INNER_W, TAB_H), gap = 4 },
                        content = ui.content{ tabButton('Ingredients', 'ingredients'), tabButton('Shopping Planner', 'planner') },
                    },
                    -- Body (rebuilt per tab)
                    {
                        type = ui.TYPE.Flex,
                        props = { horizontal = false, autoSize = false, size = v2(INNER_W, BODY_H) },
                        content = ui.content{},
                    },
                },
    }

    local root = {
        type = ui.TYPE.Container,
        template = frameTemplate(),
        layer = 'Windows',
        props = {
            size = v2(WIN_W, WIN_H),
            anchor = v2(0.5, 0.5),
            relativePosition = v2(0.5, 0.5),
            visible = false,
        },
        content = ui.content{ innerFlex },
    }

    local inner = root.content[1]
    nodes.root = root
    nodes.tabIng = inner.content[2].content[1]
    nodes.tabPlanner = inner.content[2].content[2]
    nodes.body = inner.content[3]
    return root
end

-- ---------------------------------------------------------------------------
-- Mode reconciliation (Interface mode).
-- Owns 'Interface' mode only when it had to create it (nothing else was
-- open); otherwise the window simply overlays the current mode.
-- ---------------------------------------------------------------------------

local ownsMode = false
local applyingMode = false

local function reconcilePause()
    if applyingMode then
        return
    end
    local want = state.visible
    if want == ownsMode then
        return
    end

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

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function api.create()
    if nodes.root then
        return
    end
    local root = buildWindow()
    element = ui.create(root)
end

function api.show()
    if state.visible then
        return
    end
    state.visible = true
    reconcilePause()
    if not nodes.root then
        api.create()
    end
    nodes.root.props.visible = true
    -- Spec: refresh on open (rebuilds the active tab and re-queries data).
    setTab(state.tab)
end

function api.hide()
    if not state.visible then
        return
    end
    state.visible = false
    if nodes.root then
        nodes.root.props.visible = false
        applyUpdate()
    end
    reconcilePause()
end

function api.destroy()
    if state.visible then
        api.hide() -- releases the Interface mode if we own it
    end
    if element then
        element:destroy()
        element = nil
    end
    nodes = {}
    views = {}
    state.visible = false
    ownsMode = false
end

function api.isVisible()
    return state.visible
end

return {
    create = api.create,
    show = api.show,
    hide = api.hide,
    destroy = api.destroy,
    isVisible = api.isVisible,
}
