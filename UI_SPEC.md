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

## Implementation Notes (UI)

- Styling follows the native game menus and other Lua mods (Squire spell shop): `boxTransparentThick` window frame, gold/white/dim palette, shadowed text at menu font sizes, absolute positioning inside one window container.
- The window is two elements, both rebuilt by destroy + `ui.create` (Squire pattern): a frame element (title, tabs, labels, search fields, toggles) and a list-region element (rows + page bar) positioned exactly over the active tab's list band. In-place `element:update()` calls are avoided because lua_ui re-attaches TextEdit input widgets on every update, which drops keyboard focus.
- The list element is aligned with the frame using `relativePosition` + `anchor` only — never an absolute `position`, which interacts unreliably with `size` on root elements and misplaces the list. Both share the canvas center: `anchor = (0.5, (WIN_H/2 − regionTop)/regionHeight)` puts the band's top-left at window-local `(0, regionTop)` for any canvas size.
- The frame carries an invisible placeholder container over the active tab's list band: the frame window sizes from its content, so without the placeholder the empty band collapses and the frame renders smaller than the list element. The placeholder is offset −4px in slot coordinates (thick-border inset) so its window-space extent matches the list element exactly.
- Esc closes via the engine's `UiModeChanged` global event: when the mode stack empties while the window is visible, the binding calls `hide()`. Without this hook, Esc pops the Interface mode on the engine side and leaves the frame orphaned (visible but uninteractable).
- Search filters live: `textChanged` on each keystroke rebuilds only the list element, so the focused search field (in the frame element) keeps keyboard focus. Full frame + list rebuild happens on open and tab switch; reentrancy guards skip nested rebuilds.

## Notes

- Effect display names are collected at init from the engine itself: each effect entry on an ingredient record references its MagicEffect record (`eff.effect`), whose `.name` is the localized display name — mod-added MGEFs included. IDs whose effect record or name is missing fall back to a generated CamelCase-split name (e.g. `WeaknessToFire` → "Weakness to Fire"). Attribute/skill target names come from a small static table (`shared/data/effect-names.lua`, GMST-sourced) because the engine exposes no API for them.
- The only icons used are ingredient record icons; effects are displayed as text.
- List data is refreshed when the window opens and on tab switch; it is not live-updated while the window stays open.
- "Restocking supply" means ingredients a merchant holds at a negative count in their inventory — what they sell and restock.
