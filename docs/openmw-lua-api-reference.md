# OpenMW Lua API Reference (0.50+)

> **Version scope:** This document covers OpenMW **0.50 and later**. Only notable API differences from earlier versions are flagged, and only where they affect how a 0.50+ mod author should write or debug code.

---

## 1. Lua Mod Loading and Initialization

### 1.1 Overview

OpenMW Lua is a scripting subsystem that runs independently of ESP/ESM content plugins. Lua scripts are not controlled by game data files; they are activated through OpenMW-specific mechanism files and registered in `openmw.cfg`.

### 1.2 Manifest Format (`.omwscripts`)

Lua scripts are registered via `.omwscripts` text files placed in the mod's data directory. Each line follows the format:

```
<flags>: <path to .lua file in virtual file system>
```

The order of lines determines script load order (priorities). Lines beginning with `#` are comments.

**Available flags:**

| Flag | Context | Description |
|------|---------|-------------|
| `GLOBAL` | global | Global script; always active, cannot be stopped |
| `MENU` | menu | Menu script; runs even before a game is loaded |
| `CUSTOM` | local | Dynamic local script; can be started/stopped by a global script |
| `PLAYER` | player | Auto-started player script (a special local script attached to the player) |
| `LOAD` | load | Load script; active while content files are being loaded (new in 0.51.0) |
| `ACTIVATOR` | local | Auto-attached to any activator |
| `ARMOR` | local | Auto-attached to any armor |
| `BOOK` | local | Auto-attached to any book |
| `CLOTHING` | local | Auto-attached to any clothing |
| `CONTAINER` | local | Auto-attached to any container |
| `CREATURE` | local | Auto-attached to any creature |
| `DOOR` | local | Auto-attached to any door |
| `INGREDIENT` | local | Auto-attached to any ingredient |
| `LIGHT` | local | Auto-attached to any light |
| `MISC_ITEM` | local | Auto-attached to any miscellaneous item |
| `NPC` | local | Auto-attached to any NPC |
| `POTION` | local | Auto-attached to any potion |
| `WEAPON` | local | Auto-attached to any weapon |
| `APPARATUS` | local | Auto-attached to any apparatus |
| `LOCKPICK` | local | Auto-attached to any lockpick |
| `PROBE` | local | Auto-attached to any probe tool |
| `REPAIR` | local | Auto-attached to any repair tool |

Multiple flags (except `GLOBAL`) may be combined on a single line using space or comma as a separator:

```
# Example: auto-attach to both potions and ingredients
POTION, INGREDIENT: scripts/my_mod/ingredient_based.lua
```

**No `.omwaddon` manifest format is currently implemented.** The documentation mentions `openmw.addon` (`omwaddon` files), but this feature was "not implemented yet" as of 0.50 and remains undocumented for 0.51.

### 1.3 Registration in `openmw.cfg`

After creating the `.omwscripts` file, register the mod in `openmw.cfg` the same way as any other data directory:

```ini
data=path/to/my_lua_mod
# or equivalently:
content=my_lua_mod.omwscripts
```

For `.omwaddon` files (future use):

```ini
content=my_lua_mod.omwaddon
```

### 1.4 Directory Structure

Recommended directory layout:

```
my_mod/
  my_mod.omwscripts          # manifest file
  scripts/
    <ModName>/
      <ScriptName>.lua       # general case
      player.lua             # player script
      global.lua             # global script
```

Alternative layouts:

- `scripts/<AuthorName>/<ModName>/<ScriptName>.lua` — if `ModName` is short and may collide
- `scripts/<ModName>.lua` — single-script mod; placed directly in `scripts/`

The directory `scripts/omw/` is reserved for built-in OpenMW scripts. Do not use it.

### 1.5 Entry Points: Script Structure

A script is a Lua file that returns a table. The engine parses this table and registers its handlers, interfaces, and events.

