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

- Styling follows the native game menus and other Lua mods (Squire spell shop): `boxTransparentThick` window frame, gold/white/dim palette, shadowed text at menu font sizes, absolute positioning inside each element.
- The window is three elements, all rebuilt by destroy + `ui.create` (Squire pattern): a frame element (border, title, band placeholder), a controls element (tabs, close, labels, search fields, toggles, sort buttons) and a list-region element (rows + page bar) positioned exactly over the active tab's list band. In-place `element:update()` calls are avoided because lua_ui re-attaches TextEdit input widgets on every update, which drops keyboard focus.
- The controls are a separate element from the frame background: clicking any widget promotes its root element in MyGUI's layer order, so if the controls lived inside the frame element every click would drag the whole window background up over the list. The controls band (window-local y 4..regionTop) never overlaps the list band, so promotion is harmless. Toggle/sort clicks rebuild only controls + list; open/tab switch rebuilds all three.
- All elements are aligned with the frame using `relativePosition` + `anchor` only — never an absolute `position`, which interacts unreliably with `size` on root elements and misplaces them. Both share the canvas center: `anchor = (0.5, (WIN_H/2 − regionTop)/regionHeight)` puts a band's top-left at window-local `(0, regionTop)` for any canvas size; the controls element uses width `WIN_W − 8` with `anchor_x = 0.5`, which lands its left edge on window x = 4 (the frame slot origin), so children keep their slot coordinates.
- The frame carries an invisible placeholder container over the active tab's list band: the frame window sizes from its content, so without the placeholder the empty band collapses and the frame renders smaller than the list element. The placeholder is offset −4px in slot coordinates (thick-border inset) so its window-space extent matches the list element exactly.
- Esc closes via the engine's `UiModeChanged` global event: when the mode stack empties while the window is visible, the binding calls `hide()`. Without this hook, Esc pops the Interface mode on the engine side and leaves the frame orphaned (visible but uninteractable).
- Search filters live: `textChanged` on each keystroke rebuilds only the list element, so the focused search field (in the controls element) keeps keyboard focus. Full three-element rebuild happens on open and tab switch; reentrancy guards skip nested rebuilds.

## Notes

- Effect display names are collected at init from the engine itself: each effect entry on an ingredient record references its MagicEffect record (`eff.effect`), whose `.name` is the localized display name — mod-added MGEFs included. IDs whose effect record or name is missing fall back to a generated CamelCase-split name (e.g. `WeaknessToFire` → "Weakness to Fire"). Attribute/skill target names come from a small static table (`shared/data/effect-names.lua`, GMST-sourced) because the engine exposes no API for them.
- The engine serializes RefIds to lowercase when pushing them into Lua (`RefId::serializeText` lowercases StringRefIds), so ids arriving from record properties look like `fortifyattribute` / `strength`. All target-name maps are therefore keyed by lowercase id, lookups are case-insensitive, generated fallback names capitalize the first letter of all-lowercase ids, and the public query API (`queryByEffect`, `querySharedWith`, `queryEffects`) normalizes caller-supplied ids before index lookup.
- The only icons used are ingredient record icons; effects are displayed as text.
- List data is refreshed when the window opens and on tab switch; it is not live-updated while the window stays open.
- "Restocking supply" means ingredients a merchant holds at a negative count in their inventory — what they sell and restock.
