#!/bin/sh
# Package the mod into dist/alchemy-helper.zip for OpenMW's Data Files.
#
# Layout requirement: OpenMW treats a .zip in Data Files as a content folder;
# the .omwscripts manifest must sit at the ROOT of the archive, with every
# script at the relative path listed in it (required modules included, even
# though the manifest only names entry scripts). No wrapping top-level
# directory inside the zip.
set -e
cd "$(dirname "$0")"

MANIFEST=alchemy-helper.omwscripts

# Every script referenced by the manifest must exist before packaging.
for path in $(grep -E '^[A-Z][A-Z ]*:' "$MANIFEST" | sed 's/^[^:]*:[[:space:]]*//'); do
    if [ ! -f "$path" ]; then
        echo "manifest references missing file: $path" >&2
        exit 1
    fi
done

rm -f dist/alchemy-helper.zip
mkdir -p dist
zip -qr dist/alchemy-helper.zip "$MANIFEST" scripts

echo "wrote dist/alchemy-helper.zip:"
unzip -l dist/alchemy-helper.zip
