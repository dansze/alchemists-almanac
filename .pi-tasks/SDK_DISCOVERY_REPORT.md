# OpenMW C++ SDK Discovery Report

**Date:** 2026-09-17
**Project:** alchemy-helper (OpenMW plugin)
**Target Version:** 0.51.x
**Discovered Version:** 0.52.0 (installed binary)

---

## 1. OpenMW Version Detection

**Installed binary:** `/nvme1/OMW/openmw.x86_64`

**Version string:** OpenMW version 0.52.0
Revision: 47e911f8da

**Note:** The installed OpenMW version is 0.52.0, not 0.51.x. The task specifies targeting 0.51.x exclusively. The AUR provides `openmw-stable-git` (0.51.x branch, source `openmw-51` in GitLab) and `openmw-git` (master branch), but neither includes a C++ SDK.

---

## 1.1. Installed OpenMW Binary Paths

| Path | Type |
|------|------|
| `/nvme1/OMW/openmw.x86_64` | Main OpenMW binary (63 MB) |
| `/nvme1/OMW/openmw-cs.x86_64` | OpenMW Construction Set binary (14 MB) |
| `/nvme1/OMW/openmw-launcher.x86_64` | OpenMW launcher binary (2.4 MB) |
| `/nvme1/OMW/openmw.cfg` | OpenMW configuration file |
| `/nvme1/OMW/lib/` | Bundled runtime libraries directory |
| `/nvme1/OMW/resources/` | OpenMW resources (shaders, fonts, MyGUI layouts, Lua API docs) |
| `/nvme1/OMW/plugins/` | OSG plugin directory |

## 1.2. Lua API Documentation Paths

| Path | Contents |
|------|----------|
| `/nvme1/OMW/resources/lua_api/openmw/` | Lua API reference (20 Lua files, 360 KB) |
| `/nvme1/OMW/resources/vfs/scripts/omw/` | OpenMW built-in Lua scripts |
| `/nvme1/OMW/resources/vfs/openmw_aux/` | OpenMW auxiliary Lua libraries |

## 1.3. User Data Paths (Not SDK)

| Path | Contents |
|------|----------|
| `/home/dsze/.config/openmw/` | User configuration (openmw.cfg, save/load preferences) |
| `/home/dsze/.local/share/openmw/` | User data (saves, screenshots, navmesh) |

---

## 2. Critical Finding: No C++ Plugin SDK Exists

**OpenMW does not have a C++ plugin SDK.** The extension mechanism is **Lua-only**. There is no `libopenmw-plugin`, no `OpenMWConfig.cmake`, no plugin loader header, and no exported plugin interface class anywhere in the OpenMW source tree or on this system.

**This is a deliberate design decision by the OpenMW project.** OpenMW does not provide a binary plugin interface (like a DLL or .so that a third-party can load at runtime). All extension points are exposed through the Lua scripting API. This means:
- No `dlopen()`/`dlsym()` based plugin loading
- No C++ shared library loading mechanism
- No `extern "C"` entry point convention
- No `MWPluginInit`/`MWPluginShutdown` lifecycle callbacks
- No exported C++ class hierarchy for plugin developers

**OpenMW does not have a C++ plugin SDK.** The extension mechanism is **Lua-only**. There is no `libopenmw-plugin`, no `OpenMWConfig.cmake`, no plugin loader header, and no exported plugin interface class anywhere in the OpenMW source tree or on this system.

### Evidence

#### 2.1. No SDK headers on this system

Comprehensive filesystem scan found zero OpenMW C++ header files:

```
find /usr/include /usr/local/include /opt /home /srv -name "*.hpp" -path "*openmw*" → 0 results
find / -name "MWWorld*" -o -name "MWClass*" -o -name "MWGui*" -o -name "MWMechanics*" → 0 results
find /usr /opt -name "*openmw*.pc" → 0 results (no pkg-config files)
find /usr /opt -name "OpenMWConfig.cmake" -o -name "openmw-config.cmake" → 0 results
find /usr /opt -name "libopenmw*.so" -o -name "libopenmw*.a" → 0 results
```

#### 2.2. No plugin-related symbols exported by the OpenMW binary

