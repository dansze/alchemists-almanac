# Sandbox & Serialization Constraints

> **Scope:** OpenMW 0.50+ embedded Lua interpreter.
>
> **Source:** All constraints are sourced from `docs/openmw-lua-api-reference.md` unless explicitly marked as unverified.

---

## 1. Lua Runtime

The OpenMW interpreter embeds **Lua 5.1** with selected extensions from **Lua 5.2** and **Lua 5.3**. No plans exist to upgrade beyond Lua 5.1 because of LuaJIT compatibility.

### 1.1 Allowed Standard Library (permitted modules)

| Library | Restrictions |
|---------|-------------|
| `coroutine` | Full access |
| `math` | `math.randomseed` is blocked — the engine calls it on startup |
| `string` | Full access |
| `table` | Full access |
| `os` | Only `os.date`, `os.difftime`, `os.time` are available. `os.execute`, `os.exit`, `os.setlocale` are blocked. |

### 1.2 Allowed Basic Functions

The following functions are available at the top level:

```
assert, error, ipairs, next, pairs, pcall, print, select,
tonumber, tostring, type, unpack, xpcall, rawequal,
rawget, rawset, getmetatable, setmetatable
```

### 1.3 Unavailable Basic Functions

- **`loadstring`** — unavailable. It is not listed among the allowed basic functions.
- **`dofile`** — unavailable.
- **`require`** — restricted to the OpenMW API packages only; the standard Lua module loader is not available.

### 1.4 Lua 5.2 Extensions (Supported)

| Feature | Notes |
|---------|-------|
| `goto` / `::labels::` | Jump labels supported |
| Hex escapes `\x3F` | In string literals |
| `\*` escape | In string literals |
| `math.log(x [,base])` | Two-argument logarithm |
| `string.rep(s, n [,sep])` | Third argument `sep` is optional |
| `string.format` `%q` | Reversible — output round-trips to the original string |
| `string.format` `%s` | Uses `__tostring` metamethod |
| `string.format` `%a`, `%A` | Hexadecimal float format specifiers |
| String matching `%g` | General category pattern |
| `__pairs` metamethod | Custom iterator for `pairs()` |
| `__ipairs` metamethod | Custom iterator for `ipairs()` |
| `table.unpack` | Alias to Lua 5.1 `unpack` |

### 1.5 Lua 5.3 Extensions (Supported)

| Feature | Notes |
|---------|-------|
| `utf8` library | All functions in the UTF-8 library are available |

### 1.6 Prohibited Operations

- Loading DLLs is prohibited.
- Loading precompiled Lua files (`.luac`) is prohibited.
- The `debug` library is **not available**. No introspection, profiling, or stack manipulation is possible.

---

## 2. Serialization: `onSave()` and `onLoad()`

### 2.1 Overview

Every script context supports the `onSave()` and `onLoad()` engine handlers:

- **`onSave()`** — Called on game save. Must return a serializable table.
- **`onLoad(data)`** — Called on game load. `data` is the value returned by `onSave()` from the save file.

These handlers exist on all script contexts: global, menu, local, player, and load.

### 2.2 Serializable Types

The following types may appear in the value returned by `onSave()` and will survive save/load:

| Type | Notes |
|------|-------|
| `nil` | Always serializable |
| Numbers | Integers and floats |
| Strings | UTF-8 strings |
| Game objects | RefNums / form references (e.g. items, actors, cells) |
| `util.vector3` | 3D vector values |
| Tables | Only if all keys and all values are themselves serializable |

### 2.3 Non-Serializable Types

The following types **cannot** be persisted through `onSave()` / `onLoad()`:

| Type | Notes |
|------|-------|
| Functions | Closures, builtin functions, anything callable |
| Tables with custom metatables | Any table that has a metatable set via `setmetatable` |
| Tables with multiple references to the same table | Duplicate table references break serialization |
| Circular references | Tables that reference each other (directly or transitively) |

### 2.4 Unverified Constraints

The following constraints are **unverified in OpenMW 0.50+ documentation**:

| Constraint | Status |
|-----------|--------|
| **Payload size limit** (bytes) | Unverified in OpenMW 0.50+ documentation |
| **Nesting depth limit** (table depth) | Unverified in OpenMW 0.50+ documentation |
| **Key count limit** (entries per table) | Unverified in OpenMW 0.50+ documentation |
| **Exact serialization format** (binary, MessagePack, custom) | Unverified in OpenMW 0.50+ documentation |

