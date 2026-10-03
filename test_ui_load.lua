-- Standalone load check for alchemy-ui.lua. Run: lua test_ui_load.lua
-- Stubs the openmw.* modules + (absence of) UIToolkit, loads the UI module,
-- and exercises the no-toolkit fallback path. Catches load-time errors
-- (e.g. toolkit class instantiation when the toolkit is not installed).
package.path = './?.lua;' .. package.path

local created = {}
package.preload['openmw.ui'] = function()
    return {
        TYPE = { Text = 'Text', Container = 'Container', Image = 'Image', Widget = 'Widget', TextEdit = 'TextEdit' },
        ALIGNMENT = { Center = 'Center', End = 'End' },
        texture = function(o) assert(type(o.path) == 'string', 'texture needs path'); return { path = o.path } end,
        content = function(t) return t or {} end,
        create = function(spec)
            local el = {
                layout = { props = spec.props or {}, content = spec.content },
                update = function(self) end,
                destroy = function(self) self.layout = nil end,
            }
            created[#created + 1] = el
            return el
        end,
    }
end

package.preload['openmw.util'] = function()
    return {
        vector2 = function(x, y) return { x = x or 0, y = y or 0 } end,
        color = { rgb = function(r, g, b) return { r = r, g = g, b = b } end },
        round = math.round or function(n) return math.floor(n + 0.5) end,
    }
end

package.preload['openmw.async'] = function()
    return { callback = function(self, f) return f end }
end

local stored = {}
local function sectionTable(name)
    stored[name] = stored[name] or {}
    local data = stored[name]
    return {
        get = function(self, k) return data[k] end,
        set = function(self, k, v) data[k] = v end,
        asTable = function(self) return data end,
        setLifeTime = function(self, lt) end,
        subscribe = function(self, fn) end,
    }
end
package.preload['openmw.storage'] = function()
    return {
        playerSection = sectionTable,
        globalSection = sectionTable,
    }
end

-- Shared table: part 1 has no UIToolkit (fallback path), part 2 attaches
-- fakeToolkit to the SAME table (require caches the module, re-preloading
-- would be ignored).
local ifaces = { UI = {
    getMode = function() return nil end,
    setMode = function() end,
    removeMode = function() end,
} }
package.preload['openmw.interfaces'] = function()
    return ifaces
end

local ui = assert(dofile('scripts/alchemy-helper/alchemy-ui.lua'))

assert(type(ui.show) == 'function', 'missing show')
assert(type(ui.hide) == 'function', 'missing hide')
assert(type(ui.destroy) == 'function', 'missing destroy')
assert(type(ui.isVisible) == 'function', 'missing isVisible')
assert(type(ui.onUiModeChanged) == 'function', 'missing onUiModeChanged')

ui.show() -- must not error; warns once, creates nothing
assert(ui.isVisible() == false, 'should report closed without toolkit')
ui.hide() -- no-op
ui.onUiModeChanged({ newMode = nil }) -- no-op while closed

print('OK: alchemy-ui load + no-toolkit fallback checks passed')

-- ---------------------------------------------------------------------------
-- Toolkit-present path: fake I.UIToolkit + leaf modules, drive show() through
-- onOpened -> buildIngredientsContent -> rebuildIngest. Catches builders that
-- return nil (e.g. a dropped `return items`) and open-path wiring errors.
-- ---------------------------------------------------------------------------

local function makeEl(props)
    return {
        layout = { props = props or {}, content = nil },
        update = function(self) end,
        destroy = function(self) self.layout = nil end,
    }
end

local function makeComp(props)
    local comp = { element = makeEl(props or {}) }
    function comp:updateProps(p)
        for k, v in pairs(p) do self.element.layout.props[k] = v end
        return self
    end
    function comp:setDisabled(v) return self end
    function comp:setActive(v) return self end
    return comp
end

package.preload['scripts.UIToolkit.class'] = function()
    return function(base) return {} end
end
package.preload['scripts.UIToolkit.window_handler'] = function()
    return {}
end
package.preload['scripts.UIToolkit.components.list_items.text_item'] = function()
    return { new = function(self) return {} end }
end

local openedWnd = nil
local regOpts = nil
local fakeToolkit = {
    Interactive = { updateState = function() end },
    queueUpdate = function() end,
    Components = {
        textButton = function(opts) return makeComp() end,
        textEdit = function(opts) return makeComp() end,
        itemList = function(opts)
            local c = makeComp()
            function c:setItems(items) assert(type(items) == 'table', 'setItems got non-table') end
            return c
        end,
    },
    WindowManager = {
        register = function(id, opts) regOpts = opts end,
        open = function(id)
            openedWnd = {
                setContent = function(self, content) self.content = content end,
                getInnerSize = function(self) return { x = 792, y = 592 } end,
            }
            regOpts.handler:onOpened(openedWnd, nil, nil)
        end,
        close = function(id)
            if openedWnd then regOpts.handler:onClosed(openedWnd) end
            openedWnd = nil
        end,
        isOpen = function(id) return openedWnd ~= nil end,
        getCenterPositionForSize = function(sz) return { x = 0, y = 0 } end,
    },
}
ifaces.UIToolkit = fakeToolkit

local ui2 = assert(dofile('scripts/alchemy-helper/alchemy-ui.lua'))
ui2.show()
assert(ui2.isVisible() == true, 'window should be open after show()')
assert(type(openedWnd.content) == 'table', 'onOpened must set window content')
-- ingredients builder must have produced a table (empty db -> {} not nil);
-- rebuildIngest ran without error and rendered the '(none)' fallback row.
ui2.hide() -- no toolkit close side effects in the fake; just ensure no error
print('OK: alchemy-ui open-path checks passed')

-- ---------------------------------------------------------------------------
-- alchemy-binding.lua: Inventory Extender "AA" button integration.
--   1. Load with NO InventoryExtender -> nothing mounted (soft dependency).
--   2. Attach a fake IE, fire UiModeChanged -> retry mounts the button.
--   3. Click the button -> almanac toggles open/closed.
-- ---------------------------------------------------------------------------

package.preload['openmw.core'] = function()
    return { sendGlobalEvent = function() end }
end
package.preload['openmw.input'] = function()
    return {
        ACTION_TYPE = { Boolean = 'Boolean' },
        registerAction = function() end,
        registerActionHandler = function() end,
    }
end
package.preload['openmw.ambient'] = function()
    return { playSound = function() end }
end
ifaces.Settings = {
    registerPage = function() end,
    registerGroup = function() end,
}

local mountedLayouts = {}
-- No ifaces.InventoryExtender yet: first load must mount nothing.
local binding = assert(dofile('scripts/alchemy-helper/alchemy-binding.lua'))
assert(type(binding.eventHandlers.UiModeChanged) == 'function', 'missing UiModeChanged handler')
assert(#mountedLayouts == 0, 'must not mount without Inventory Extender')

-- IE appears later: getWindow returns an inventory window with an info bar.
ifaces.InventoryExtender = {
    getWindow = function(name)
        if name ~= 'Inventory' then return nil end
        return {
            infoBar = { layout = { userData = {
                addInfoLayout = function(l) mountedLayouts[#mountedLayouts + 1] = l end,
            } } },
            ctx = {},
        }
    end,
}
binding.eventHandlers.UiModeChanged({ oldMode = nil, newMode = 'Interface' })
assert(#mountedLayouts == 1, 'mode-change retry should mount the AA button')

-- The mounted layout: a 28x28 box whose left-click toggles the almanac.
local btn = mountedLayouts[1]
assert(btn.props.size.x == 28 and btn.props.size.y == 28, 'button size')
local release = btn.events.mouseRelease
assert(type(release) == 'function', 'button needs mouseRelease')

-- Find the alchemy-ui instance the binding required, via its own state:
-- clicking should flip isVisible. The binding's ui module is cached in
-- package.loaded under its require path.
local boundUI = package.loaded['scripts.alchemy-helper.alchemy-ui']
assert(type(boundUI) == 'table', 'binding must require alchemy-ui')
release({ button = 1 })
assert(boundUI.isVisible() == true, 'left click should open the almanac')
release({ button = 1 })
assert(boundUI.isVisible() == false, 'second left click should close it')
release({ button = 2 }) -- non-left clicks are ignored (still closed)
assert(boundUI.isVisible() == false, 'right click must not toggle')

print('OK: alchemy-binding IE button checks passed')
