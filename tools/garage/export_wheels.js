#!/usr/bin/env node
// Builds the workshop's wheel designs with the garage designer's own wheel (see wheels_core.js) and writes them for the
// game, at one size that the game fits to each car's tyres:
//
//   node tools/garage/export_wheels.js assets/models/wheels
'use strict';
require('./designer.js').run('wheels_core.js', process.argv.slice(2));