```lua
local util = require('openmw.util')

local function onUpdate(dt)
  -- called every frame
end

local function onSave()
  -- must return a serializable table
  return { someValue = 42 }
end

local function onLoad(data)
  -- data is the value returned by onSave from the save file
  if data then
    someValue = data.someValue
  end
end

local function myEventHandler(eventData)
  -- handle a custom event
end

return {
  interfaceName = 'MyScriptInterface',
  interface = {
    -- public functions callable by other scripts
  },
  eventHandlers = {
    MyEvent = myEventHandler,
  },
  engineHandlers = {
    onUpdate = onUpdate,
    onSave = onSave,
    onLoad = onLoad,
  },
}
```

**Minimal valid script** — if you only need per-frame logic:

```lua
return {
  engineHandlers = {
    onUpdate = function()
      print('Hello, World!')
    end,
  },
}
```

### 1.6 Script Contexts

| Context | Lifetime | Scope |
|---------|----------|-------|
| **Global** | Always active during a game session | Entire world; read-write access |
| **Menu** | Always active (even before loading a game) | Main menu, save management |
| **Local** | Only when attached object is in an active cell | Read-only access to objects outside the attached object; can only modify the attached object |
| **Player** | A special local script attached to the player | Player-specific: UI, camera, input; also all local-script capabilities |
| **Load** | Runs once after all content files are loaded (0.51.0+); exposed records as mutable data; records injected via this context are not serialized into saves | New in 0.51.0 |

### 1.7 Sandbox Restrictions

OpenMW supports **Lua 5.1** with some extensions from **Lua 5.2** and **Lua 5.3**. No plans to upgrade beyond Lua 5.1 due to LuaJIT compatibility.

**Allowed standard libraries:**
- `coroutine`
- `math` (except `math.randomseed` — the engine calls this on startup)
- `string`
- `table`
- `os` (only `os.date`, `os.difftime`, `os.time`)

**Allowed basic functions:**
`assert`, `error`, `ipairs`, `next`, `pairs`, `pcall`, `print`, `select`, `tonumber`, `tostring`, `type`, `unpack`, `xpcall`, `rawequal`, `rawget`, `rawset`, `getmetatable`, `setmetatable`

**Supported Lua 5.2 features:**
- `goto` and `::labels::`
- Hex escapes `\x3F` and `\*` escape in strings
- `math.log(x [,base])`
- `string.rep(s, n [,sep])`
- In `string.format()`: `%q` is reversible, `%s` uses `__tostring`, `%a` and `%A` are added
- String matching pattern `%g`
- `__pairs` and `__ipairs` metamethods
- `table.unpack` (alias to Lua 5.1 `unpack`)

**Supported Lua 5.3 features:**
- All functions in the UTF-8 Library

**Prohibited:** Loading DLLs and precompiled Lua files (`.luac`).

### 1.8 Hot Reloading

Run `reloadlua` in the in-game console to reload all Lua scripts. This restarts scripts using their `onSave`/`onLoad` handlers as if the game were saved and loaded. Only `.lua` files not packed into archives are reloaded. `.omwaddon` files and scripts packed into BSA archives require a full game restart.

**New in 0.51.0:** The `load` context scripts do not re-run after `reloadlua`; a full restart is required.

### 1.9 Lua Console

Enter interactive Lua mode from the in-game console:

| Command | Context |
|---------|---------|
| `lua player` / `luap` | Player context |
| `lua global` / `luag` | Global context |
| `lua selected` / `luas` | Local context on the selected object |
| `lua menu` / `luam` | Menu context |

---

## 2. Public Lua API Surface

### 2.1 Loading Packages

All API packages are loaded via `require()`:

```lua
local packageName = require('openmw.packageName')
```

Packages cannot be overloaded even if a mod defines a file with the same name.

### 2.2 API Packages (Global Scripts)

These packages are available in the **global** script context:

