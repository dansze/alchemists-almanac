-- Alchemist's Almanac — main UI window (PLAYER context).
--
-- Two-tab window per UI_SPEC.md:
--   1. Ingredients List — searchable; icon, name, effect display names and
--      the number of discovered merchants restocking each ingredient.
--   2. Shopping Planner — pick effects (AND semantics), see which discovered
--      merchants restock ingredients providing them; optional Strict Mode.
--
-- Styling follows the native game menus and other Lua mods (Squire spell
-- shop): boxTransparentThick window frame, gold/white/dim palette, shadowed
-- text at menu font sizes, absolute positioning inside one window container.
--
-- The window is two elements (destroy + ui.create rebuilds, Squire-style):
-- a frame element (chrome, labels, search fields) and a list-region element
-- (rows + page bar). In-place element:update() calls are avoided because
-- lua_ui re-attaches TextEdit input widgets on every update, which drops
-- keyboard focus. Live filtering rebuilds only the list element on each
-- keystroke, so a focused search field in the frame keeps typing focus.

local ui = require('openmw.ui')
local async = require('openmw.async')
local storage = require('openmw.storage')
local util = require('openmw.util')
local interfaces = require('openmw.interfaces')

local db = require('scripts.alchemy-helper.shared.db')
local SETTINGS = require('scripts.alchemy-helper.shared.settings')

--- Vector2 for layout props.
local function v2(x, y)
    return util.vector2(x or 0, y or 0)
end

local function templates()
    return (interfaces.MWUI and interfaces.MWUI.templates) or {}
end

-- ui.ALIGNMENT may be absent on older builds; nil means "no explicit align".
local ALIGN_CENTER = ui.ALIGNMENT and ui.ALIGNMENT.Center or nil

-- Morrowind menu palette: gold headers/labels, warm white body, dim notes.
local C_GOLD = util.color.rgb(0.76, 0.7, 0.5)
local C_WHITE = util.color.rgb(0.96, 0.96, 0.90)
local C_DIM = util.color.rgb(0.58, 0.58, 0.58)

-- Window geometry (px). Content coordinates are relative to the window's
-- template slot (the thick border insets by 4px; margins below absorb it).
local WIN_W, WIN_H = 800, 620
local MARGIN = 24
local INNER_W = WIN_W - 2 * MARGIN -- 752

local TITLE_Y = 10
local TAB_Y, TAB_H = 48, 34
local BODY_Y = 92
local LABEL_H = 16
local FIELD_H = 30
local FIELD_GAP = 20 -- label top -> field top

-- Ingredients tab.
local ING_FIELD_Y = BODY_Y + FIELD_GAP -- 112 (label at BODY_Y)
local ING_LIST_Y = ING_FIELD_Y + FIELD_H + 8 -- 150
local ING_PAGE_Y = WIN_H - 40 -- 580
local ING_ROW_H = 44
local ING_LIST_H = ING_PAGE_Y - ING_LIST_Y -- 430 -> 9 rows/page

-- Shopping Planner tab.
local PLAN_HDR_Y = BODY_Y + 32 -- 124
local PLAN_LABEL_Y = PLAN_HDR_Y + 28 -- 152
local PLAN_FIELD_Y = PLAN_LABEL_Y + FIELD_GAP -- 172
local PLAN_LIST_Y = PLAN_FIELD_Y + FIELD_H + 8 -- 210
local PLAN_PAGE_Y = WIN_H - 36 -- 584
local EFF_W = 350
local MERCH_X = MARGIN + EFF_W + 24 -- 398
local MERCH_W = WIN_W - MARGIN - MERCH_X -- 378
local EFF_ROW_H = 24 -- 16 rows/page
local MERCH_ROW_H = 60 -- 6 rows/page

-- Vertical bands (window-local y) covered by the list element. No interactive
-- frame widget sits inside a band, so the list element may consume clicks in
-- its empty areas harmlessly.
local ING_REGION_TOP, ING_REGION_BOT = ING_LIST_Y, ING_PAGE_Y + 32
local PLAN_REGION_TOP, PLAN_REGION_BOT = PLAN_LIST_Y, PLAN_PAGE_Y + 30

