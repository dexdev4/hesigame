#!/usr/bin/env node
// Exports the cars of the garage designer (tools/garage/garage_concepts.html, the "Redline Rush — Garage Concepts" page, plus
// the cars of more_cars.js) as GLB files in the layout tools/convert_garage.py reads ("Redline Rush garage exporter").
//
//   node tools/garage/export.js OUT_DIR [car ids...]      (no ids: every car; GARAGE_FULL=1: the designer's full sampling)
//
// The designer's own modelling code runs here unchanged, with four small tags patched in (which parts are wheels, which
// are the steering wheel, which are the interior, and flat decals turned to face the way they were projected from); then
// export_core.js turns what the designer draws with its shader (masks, arch cut-outs, the open tub under the glass, panel
// lines) into geometry, and writes the file.
'use strict';
require('./designer.js').run('export_core.js', process.argv.slice(2));