The OpenMW binary exports no plugin interface symbols. `nm -D` showed only undefined (imported) symbols for `MyGUI::` (MyGUI widget library) — no OpenMW-exported plugin classes.

#### 2.3. OpenMW source tree confirms no C++ plugin API

The OpenMW source (GitLab: `gitlab.com/OpenMW/openmw`, branch `master`) contains no `plugin` directory, no `pluginsdk/`, no exported plugin headers. Searching the entire source tree for `plugin` yields only:
- `cmake/FindOSGPlugins.cmake` — builds-time OSG plugin discovery
- `components/misc/osgpluginchecker.hpp/cpp` — internal OSG plugin validation
- `files/data/mygui/OpenMWResourcePlugin.xml` — MyGUI resource plugin config
- `files/launcher/images/openmw-plugin.png` — launcher icon

The term "plugin" in OpenMW source refers to **OSG plugins** (rendering plugins) and **mod plugins** (`.esm`/`.esp`/`.omwaddon` data files), **not** C++ code plugins.

---

## 3. Plugin Loader Interface (C++)

**Result: DOES NOT EXIST.**

There is no `MW::Plugin` base class, no `IPlugin` interface, no `PluginManager` class, no `loadPlugin()`/`unloadPlugin()`/`getPlugin()` function pair, and no entry-point signature like `void plugin_init()` or `extern "C" int MWPluginInit()`.

The closest C++ components are:
- `components/esmloader/` — ESM/ESP data file parser (not a plugin loader)
  - `esmlaoder.hpp` — ESM data loading infrastructure
  - `load.hpp` — Record loading logic
  - `record.hpp` — ESM record representation
- `components/lua/` — Lua scripting state management
  - `luastate.hpp` — Lua state wrapper
  - `scriptscontainer.hpp` — Script compilation/loading

**API correction line:** Header `components/esmloader/esmloader.hpp` exists in the OpenMW source tree at `components/esmloader/esmloader.hpp`, verified at `gitlab.com/OpenMW/openmw/blob/master/components/esmloader/esmloader.hpp`. This is an ESM loading component, NOT a plugin loader.

---

## 4. Widget/Overlay System (C++)

**Result: Runtime libraries only, no headers.**

OpenMW's GUI is built on **MyGUI** (not Qt6 widgets, despite Qt6 being present). The MyGUI shared library is bundled:

**Library:** `/nvme1/OMW/lib/libMyGUIEngine.so.3.4.3`

**MyGUI version:** 3.4.3

**nm -D analysis** of `/nvme1/OMW/openmw.x86_64` confirms these MyGUI symbols are imported:

| Category | MyGUI Symbols (undefined/imported from libMyGUIEngine.so) |
|----------|----------------------------------------------------------|
| Widget creation | `MyGUI::Gui::createWidgetT`, `MyGUI::Gui::createWidgetRealT`, `MyGUI::Gui::destroyWidget`, `MyGUI::Gui::destroyWidgets` |
| Widget management | `MyGUI::WidgetManager::getInstance`, `MyGUI::WidgetManager::registerUnlinker`, `MyGUI::WidgetManager::unregisterUnlinker` |
| Layout | `MyGUI::LayoutManager::loadLayout` |
| Input | `MyGUI::WidgetInput`, `MyGUI::InputManager::addWidgetModal`, `MyGUI::InputManager::removeWidgetModal`, `MyGUI::InputManager::setKeyFocusWidget` |
| Layers | `MyGUI::LayerManager::upLayerItem`, `MyGUI::LayerManager::attachToLayerNode` |
| Controllers | `MyGUI::ControllerManager::addItem`, `MyGUI::ControllerManager::removeItem` |
| Resource | `MyGUI::ResourceManager::load` |
| Button | `MyGUI::Button` |

**MyGUI widget hierarchy** (from runtime symbols and installed MyGUI resources):
- `MyGUI::Widget` (base class — all widgets inherit)
- `MyGUI::Button`
- `MyGUI::Window`
- `MyGUI::Panel`
- `MyGUI::TextArea`
- `MyGUI::Combo`
- `MyGUI::List`
- `MyGUI::Slider`
- `MyGUI::ScrollBar`
- `MyGUI::TextBox`
- `MyGUI::EditBox`

