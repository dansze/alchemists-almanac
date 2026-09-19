# OpenMW 0.50+ Sandbox & Serialization Constraints

> **Source:** All constraints below are sourced from `docs/openmw-lua-api-reference.md`, which documents OpenMW **0.50 and later**. Items not found in that reference are explicitly flagged as **unverified in OpenMW 0.50+ documentation**.

> **Entry-point script:** Discovered from the `.omwscripts` manifest (`alchemy-helper.omwscripts` via the `GLOBAL:` flag) as `scripts/alchemy-helper/init.lua`. Syntax-validated via `luac -p` (see VERIFY output below).

---

## 1. Lua Version & Runtime

OpenMW embeds **Lua 5.1** with selective back-ports from **Lua 5.2** and **Lua 5.3**. No plans exist to upgrade beyond Lua 5.1 due to LuaJIT compatibility.

---

## 2. Allowed Standard Libraries

The allowed standard library modules are listed below.

| Library | Available | Notes |
|---------|-----------|-------|
| `coroutine` | ✅ Yes | Full library |
| `math` | ✅ Yes | `math.randomseed` is **blocked** — the engine calls this on startup |
| `string` | ✅ Yes | Full library, plus Lua 5.2 extensions (see §3) |
| `table` | ✅ Yes | Full library, plus `table.unpack` alias (see §3) |
| `os` | ⚠️ Partial | Only `os.date`, `os.difftime`, `os.time` are available |

**Not available:** `io`, `file` — I/O operations are prohibited.

---

## 3. Allowed Basic Functions

The following 17 functions are available:

```
assert, error, ipairs, next, pairs, pcall, print, select,
tonumber, tostring, type, unpack, xpcall, rawequal, rawget,
rawset, getmetatable, setmetatable
```

### 3.1 `loadstring` Status

**`loadstring` is unavailable** in the OpenMW Lua sandbox. It is **not** listed among the allowed basic functions. This means dynamic code execution from strings is prohibited.

### 3.2 `debug` Library

The `debug` library is **not available**. Mod authors cannot inspect the call stack, set hooks, or access upvalues from within sandboxed code.

---

## 4. Lua 5.2 Extensions

The following Lua 5.2 features are supported:

| Feature | Details |
|---------|---------|
| `goto` and `::labels::` | Label-based jumps, no `do … end` nesting penalty |
| Hex escapes | `\x3F` and `\*` escape sequences in strings |
| `math.log(x [,base])` | Two-argument logarithm |
| `string.rep(s, n [,sep])` | Third argument `sep` is optional |
| `string.format()` | `%q` is reversible; `%s` uses `__tostring`; `%a` and `%A` added |
| String matching | `%g` pattern available |
| `__pairs` metamethod | Custom iteration order via metatable |
| `__ipairs` metamethod | Custom sequential iteration via metatable |
| `table.unpack` | Alias to Lua 5.1 `unpack` |

---

## 5. Lua 5.3 Extensions

| Feature | Details |
|---------|---------|
| `utf8` library | All functions in the UTF-8 Library are available |

---

## 6. Prohibited Operations

| Operation | Status | Notes |
|-----------|--------|-------|
| Loading DLLs (`.dll`, `.so`, `.dylib`) | ❌ Prohibited | `package.loadlib` is unavailable |
| Precompiled `.luac` files | ❌ Prohibited | Only raw `.lua` source is accepted |
| `loadstring` | ❌ Prohibited | Dynamic code execution is blocked |
| `io.*` / `file.*` | ❌ Prohibited | No file I/O |
| `os.execute`, `os.remove`, `os.setlocale`, `os.getenv` | ❌ Prohibited | Only `os.date`, `os.time`, `os.difftime` are available |
| `debug` library | ❌ Prohibited | No introspection |

---

## 7. Hot Reloading: `reloadlua`

Run `reloadlua` in the in-game console to reload all Lua scripts. This restarts scripts using their `onSave`/`onLoad` handlers as if the game were saved and loaded.

**Behavioral distinction:**

- **GLOBAL and LOAD context scripts:** `reloadlua` reloads all `.lua` files not packed into archives. Scripts restart as if going through a save/load cycle.
- **LOAD context (0.51.0+):** Scripts in the `load` context do **not** re-run after `reloadlua`; a full game restart is required.
- **Archived scripts:** `.omwaddon` files and scripts packed into BSA archives require a full game restart (not affected by `reloadlua`).

---

## 8. Serialization Constraints for `onSave()` and `onLoad()`

### 8.1 Serializable Types

The following data shapes may be returned by `onSave()` and will be persisted to disk, then passed to `onLoad(data)` on load:

| Type | Serializable? | Notes |
|------|---------------|-------|
| `nil` | ✅ Yes | |
| Numbers (integers, floats) | ✅ Yes | |
| Strings | ✅ Yes | |
| Game objects | ✅ Yes | |
| `util.vector3` values | ✅ Yes | |
| Plain tables | ✅ Yes | Only if all keys and values are themselves serializable |

Tables with serializable keys and values will be recursively serialized. The engine reconstructs the table structure on `onLoad()`.

**Practical example:** Store effect IDs as integers and ingredient IDs as strings, then reconstruct effect objects on `onLoad()`.

### 8.2 Non-Serializable Types

The following data shapes **cannot** be persisted across save/load cycles:

