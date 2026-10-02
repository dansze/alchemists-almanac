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
package.preload['openmw.storage'] = function()
    return {
        playerSection = function(name)
            stored[name] = stored[name] or {}
            local data = stored[name]
            return { get = function(self, k) return data[k] end }
        end,
    }
end

-- No openmw.interfaces.UIToolkit: the no-toolkit fallback path.
package.preload['openmw.interfaces'] = function()
    return { UI = { getMode = function() return nil end } }
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