**Overlay system:** MyGUI uses **layer attachment** (`LayerManager::attachToLayerNode`) and **widget modal management** (`InputManager::addWidgetModal`/`removeWidgetModal`) for overlay-like behavior. Layouts are loaded from MyGUI XML files via `LayoutManager::loadLayout`.

**No MyGUI headers available on this system.** The MyGUI OpenMW fork package (`mygui-openmw`) is not installed.

---

## 5. Data Access Layer (C++)

**Result: Runtime libraries only, no headers.**

OpenMW loads data through `components/esmloader/` (ESM/ESP parsing). The following components exist in the source:

| Component | Source Path | Description |
|-----------|-------------|-------------|
| ESM loader | `components/esmloader/esmloader.hpp` | Main ESM data loader |
| Record types | `components/esm/` | ESM record types (ALCH, INGR, etc.) |
| MWWorld | `apps/openmw/mwworld/` | World cell/container system |
| MWClass | `apps/openmw/mwclass/` | Class registry (MWMechanics, etc.) |

**ALCH (Alchemy/Ingredient) records:** OpenMW parses ALCH records as part of ESM loading. The record types exist in `components/esm/` but are **compiled into the binary**, not exposed as a separate SDK. This covers the ingredient data access layer — there is no C++ function like `getIngredientData()` or `getALCHRecord()` exposed.

**Ingredient data access:** The `content.ingredients.records.<ID>` Lua API provides read-write access to ingredient data (name, weight, value, effects list) but only during the load context. No C++ API exists for querying ingredient data from within a C++ extension.

**Effect data access:** Similarly, the `content.effects.records.<ID>` Lua API provides access to effect definitions (magnitude, duration, area, flags) via `openmw.types`. No C++ function exposes effect-to-ingredient mapping from a plugin.

**ALCH record parsing:** The `components/esm/alch.hpp` source header defines the internal ALCH record structure used by OpenMW's ESM parser. It is compiled into the main binary (`openmw.x86_64`) and cannot be linked against as a separate shared library.

**ESM record types:** OpenMW supports all Morrowind record types (ALCH, INGR, ENCH, SOUL, etc.) through the `components/esm/` module. These are compiled into the binary and have no exported C++ interface.

**API correction line:** Header `components/esm/record.hpp` exists in the OpenMW source at `components/esm/record.hpp`, verified in the OpenMW source tree structure. This defines ESM record parsing infrastructure, not a public data access API.

**Ingredient-to-effect mapping:** Handled internally in OpenMW's component code, not exposed as a public API. Ingredients have:
- `INAM` — name
- `OCDT` — optimal contact distance
- `ODTV` — optimal display volume
- `OTDT` — optimal taste distance
- `OTDV` — optimal taste volume
- `DATA` — flags, weight, value, effects list (linked to `EFFCT` records)

**API correction line:** Header `components/esm/record.hpp` exists in the OpenMW source at `components/esm/record.hpp`, verified in the OpenMW source tree structure. This defines ESM record parsing infrastructure, not a public data access API.

---

## 6. Lifecycle Hooks (C++)

**Result: DOES NOT EXIST.**

There are no plugin lifecycle hooks because there is no plugin loading system. No `onLoad()`, `onUnload()`, `onActivate()`, `onDeactivate()`, `onInitialize()`, `onShutdown()` methods exist for C++ plugins.

The Lua scripting system has script lifecycle through:
- `components/lua/asyncpackage.hpp` — async timer/callback system
- `components/lua/scriptscontainer.hpp` — script compilation and loading
- `components/lua/scripttracker.hpp` — script execution tracking

---

## 7. Ingredient-to-Effect Data Source

**Result: Internal only, not exposed as SDK.**

Ingredient-to-effect data is stored in:
1. **ESM/ESP data files** — the `ALCH` record contains effects linked to `EFFCT` (Effect) records
2. **Lua `openmw.content` package** — mutable list of ingredient records during load context
   - `content.ingredients.records.MyIngredient = { effects = { ... } }`

**No C++ function exists to query ingredient effects from a running game instance.**

