-- Alchemist's Almanac — main UI window (PLAYER context).
--
-- Two-tab window per UI_SPEC.md:
--   1. Ingredients List — searchable; icon, name, effect display names and
--      the number of discovered merchants restocking each ingredient.
--   2. Shopping Planner — pick effects (AND semantics) and see which
--      discovered merchants restock ingredients providing them; optional
--      Strict Mode.
--
-- Built on OpenMW-UIToolkit (EnderWiggin/OpenMW-UIToolkit, installed as a
-- sibling Data Files entry): the window is a registered WindowManager window
-- (frame, title bar, focus handling come from the toolkit), the ingredients
-- list and effects list are virtualized toolkit lists (no manual paging or
-- wheel handlers), and search/checkbox/sort controls are toolkit components.
-- Only the merchant column stays hand-built: its rows have variable height
-- (expanded restock view) and toolkit lists support a single uniform row
-- height.
--
-- Components must be destroyed through the toolkit's destroy path, so the
-- merchant rows container is rebuilt by swapping plain content on its root
-- element (rows contain no components); page-bar buttons are persistent
-- components updated in place via setDisabled/setText.

local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local storage = require('openmw.storage')
local interfaces = require('openmw.interfaces')

local db = require('scripts.alchemy-helper.shared.db')
local SETTINGS = require('scripts.alchemy-helper.shared.settings')

-- Toolkit leaf modules are plain classes (no self-registration), safe to
-- require before the toolkit's own interface script has run. If the toolkit
-- is not installed the mod degrades to a no-op UI with one console warning.
local okClass, Class = pcall(require, 'scripts.UIToolkit.class')
local okWh, WindowHandler = pcall(require, 'scripts.UIToolkit.window_handler')
local okTi, TextItem = pcall(require, 'scripts.UIToolkit.components.list_items.text_item')
local toolkitInstalled = okClass and okWh and okTi

--- Vector2 for layout props.
local function v2(x, y)
    return util.vector2(x or 0, y or 0)
end

-- Morrowind menu palette: gold headers/labels, warm white body, dim notes.
local C_GOLD = util.color.rgb(0.76, 0.7, 0.5)
local C_WHITE = util.color.rgb(0.96, 0.96, 0.90)
local C_DIM = util.color.rgb(0.58, 0.58, 0.58)

-- ui.ALIGNMENT may be absent on older builds; nil means "no explicit align".
local ALIGN_END = ui.ALIGNMENT and ui.ALIGNMENT.End or nil

local WND_ID = 'alchemy-helper-almanac'
local WIN_W, WIN_H = 800, 620

-- Window body layout (px, relative to the body slot below the title header).
local PAD = 8
local TAB_Y = 8
local TOGGLE_Y = 52 -- planner: strict toggle row
local HDR_Y = 80 -- planner: column headers row
local FIELD_Y = 106 -- search / filter field row
local LIST_Y = 144 -- list top
local PAGE_BTN_H = 30

-- Shopping Planner tab columns.
local EFF_W = 350
local EFF_GAP = 16
local MERCH_ROW_H = 60 -- 6 rows/page base
-- Expanded merchant row: header is name + location only (the short matched
-- line is hidden while the full list shows); restock names start below it,
-- one per line.
local MERCH_EXP_HDR = 42
local MERCH_ING_LINE = 17
local ING_ROW_H = 44 -- ingredients rows: icon + two text lines

--- Immersive Mode: filter UI to discovered ingredients. Read live so an
-- in-game settings toggle applies on the next open; nil (unset) = on.
local function immersiveMode()
    local section = storage.playerSection(SETTINGS.group)
    return section:get(SETTINGS.immersiveMode) ~= false
end

local api = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local state = {
    tab = 'ingredients', -- 'ingredients' | 'planner'
    ingSearch = '',
    effSearch = '',
    merchFilter = '',
    merchSort = 'name', -- 'name' | 'location'
    strict = false, -- session-only per spec
    selectedEffects = {}, -- set: compoundKey -> true
    expandedMerchant = nil, -- merchant id with its restock list expanded
    ingOffset = 0,
    merchOffset = 0,
}

