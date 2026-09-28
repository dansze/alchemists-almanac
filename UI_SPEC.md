# Alchemist's Almanac UI
The main mod UI consists of a window with two tabs: a searchable Ingredients List, and an effect-based Shopping Planner.

## Ingredients List

The ingredients list primarily consists of a list of Ingredients and a search bar text field. The ingredients list should show a scrollable view of all ingredients that have a substring match to the search bar with in any of its:

- Name
- Effect Names, including any parameters that would affect the display name of the effect like Strength or Fatigue

Ingredients should also be filtered to only discovered ingredients if Immersive Mode is on in the mod's settings.

Each ingredient display should include the following.

- Name
- Icon
- Effects (including effect icon)

## Shopping Planner

The shopping planner consists of two lists. The first is a list of effects, filterable by name. In Immersive mode, this should only include effects from discovered ingredients. These effects should be selectable.