--- Immersive Mode: filter UI to discovered ingredients. Read live so an
-- in-game settings toggle applies on the next rebuild; nil (unset) = on.
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
    ingOffset = 0,
    effOffset = 0,
    merchOffset = 0,
}

--- UiElements from ui.create; nil while the window is closed. The frame
-- (chrome, labels, search fields) and the list region are separate
-- elements: live filtering rebuilds only the list element, so a focused TextEdit in
-- the frame keeps keyboard focus (destroying/updating its own tree would
-- detach the MyGUI EditBox and drop focus).
local frameEl = nil
local listEl = nil

-- Forward declarations: interaction callbacks reference these before their
-- definitions below (closures resolve lexically at compile time).
local rebuild
local rebuildList

-- ---------------------------------------------------------------------------
-- Layout helpers (absolute positioning, Squire-style)
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
    if o.alignV then
        props.textAlignV = o.alignV
    end
    local t = { type = ui.TYPE.Text, props = props }
    local tpl = templates().textNormal
    if tpl then
        t.template = tpl
    end
    return t
end

--- Native-looking button: bordered container + centered label.
local function button(x, y, w, h, label, callback, enabled, color)
    enabled = enabled ~= false
    local t = {
        type = ui.TYPE.Container,
        props = {
            position = v2(x, y),
            size = v2(w, h),
            propagateEvents = false,
        },
        content = ui.content{
            text(label, {
                x = 2,
                y = 2,
                w = w - 4,
                h = h - 4,
                size = 15,
                color = enabled and (color or C_GOLD) or C_DIM,
                alignH = ALIGN_CENTER,
                alignV = ALIGN_CENTER,
            }),
        },
    }
    local tpl = templates().boxTransparentThick or templates().boxThick
    if tpl then
        t.template = tpl
    end
    if enabled then
        t.events = { mouseClick = async:callback(callback) }
    end
    return t
end

--- Bordered row background (thin border, like the Squire shop rows).
local function rowBox(x, y, w, h)
    local t = {
        type = ui.TYPE.Container,
        props = { position = v2(x, y), size = v2(w, h) },
    }
    local tpl = templates().boxTransparent or templates().box
    if tpl then
        t.template = tpl
    end
    return t
end

--- Labeled, bordered search field: gold label above a TextEdit wrapped in
-- a thin-border box (the engine has no native bordered-field template).
-- Typing re-filters live on every keystroke: only the list element is
-- rebuilt, so this TextEdit (in the frame element) keeps keyboard focus.
local function searchField(x, y, w, label, getState, setState)
    local box = rowBox(x, y + FIELD_GAP, w, FIELD_H)
    box.content = ui.content{
        {
            type = ui.TYPE.TextEdit,
            props = {
                position = v2(2, 2),
                size = v2(w - 6, FIELD_H - 6),
                autoSize = false,
                text = getState(),
                textSize = 15,
                textColor = C_WHITE,
            },
            events = {
                textChanged = async:callback(function(t)
                    setState(t or '')
                    rebuildList()
                end),
            },
        },
    }
    return {
        text(label, { x = x, y = y, w = 200, h = LABEL_H, size = 14, color = C_GOLD }),
        box,
    }
end

local function pageCount(n, perPage)
    return math.max(1, math.ceil((n or 0) / perPage))
end

local function clampOffset(offset, n, perPage)
    local maxOff = math.max(0, n - perPage)
    return math.max(0, math.min(maxOff, offset or 0))
end

-- ---------------------------------------------------------------------------
-- Data shaping (shared by the rebuild pass)
-- ---------------------------------------------------------------------------