-- True while the window is open (set in onOpened/onClosed). Guards deferred
-- async callbacks that land after a close.
local open = false

-- Live component/element handles for the active tab's content; cleared while
-- the window is closed or between tab rebuilds.
local refs = {}

-- Forward declarations: interaction callbacks reference these before their
-- definitions below (closures resolve lexically at compile time).
local rebuildIngest
local rebuildMerch
local makeTabButtons
local switchToTab
local buildIngredientsContent
local buildPlannerContent

-- ---------------------------------------------------------------------------
-- Layout helpers (plain lua_ui, used by the hand-built merchant column)
-- ---------------------------------------------------------------------------

local function text(str, o)
    local props = {
        position = v2(o.x, o.y),
        size = v2(o.w or 100, o.h or 20),
        autoSize = false,
        text = str or '',
        textSize = o.size or 16,
        textColor = o.color or C_WHITE,
        textShadow = true,
    }
    if o.alignH then
        props.textAlignH = o.alignH
    end
    local t = { type = ui.TYPE.Text, props = props }
    local mwui = interfaces.MWUI
    if mwui and mwui.templates and mwui.templates.textNormal then
        t.template = mwui.templates.textNormal
    end
    return t
end

--- Gold value for row display (record .value; 0/missing -> "0g").
local function formatGold(v)
    if type(v) ~= 'number' or v <= 0 then return '0g' end
    return math.floor(v) .. 'g'
end

--- Bordered row background (thin border, like the Squire shop rows).
local function rowBox(x, y, w, h)
    local t = {
        type = ui.TYPE.Container,
        props = { position = v2(x, y), size = v2(w, h) },
    }
    local mwui = interfaces.MWUI
    if mwui and mwui.templates then
        local tpl = mwui.templates.boxTransparent or mwui.templates.box
        if tpl then
            t.template = tpl
        end
    end
    return t
end

local function pageCount(n, perPage)
    return math.max(1, math.ceil((n or 0) / perPage))
end

local function clampOffset(offset, n, perPage)
    local maxOff = math.max(0, n - perPage)
    return math.max(0, math.min(maxOff, offset or 0))
end

-- ---------------------------------------------------------------------------
-- Data shaping (shared by the build passes)
-- ---------------------------------------------------------------------------

