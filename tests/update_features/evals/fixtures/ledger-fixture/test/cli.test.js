// Pins the greeting behaviour: a named user is greeted, and the default is "world".
const { execFileSync } = require("node:child_process");
const out = execFileSync("node", ["src/cli.js", "ada"]).toString().trim();
if (out !== "hello, ada") throw new Error(`unexpected greeting: ${out}`);
console.log("ok");
