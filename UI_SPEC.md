# Alchemist's Almanac UI

The main mod UI consists of a window with two tabs: a searchable Ingredients List, and an effect-based Shopping Planner. The almanac keybind opens this window (replacing the previous single-panel effect view).

## Ingredients List

The ingredients list primarily consists of a list of Ingredients and a search bar text field. The list shows a windowed view — mouse-wheel scrolling with page up/down buttons, since the engine's Lua UI has no native scrollbars — of all ingredients that have a case-insensitive substring match to the search bar in any of:

- Name
- Effect display names, including any parameters that affect the display name of the effect, like Strength or Fatigue

The list is sorted alphabetically by ingredient name. Ingredients should also be filtered to only discovered ingredients if Immersive Mode is on in the mod's settings.

Each ingredient row displays the following.

- Name
- Icon (the ingredient record's icon, `IngredientRecord.icon`)
- Effects (display names; compound — one entry per effect + attribute/skill combination)
- Cost (the ingredient record's gold value, `IngredientRecord.value`)
- Number of discovered merchants that restock the ingredient (i.e., include it in their restocking supply). A merchant with the Ingredients service but no restocking supply of the item does not count.

## Shopping Planner

The shopping planner consists of a header, an effects list, and a merchant list.

The header has a toggle for Strict Mode. Strict Mode is off by default and session-only (not persisted).

### Effects List

A list of effects, one entry per compound effect (effect + attribute/skill combination), sorted and filterable by display name. In Immersive mode, this should only include effects present on discovered ingredients. Entries are selectable; multiple selections use AND semantics — each selected effect further filters the merchant list to only merchants that have at least one restocking ingredient with that effect, or at least two distinct restocking ingredients with that effect if Strict Mode is enabled. "Distinct" means distinct ingredient records: if two mods add their own versions of an ingredient with the same name, they count as two.

### Merchant List

A list of all discovered merchants, filtered by the effect selection (with no effects selected, all discovered merchants are shown). Each merchant displays:

- Actor Name
- Location Name — the last-known cell display name, captured when the merchant was encountered and updated on re-encounter
- List of ingredients they restock that match any selected effect (ingredient record names; with no selection, their full restocking supply)

The merchant list should be sortable and filterable by both Actor and Location names.

Clicking a merchant expands its row to show the full restocking supply (every ingredient ever seen in their negative-count inventory, union across encounters, sorted by name; each entry shows the ingredient's gold value); clicking again collapses it. Only one merchant is expanded at a time. Both views share the same sorted order — the collapsed short form is a prefix of the expanded list — and the short form is hidden while the full list is visible (and vice versa). The expanded block grows downward within the column — names that do not fit above the page bar collapse into a "+N more" line, and rows pushed out of view are skipped until the expansion is collapsed or the list is paged.

## Implementation Notes (UI)

- Built on OpenMW-UIToolkit (EnderWiggin/OpenMW-UIToolkit, a required sibling Data Files entry): the almanac is a `WindowManager` window (`alchemy-helper-almanac`, fixed 800×620, centered) with a `WindowHandler`; frame, title bar and focus handling come from the toolkit. Without the toolkit installed the UI degrades to a no-op with one console warning.
- Ingredients tab: a toolkit `sortedList` (virtualized, uniform row height) with columns icon / name / effects / cost / merchant count; the column header provides click-to-sort (default: name). The search field is a toolkit `textEdit`; typing calls `setFilter` on the list only, so the focused edit keeps keyboard focus. No manual paging or wheel handlers.
- Planner tab: the effects list is a toolkit `itemList` with a `TextItem` provider; selection is the row's active state (`data.isActive` reads the live selection set), so a click toggles the set and calls `provider:refreshState(id)` — no row rebuild. Strict Mode is a toolkit `checkbox`; merchant sort (NAME/LOC) are toolkit `textButton`s with active-state highlighting.
- The merchant column stays hand-built plain lua_ui: its rows have variable height (expanded restock view) and toolkit lists support only a single uniform row height. It is a root element embedded in the window content (the toolkit's own pattern for components), rebuilt by swapping `layout.content` + `update()` — safe because rows contain no components, which must go through the toolkit's destroy path. Wheel scrolling + page buttons persist across rebuilds; buttons are persistent components guarded by `canClick` and mirrored with `setDisabled`.
- Components/elements are positioned absolutely in window-body coordinates via `updateProps{position=...}` (body slot = below the 20px title header); sizes come from `wnd:getInnerSize()` at open. Tab switch replaces the whole body via `wnd:setContent`; open rebuilds fresh data (spec: refresh on open).
- Mode ownership: the handler owns the `Interface` mode only when it had to create it (nothing else was open); otherwise the window overlays the current mode. On close, it removes the mode only if it still owns it.
- Esc closes via the engine's `UiModeChanged` global event: when the mode stack empties while the window is visible, the binding calls `hide()`. Without this hook, Esc pops the Interface mode on the engine side and leaves the window orphaned (visible but uninteractable).
- Reentrancy guards (`open` flag + per-rebuild flags) skip nested rebuilds; deferred async callbacks that land after a close are dropped by the `open` check.

## Notes

- Effect display names are collected at init from the engine itself: each effect entry on an ingredient record references its MagicEffect record (`eff.effect`), whose `.name` is the localized display name — mod-added MGEFs included. IDs whose effect record or name is missing fall back to a generated CamelCase-split name (e.g. `WeaknessToFire` → "Weakness to Fire"). Attribute/skill target names come from a small static table (`shared/data/effect-names.lua`, GMST-sourced) because the engine exposes no API for them.
- The engine serializes RefIds to lowercase when pushing them into Lua (`RefId::serializeText` lowercases StringRefIds), so ids arriving from record properties look like `fortifyattribute` / `strength`. All target-name maps are therefore keyed by lowercase id, lookups are case-insensitive, generated fallback names capitalize the first letter of all-lowercase ids, and the public query API (`queryByEffect`, `querySharedWith`, `queryEffects`) normalizes caller-supplied ids before index lookup.
- The only icons used are ingredient record icons; effects are displayed as text.
- List data is refreshed when the window opens and on tab switch; it is not live-updated while the window stays open.
- "Restocking supply" means ingredients a merchant holds at a negative count in their inventory — what they sell and restock.
