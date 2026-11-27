#!/usr/bin/env node
// Prints the fixture's one behaviour: a greeting for the named user.
const name = process.argv[2] || "world";
console.log(`hello, ${name}`);