local function ingredientList()
    local list = db.getIngredientList(immersiveMode())
    local q = state.ingSearch:lower()
    if q ~= '' then
        local names = db.getEffectNames()
        local filtered = {}
        for _, item in ipairs(list) do
            if (item.name or ''):lower():find(q, 1, true) then
                filtered[#filtered + 1] = item
            else
                -- Also match any effect display name on the ingredient.
                for _, key in ipairs(item.effects or {}) do
                    if db.formatEffectName(key, names):lower():find(q, 1, true) then
                        filtered[#filtered + 1] = item
                        break
                    end
                end
            end
        end
        list = filtered
    end
    return list
end

local function effectList()
    local names = db.getEffectNames()
    local items = {}
    for _, key in ipairs(db.getEffectList(immersiveMode())) do
        items[#items + 1] = { key = key, name = db.formatEffectName(key, names) }
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
-- Ingredients tab content
-- ---------------------------------------------------------------------------

local function ingredientRow(item, y, counts, names)
    local effNames = {}
    for _, key in ipairs(item.effects or {}) do
        effNames[#effNames + 1] = db.formatEffectName(key, names)
    end
    table.sort(effNames)
    local n = counts[item.id] or 0

    local box = rowBox(0, y, INNER_W - 4, ING_ROW_H - 4)
    local kids = {}
    -- Guard: a bad icon path must not kill the whole window rebuild.
    local ok, tex = pcall(ui.texture, { path = item.icon })
    if ok and tex then
        kids[#kids + 1] = {
            type = ui.TYPE.Image,
            props = {
                position = v2(2, 1),
                size = v2(36, 36),
                resource = tex,
            },
        }
    end
    kids[#kids + 1] = text(item.name, { x = 46, y = 2, w = 560, h = 18, size = 17, color = C_WHITE })
    kids[#kids + 1] = text(table.concat(effNames, ', '), { x = 46, y = 21, w = 560, h = 17, size = 14, color = C_DIM })
    kids[#kids + 1] = text(n .. (n == 1 and ' merchant' or ' merchants'), { x = 616, y = 21, w = 128, h = 17, size = 14, color = C_DIM })
    box.content = ui.content(kids)
    return box
end

local function buildIngredientsList()
    local perPage = math.max(1, math.floor(ING_LIST_H / ING_ROW_H))
    local list = ingredientList()
    state.ingOffset = clampOffset(state.ingOffset, #list, perPage)

    local counts = db.restockCounts()
    local names = db.getEffectNames()
    local rows = {}
    for i = state.ingOffset + 1, math.min(#list, state.ingOffset + perPage) do
        rows[#rows + 1] = ingredientRow(list[i], (i - 1 - state.ingOffset) * ING_ROW_H, counts, names)
    end
    if #rows == 0 then
        rows[1] = text('(none)', { x = 8, y = 8, w = 200, h = 20, size = 16, color = C_DIM })
    end

    -- Child coordinates are relative to the list element's origin
    -- (window-local y = ING_REGION_TOP).
    local wheelArea = {
        type = ui.TYPE.Container,
        props = { position = v2(MARGIN, 0), size = v2(INNER_W, ING_LIST_H) },
        events = {
            mouseWheel = async:callback(function(e)
                state.ingOffset = clampOffset(
                    state.ingOffset + (e and e.delta and e.delta.y > 0 and -1 or 1), #list, perPage)
                rebuildList()
            end),
        },
        content = ui.content(rows),
    }

    local pages = pageCount(#list, perPage)
    local page = math.floor(state.ingOffset / perPage) + 1
    local out = { wheelArea }
    local pageY = ING_PAGE_Y - ING_LIST_Y
    out[#out + 1] = button(MARGIN, pageY, 90, 32, 'PREVIOUS', function()
        state.ingOffset = clampOffset(state.ingOffset - perPage, #list, perPage)
        rebuildList()
    end, page > 1)
    out[#out + 1] = text('Page ' .. page .. ' of ' .. pages, { x = MARGIN + 100, y = pageY + 5, w = INNER_W - 290, h = 24, size = 15, color = C_GOLD })
    out[#out + 1] = button(WIN_W - MARGIN - 90, pageY, 90, 32, 'NEXT', function()
        state.ingOffset = clampOffset(state.ingOffset + perPage, #list, perPage)
        rebuildList()
    end, page < pages)
    return out
end

-- ---------------------------------------------------------------------------
-- Shopping Planner tab content
-- ---------------------------------------------------------------------------

local function effectRow(item, y)
    local sel = state.selectedEffects[item.key] == true
    local box = rowBox(0, y, EFF_W - 4, EFF_ROW_H - 2)
    box.content = ui.content{
        text((sel and '[X] ' or '[ ] ') .. item.name, {
            x = 8,
            y = 1,
            w = EFF_W - 20,
            h = 20,
            size = 15,
            color = sel and C_WHITE or C_GOLD,
        }),
    }
    box.events = {
        mouseClick = async:callback(function()
            if state.selectedEffects[item.key] then
                state.selectedEffects[item.key] = nil
            else
                state.selectedEffects[item.key] = true
            end
            rebuildList() -- rows + merchant list both live in the list element
        end),
    }
    -- propagateEvents stays on: the wheel handler lives on the list container
    -- (an ancestor), so mouseWheel over a row must reach it.
    return box
end

local function merchantRow(m, y)
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
    local box = rowBox(0, y, MERCH_W - 4, MERCH_ROW_H - 4)
    box.content = ui.content{
        text(m.name, { x = 8, y = 2, w = MERCH_W - 20, h = 18, size = 17, color = C_WHITE }),
        text(m.location or 'unknown location', { x = 8, y = 22, w = MERCH_W - 20, h = 16, size = 14, color = C_DIM }),
        text(line ~= '' and line or '(no matching ingredients)', { x = 8, y = 40, w = MERCH_W - 20, h = 15, size = 13, color = C_DIM }),
    }
    return box
end

local function buildPlannerList()
    local effPerPage = math.max(1, math.floor((PLAN_PAGE_Y - PLAN_LIST_Y) / EFF_ROW_H))
    local merchPerPage = math.max(1, math.floor((PLAN_PAGE_Y - PLAN_LIST_Y) / MERCH_ROW_H))
    local effects = effectList()
    local merchants = merchantList()
    state.effOffset = clampOffset(state.effOffset, #effects, effPerPage)
    state.merchOffset = clampOffset(state.merchOffset, #merchants, merchPerPage)

    local effRows = {}
    for i = state.effOffset + 1, math.min(#effects, state.effOffset + effPerPage) do
        effRows[#effRows + 1] = effectRow(effects[i], (i - 1 - state.effOffset) * EFF_ROW_H)
    end
    if #effRows == 0 then
        effRows[1] = text('(none)', { x = 8, y = 4, w = 200, h = 20, size = 15, color = C_DIM })
    end

    local merchRows = {}
    for i = state.merchOffset + 1, math.min(#merchants, state.merchOffset + merchPerPage) do
        merchRows[#merchRows + 1] = merchantRow(merchants[i], (i - 1 - state.merchOffset) * MERCH_ROW_H)
    end
    if #merchRows == 0 then
        merchRows[1] = text('(none)', { x = 8, y = 4, w = 200, h = 20, size = 15, color = C_DIM })
    end

    local effPages = pageCount(#effects, effPerPage)
    local effPage = math.floor(state.effOffset / effPerPage) + 1
    local merchPages = pageCount(#merchants, merchPerPage)
    local merchPage = math.floor(state.merchOffset / merchPerPage) + 1

    -- Child coordinates are relative to the list element's origin
    -- (window-local y = PLAN_REGION_TOP).
    local pageY = PLAN_PAGE_Y - PLAN_LIST_Y
    return {
        {
            type = ui.TYPE.Container,
            props = { position = v2(MARGIN, 0), size = v2(EFF_W, PLAN_PAGE_Y - PLAN_LIST_Y) },
            events = {
                mouseWheel = async:callback(function(e)
                    state.effOffset = clampOffset(
                        state.effOffset + (e and e.delta and e.delta.y > 0 and -1 or 1), #effects, effPerPage)
                    rebuildList()
                end),
            },
            content = ui.content(effRows),
        },
        {
            type = ui.TYPE.Container,
            props = { position = v2(MERCH_X, 0), size = v2(MERCH_W, PLAN_PAGE_Y - PLAN_LIST_Y) },
            events = {
                mouseWheel = async:callback(function(e)
                    state.merchOffset = clampOffset(
                        state.merchOffset + (e and e.delta and e.delta.y > 0 and -1 or 1), #merchants, merchPerPage)
                    rebuildList()
                end),
            },
            content = ui.content(merchRows),
        },
        button(MARGIN, pageY, 70, 30, '<', function()
            state.effOffset = clampOffset(state.effOffset - effPerPage, #effects, effPerPage)
            rebuildList()
        end, effPage > 1),
        text('Page ' .. effPage .. ' of ' .. effPages, { x = MARGIN + 76, y = pageY + 5, w = 180, h = 22, size = 14, color = C_GOLD }),
        button(MARGIN + 270, pageY, 70, 30, '>', function()
            state.effOffset = clampOffset(state.effOffset + effPerPage, #effects, effPerPage)
            rebuildList()
        end, effPage < effPages),
        button(MERCH_X, pageY, 70, 30, '<', function()
            state.merchOffset = clampOffset(state.merchOffset - merchPerPage, #merchants, merchPerPage)
            rebuildList()
        end, merchPage > 1),
        text('Page ' .. merchPage .. ' of ' .. merchPages, { x = MERCH_X + 76, y = pageY + 5, w = 180, h = 22, size = 14, color = C_GOLD }),
        button(MERCH_X + 270, pageY, 70, 30, '>', function()
            state.merchOffset = clampOffset(state.merchOffset + merchPerPage, #merchants, merchPerPage)
            rebuildList()
        end, merchPage < merchPages),
    }
end

-- ---------------------------------------------------------------------------
-- Frame build: chrome, labels and search fields. Rebuilt only on open and
-- tab switch — never while a search field is focused.
-- ---------------------------------------------------------------------------

local function tabButton(x, w, label, name)
    local active = state.tab == name
    return button(x, TAB_Y, w, TAB_H, label, function()
        if not active then
            state.tab = name
            rebuild()
        end
    end, true, active and C_GOLD or C_DIM)
end

local function buildFrameContent()
    local c = {
        text('ALCHEMIST\'S ALMANAC', { x = MARGIN, y = TITLE_Y, w = 560, h = 30, size = 22, color = C_GOLD }),
        button(WIN_W - MARGIN - 90, TITLE_Y + 2, 90, 32, 'CLOSE', function()
            api.hide()
        end),
        tabButton(MARGIN, 250, 'INGREDIENTS', 'ingredients'),
        tabButton(MARGIN + 258, 250, 'SHOPPING PLANNER', 'planner'),
    }
    if state.tab == 'ingredients' then
        for _, item in ipairs(searchField(MARGIN, BODY_Y, INNER_W, 'SEARCH',
            function() return state.ingSearch end,
            function(t) state.ingSearch = t end)) do
            c[#c + 1] = item
        end
    else
        -- Strict Mode toggle (Squire-style [X] marker; session-only).
        c[#c + 1] = {
            type = ui.TYPE.Text,
            props = {
                position = v2(MARGIN, BODY_Y),
                size = v2(220, 24),
                autoSize = false,
                text = (state.strict and '[X] ' or '[ ] ') .. 'STRICT MODE',
                textSize = 16,
                textColor = state.strict and C_GOLD or C_DIM,
                textShadow = true,
            },
            events = {
                mouseClick = async:callback(function()
                    state.strict = not state.strict
                    rebuild()
                end),
            },
        }
        c[#c + 1] = text('EFFECTS', { x = MARGIN, y = PLAN_HDR_Y, w = EFF_W, h = 24, size = 18, color = C_GOLD })
        c[#c + 1] = text('MERCHANTS', { x = MERCH_X, y = PLAN_HDR_Y, w = MERCH_W, h = 24, size = 18, color = C_GOLD })
        for _, item in ipairs(searchField(MARGIN, PLAN_LABEL_Y, EFF_W, 'FILTER EFFECTS',
            function() return state.effSearch end,
            function(t) state.effSearch = t end)) do
            c[#c + 1] = item
        end
        for _, item in ipairs(searchField(MERCH_X, PLAN_LABEL_Y, 260, 'FILTER MERCHANTS',
            function() return state.merchFilter end,
            function(t) state.merchFilter = t end)) do
            c[#c + 1] = item
        end
        c[#c + 1] = button(MERCH_X + 268, PLAN_FIELD_Y, 52, 28, 'NAME', function()
            state.merchSort = 'name'
            rebuild()
        end, true, state.merchSort == 'name' and C_GOLD or C_DIM)
        c[#c + 1] = button(MERCH_X + 326, PLAN_FIELD_Y, 52, 28, 'LOC', function()
            state.merchSort = 'location'
            rebuild()
        end, true, state.merchSort == 'location' and C_GOLD or C_DIM)
    end
    -- Invisible placeholder occupying the list band. The frame window sizes
    -- from its content; without this the empty band collapses and the frame
    -- renders smaller than the list element overlaid on it. Slot coordinates
    -- are inset 4px (thick border) from the window, so offset by -4 to make
    -- the placeholder's window-space extent match the list element exactly.
    local top, bot = state.tab == 'ingredients'
        and ING_REGION_TOP or PLAN_REGION_TOP,
        state.tab == 'ingredients' and ING_REGION_BOT or PLAN_REGION_BOT
    c[#c + 1] = {
        type = ui.TYPE.Widget,
        props = { position = v2(-4, top - 4), size = v2(WIN_W + 8, bot - top) },
    }
    return c
end

--- Rebuild only the list element (rows + page bar). Runs on every
-- keystroke, row click and page change; the frame element — including any
-- focused TextEdit — is left untouched so typing keeps keyboard focus.
local rebuildingList = false
function rebuildList()
    if not state.visible or rebuildingList then
        return
    end
    rebuildingList = true
    local ok, err = pcall(function()
        if listEl then
            listEl:destroy()
            listEl = nil
        end
        -- The band for the active tab (window-local y), full window width.
        local top, bot = state.tab == 'ingredients'
            and ING_REGION_TOP or PLAN_REGION_TOP,
            state.tab == 'ingredients' and ING_REGION_BOT or PLAN_REGION_BOT
        local regionH = bot - top
        -- Aligned with the frame using relativePosition + anchor only (the
        -- same mechanism that centers the frame — no absolute position, which
        -- interacts unreliably with size on root elements). The band spans the
        -- full window width and is centered like the frame, so anchor_x = 0.5;
        -- anchor_y shifts it down so its top-left lands at window-local (0, top).
        listEl = ui.create({
            layer = 'Windows',
            type = ui.TYPE.Container,
            props = {
                relativePosition = v2(0.5, 0.5),
                anchor = v2(0.5, (WIN_H / 2 - top) / regionH),
                size = v2(WIN_W, regionH),
            },
            content = ui.content(state.tab == 'ingredients' and buildIngredientsList() or buildPlannerList()),
        })
    end)
    rebuildingList = false
    if not ok then
        error(err, 0)
    end
end

-- Full rebuild: frame + list. Used on open and tab switch. Reentrancy guard:
-- a nested pass would destroy/create elements mid-flight.
local rebuilding = false
function rebuild()
    if not state.visible or rebuilding then
        return
    end
    rebuilding = true
    local ok, err = pcall(function()
        if frameEl then
            frameEl:destroy()
            frameEl = nil
        end
        local t = {
            layer = 'Windows',
            type = ui.TYPE.Container,
            props = {
                relativePosition = v2(0.5, 0.5),
                anchor = v2(0.5, 0.5),
                size = v2(WIN_W, WIN_H),
            },
            content = ui.content(buildFrameContent()),
        }
        local tpl = templates().boxTransparentThick or templates().boxThick
        if tpl then
            t.template = tpl
        end
        frameEl = ui.create(t)
        rebuildList()
    end)
    rebuilding = false
    if not ok then
        error(err, 0)
    end
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

function api.show()
    if state.visible then
        return
    end
    state.visible = true
    reconcilePause()
    rebuild() -- fresh data on open (spec: refresh on open)
end

function api.hide()
    if not state.visible then
        return
    end
    state.visible = false
    if frameEl then
        frameEl:destroy()
        frameEl = nil
    end
    if listEl then
        listEl:destroy()
        listEl = nil
    end
    reconcilePause()
end

function api.destroy()
    api.hide()
end

function api.isVisible()
    return state.visible
end

--- Global event UiModeChanged {oldMode, newMode, arg}: fires on every mode
-- stack change, including Esc closing a mode from the engine side. When all
-- modes are gone our window is orphaned (visible but uninteractable) — close
-- it. Our own show/hide never match: by the time their mode change event
-- lands, state.visible has already been flipped.
function api.onUiModeChanged(data)
    if state.visible and data and data.newMode == nil then
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
