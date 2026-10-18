# Matrix bitmap data

`led-fonts.json` and `markup_icons.json` are vendored without modification from
Fiestaboard/FiestaBoard commit `043227c018b9a9d0f6a7a3730a77ec3eeec49bdd`,
paths `src/fiestaui/led-fonts.json` and `src/markup_icons.json`.
The accompanying MIT license is from that checkout. `provenance.json` preserves
the upstream FiestaUI font provenance; the icon registry has its own provenance
header. Only these two data files are consumed by the app.

`MatrixRaster.swift` ports the relevant layout rules in `src/led/matrix.py` at
the same commit. Re-vendor deliberately when the upstream output stack releases.