| Package | Description |
|---------|-------------|
| `openmw.content` | Content manipulation (load context only) |
| `openmw.core` | Functions common to all script types |
| `openmw.interfaces` | Public interfaces of other scripts |
| `openmw.markup` | API to work with markup languages |
| `openmw.storage` | Storage API; persist data between game sessions |
| `openmw.types` | Functions for specific types of game objects |
| `openmw.util` | Utility functions and classes (3D vectors) independent of the game world |
| `openmw.vfs` | Read-only access to data directories via VFS |
| `openmw.world` | Read-write access to the game world |

### 2.3 API Packages (Menu Scripts)

| Package | Description |
|---------|-------------|
| `openmw.ambient` | Controls background sounds for a player |
| `openmw.async` | Timers and callbacks |
| `openmw.core` | Functions common to all script types |
| `openmw.interfaces` | Public interfaces of other scripts |
| `openmw.markup` | API to work with markup languages |
| `openmw.menu` | Main menu functionality; manage game saves |
| `openmw.storage` | Storage API |
| `openmw.types` | Functions for specific types of game objects |
| `openmw.util` | Utility functions and classes |
| `openmw.vfs` | Read-only access to data directories via VFS |
| `openmw.world` | Read-write access to the game world (not all functions) |

### 2.4 API Packages (Local Scripts)

| Package | Description |
|---------|-------------|
| `openmw.animation` | Animation controls |
| `openmw.async` | Timers and callbacks |
| `openmw.core` | Functions common to all script types |
| `openmw.interfaces` | Public interfaces of other scripts |
| `openmw.markup` | API to work with markup languages |
| `openmw.nearby` | Read-only access to the nearest area of the game world |
| `openmw.self` | Full access to the object the script is attached to |
| `openmw.storage` | Storage API |
| `openmw.types` | Functions for specific types of game objects |
| `openmw.util` | Utility functions and classes |
| `openmw.vfs` | Read-only access to data directories via VFS |

### 2.5 API Packages (Player Scripts)

| Package | Description |
|---------|-------------|
| `openmw.ambient` | Controls background sounds for the player |
| `openmw.camera` | Controls camera |
| `openmw.core` | Functions common to all script types |
| `openmw.debug` | Collection of debug utilities |
| `openmw.input` | User input |
| `openmw.interfaces` | Public interfaces of other scripts |
| `openmw.markup` | API to work with markup languages |
| `openmw.postprocessing` | Controls post-process shaders |
| `openmw.self` | Full access to the player object |
| `openmw.storage` | Storage API |
| `openmw.types` | Functions for specific types of game objects |
| `openmw.ui` | Controls the user interface |
| `openmw.util` | Utility functions and classes |
| `openmw.vfs` | Read-only access to data directories via VFS |

### 2.6 Auxiliary Packages

Auxiliary packages (`openmw_aux.*`) are implemented in Lua. They provide no capabilities beyond the basic API but are more convenient:

| Module | Context | Description |
|--------|---------|-------------|
| `openmw_aux.calendar` | global menu local | Game time calendar |
| `openmw_aux.time` | global menu local | Timers and game time utilities |
| `openmw_aux.ui` | menu player | User interface utilities |
| `openmw_aux.util` | global menu local | Miscellaneous utilities |

### 2.7 Key Types and Objects

#### `openmw.types` — Object Type Functions

The `openmw.types` package provides functions for working with game object records:

**Type constructors (records are read-only):**

| Type | Description |
|------|-------------|
| `types.Activator` | Activators |
| `types.Actor` | Common functions for Creature, NPC, and Player |
| `types.Apparatus` | Apparatus (tools) |
| `types.Armor` | Armor |
| `types.Book` | Books (including scrolls) |
| `types.Clothing` | Clothing |
| `types.Container` | Containers |
| `types.Creature` | Creatures |
| `types.Door` | Doors |
| `types.Ingredient` | Ingredients |
| `types.Item` | All items that can be placed in an inventory or container |
| `types.Light` | Light sources |
| `types.Lockable` | Lockable objects |
| `types.Lockpick` | Lockpicks |
| `types.Miscellaneous` | Miscellaneous items |
| `types.NPC` | Non-player characters |
| `types.Player` | The player character |
| `types.Potion` | Potions |
| `types.Probe` | Probe tools |
| `types.Repair` | Repair tools |
| `types.Static` | Static world objects |
| `types.Weapon` | Weapons |
| `types.LevelledCreature` | Levelled creature lists |