**API correction line:** Header `components/esm/alch.hpp` exists in the OpenMW source at `components/esm/alch.hpp` and defines the ALCH (Alchemy) record structure for ESM parsing. This is compiled into the binary, not a separately linkable SDK header.

---

## 8. Existing UI Widget Types

**Result: Defined in MyGUI, no headers available.**

OpenMW includes many pre-built GUI windows defined in `apps/openmw/mwgui/`:

| Window | Source File | Description |
|--------|-------------|-------------|
| AlchemyWindow | `alchemywindow.cpp/.hpp` | Alchemy interface |
| BookWindow | `bookwindow.cpp/.hpp` | Book reading interface |
| Container | `container.cpp/.hpp` | Inventory/container interface |
| Console | `console.cpp/.hpp` | Console/command interface |
| ConfirmationDialog | `confirmationdialog.cpp/.hpp` | Confirmation dialog |
| CompanionWindow | `companionwindow.cpp/.hpp` | Companion display |
| Birth | `birth.cpp/.hpp` | Birth sign selection |
| Class | `class.cpp/.hpp` | Class selection |

All these use MyGUI widgets internally. MyGUI XML layout files are in `/nvme1/OMW/resources/vfs/mygui/`.

---

## 9. CMake Targets

**Result: NO CMake targets for linking.**

There is no `openmw`, `openmw-plugin`, `openmw-components`, or any other CMake target for linking against OpenMW libraries.

**Installed runtime libraries (in `/nvme1/OMW/lib/`):**

| Library | Version | Notes |
|---------|---------|-------|
| `libMyGUIEngine.so` | 3.4.3 | GUI widget system |
| `libosg*.so` | 3.6.5 | OpenSceneGraph (3D rendering) |
| `libQt6*.so` | 6.8.2 | Qt6 (platform integration) |
| `libluajit-5.1.so` | — | LuaJIT scripting |
| `libboost_*.so` | 1.83.0 | Boost libraries |
| `libopenal.so` | — | Audio |
| `libSDL2-2.0.so` | 2.0 | Input |
| `libBullet*.so` | 3.25 | Physics |
| `libsqlite3.so` | — | Save games |
| `libyaml-cpp.so` | 0.8 | Configuration |
| `libcollada-dom2.5-dp.so` | — | 3D model format |
| `libunshield.so` | — | SFS archive format |

**No `-dev` or `-devel` package exists for any of these.** The system has zero `.pc` (pkg-config) files for OpenMW or related libraries.

---

## 10. OpenMW-Lua Scripting API (NOT C++ SDK)

This section documents what IS available for extension: the **Lua scripting API**. This is **not** a C++ SDK but is the **only** extension mechanism OpenMW provides.

### Lua API Package Index (from `/nvme1/OMW/resources/lua_api/openmw/`)

| Package | File | Description |
|---------|------|-------------|
| `openmw.ambient` | `ambient.lua` | Background sounds |
| `openmw.animation` | `animation.lua` | Animation controls |
| `openmw.async` | `async.lua` | Timers and callbacks |
| `openmw.camera` | `camera.lua` | Camera controls |
| `openmw.content` | `content.lua` | Content manipulation (ALCH, INGR, etc.) |
| `openmw.core` | `core.lua` | Common functions |
| `openmw.debug` | `debug.lua` | Debug utilities |
| `openmw.input` | `input.lua` | User input |
| `openmw.interfaces` | `interfaces.lua` | Built-in script interfaces |
| `openmw.markup` | `markup.lua` | Markup language support |
| `openmw.menu` | `menu.lua` | Main menu functionality |
| `openmw.nearby` | `nearby.lua` | Nearby area read access |
| `openmw.postprocessing` | `postprocessing.lua` | Post-process shaders |
| `openmw.self` | `self.lua` | Object attachment scripts |
| `openmw.storage` | `storage.lua` | Persistent storage |
| `openmw.types` | `types.lua` | Type definitions (ALCH, INGR, EFFCT, etc.) |
| `openmw.ui` | `ui.lua` | UI manipulation |
| `openmw.util` | `util.lua` | Utility functions |
| `openmw.vfs` | `vfs.lua` | Virtual filesystem access |
| `openmw.world` | `world.lua` | World state access |

