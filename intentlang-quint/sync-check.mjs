// Drift guard for the two-tier setup: every IntentLang action and invariant
// must have a counterpart in the Quint model, and the other way round.
//
// This is a name-level check only. It proves the two files talk about the same
// things, not that they say the same thing about them.
//
//   intent compile orders.intent > ir.json && node sync-check.mjs [orders.qnt]

import { readFileSync } from "node:fs";
import { join } from "node:path";

const dir = import.meta.dirname;
const ir = JSON.parse(readFileSync(join(dir, "ir.json"), "utf8"));
const quint = readFileSync(join(dir, process.argv[2] ?? "orders.qnt"), "utf8");

const camel = (s) => s[0].toLowerCase() + s.slice(1);
const intentActions = ir.functions.map((f) => camel(f.name));
const intentInvariants = ir.invariants.map((i) => camel(i.name));
const quintActions = [...quint.matchAll(/^\s*action (\w+)\(/gm)].map((m) => m[1]);
const quintInvariants = [...quint.matchAll(/val allInvariants[^{]*\{([^}]*)\}/g)][0][1]
  .split(",").map((s) => s.trim()).filter(Boolean);

const problems = [
  ...intentActions.filter((a) => !quintActions.includes(a)).map((a) => `IntentLang action ${a} has no Quint action`),
  ...quintActions.filter((a) => !intentActions.includes(a)).map((a) => `Quint action ${a} has no IntentLang action`),
  ...intentInvariants.filter((i) => !quintInvariants.includes(i)).map((i) => `IntentLang invariant ${i} is not checked in Quint`),
  ...quintInvariants.filter((i) => !intentInvariants.includes(i)).map((i) => `Quint invariant ${i} has no IntentLang invariant`),
];

if (problems.length) {
  console.error("DRIFT between orders.intent and the Quint model:");
  for (const p of problems) console.error("  - " + p);
  process.exit(1);
}
console.log(`in sync: ${intentActions.length} actions, ${intentInvariants.length} invariants`);