**ESM4 Record types (raw record access):**

| Type | Description |
|------|-------------|
| `types.ESM4Activator` | ESM4 activator records |
| `types.ESM4Ammunition` | ESM4 ammunition records |
| `types.ESM4Armor` | ESM4 armor records |
| `types.ESM4Book` | ESM4 book records |
| `types.ESM4Clothing` | ESM4 clothing records |
| `types.ESM4Door` | ESM4 door records |
| `types.ESM4Flora` | ESM4 flora records |
| `types.ESM4Ingredient` | ESM4 ingredient records |
| `types.ESM4ItemMod` | ESM4 item modifications |
| `types.ESM4Light` | ESM4 light records |
| `types.ESM4Miscellaneous` | ESM4 miscellaneous records |
| `types.ESM4MovableStatic` | ESM4 movable static records |
| `types.ESM4Potion` | ESM4 potion records |
| `types.ESM4Static` | ESM4 static records |
| `types.ESM4StaticCollection` | ESM4 static collection records |
| `types.ESM4Terminal` | ESM4 terminal records |
| `types.ESM4Weapon` | ESM4 weapon records |

**Actor-related types:**

| Type | Description |
|------|-------------|
| `types.Actor.activeEffects(actor)` | Returns `ActorActiveEffects` — active magic effects on an actor |
| `types.Actor.activeSpells(actor)` | Returns `ActorActiveSpells` — active spells on an actor |
| `types.Actor.spells(actor)` | Returns `ActorSpells` — the actor's spell list |
| `types.Actor.stats` | Actor stats object |

**`ActorActiveEffects` methods:**

| Method | Description |
|--------|-------------|
| `ActorActiveEffects:getEffect(effectId, extraParam)` | Get a specific active effect on the actor |
| `ActorActiveEffects:modify(value, effectId, extraParam)` | Permanently modify the magnitude of an active effect |
| `ActorActiveEffects:remove(effectId, extraParam)` | Completely remove an active effect from the actor |
| `ActorActiveEffects:set(value, effectId, extraParam)` | Set an active effect (overrides all other sources) |

#### `openmw.world` — World Access (Global Scripts)

| Property/Method | Description |
|-----------------|-------------|
| `world.activeActors` | List of currently active actors |
| `world.cells` | List of all cells |
| `world.players` | List of players (always one element in single-player) |
| `world.createObject(recordId, count)` | Create a new instance of a record |
| `world.createRecord(record)` | Create a custom record in the world database |
| `world.getCellById(cellId)` | Load a cell by ID |
| `world.getCellByName(cellName)` | Load a named cell |
| `world.getExteriorCell(gridX, gridY, cellOrName)` | Load an exterior cell |
| `world.getGameTime()` | Game time in seconds |
| `world.getGameTimeScale()` | Ratio of game time speed to simulation time |
| `world.getObjectByFormId(formId)` | Return an object by RefNum/FormId |
| `world.getObjectsByRecordId(recordId, worldSpaceId, loadedOnly)` | Find objects by record ID |
| `world.getObjectsInRange(position, range)` | Find objects within range of a position |
| `world.getPausedTags()` | Currently pausing tags |
| `world.getSimulationTime()` | Simulation time in seconds |
| `world.getSimulationTimeScale()` | Ratio of simulation time to real time |
| `world.isWorldPaused()` | Whether the world is paused |
| `world.mwscript` | MWScript functions |
| `world.vfx` | Visual effects (VFX) |
| `world.advanceTime(hours)` | Advance time by hours |
| `world.pause(tag)` | Pause the game |
| `world.setGameTimeScale(ratio)` | Set game time scale |
| `world.setSimulationTimeScale(scale)` | Set simulation time scale |
| `world.unpause(tag)` | Remove a pause tag |