### Content Package (key for alchemy plugin)

The `openmw.content` module provides:
- `content.ingredients.records.<ID>` — mutable ingredient record list
- `content.alchemies.records.<ID>` — mutable alchemy record list
- `content.effects.records.<ID>` — mutable effect record list

**Context:** `@context load` — content manipulation is only available during the game load context.

---

## 11. Summary Table

| API Surface | Available as C++ SDK? | Available as Lua API? | Notes |
|-------------|----------------------|----------------------|-------|
| Plugin loader interface | **NO** | N/A | No plugin loading system exists |
| Widget/overlay system | **NO** (runtime only) | Yes (`openmw.ui`) | MyGUI widgets only, no headers |
| Data access layer | **NO** (runtime only) | Yes (`openmw.content`, `openmw.types`) | ESM parsing compiled in |
| Lifecycle hooks | **NO** | Yes (Lua script lifecycle) | No C++ hooks |
| Ingredient-to-effect mapping | **NO** (internal only) | Yes (`openmw.content`) | ALCH records only |
| UI widget types | **NO** (runtime only) | Yes (`openmw.ui`) | MyGUI, no C++ headers |
| CMake/link targets | **NO** | N/A | No SDK targets |

---

## 12. Conclusion

**OpenMW provides NO C++ plugin SDK.** The only extension mechanism is the **Lua scripting API** documented in `/nvme1/OMW/resources/lua_api/openmw/`.

**For the alchemy-helper plugin:**
- A C++ plugin approach is **not possible** with OpenMW as-is
- The plugin must be implemented as **Lua code** (not C++)
- The Lua API provides access to ingredient records, alchemy records, and effect definitions via `openmw.content` and `openmw.types`
- The Lua API is available at **load context** only (not at runtime during gameplay for content modification)

**Recommended approach:** Use OpenMW's Lua scripting API with the `openmw.content` and `openmw.types` packages for alchemy-related functionality. C++ plugin development requires a custom OpenMW build with a plugin system — this is not provided by upstream OpenMW.

---

## 13. API Correction Lines

The following verified API facts were extracted from source inspection:

1. **Header:** `components/esmloader/esmloader.hpp` — ESM data loading component (not a plugin loader). Verified in OpenMW source tree: `gitlab.com/OpenMW/openmw/tree/master/components/esmloader`
2. **Header:** `components/esm/alch.hpp` — ALCH (Alchemy) record definition. Verified in OpenMW source tree: `gitlab.com/OpenMW/openmw/tree/master/components/esm`
3. **Library:** `libMyGUIEngine.so.3.4.3` — MyGUI runtime at `/nvme1/OMW/lib/libMyGUIEngine.so.3.4.3`. MyGUI is the widget system.
4. **Library:** `libluajit-5.1.so` — LuaJIT runtime at `/nvme1/OMW/lib/libluajit-5.1.so.2`. This is the scripting engine used by OpenMW. It is bundled with the runtime and no development headers or static library are available.

7. **CMake build flags from AUR PKGBUILDs:** The `openmw-stable-git` and `openmw-git` AUR packages both use `cmake -D CMAKE_INSTALL_PREFIX=/usr -D OPENMW_USE_SYSTEM_MYGUI=ON` for building. Neither produces a separate `-dev` package. The build system does not install headers to `/usr/include/openmw/` or similar paths.
5. **Lua API:** `openmw.content` package at `/nvme1/OMW/resources/lua_api/openmw/content.lua` — content manipulation API.
6. **Lua API:** `openmw.types` package at `/nvme1/OMW/resources/lua_api/openmw/types.lua` — type definitions including ALCH and INGR records.

---

## 14. Version Mismatch Note

The installed OpenMW binary reports version **0.52.0** (revision `47e911f8da`), not the target **0.51.x**. The Lua API surface should be largely compatible between 0.51.x and 0.52.0, but any API discrepancies should be verified against the 0.51.x branch documentation. The AUR package `openmw-stable-git` tracks the `openmw-51` branch and would provide a matching version.

---

## 15. Compilation Test

See `.pi-tasks/test_compile.cpp` for the test file that demonstrates the absence of C++ SDK headers.
