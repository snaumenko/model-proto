#!/usr/bin/env bash
# Quint only. Run from anywhere: bash quint/check.sh
set -u
cd "$(dirname "$0")"; source ../scripts/lib.sh
INV="invoiceHasOrder oneActiveInvoice fulfilledIsPaid cancelledHasNoLiveInvoice noticesAreTruthful"

section "1. The spec is well-formed"
expect pass "typecheck"                               "$QUINT" typecheck orders.qnt

section "2. The spec keeps its invariants"
expect pass "simulator: 5,000 random runs"            "$QUINT" run orders.qnt --backend "$QUINT_BACKEND" --invariants $INV --max-samples 5000 --max-steps 20
expect pass "model checker: every reachable state"    "$QUINT" verify orders.qnt --backend tlc --invariants $INV

section "3. The spec is not vacuous (a counterexample here is a witness)"
expect_report "an order can be fulfilled" "\[violation\]"   "$QUINT" verify orders.qnt --backend tlc --invariant neverFulfilled
expect_report "an order can be cancelled" "\[violation\]"   "$QUINT" verify orders.qnt --backend tlc --invariant neverCancelled
expect_report "an invoice can be reissued" "\[violation\]"  "$QUINT" verify orders.qnt --backend tlc --invariant neverReissued

section "4. The planted bug (cancel forgets to void the invoice)"
expect pass "typecheck still passes"                  "$QUINT" typecheck orders_bug.qnt
expect_report "simulator reports a violation" "cancelledHasNoLiveInvoice" "$QUINT" run orders_bug.qnt --backend "$QUINT_BACKEND" --invariants $INV --max-samples 5000 --max-steps 20
expect_report "model checker reports a violation" "\[violation\]" "$QUINT" verify orders_bug.qnt --backend tlc --invariants $INV

section "5. The code follows the spec"
rm -rf traces && mkdir traces
expect pass "generate 200 traces from the spec"       "$QUINT" run orders.qnt --backend "$QUINT_BACKEND" --mbt --n-traces 200 --max-samples 200 --max-steps 15 --out-itf "traces/t{seq}.itf.json"
expect pass "implementation replays every trace"      node --test conformance.test.ts
expect_report "buggy implementation is caught" "state diverged" env BUGGY_IMPL=1 node --test conformance.test.ts

finish