#### `openmw.core` — Core Functions

| Function | Description |
|----------|-------------|
| `core.getFormId(string)` | Get the FormId string |
| `core.getObjectById(id)` | Get an object by its ID |
| `core.sendGlobalEvent(eventName, eventData)` | Send a global event |
| `core.getGameTime()` | Get current game time |
| `core.getSimulationTime()` | Get current simulation time |
| `core.getObjectFromId(id)` | Get object from string ID |

**Object methods (on any `GameObject`):**

| Method | Description |
|--------|-------------|
| `GameObject:sendEvent(eventName, eventData)` | Send an event to scripts attached to this object |
| `GameObject:isValid()` | Check if the object is valid |
| `GameObject:teleport(cellName, position)` | Teleport to a cell and position |
| `GameObject:moveInto(target)` | Move the object into a container or inventory |

#### `openmw.util` — Utilities

| Type | Description |
|------|-------------|
| `util.vector3(x, y, z)` | Create a 3D vector |
| `Vector3:length()` | Get the vector's length |
| `Vector3:x()`, `Vector3:y()`, `Vector3:z()` | Access components |

### 2.8 Script Interfaces

Scripts can expose named interfaces for inter-script communication:

```lua
return {
  interfaceName = "MyInterface",
  interface = {
    version = 1,
    myFunction = function(x, y)
      -- implementation
    end,
  },
  engineHandlers = {
    onInterfaceOverride = function(base)
      -- called when another script overrides this interface
    end,
  },
}
```

Using an interface:

```lua
local interfaces = require('openmw.interfaces')
interfaces.MyInterface.myFunction(2, 3)
```

### 2.9 Interfaces of Built-in Scripts

| Interface | Context | Description |
|-----------|---------|-------------|
| `Activation` | global | Extend or override activation mechanics |
| `AI` | local | Control basic AI of NPCs and creatures |
| `AnimationController` | local | Control animations |
| `Camera` | player | Alter built-in camera behavior |
| `Combat` | local / global | Control combat |
| `Controls` | player | Alter player controls behavior |
| `Crimes` | global | Commit crimes |
| `GamepadControls` | player | Alter gamepad controls behavior |
| `ItemUsage` | global | Extend or override item usage |
| `MWUI` | menu / player | Morrowind-style UI templates |
| `Projectiles` | global | Alter projectile behavior |
| `Settings` | global / menu / player | Save, display, and track setting changes |
| `SkillProgression` | player (global in 0.50; local in 0.51) | Control skill progression |
| `SpellCasting` | local | Control spell casting |
| `UI` | player | High-level UI modes |

### 2.10 Event System

**Sending events:**

| Method | Sender → Receiver |
|--------|-------------------|
| `core.sendGlobalEvent(eventName, eventData)` | Any script → global scripts |
| `GameObject:sendEvent(eventName, eventData)` | Any script → local scripts on an object |
| `types.Player.sendMenuEvent(eventName, eventData)` | Any script → menu scripts |

