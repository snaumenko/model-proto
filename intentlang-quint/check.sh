#!/usr/bin/env bash
# IntentLang on top, Quint underneath. bash intentlang-quint/check.sh
set -u
cd "$(dirname "$0")"; source ../scripts/lib.sh
INV="invoiceHasOrder oneActiveInvoice fulfilledIsPaid cancelledHasNoLiveInvoice noticesAreTruthful"
# `intent test` prints PASS/FAIL lines; make a FAIL line a failing exit code.
intent_test_ok() { local out; out="$("$INTENT" test "$1" 2>&1)"; echo "$out"; echo "$out" | grep -q "passed" && ! echo "$out" | grep -q "FAIL"; }

section "1. The readable spec is well-formed (IntentLang)"
expect pass "intent check"                            "$INTENT" check orders.intent
expect pass "intent verify"                           "$INTENT" verify orders.intent
expect pass "intent test: 6 example scenarios"        intent_test_ok orders.intent

section "2. The two tiers have not drifted apart"
"$INTENT" compile orders.intent > ir.json
expect pass "every action and invariant exists in both" node sync-check.mjs

section "3. The derived model keeps its invariants (Quint)"
expect pass "typecheck"                               "$QUINT" typecheck orders.qnt
expect pass "model checker: every reachable state"    "$QUINT" verify orders.qnt --backend tlc --invariants $INV

section "4. The model is not vacuous (a counterexample here is a witness)"
expect_report "an order can be fulfilled" "\[violation\]"   "$QUINT" verify orders.qnt --backend tlc --invariant neverFulfilled
expect_report "an order can be cancelled" "\[violation\]"   "$QUINT" verify orders.qnt --backend tlc --invariant neverCancelled
expect_report "an invoice can be reissued" "\[violation\]"  "$QUINT" verify orders.qnt --backend tlc --invariant neverReissued

section "5. The planted bug (cancel forgets to void the invoice)"
expect pass "intent check still passes"               "$INTENT" check orders_bug.intent
expect pass "intent verify still passes"              "$INTENT" verify orders_bug.intent
expect_report "intent test: one hand-written scenario fails" "FAIL +cancelling voids the issued invoice" intent_test_ok orders_bug.intent
expect pass "name-level drift guard still passes"     node sync-check.mjs orders_bug.qnt
expect_report "Quint model checker reports a violation" "\[violation\]" "$QUINT" verify orders_bug.qnt --backend tlc --invariants $INV

section "6. The code follows the spec"
expect pass "contract property tests"                 node --test contracts.test.ts
expect_report "buggy implementation is caught" "Counterexample" env BUGGY_IMPL=1 node --test contracts.test.ts

finish
