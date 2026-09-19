# Registering Alchemist's Almanac in OpenMW

## Overview

**Alchemist's Almanac** (project directory: `alchemy-helper`) is an OpenMW Lua mod
that provides an in-game alchemy reference — a searchable list of ingredients with
their effects, values, and vendor information.

**Target version:** OpenMW 0.50 and later.

## Mod Structure

```
alchemy-helper/
├── alchemy-helper.omwscripts   # OpenMW Lua script manifest
├── scripts/
│   └── alchemy-helper/
│       └── init.lua            # Script entry point (GLOBAL context)
├── data/                       # Placeholder for future assets
└── docs/
    └── registration.md         # This file
```

The manifest declares the `init.lua` script as a `GLOBAL` context script, meaning
it is always active during a game session and has read-write access to the entire
world.

## Registering the Mod

Add one of the following lines to your `openmw.cfg`:

### Method 1: `data=` (recommended)

```ini
data=path/to/alchemy-helper
```

Place the `alchemy-helper` directory (the one containing `alchemy-helper.omwscripts`)
somewhere on your filesystem and point `data=` to that directory. OpenMW will
search that path when resolving script file references from the manifest.

### Method 2: `content=`

```ini
content=alchemy-helper.omwscripts
```

Place the `.omwscripts` file in a directory that is already listed in your `data=`
path, then reference the manifest filename directly. OpenMW resolves the relative
paths in the manifest against the `data=` search path.

### Example `openmw.cfg` entries

```ini
# Add the mod's directory to the data search path
data=/home/username/MyMods/alchemy-helper

# Or reference the manifest directly (requires the manifest to be in a data= path)
# content=alchemy-helper.omwscripts
```

## Configuration

The mod supports the following configuration option via OpenMW's standard mod
configuration mechanisms:

- **Immersive Mode** — When enabled, the Ingredient List and Shopping Planner
  show only ingredients and merchants the player has encountered.

## Version Notes

- Requires **OpenMW 0.50+**.
- Uses the `GLOBAL` flag, available since OpenMW 0.50.
- Does **not** use the `LOAD` flag (introduced in OpenMW 0.51.0), ensuring
  compatibility with 0.50.x releases.