--- Flat item tables for the ingredients sorted list. Display strings are
-- precomputed for display. Icon
-- paths are validated up front so a bad path degrades to the toolkit's
-- fallback icon instead of erroring inside the column renderer.
local function buildIngredientItems()
    local list = db.getIngredientList(immersiveMode())
    local counts = db.restockCounts()
    local names = db.getEffectNames()
    local items = {}
    for _, item in ipairs(list) do
        local effNames = {}
        for _, key in ipairs(item.effects or {}) do
            effNames[#effNames + 1] = db.formatEffectName(key, names)
        end
        table.sort(effNames)
        local n = counts[item.id] or 0
        local iconOk = pcall(ui.texture, { path = item.icon })
        items[#items + 1] = {
            id = item.id,
            icon = iconOk and item.icon or 'icons/UIToolkit/unknown-effect.dds',
            name = item.name or item.id,
            effects = table.concat(effNames, ', '),
            value = formatGold(item.value),
            merchants = n .. (n == 1 and ' merchant' or ' merchants'),
        }
    end
    -- db.getIngredientList iterates a hash (no order); the spec wants
    -- alphabetical by name.
    table.sort(items, function(a, b)
        local la, lb = a.name:lower(), b.name:lower()
        if la == lb then
            return a.id < b.id
        end
        return la < lb
    end)
    return items
end

--- Item tables for the effects list. `isActive` reads the live selection set
-- so a toggle only needs an in-place active-state update of the cached row —
-- no row rebuild.
local function buildEffectItems()
    local names = db.getEffectNames()
    local items = {}
    for _, key in ipairs(db.getEffectList(immersiveMode())) do
        items[#items + 1] = { id = key, name = db.formatEffectName(key, names) }
    end
    table.sort(items, function(a, b)
        local la, lb = a.name:lower(), b.name:lower()
        if la == lb then
            return a.id < b.id
        end
        return la < lb
    end)
    for i = 1, #items do
        local it = items[i]
        it.text = it.name -- TextItem renders data.text
        it.isActive = function() return state.selectedEffects[it.id] == true end
    end
    return items
end

local function merchantList()
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
    return merchants
end

-- ---------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------

--- Tab + close button row. Returns an array of element layouts.
function makeTabButtons(C, innerW)
    local bIng = C.textButton {
        text = 'Ingredients', width = 250,
        onClick = function() switchToTab('ingredients') end,
    }
    local bPlan = C.textButton {
        text = 'Shopping Planner', width = 250,
        onClick = function() switchToTab('planner') end,
    }
    local bClose = C.textButton {
        text = 'Close', width = 90,
        onClick = function() api.hide() end,
    }
    bIng:updateProps { position = v2(PAD, TAB_Y) }
    bPlan:updateProps { position = v2(PAD + 258, TAB_Y) }
    bClose:updateProps { position = v2(innerW - PAD - 90, TAB_Y) }
    bIng:setActive(state.tab == 'ingredients')
    bPlan:setActive(state.tab == 'planner')
    return { bIng.element, bPlan.element, bClose.element }
end

function switchToTab(name)
    if not open or name == state.tab or not refs.wnd then
        return
    end
    state.tab = name
    local C = interfaces.UIToolkit.Components
    local inner = refs.wnd:getInnerSize()
    refs.wnd:setContent(state.tab == 'ingredients'
        and buildIngredientsContent(C, inner.x, inner.y)
        or buildPlannerContent(C, inner.x, inner.y))
end

-- ---------------------------------------------------------------------------
-- Ingredients tab
-- ---------------------------------------------------------------------------

--- Ingredients matching the current search (case-insensitive substring in
-- name or effect display names).
local function ingredientFilteredList()
    local q = state.ingSearch:lower()
    if q == '' then
        return refs.allIngredients
    end
    local filtered = {}
    for _, item in ipairs(refs.allIngredients) do
        if (item.name or ''):lower():find(q, 1, true)
            or (item.effects or ''):lower():find(q, 1, true) then
            filtered[#filtered + 1] = item
        end
    end
    return filtered
end

--- Ingredient row: icon, name over the effects line, cost and merchant
-- count right-aligned — plain lua_ui like the merchant rows.
local function ingredientRow(item, y, colW)
    local box = rowBox(0, y, colW - 4, ING_ROW_H - 4)
    box.content = ui.content {
        {
            type = ui.TYPE.Image,
            props = { position = v2(2, 1), size = v2(36, 36), resource = ui.texture { path = item.icon } },
        },
        text(item.name, { x = 46, y = 2, w = colW - 216, h = 18, size = 17, color = C_WHITE }),
        text(item.effects, { x = 46, y = 21, w = colW - 216, h = 17, size = 14, color = C_DIM }),
        text(item.value, { x = colW - 160, y = 2, w = 140, h = 17, size = 14, color = C_GOLD, alignH = ALIGN_END }),
        text(item.merchants, { x = colW - 160, y = 21, w = 140, h = 17, size = 14, color = C_DIM, alignH = ALIGN_END }),
    }
    return box
end

--- Rebuild only the ingredient rows + page bar state. Runs on every search
-- keystroke and page change; the search edit is left untouched so typing
-- keeps keyboard focus.
local rebuildingIngest = false
function rebuildIngest()
    if not open or rebuildingIngest or not refs.ingCol then
        return
    end
    rebuildingIngest = true
    local list = ingredientFilteredList()
    local perPage = math.max(1, math.floor(refs.ingColH / ING_ROW_H))
    state.ingOffset = clampOffset(state.ingOffset, #list, perPage)

    local rows = {}
    for i = state.ingOffset + 1, math.min(#list, state.ingOffset + perPage) do
        rows[#rows + 1] = ingredientRow(list[i], (i - 1 - state.ingOffset) * ING_ROW_H, refs.ingColW)
    end
    if #rows == 0 then
        rows[1] = text('(none)', { x = 8, y = 4, w = 200, h = 20, size = 15, color = C_DIM })
    end

    -- Rows are plain elements (no components), so swapping the container's
    -- content and letting the engine drop the old children is safe.
    refs.ingCol.layout.content = ui.content(rows)
    refs.ingCol:update()

    local pages = pageCount(#list, perPage)
    local page = math.floor(state.ingOffset / perPage) + 1
    refs.ingPageLabel.layout.props.text = 'Page ' .. page .. ' of ' .. pages
    refs.ingPageLabel:update()
    refs.ingCanPrev = page > 1
    refs.ingCanNext = page < pages
    refs.btnIngPrev:setDisabled(page <= 1)
    refs.btnIngNext:setDisabled(page >= pages)
    rebuildingIngest = false
end

buildIngredientsContent = function(C, innerW, innerH)
    local colW = innerW - 2 * PAD
    local colH = innerH - LIST_Y - PAD - PAGE_BTN_H - 6
    local pageY = innerH - PAD - PAGE_BTN_H

    refs.allIngredients = buildIngredientItems()
    refs.ingColW = colW
    refs.ingColH = colH

    -- Rows host (wheel + rows). A root element embedded in the window
    -- content so it can be updated in place; plain children, safe to swap.
    local ingCol = ui.create {
        type = ui.TYPE.Container,
        props = { position = v2(PAD, LIST_Y), size = v2(colW, colH) },
        events = {
            mouseWheel = async:callback(function(e)
                state.ingOffset = state.ingOffset + (e and e.delta and e.delta.y > 0 and -1 or 1)
                rebuildIngest()
            end),
        },
    }

    local btnPrev = C.textButton {
        text = '<', width = 70,
        canClick = function() return refs.ingCanPrev end,
        onClick = function()
            local list = ingredientFilteredList()
            local perPage = math.max(1, math.floor(colH / ING_ROW_H))
            state.ingOffset = clampOffset(state.ingOffset - perPage, #list, perPage)
            rebuildIngest()
        end,
    }
    local btnNext = C.textButton {
        text = '>', width = 70,
        canClick = function() return refs.ingCanNext end,
        onClick = function()
            local list = ingredientFilteredList()
            local perPage = math.max(1, math.floor(colH / ING_ROW_H))
            state.ingOffset = clampOffset(state.ingOffset + perPage, #list, perPage)
            rebuildIngest()
        end,
    }
    btnPrev:updateProps { position = v2(PAD, pageY) }
    btnNext:updateProps { position = v2(PAD + 270, pageY) }
    local pageLabel = ui.create {
        type = ui.TYPE.Text,
        props = {
            position = v2(PAD + 76, pageY + 5),
            size = v2(180, 22),
            autoSize = false,
            text = 'Page 1 of 1',
            textSize = 14,
            textColor = C_GOLD,
            textShadow = true,
        },
    }

    refs.ingCol = ingCol
    refs.btnIngPrev = btnPrev
    refs.btnIngNext = btnNext
    refs.ingPageLabel = pageLabel
    refs.ingCanPrev = false
    refs.ingCanNext = false

    local search = C.textEdit {
        default = state.ingSearch,
        width = colW,
        placeholder = 'Search',
        onValueChanged = function(val)
            state.ingSearch = val or ''
            rebuildIngest()
        end,
    }
    search:updateProps { position = v2(PAD, FIELD_Y) }

    local c = makeTabButtons(C, innerW)
    c[#c + 1] = search.element
    c[#c + 1] = ingCol
    c[#c + 1] = btnPrev.element
    c[#c + 1] = pageLabel
    c[#c + 1] = btnNext.element

    rebuildIngest()
    return ui.content(c)
end

-- ---------------------------------------------------------------------------
-- Shopping Planner tab: effects list (toolkit) + merchant column (custom)
-- ---------------------------------------------------------------------------

--- Merchant row. Clicking toggles expansion: the row grows to list every
-- ingredient the merchant restocks (union across encounters, sorted — the
-- same canonical order as the collapsed short form, which is its prefix).
-- The block is capped at availH - y so it never overlaps the page bar; names
-- that do not fit collapse into a "+N more" line. Returns (box, height).
local function merchantRow(m, y, availH, merchW)
    local ingNames = m.ingredients or {}
    local shown = {}
    for i = 1, math.min(2, #ingNames) do
        shown[i] = ingNames[i]
    end
    local line = table.concat(shown, ', ')
    local extra = #ingNames - #shown
    if extra > 0 then
        line = line .. ' +' .. extra .. ' more'
    end

    local h = MERCH_ROW_H - 4
    local restock = nil
    if state.expandedMerchant == m.id then
        local all = db.getMerchantRestock(m.id)
        local maxLines = math.floor((availH - y - MERCH_EXP_HDR) / MERCH_ING_LINE)
        if maxLines >= 1 then
            local count = math.min(#all, maxLines)
            local hidden = #all > count and 1 or 0
            count = count - hidden
            restock = { all = all, count = count, hidden = hidden }
            -- at least one line: the "+N more" marker or the empty-supply note
            h = MERCH_EXP_HDR + math.max(1, count + hidden) * MERCH_ING_LINE
        end
        -- maxLines < 1: not enough room below the header; render collapsed.
    end

    local box = rowBox(0, y, merchW - 4, h)
    local c = {
        text(m.name, { x = 8, y = 2, w = merchW - 20, h = 18, size = 17, color = C_WHITE }),
        text(m.location or 'unknown location', { x = 8, y = 22, w = merchW - 20, h = 16, size = 14, color = C_DIM }),
    }
    if restock then
        -- Full restock list visible: the short matched line is hidden.
        if #restock.all == 0 then
            c[#c + 1] = text('(no restocking supply)', { x = 14, y = MERCH_EXP_HDR, w = merchW - 26, h = 15, size = 13, color = C_DIM })
        else
            for i = 1, restock.count do
                local ly = MERCH_EXP_HDR + (i - 1) * MERCH_ING_LINE
                c[#c + 1] = text(restock.all[i].name, { x = 14, y = ly, w = 280, h = 15, size = 13, color = C_DIM })
                c[#c + 1] = text(formatGold(restock.all[i].value), { x = merchW - 74, y = ly, w = 60, h = 15, size = 13, color = C_GOLD, alignH = ALIGN_END })
            end
            if restock.hidden == 1 then
                c[#c + 1] = text('+' .. (#restock.all - restock.count) .. ' more', { x = 14, y = MERCH_EXP_HDR + restock.count * MERCH_ING_LINE, w = merchW - 26, h = 15, size = 13, color = C_DIM })
            end
        end
    else
        c[#c + 1] = text(line ~= '' and line or '(no matching ingredients)', { x = 8, y = 40, w = merchW - 20, h = 15, size = 13, color = C_DIM })
    end
    box.content = ui.content(c)
    box.events = {
        mouseClick = async:callback(function()
            -- if/else, not `(cond) and nil or id`: the ternary form parses
            -- as `((cond) and nil) or id` and can never yield nil.
            if state.expandedMerchant == m.id then
                state.expandedMerchant = nil
            else
                state.expandedMerchant = m.id
            end
            rebuildMerch()
        end),
    }
    -- propagateEvents stays on: the wheel handler lives on the column
    -- container (an ancestor), so mouseWheel over a row must reach it.
    return box, h
end

--- Rebuild only the merchant rows + page bar state. Runs on effect toggle,
-- strict toggle, filter/sort change, expansion and paging; the toolkit lists
-- and edits are left untouched so a focused search field keeps typing focus.
local rebuildingMerch = false
function rebuildMerch()
    if not open or rebuildingMerch or not refs.merchCol then
        return
    end
    rebuildingMerch = true
    local merchants = merchantList()
    local availH = refs.merchColH
    local perPage = math.max(1, math.floor(availH / MERCH_ROW_H))
    state.merchOffset = clampOffset(state.merchOffset, #merchants, perPage)

    -- Variable row heights: an expanded merchant grows, following rows shift
    -- down, and rows that no longer fit below the page bar are skipped
    -- (they remain reachable on later pages).
    local rows = {}
    local y = 0
    for i = state.merchOffset + 1, math.min(#merchants, state.merchOffset + perPage) do
        local row, h = merchantRow(merchants[i], y, availH, refs.merchW)
        if y + h <= availH then
            rows[#rows + 1] = row
            y = y + h + 4
        end
    end
    if #rows == 0 then
        rows[1] = text('(none)', { x = 8, y = 4, w = 200, h = 20, size = 15, color = C_DIM })
    end

    -- Rows are plain elements (no components), so swapping the container's
    -- content and letting the engine drop the old children is safe — the same
    -- setContent + update pattern the toolkit's own window uses.
    refs.merchCol.layout.content = ui.content(rows)
    refs.merchCol:update()

    local pages = pageCount(#merchants, perPage)
    local page = math.floor(state.merchOffset / perPage) + 1
    refs.pageLabel.layout.props.text = 'Page ' .. page .. ' of ' .. pages
    refs.pageLabel:update()
    refs.merchCanPrev = page > 1
    refs.merchCanNext = page < pages
    refs.btnPrev:setDisabled(page <= 1)
    refs.btnNext:setDisabled(page >= pages)
    rebuildingMerch = false
end

buildPlannerContent = function(C, innerW, innerH)
    local merchX = PAD + EFF_W + EFF_GAP
    local merchW = innerW - merchX - PAD
    local colH = innerH - LIST_Y - PAD - PAGE_BTN_H - 6
    local pageY = innerH - PAD - PAGE_BTN_H

    -- Effects list: fixed-height text rows; selection is the row's active
    -- state, toggled in place on the cached row component (no rebuild).
    local effProvider = TextItem:new()
    local allEffects = buildEffectItems()
    local function applyEffFilter()
        local q = state.effSearch:lower()
        local items = allEffects
        if q ~= '' then
            local filtered = {}
            for _, it in ipairs(allEffects) do
                if it.name:lower():find(q, 1, true) then
                    filtered[#filtered + 1] = it
                end
            end
            items = filtered
        end
        refs.effList:setItems(items)
    end

    local effList = C.itemList {
        size = v2(EFF_W, colH),
        provider = effProvider,
        onItemClicked = function(data)
            if state.selectedEffects[data.id] then
                state.selectedEffects[data.id] = nil
            else
                state.selectedEffects[data.id] = true
            end
            -- Toolkit 1.2.0's provider:refreshState is broken: it passes the
            -- cached ELEMENT to updateState, which then calls
            -- component:isActive() on it (nil). Do what refreshState does,
            -- with the real component: apply the active state + deep update.
            -- Uncached rows pick up their state when materialized.
            local comp = effProvider:getCachedComponent(data.id)
            if comp then
                interfaces.UIToolkit.Interactive.updateState(comp.element, {
                    active = state.selectedEffects[data.id] == true,
                })
                interfaces.UIToolkit.queueUpdate(comp.element, true)
            end
            rebuildMerch()
        end,
    }

    refs.effList = effList
    refs.effProvider = effProvider
    refs.merchColH = colH
    refs.merchW = merchW

    -- Merchant column container (wheel + row host). A root element embedded
    -- in the window content (the toolkit's own pattern for components) so it
    -- can be updated in place; plain children, safe to swap.
    local merchCol = ui.create {
        type = ui.TYPE.Container,
        props = { position = v2(merchX, LIST_Y), size = v2(merchW, colH) },
        events = {
            mouseWheel = async:callback(function(e)
                local perPage = math.max(1, math.floor(colH / MERCH_ROW_H))
                state.merchOffset = clampOffset(
                    state.merchOffset + (e and e.delta and e.delta.y > 0 and -1 or 1),
                    #merchantList(), perPage)
                rebuildMerch()
            end),
        },
    }

    -- Page bar: persistent toolkit buttons (canClick guards the action;
    -- setDisabled in rebuildMerch mirrors the state visually).
    local btnPrev = C.textButton {
        text = '<', width = 70,
        canClick = function() return refs.merchCanPrev end,
        onClick = function()
            local perPage = math.max(1, math.floor(colH / MERCH_ROW_H))
            state.merchOffset = clampOffset(state.merchOffset - perPage, #merchantList(), perPage)
            rebuildMerch()
        end,
    }
    local btnNext = C.textButton {
        text = '>', width = 70,
        canClick = function() return refs.merchCanNext end,
        onClick = function()
            local perPage = math.max(1, math.floor(colH / MERCH_ROW_H))
            state.merchOffset = clampOffset(state.merchOffset + perPage, #merchantList(), perPage)
            rebuildMerch()
        end,
    }
    btnPrev:updateProps { position = v2(merchX, pageY) }
    btnNext:updateProps { position = v2(merchX + 270, pageY) }
    local pageLabel = ui.create {
        type = ui.TYPE.Text,
        props = {
            position = v2(merchX + 76, pageY + 5),
            size = v2(180, 22),
            autoSize = false,
            text = 'Page 1 of 1',
            textSize = 14,
            textColor = C_GOLD,
            textShadow = true,
        },
    }

    refs.merchCol = merchCol
    refs.btnPrev = btnPrev
    refs.btnNext = btnNext
    refs.pageLabel = pageLabel
    refs.merchCanPrev = false
    refs.merchCanNext = false

    local effEdit = C.textEdit {
        default = state.effSearch, width = EFF_W, placeholder = 'Filter effects',
        onValueChanged = function(val)
            state.effSearch = val or ''
            applyEffFilter()
        end,
    }
    local merchEdit = C.textEdit {
        default = state.merchFilter, width = 260, placeholder = 'Filter merchants',
        onValueChanged = function(val)
            state.merchFilter = val or ''
            rebuildMerch()
        end,
    }

    local btnName
    local btnLoc
    btnName = C.textButton {
        text = 'Name', width = 52,
        onClick = function()
            state.merchSort = 'name'
            btnName:setActive(true)
            btnLoc:setActive(false)
            rebuildMerch()
        end,
    }
    btnLoc = C.textButton {
        text = 'Location', width = 64,
        onClick = function()
            state.merchSort = 'location'
            btnName:setActive(false)
            btnLoc:setActive(true)
            rebuildMerch()
        end,
    }
    if state.merchSort == 'name' then
        btnName:setActive(true)
    else
        btnLoc:setActive(true)
    end

    effEdit:updateProps { position = v2(PAD, FIELD_Y) }
    merchEdit:updateProps { position = v2(merchX, FIELD_Y) }
    btnName:updateProps { position = v2(merchX + 268, FIELD_Y) }
    btnLoc:updateProps { position = v2(merchX + 326, FIELD_Y) }
    effList:updateProps { position = v2(PAD, LIST_Y) }

    local strictBox = C.checkbox {
        text = 'STRICT MODE', default = state.strict,
        onValueChanged = function(val)
            state.strict = val and true or false
            rebuildMerch()
        end,
    }
    strictBox:updateProps { position = v2(PAD, TOGGLE_Y) }

    local c = makeTabButtons(C, innerW)
    c[#c + 1] = strictBox.element
    c[#c + 1] = text('Effects', { x = PAD, y = HDR_Y, w = EFF_W, h = 24, size = 18, color = C_GOLD })
    c[#c + 1] = text('Merchants', { x = merchX, y = HDR_Y, w = merchW, h = 24, size = 18, color = C_GOLD })
    c[#c + 1] = effEdit.element
    c[#c + 1] = merchEdit.element
    c[#c + 1] = btnName.element
    c[#c + 1] = btnLoc.element
    c[#c + 1] = effList.element
    c[#c + 1] = merchCol
    c[#c + 1] = btnPrev.element
    c[#c + 1] = pageLabel
    c[#c + 1] = btnNext.element

    applyEffFilter()
    rebuildMerch()
    return ui.content(c)
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
    local want = open
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
-- Window handler + registration
-- ---------------------------------------------------------------------------

-- Dummy table when the toolkit is missing: methods attach harmlessly and
-- are never called (api.show bails on toolkitInstalled first).
local Handler = toolkitInstalled and Class(WindowHandler) or {}

function Handler:onOpened(wnd, data, saved)
    open = true
    refs.wnd = wnd
    reconcilePause()
    local C = interfaces.UIToolkit.Components
    local inner = wnd:getInnerSize()
    -- Fresh data on open (spec: refresh on open).
    wnd:setContent(state.tab == 'ingredients'
        and buildIngredientsContent(C, inner.x, inner.y)
        or buildPlannerContent(C, inner.x, inner.y))
end

function Handler:onClosed()
    open = false
    refs = {}
    reconcilePause()
end

--- Right-stick scrolling target for the toolkit's focused-window routing.
-- Only the planner's effects list is a toolkit scrollable; the ingredients
-- and merchant columns are hand-built with wheel + page buttons.
function Handler:getFocusedScrollable()
    if not open or state.tab ~= 'planner' then return nil end
    return refs.effList
end

local registered = false
local warnedNoToolkit = false

local function ensureRegistered()
    local TK = interfaces.UIToolkit
    if not TK or not TK.WindowManager then
        if not warnedNoToolkit then
            warnedNoToolkit = true
            print('[AlchemyHelper] OpenMW-UIToolkit not found — the almanac UI is disabled. Install it as a Data Files entry.')
        end
        return false
    end
    if not registered then
        local WM = TK.WindowManager
        WM.register(WND_ID, {
            title = "Alchemist's Almanac",
            handler = Handler,
            size = v2(WIN_W, WIN_H),
            position = WM.getCenterPositionForSize(v2(WIN_W, WIN_H)),
            resizing = false, -- fixed-size window; also disables dragging
        })
        registered = true
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Public API (unchanged shape: alchemy-binding.lua drives show/hide)
-- ---------------------------------------------------------------------------

function api.show()
    if not toolkitInstalled then
        if not warnedNoToolkit then
            warnedNoToolkit = true
            print('[AlchemyHelper] OpenMW-UIToolkit scripts not found — the almanac UI is disabled.')
        end
        return
    end
    if not ensureRegistered() then
        return
    end
    local WM = interfaces.UIToolkit.WindowManager
    if WM.isOpen(WND_ID) then
        return
    end
    WM.open(WND_ID)
end

function api.hide()
    local TK = interfaces.UIToolkit
    if not TK or not TK.WindowManager then
        return
    end
    local WM = TK.WindowManager
    if WM.isOpen(WND_ID) then
        WM.close(WND_ID) -- onClosed reconciles the mode + clears refs
    end
end

function api.destroy()
    api.hide()
end

function api.isVisible()
    local TK = interfaces.UIToolkit
    return (TK and TK.WindowManager and TK.WindowManager.isOpen(WND_ID)) or false
end

--- Global event UiModeChanged {oldMode, newMode, arg}: fires on every mode
-- stack change, including Esc closing a mode from the engine side. When all
-- modes are gone our window is orphaned (visible but uninteractable) — close
-- it. Our own show/hide never match: by the time their mode change event
-- lands, `open` has already been flipped in onOpened/onClosed.
function api.onUiModeChanged(data)
    if open and data and data.newMode == nil then
        api.hide()
    end
end

return {
    show = api.show,
    hide = api.hide,
    destroy = api.destroy,
    isVisible = api.isVisible,
    onUiModeChanged = api.onUiModeChanged,
}
