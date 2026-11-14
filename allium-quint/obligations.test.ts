// Tests written from the obligations that `allium plan orders.allium` emits.
// Each test is named after the obligation id it discharges. The last test fails
// if the plan contains an obligation that is neither tested nor waived, so a
// spec change that adds behaviour cannot slip past the tests.
//
//   allium plan orders.allium > plan.json
//   node --test obligations.test.ts
//   BUGGY_IMPL=1 node --test obligations.test.ts

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import fc from "fast-check";
import { OrderSystem, Rejected, invariants, type Actor } from "../impl/orders.ts";

const buggyImpl = process.env.BUGGY_IMPL === "1";
const fresh = () => new OrderSystem({ cancelVoidsInvoice: !buggyImpl });
const rejects = (f: () => void) => assert.throws(f, Rejected);

// ---- fixtures: a system brought to a named point in the lifecycle ----
function withDraft() { const s = fresh(); s.createOrder("Customer", 1); return s; }
function withConfirmed() { const s = withDraft(); s.confirmOrder("Customer", 1); return s; }
function withIssued() { const s = withConfirmed(); s.issueInvoice("System", 1, 1); return s; }
function withPaid() { const s = withIssued(); s.payInvoice("Customer", 1); return s; }
function withFulfilled() { const s = withPaid(); s.fulfilOrder("Staff", 1); return s; }
function withCancelled() { const s = withIssued(); s.cancelOrder("Customer", 1); return s; }

const covered = new Set<string>();
function obligation(ids: string | string[], body: () => void) {
  const list = [ids].flat();
  for (const id of list) covered.add(id);
  test(list.join(" + "), body);
}

// ---- rules: success, entity creation, failure per `requires` ----
obligation(["rule-success.CustomerCreatesOrder", "rule-entity-creation.CustomerCreatesOrder.1"], () => {
  assert.equal(withDraft().orders.get(1), "Draft");
});

obligation(["rule-success.CustomerConfirmsOrder", "transition-edge.Order.draft.confirmed"], () => {
  assert.equal(withConfirmed().orders.get(1), "Confirmed");
});
obligation("rule-failure.CustomerConfirmsOrder.1", () => {
  const s = withConfirmed();
  rejects(() => s.confirmOrder("Customer", 1)); // requires: order.status = draft
});

obligation(["rule-success.SystemIssuesInvoice", "rule-entity-creation.SystemIssuesInvoice.1"], () => {
  assert.deepEqual(withIssued().invoices.get(1), { order: 1, status: "Issued" });
});
obligation(["rule-success.InvoiceEmailOnIssue", "rule-entity-creation.InvoiceEmailOnIssue.1"], () => {
  assert.deepEqual(withIssued().outbox, [{ kind: "InvoiceEmail", invoice: 1 }]);
});
obligation("derived.Order.awaiting_invoice", () => {
  // The system issues only while a confirmed order has no active invoice.
  rejects(() => withDraft().issueInvoice("System", 1, 1));
  rejects(() => withIssued().issueInvoice("System", 1, 2));
  const s = withIssued();
  s.voidInvoice("Staff", 1);
  s.issueInvoice("System", 1, 2); // awaiting again after the void
  assert.equal(s.invoices.get(2)!.status, "Issued");
});

obligation(
  ["rule-success.CustomerPaysInvoice", "rule-entity-creation.CustomerPaysInvoice.1", "transition-edge.Invoice.issued.paid"],
  () => {
    const s = withPaid();
    assert.equal(s.invoices.get(1)!.status, "Paid");
    assert.deepEqual(s.outbox.at(-1), { kind: "Receipt", invoice: 1 });
  },
);
obligation("rule-failure.CustomerPaysInvoice.1", () => {
  const s = withPaid();
  rejects(() => s.payInvoice("Customer", 1)); // requires: invoice.status = issued
});

obligation(["rule-success.StaffVoidsInvoice", "transition-edge.Invoice.issued.void"], () => {
  const s = withIssued();
  s.voidInvoice("Staff", 1);
  assert.equal(s.invoices.get(1)!.status, "Void");
});
obligation("rule-failure.StaffVoidsInvoice.1", () => {
  const s = withPaid();
  rejects(() => s.voidInvoice("Staff", 1)); // requires: invoice.status = issued
});

obligation(["rule-success.StaffFulfilsOrder", "transition-edge.Order.confirmed.fulfilled"], () => {
  assert.equal(withFulfilled().orders.get(1), "Fulfilled");
});
obligation("rule-failure.StaffFulfilsOrder.1", () => {
  rejects(() => withDraft().fulfilOrder("Staff", 1)); // requires: order.status = confirmed
});
obligation("rule-failure.StaffFulfilsOrder.2", () => {
  rejects(() => withIssued().fulfilOrder("Staff", 1)); // requires: order.is_paid
});

obligation(["rule-success.CustomerCancelsOrder", "transition-edge.Order.confirmed.cancelled"], () => {
  const s = withCancelled();
  assert.equal(s.orders.get(1), "Cancelled");
  // ensures: for invoice in order.issued_invoices: invoice.status = void
  assert.equal(s.invoices.get(1)!.status, "Void");
});
obligation("transition-edge.Order.draft.cancelled", () => {
  const s = withDraft();
  s.cancelOrder("Customer", 1);
  assert.equal(s.orders.get(1), "Cancelled");
});
obligation("rule-failure.CustomerCancelsOrder.1", () => {
  rejects(() => withFulfilled().cancelOrder("Customer", 1)); // requires: status in {draft, confirmed}
});
obligation("rule-failure.CustomerCancelsOrder.2", () => {
  rejects(() => withPaid().cancelOrder("Customer", 1)); // requires: not order.is_paid
});

