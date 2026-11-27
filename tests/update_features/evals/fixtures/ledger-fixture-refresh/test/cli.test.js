// Pins both behaviours: the plain greeting and the --shout upper-cased form.
const { execFileSync } = require("node:child_process");
const run = (args) => execFileSync("node", ["src/cli.js", ...args]).toString().trim();
if (run(["ada"]) !== "hello, ada") throw new Error("plain greeting changed");
if (run(["ada", "--shout"]) !== "HELLO, ADA") throw new Error("--shout not honoured");
if (run([]) !== "hello, world") throw new Error("default name changed");
console.log("ok");
