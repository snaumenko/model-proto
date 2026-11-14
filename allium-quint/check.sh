#!/usr/bin/env bash
# Allium on top, Quint underneath. bash allium-quint/check.sh
set -u
cd "$(dirname "$0")"; source ../scripts/lib.sh
INV="invoiceHasOrder oneActiveInvoice fulfilledIsPaid cancelledHasNoLiveInvoice receiptOnlyForPaidInvoice"
# allium exits 1 on any diagnostic, including info-level ones; fail only on warnings and errors.
allium_clean() { "$ALLIUM" "$1" "$2" | node -e '
  const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
  const bad = [...(d.diagnostics ?? []), ...(d.findings ?? [])].filter((x) => x.severity !== "info");
  for (const x of bad) console.log(`${x.severity} ${x.code}: ${x.message}`);
  process.exit(bad.length ? 1 : 0);'; }

section "1. The readable spec is well-formed (Allium)"
expect pass "allium check"                            allium_clean check orders.allium
expect pass "allium analyse"                          allium_clean analyse orders.allium

section "2. The two tiers have not drifted apart"
"$ALLIUM" plan orders.allium > plan.json
expect pass "every rule and invariant exists in both" node sync-check.mjs

section "3. The derived model keeps its invariants (Quint)"
expect pass "typecheck"                               "$QUINT" typecheck orders.qnt
expect pass "model checker: every reachable state"    "$QUINT" verify orders.qnt --backend tlc --invariants $INV

section "4. The model is not vacuous (a counterexample here is a witness)"
expect_report "an order can be fulfilled" "\[violation\]"   "$QUINT" verify orders.qnt --backend tlc --invariant neverFulfilled
expect_report "an order can be cancelled" "\[violation\]"   "$QUINT" verify orders.qnt --backend tlc --invariant neverCancelled

section "5. The planted bug (cancel forgets to void the invoice)"
expect pass "allium check still passes"               allium_clean check orders_bug.allium
expect pass "allium analyse still passes"             allium_clean analyse orders_bug.allium
expect pass "name-level drift guard still passes"     node sync-check.mjs orders_bug.qnt
expect_report "Quint model checker reports a violation" "\[violation\]" "$QUINT" verify orders_bug.qnt --backend tlc --invariants $INV

section "6. The code follows the spec"
expect pass "obligation-driven tests"                 node --test obligations.test.ts
expect_report "buggy implementation is caught" "CancelledHasNoLiveInvoice" env BUGGY_IMPL=1 node --test obligations.test.ts

finish