| Type | Status | Notes |
|------|--------|-------|
| Functions | ❌ No | Cannot be serialized |
| Tables with custom metatables | ❌ No | Metatable information is lost |
| Tables with multiple references to the same table | ❌ No | Shared references are not preserved |
| Circular references | ❌ No | Will cause errors during serialization |

### 8.3 Engine Handlers Involved

| Handler | Context | Description |
|---------|---------|-------------|
| `onSave()` | all | Called on game save; **must return a serializable table** |
| `onLoad(data)` | all | Called on game load; `data` is the value returned by `onSave()` from the save file |

Other handlers that may be relevant to persistence workflows:

| Handler | Context | Description |
|---------|---------|-------------|
| `onActivated()` | local | Object was activated; may trigger state changes worth preserving |
| `onObjectAdded(object)` | local | Object was added (to inventory); may trigger state changes worth preserving |

### 8.4 Unverified Constraints

The following limits are **unverified in OpenMW 0.50+ documentation**. Mod authors should empirically test these boundaries in their target OpenMW version:

| Constraint | Status |
|------------|--------|
| **Payload size limits** (maximum bytes per `onSave()` return table) | 🔍 **unverified in OpenMW 0.50+ documentation** |
| **Nesting depth limits** (maximum table nesting level) | 🔍 **unverified in OpenMW 0.50+ documentation** |
| **Key count limits** (maximum number of keys per serialized table) | 🔍 **unverified in OpenMW 0.50+ documentation** |
| **Exact serialization format** (binary? msgpack? custom?) | 🔍 **unverified in OpenMW 0.50+ documentation** |

### 8.5 Inter-Script Communication via `interfaces.AlchemyHelper.queryEffects(ids)`

When designing inter-script communication, consider serialization implications:

- Interface methods (e.g., `interfaces.AlchemyHelper.queryEffects(ids)`) are **live runtime calls**, not persisted data. The arguments and return values of interface calls must be serializable types if the calling context is subject to save/load (e.g., a script that persists its interface registry).
- Interface data is resolved at runtime via `require('openmw.interfaces')`. It is not saved into game saves.

### 8.6 Save Storage Alternative: `openmw.storage`

OpenMW provides the `openmw.storage` package as an explicit persistence API:

```lua
local storage = require('openmw.storage')
storage.set('key', serializable_value)
local value = storage.get('key')
```

This is separate from the `onSave()`/`onLoad()` mechanism and may have different constraints. Consult the API reference for details.

---

## 9. Script Contexts and Handler Availability

| Handler | GLOBAL | MENU | LOCAL | PLAYER | LOAD |
|---------|--------|------|-------|--------|------|
| `onUpdate(dt)` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `onSave()` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `onLoad(data)` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `onInit()` | — | — | ✅ | ✅ | — |
| `onActivated()` | — | — | ✅ | — | — |
| `onObjectAdded(object)` | — | — | ✅ | — | — |
| `onKeyPress(key)` | — | — | — | ✅ | — |
| `onDialogueResponse(response)` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `onAnimationEnd(animId)` | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 10. Entry-Point Script Verification

**Discovered from `alchemy-helper.omwscripts`** (via the `GLOBAL:` flag):

- **Entry-point path:** `scripts/alchemy-helper/init.lua`
- **Syntax check:** `luac -p scripts/alchemy-helper/init.lua` — **passes**

The entry-point script is a valid Lua 5.1 module that returns a table with an `engineHandlers` field containing a no-op `onUpdate` function.

---

## 11. Quick Reference: Identifiers in This Mod

All concrete identifiers from the mod plan that appear in constraints sections:

| Identifier | Context | Section |
|------------|---------|---------|
| `onSave()` | Engine handler, serialization | §8.3, §8.6 |
| `onLoad(data)` | Engine handler, serialization | §8.3, §8.6 |
| `onActivated()` | Engine handler, local context | §8.3, §9 |
| `onObjectAdded(object)` | Engine handler, local context | §8.3, §9 |
| `interfaces.AlchemyHelper.queryEffects(ids)` | Inter-script interface | §8.5 |
| `reloadlua` | Console command, hot reload | §7 |
| OpenMW 0.50+ | Target runtime version | Header, all sections |

---

## 12. Summary: What's Blocked vs. What's Allowed

| Category | Allowed | Blocked / Restricted |
|----------|---------|----------------------|
| Lua version | Lua 5.1 + Lua 5.2 subset + Lua 5.3 `utf8` | Lua 5.4, LuaJIT-specific constructs |
| Basic functions | 17 listed in §3 | `loadstring` (not available) |
| Standard libs | `coroutine`, `math`, `string`, `table`, partial `os` | `io`, `file` |
| Metatables | `getmetatable`, `setmetatable` (basic ops) | Custom metatables not serializable (§8.2) |
| Dynamic code | `goto`, hex escapes, `__pairs`/`__ipairs` | `loadstring`, DLL loading, `.luac` |
| Serialization | `nil`, numbers, strings, game objects, `util.vector3`, plain tables | Functions, custom metatables, shared refs, circular refs |
| Size/depth/key limits | — | 🔍 **unverified in OpenMW 0.50+ documentation** |

---

*Document version: 1.0 | Source: `docs/openmw-lua-api-reference.md` | Target: OpenMW 0.50+*
