// Drift guard for the two-tier setup: every Allium rule and invariant must have
// a counterpart in the Quint model, and the other way round.
//
// This is a name-level check only. It proves the two files talk about the same
// things, not that they say the same thing about them.
//
//   allium plan orders.allium > plan.json && node sync-check.mjs [orders.qnt]

import { readFileSync } from "node:fs";
import { join } from "node:path";

const dir = import.meta.dirname;
const plan = JSON.parse(readFileSync(join(dir, "plan.json"), "utf8"));
const quint = readFileSync(join(dir, process.argv[2] ?? "orders.qnt"), "utf8");

const camel = (s) => s[0].toLowerCase() + s.slice(1);
const ids = (category) =>
  plan.obligations.filter((o) => o.category === category).map((o) => o.id.split(".").at(-1));

// Deliberate differences, each with its reason.
const foldedRules = { InvoiceEmailOnIssue: "part of systemIssuesInvoice" };
const quintOnlyInvariants = { invoiceHasOrder: "a required field in Allium, so not a named invariant there" };

const alliumRules = ids("rule_success");
const alliumInvariants = ids("invariant");
const quintActions = [...quint.matchAll(/^\s*action (\w+)\(/gm)].map((m) => m[1]);
const quintInvariants = [...quint.matchAll(/val allInvariants[^{]*\{([^}]*)\}/g)][0][1]
  .split(",").map((s) => s.trim()).filter(Boolean);

const problems = [];
for (const rule of alliumRules) {
  if (!(rule in foldedRules) && !quintActions.includes(camel(rule)))
    problems.push(`Allium rule ${rule} has no Quint action ${camel(rule)}`);
}
for (const action of quintActions) {
  if (!alliumRules.map(camel).includes(action))
    problems.push(`Quint action ${action} has no Allium rule`);
}
for (const inv of alliumInvariants) {
  if (!quintInvariants.includes(camel(inv)))
    problems.push(`Allium invariant ${inv} is not checked in Quint (${camel(inv)})`);
}
for (const inv of quintInvariants) {
  if (!(inv in quintOnlyInvariants) && !alliumInvariants.map(camel).includes(inv))
    problems.push(`Quint invariant ${inv} has no Allium invariant`);
}

if (problems.length) {
  console.error("DRIFT between orders.allium and the Quint model:");
  for (const p of problems) console.error("  - " + p);
  process.exit(1);
}
console.log(
  `in sync: ${alliumRules.length} rules (${Object.keys(foldedRules).length} folded), ` +
    `${alliumInvariants.length} Allium invariants, ${quintInvariants.length} Quint invariants`,
);