**Registering handlers** (in script's returned table):

```lua
return {
  eventHandlers = {
    MyEvent = function(eventData)
      -- process event
    end,
  },
}
```

Events are delivered with a one-frame delay. Return `false` from an event handler to skip subsequent handlers. Event handlers are called in **reverse** load order (opposite to engine handlers).

### 2.11 Timers

Located in `openmw.async`:

| Function | Description |
|----------|-------------|
| `async:newSimulationTimer(delay, callback, data)` | Reliable timer in simulation time (saved/restored) |
| `async:newUnsavableSimulationTimer(delay, callback, data)` | Unsavable timer in simulation time |
| `async:newGameTimer(delay, callback, data)` | Reliable timer in game time |
| `async:newUnsavableGameTimer(delay, callback, data)` | Unsavable timer in game time |
| `async:registerTimerCallback(name, func)` | Register a callback name for reliable timers |

**Reliable timers** are automatically saved and restored across saves. Callbacks must be pre-registered with `registerTimerCallback`.

**Unsavable timers** are lost on save/reload.

**Auxiliary helper** (`openmw_aux.time`):

```lua
local time = require('openmw_aux.time')
local stopFn = time.runRepeatedly(callback, time.day, {
  initialDelay = timeBeforeMidnight,
  type = time.GameTime,
})
```

### 2.12 Engine Handlers

Engine handlers are functions defined by the script that the engine calls. They are **engine-to-script** interactions.

| Handler | Context | Description |
|---------|---------|-------------|
| `onUpdate(dt)` | all | Called every frame; `dt` is delta time |
| `onSave()` | all | Called on game save; must return serializable data |
| `onLoad(data)` | all | Called on game load; `data` is saved state |
| `onInit()` | local/player | Called when the script starts |
| `onKeyPress(key)` | player | Key pressed event |
| `onActivated()` | local | Object was activated |
| `onSpellCast(spellId)` | local | Spell was cast |
| `onContainerClosed()` | local | Container was closed |
| `onObjectDisposed(objectId)` | local | Object was disposed |
| `onObjectAdded(object)` | local | Object was added (to inventory) |
| `onObjectRemoved(object)` | local | Object was removed (from inventory) |
| `onEquip(item)` | local | Item was equipped |
| `onUnequip(item)` | local | Item was unequipped |
| `onLevelUp()` | player | Player leveled up |
| `onInterfaceOverride(base)` | all | Another script is overriding this script's interface |
| `onDialogueResponse(response)` | all | **New in 0.51.0** — dialogue response |
| `onAnimationEnd(animId)` | all | **New in 0.51.0** — animation end |

*(This table is not exhaustive. The complete list of engine handlers is documented in the OpenMW "Engine handlers reference" page at `reference/lua-scripting/engine_handlers.html`.)*

---

## 3. Alchemy-Helper Architectural Notes and Planned Use

### 3.1 Project Context

The alchemy-helper project is designed as an OpenMW Lua mod (version 0.50+) that provides alchemy assistance. It needs to interact with the game's potion and ingredient systems.

### 3.2 No `openmw.alchemy` Package Exists

**Critical:** OpenMW does **not** currently expose the `MWMechanics::Alchemy` C++ class (or any part of it) as a Lua API package. There is no `Alchemy::getEffects()`, `Alchemy::getRecipe()`, `Alchemy::listEffects()`, or `Alchemy::create()` available in Lua.

The C++ `MWMechanics::Alchemy` class is an internal engine component used by the alchemy menu UI. Its methods include:

- `listEffects()` — lists effects shared by at least two ingredients
- `beginEffects()` / `endEffects()` — iterators over effects (private)
- `create(name)` — creates a potion from current ingredient state
- `getPotionName()` — returns a suggested potion name
- `setAlchemist(npc)` — sets the alchemist
- `addIngredient(ingredient)` — adds an ingredient to the next free slot
- `removeIngredient(index)` — removes an ingredient from a slot
- `knownEffect(potionEffectIndex, npc)` — checks if NPC has sufficient alchemy skill

**None of these methods are exposed to Lua.** This has been a known gap since the OpenMW Lua system was introduced, and [issue #7277](https://gitlab.com/OpenMW/openmw/-/issues/7277) documents a request for exactly this kind of API.

> **Implication for the alchemy-helper project:** You cannot directly call `Alchemy::getEffects()` or `Alchemy::getRecipe()` from Lua. You must work with the available higher-level APIs to achieve alchemy-related functionality.

### 3.3 Available Alchemy-Related APIs

#### 3.3.1 `openmw.types.Ingredient`

Access ingredient records from the game data:

```lua
local types = require('openmw.types')

-- Get an ingredient record by ID (read-only)
local ingredientRecord = types.Ingredient.record('slaughterfish_egg')

-- Access record fields:
print(ingredientRecord.id)       -- "slaughterfish_egg"
print(ingredientRecord.name)     -- "Slaughterfish Egg"
print(ingredientRecord.icon)     -- VFS path to icon
print(ingredientRecord.model)    -- VFS path to model
print(ingredientRecord.value)    -- base value
print(ingredientRecord.weight)   -- base weight

-- Iterate all ingredient records
for _, record in ipairs(types.Ingredient.records) do
  print(record.id, record.name)
end
```

Ingredient records include the effect IDs associated with each ingredient (typically 1–4 effects per ingredient). Access these via the underlying `ESM4Ingredient` record type if needed.

#### 3.3.2 `openmw.types.Potion`

Access potion records:

```lua
local types = require('openmw.types')

-- Get a potion record by ID
local potionRecord = types.Potion.record('potion_of_restore_health_01')

-- List all potions
for _, record in ipairs(types.Potion.records) do
  print(record.id, record.name)
end
```

#### 3.3.3 `openmw.types.Potion.createRecordDraft()` (0.51.0+)

Create custom potion records at runtime:

```lua
local types = require('openmw.types')
local world = require('openmw.world')

local potionRecord = types.Potion.createRecordDraft({
  name = "My Custom Potion",
  weight = 0.1,
  value = 10,
  icon = "icons\\m\\tx_potion_exclusive_01.dds",
  model = "m\\Misc_Potion_Exclusive_01.nif",
  autocalc = false,
})

local registeredRecord = world.createRecord(potionRecord)
```

#### 3.3.4 `world.createObject()` for Dynamically Created Potions

Create instances of potion records (including dynamically created ones):

```lua
local world = require('openmw.world')
local types = require('openmw.types')
local self = require('openmw.self')

-- Get the player
local player = world.players[1]

-- Create an instance of a potion (dynamically generated or existing)
local potion = world.createObject('Generated:0x0', 1)
potion:moveInto(types.Actor.inventory(player))

-- Or create an instance of an existing record
local gold = world.createObject('gold_001', 100)
gold:teleport(player.cell.name, player.position)
```

#### 3.3.5 Ingredient Effects — The Workaround

Since `Alchemy::listEffects()` and `Alchemy::getEffects()` are not exposed to Lua, the alchemy-helper project must determine ingredient effects by inspecting ingredient records directly:

```lua
local types = require('openmw.types')

function getIngredientEffects(ingredientId)
  -- The ESM4Ingredient record type provides effect data
  -- Access the ingredient record and extract its effects
  local record = types.Ingredient.record(ingredientId)
  if not record then return {} end

  -- Effect IDs are stored on the ingredient record.
  -- The exact field names depend on the openmw.types implementation.
  -- Check types.ESM4Ingredient.record() for low-level access if needed.
  local effects = {}
  -- Populate effects from record data
  return effects
end
```

**This approach requires inspecting the underlying record data structure.** The documented `types.Ingredient` API provides record access but does not explicitly document a method for enumerating an ingredient's effects. This is a gap in the documentation. Mod authors may need to consult the `resources/lua_api` directory shipped with OpenMW for the complete field list, or inspect the source code.

### 3.4 Interaction with the Alchemy Menu

Since the `Alchemy` C++ class is not exposed to Lua, the alchemy-helper mod cannot:

- Interfere with or override the vanilla alchemy menu
- Query the currently selected ingredients in the alchemy window
- Interfere with the potion creation process at the C++ level

**Possible approach:** Use the `LOAD` context (0.51.0+) to hook into the ingredient and potion record data as it is loaded, build a local effect database, and present it through a custom UI (via `openmw.ui`). The `createPotion`/`findPotion` functionality from the `openmw.records` package (if merged into 0.50+) provides a higher-level interface for creating custom potions.

### 3.5 Notable API Differences from Earlier OpenMW Versions

| Change | Version | Impact |
|--------|---------|--------|
| `LOAD` context added | 0.51.0 | New context for reading/writing loaded records during content load |
| `async` available in `LOAD` context | 0.51.0 | Timers work during content load |
| `content` package added | 0.51.0 | Content manipulation available in load context |
| `SkillProgression` context changed from global to local | 0.51.0 | Mod that relied on `SkillProgression` in global context must update |
| `factionReaction` renamed to `factionReputation` | 0.51.0 | Old binding deprecated; update references |
| Custom magic effect records | 0.51.0 | Can now inject custom magic effects via the `LOAD` context |
| Custom ingredients | 0.51.0 | Ingredients can be custom (not just via ESM data) |
| Custom spells and enchantments | 0.51.0 | Can create via `LOAD` context or at runtime |
| Dialogue response event handler | 0.51.0 | New engine handler `onDialogueResponse(response)` |
| Animation end event handler | 0.51.0 | New engine handler `onAnimationEnd(animId)` |
| `PotionRecord.autocalc` field | 0.51.0 | New binding for potion auto-calculate flag |
| Spell effect lists from tables | 0.51.0 | Potion effect lists can be generated from Lua tables |

### 3.6 Serialization Constraints for Alchemy Data

When using `onSave()`/`onLoad()`, alchemy-related state must be serializable:

**Serializable:**
- `nil`, numbers, strings
- Game objects
- `util.vector3` values
- Tables with serializable keys and values

**Not serializable:**
- Functions
- Tables with custom metatables
- Tables with multiple references to the same table
- Circular references

When persisting alchemy state (e.g., a discovered recipe book), store effect IDs as integers and ingredient IDs as strings, then reconstruct effect objects on `onLoad()`.

---

## 4. Appendix

### 4.1 IDE Support

OpenMW ships a `resources/lua_api` directory containing LDT (Lua Development Tools) documentation files. Import these into an Eclipse-based IDE for code autocompletion and integrated API reference.

### 4.2 Debugging Tips

- Use `reloadlua` in the console to reload scripts without restarting
- Use `lua global` / `luap` / `luas` / `luam` for interactive debugging in different contexts
- Check the load order in `openmw.cfg` — it determines script execution order and interface override order
- Remember: `onLoad` is called when a script loads after a game save, not when the game loads (use `onInit` for startup logic)
- Event handlers run in reverse load order; engine handlers run in forward load order

### 4.3 Key URLs

- Official documentation: <https://openmw.readthedocs.io/en/stable/reference/lua-scripting/>
- Issue #7277 (alchemy Lua API request): <https://gitlab.com/OpenMW/openmw/-/issues/7277>
- MR !2859 (`openmw.records` package): <https://gitlab.com/OpenMW/openmw/-/merge_requests/2859>
- 0.51.0 release notes: <https://openmw.org/2026/openmw-0-51-0-released/>
- OpenMW GitHub: <https://github.com/OpenMW/openmw>

### 4.4 Documentation Gaps

The following items are explicitly **not documented** in the official OpenMW documentation as of 0.51.0:

- The `openmw.records` API package (was in a merge request but status unclear for 0.50+)
- The exact fields available on `types.Ingredient.record()` for effect data enumeration
- The `LOAD` context record API beyond a high-level description
- The complete list of engine handlers (referenced as a separate page that may be incomplete)
- The `Alchemy::getEffects()` and `Alchemy::getRecipe()` C++ methods (internal only, no Lua binding)

Where documentation is sparse, mod authors should consult the `resources/lua_api` directory shipped with OpenMW installations, which contains the source LDT files from which the documentation is generated.
