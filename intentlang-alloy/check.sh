#!/usr/bin/env bash
# IntentLang on top, Alloy underneath. bash intentlang-alloy/check.sh
set -u
cd "$(dirname "$0")"; source ../scripts/lib.sh
CHECKS="InvoiceHasOrder OneActiveInvoice FulfilledIsPaid CancelledHasNoLiveInvoice NoticesAreTruthful"
# `intent test` prints PASS/FAIL lines; make a FAIL line a failing exit code.
intent_test_ok() { local out; out="$("$INTENT" test "$1" 2>&1)"; echo "$out"; echo "$out" | grep -q "passed" && ! echo "$out" | grep -q "FAIL"; }

section "1. The readable spec is well-formed (IntentLang)"
expect pass "intent check"                            "$INTENT" check orders.intent
expect pass "intent verify"                           "$INTENT" verify orders.intent
expect pass "intent test: 6 example scenarios"        intent_test_ok orders.intent

section "2. The derived model keeps its invariants (Alloy, 2 orders, 3 invoices, 15 steps)"
for c in $CHECKS; do
  expect pass "check $c"                              alloy_holds orders.als "$c" out
done

section "3. The model is not vacuous (an instance is the witness)"
expect pass "an order can be fulfilled"               alloy_finds orders.als CanFulfil out
expect pass "an order can be cancelled"               alloy_finds orders.als CanCancel out
expect pass "an invoice can be reissued"              alloy_finds orders.als CanReissue out

section "4. The planted bug (cancel forgets to void the invoice)"
expect pass "intent check still passes"               "$INTENT" check orders_bug.intent
expect pass "intent verify still passes"              "$INTENT" verify orders_bug.intent
expect_report "intent test: one hand-written scenario fails" "FAIL +cancelling voids the issued invoice" intent_test_ok orders_bug.intent
expect pass "Alloy finds a counterexample to CancelledHasNoLiveInvoice" alloy_finds orders_bug.als CancelledHasNoLiveInvoice out_bug

section "5. The code follows the spec"
expect pass "contract property tests"                 node --test contracts.test.ts
expect_report "buggy implementation is caught" "Counterexample" env BUGGY_IMPL=1 node --test contracts.test.ts

rm -rf out
finish