Mod authors should assume reasonable defaults: keep payloads under a few hundred kilobytes, limit nesting to shallow depth (≤10), and avoid exceeding a few hundred keys per table. Empirical verification requires an OpenMW 0.50+ environment.

---

## 3. Hot Reload: `reloadlua`

Running `reloadlua` in the in-game console reloads all `.lua` files not packed into archives. This restarts scripts using their `onSave()` / `onLoad()` handlers as if the game were saved and loaded.

**Important context distinction:**

- **Global** and **LOAD** context scripts are re-executed in full after `reloadlua` (LOAD scripts only up to 0.50.x; in 0.51.0+ the `load` context does **not** re-run after `reloadlua` — a full restart is required for LOAD scripts).
- Local and player scripts are re-attached to their objects.

Only uncompressed `.lua` files on disk are reloaded. Scripts in BSA archives or `.omwaddon` manifests require a full game restart.

---

## 4. Script Contexts and Entry Points

Scripts are registered via `.omwscripts` manifest files using flags such as `GLOBAL:`, `LOAD:`, `PLAYER:`, `MENU:`, `CUSTOM:`, and object-type flags (`ACTIVATOR:`, `NPC:`, etc.). The engine discovers the entry-point Lua file path from the manifest.

| Flag | Context |
|------|---------|
| `GLOBAL` | Global script; always active |
| `MENU` | Menu script; active even before loading a game |
| `CUSTOM` | Dynamic local script; started/stopped by global scripts |
| `PLAYER` | Auto-started player script |
| `LOAD` | Load script; active after content files are loaded (0.51.0+) |
| `ACTIVATOR` | Auto-attached to any activator |

### 4.1 Engine Handlers

The following engine handlers are documented as available (not exhaustive):

| Handler | Context | Description |
|---------|---------|-------------|
| `onUpdate(dt)` | all | Called every frame; `dt` is delta time |
| `onSave()` | all | Called on game save; must return serializable data |
| `onLoad(data)` | all | Called on game load; `data` is saved state |
| `onInit()` | local/player | Called when the script starts |
| `onActivated()` | local | Object was activated |
| `onSpellCast(spellId)` | local | Spell was cast |
| `onContainerClosed()` | local | Container was closed |
| `onObjectDisposed(objectId)` | local | Object was disposed |
| `onObjectAdded(object)` | local | Object was added (to inventory) |
| `onObjectRemoved(object)` | local | Object was removed (from inventory) |
| `onEquip(item)` | local | Item was equipped |
| `onUnequip(item)` | local | Item was unequipped |
| `onLevelUp()` | player | Player leveled up |
| `onInterfaceOverride(base)` | all | Another script overrides this interface |
| `onDialogueResponse(response)` | all | Dialogue response (0.51.0+) |
| `onAnimationEnd(animId)` | all | Animation end (0.51.0+) |

### 4.2 Script Interfaces

Scripts expose named interfaces for inter-script communication:

```lua
return {
  interfaceName = "AlchemyHelper",
  interface = {
    queryEffects = function(ids)
      -- implementation
    end,
  },
}
```

Access from another script:

```lua
local interfaces = require('openmw.interfaces')
interfaces.AlchemyHelper.queryEffects(ids)
```

See `interfaces.AlchemyHelper.queryEffects(ids)` as the canonical inter-script call pattern.

---

## 5. Source Attribution

All sandbox constraints and serialization rules in this document are sourced from:

- **`docs/openmw-lua-api-reference.md`** — the project's OpenMW Lua API reference (version 0.50+).
- Section 1.7 (Sandbox Restrictions) covers standard libraries, basic functions, Lua 5.2/5.3 extensions, and prohibited operations.
- Section 3.6 (Serialization Constraints for Alchemy Data) covers serializable and non-serializable types.
- Section 1.8 (Hot Reloading) covers `reloadlua` behavior.

Items not found in these sections are explicitly marked as "unverified in OpenMW 0.50+ documentation."

---

## 6. Quick Reference

### Do ✅

- Use `pcall` for error protection.
- Return plain tables from `onSave()`.
- Store complex objects (e.g. game objects) as identifiers (form IDs / record IDs) rather than object references.
- Reconstruct derived state on `onLoad()`.

### Don't ❌

- Return functions from `onSave()`.
- Store tables with metatables.
- Create circular references in save data.
- Duplicate the same table object in multiple places in the save payload.
- Assume a specific payload size — constraints are unverified.
- Assume the serialization format — it is unverified.
- Use `loadstring` to load dynamic code.
- Use `debug` library features — the library is unavailable.
- Use `os.execute` or `os.exit` — restricted.
