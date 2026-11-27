#!/usr/bin/env node
// Greets the named user. With --shout, the greeting is upper-cased.
const args = process.argv.slice(2);
const shout = args.includes("--shout");
const name = args.find((a) => !a.startsWith("--")) || "world";
const greeting = `hello, ${name}`;
console.log(shout ? greeting.toUpperCase() : greeting);