// ---- lifecycles ----
obligation(["transition-terminal.Order.status", "transition-rejected.Order.status"], () => {
  for (const s of [withFulfilled(), withCancelled()]) {
    rejects(() => s.confirmOrder("Customer", 1));
    rejects(() => s.cancelOrder("Customer", 1));
    rejects(() => s.fulfilOrder("Staff", 1));
  }
  rejects(() => withDraft().fulfilOrder("Staff", 1)); // draft -> fulfilled is not an edge
});
obligation(["transition-terminal.Invoice.status", "transition-rejected.Invoice.status"], () => {
  const paid = withPaid();
  rejects(() => paid.voidInvoice("Staff", 1));
  rejects(() => paid.payInvoice("Customer", 1));
  const voided = withCancelled();
  rejects(() => voided.payInvoice("Customer", 1));
  rejects(() => voided.voidInvoice("Staff", 1));
});

// ---- relationships, projections, derived values ----
obligation(
  [
    "entity-relationship.Order.invoices",
    "projection.Order.issued_invoices",
    "projection.Order.paid_invoices",
    "projection.Order.active_invoices",
    "derived.Order.is_paid",
  ],
  () => {
    const s = withIssued();
    s.voidInvoice("Staff", 1);
    s.issueInvoice("System", 1, 2);
    assert.deepEqual(s.invoicesOf(1), [1, 2]);
    assert.deepEqual(s.activeInvoicesOf(1), [2]);
    assert.equal(s.hasPaidInvoice(1), false);
    s.payInvoice("Customer", 2);
    assert.equal(s.hasPaidInvoice(1), true);
  },
);

// ---- invariants: must hold after every rule, over random rule sequences ----
const step = fc.record({
  rule: fc.constantFrom("create", "confirm", "issue", "void", "pay", "fulfil", "cancel"),
  order: fc.integer({ min: 1, max: 2 }),
  invoice: fc.integer({ min: 1, max: 3 }),
});
const actorOf: Record<string, Actor> = {
  create: "Customer", confirm: "Customer", pay: "Customer", cancel: "Customer",
  issue: "System", void: "Staff", fulfil: "Staff",
};
function run(s: OrderSystem, { rule, order, invoice }: { rule: string; order: number; invoice: number }) {
  const a = actorOf[rule];
  try {
    if (rule === "create") s.createOrder(a, order);
    if (rule === "confirm") s.confirmOrder(a, order);
    if (rule === "issue") s.issueInvoice(a, order, invoice);
    if (rule === "void") s.voidInvoice(a, invoice);
    if (rule === "pay") s.payInvoice(a, invoice);
    if (rule === "fulfil") s.fulfilOrder(a, order);
    if (rule === "cancel") s.cancelOrder(a, order);
  } catch (e) {
    if (!(e instanceof Rejected)) throw e;
  }
}
const invariantOf: Record<string, string> = {
  "invariant.Order.OneActiveInvoice": "oneActiveInvoice",
  "invariant.Order.FulfilledIsPaid": "fulfilledIsPaid",
  "invariant.Order.CancelledHasNoLiveInvoice": "cancelledHasNoLiveInvoice",
  "invariant.ReceiptOnlyForPaidInvoice": "noticesAreTruthful",
};
for (const [id, name] of Object.entries(invariantOf)) {
  obligation(id, () => {
    fc.assert(
      fc.property(fc.array(step, { minLength: 20, maxLength: 40 }), (steps) => {
        const s = fresh();
        for (const st of steps) {
          run(s, st);
          assert.ok(invariants[name](s), `${name} broken after ${JSON.stringify(st)}`);
        }
      }),
      { numRuns: 1000, seed: 20261113 },
    );
  });
}

// ---- obligations this implementation cannot discharge, with the reason ----
const waived: Record<string, string> = {
  "entity-fields.User": "the implementation has roles, not user records",
  "entity-fields.Order": "covered field by field by the tests above; customer is not implemented",
  "entity-fields.Invoice": "covered by the tests above; paid_at is not implemented",
  "entity-fields.Notice": "covered by the notice assertions above",
  "when-presence.Invoice.paid_at": "paid_at is not implemented",
  "when-set.CustomerPaysInvoice.Invoice.paid_at": "paid_at is not implemented",
  "surface-actor.Storefront": "no boundary layer in this prototype",
  "surface-provides.Storefront": "no boundary layer in this prototype",
  "surface-actor.CustomerOrder": "no boundary layer in this prototype",
  "surface-exposure.CustomerOrder": "no boundary layer in this prototype",
  "surface-provides.CustomerOrder": "no boundary layer in this prototype",
  "surface-actor.BackOffice": "no boundary layer in this prototype",
  "surface-exposure.BackOffice": "no boundary layer in this prototype",
  "surface-provides.BackOffice": "no boundary layer in this prototype",
};

test("every obligation in plan.json is tested or explicitly waived", () => {
  const plan = JSON.parse(readFileSync(join(import.meta.dirname, "plan.json"), "utf8"));
  const planned: string[] = plan.obligations.map((o: { id: string }) => o.id);
  const unaccounted = planned.filter((id) => !covered.has(id) && !(id in waived));
  const stale = [...covered, ...Object.keys(waived)].filter((id) => !planned.includes(id));
  assert.deepEqual(unaccounted, [], "obligations with no test and no waiver");
  assert.deepEqual(stale, [], "tests or waivers for obligations the spec no longer has");
  console.log(`${planned.length} obligations: ${covered.size} tested, ${Object.keys(waived).length} waived`);
});
