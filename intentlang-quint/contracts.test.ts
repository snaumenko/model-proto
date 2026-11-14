// Contract-based property tests: each IntentLang action's `requires` / `ensures`
// and every `invariant`, transcribed by hand from orders.intent, then exercised
// with random action sequences.
//
// (`intent test-harness` only emits Rust today, so this file is hand-derived.)
//
//   node --test contracts.test.ts
//   BUGGY_IMPL=1 node --test contracts.test.ts

import { test } from "node:test";
import assert from "node:assert/strict";
import fc from "fast-check";
import { OrderSystem, Rejected, brokenInvariants, type Actor } from "../impl/orders.ts";

const buggyImpl = process.env.BUGGY_IMPL === "1";

type Args = { actor: Actor; order: number; invoice: number };
type Snapshot = {
  orders: Record<number, string>;
  invoices: Record<number, { order: number; status: string }>;
  notices: string[];
};

const snapshot = (s: OrderSystem): Snapshot => ({
  orders: Object.fromEntries(s.orders),
  invoices: Object.fromEntries([...s.invoices].map(([k, v]) => [k, { ...v }])),
  notices: s.outbox.map((n) => `${n.kind}:${n.invoice}`),
});

const invoicesOf = (s: Snapshot, order: number) =>
  Object.entries(s.invoices).filter(([, i]) => i.order === order);

interface Contract {
  role: Actor; // properties { requires_role }
  requires: (pre: Snapshot, a: Args) => boolean;
  ensures: (pre: Snapshot, post: Snapshot, a: Args) => boolean;
  run: (s: OrderSystem, a: Args) => void;
}

const contracts: Record<string, Contract> = {
  CreateOrder: {
    role: "Customer",
    requires: (pre, a) => !(a.order in pre.orders),
    ensures: (_pre, post, a) => post.orders[a.order] === "Draft",
    run: (s, a) => s.createOrder(a.actor, a.order),
  },
  ConfirmOrder: {
    role: "Customer",
    requires: (pre, a) => pre.orders[a.order] === "Draft",
    ensures: (_pre, post, a) => post.orders[a.order] === "Confirmed",
    run: (s, a) => s.confirmOrder(a.actor, a.order),
  },
  IssueInvoice: {
    role: "System",
    requires: (pre, a) =>
      pre.orders[a.order] === "Confirmed" &&
      !invoicesOf(pre, a.order).some(([, i]) => i.status !== "Void") &&
      !(a.invoice in pre.invoices), // fresh id: an implementation detail of this API
    ensures: (_pre, post, a) =>
      invoicesOf(post, a.order).some(([, i]) => i.status === "Issued") &&
      post.notices.includes(`InvoiceEmail:${a.invoice}`),
    run: (s, a) => s.issueInvoice(a.actor, a.order, a.invoice),
  },
  VoidInvoice: {
    role: "Staff",
    requires: (pre, a) => pre.invoices[a.invoice]?.status === "Issued",
    ensures: (_pre, post, a) => post.invoices[a.invoice].status === "Void",
    run: (s, a) => s.voidInvoice(a.actor, a.invoice),
  },
  PayInvoice: {
    role: "Customer",
    requires: (pre, a) => pre.invoices[a.invoice]?.status === "Issued",
    ensures: (_pre, post, a) =>
      post.invoices[a.invoice].status === "Paid" && post.notices.includes(`Receipt:${a.invoice}`),
    run: (s, a) => s.payInvoice(a.actor, a.invoice),
  },
  FulfilOrder: {
    role: "Staff",
    requires: (pre, a) =>
      pre.orders[a.order] === "Confirmed" && invoicesOf(pre, a.order).some(([, i]) => i.status === "Paid"),
    ensures: (_pre, post, a) => post.orders[a.order] === "Fulfilled",
    run: (s, a) => s.fulfilOrder(a.actor, a.order),
  },
  CancelOrder: {
    role: "Customer",
    requires: (pre, a) =>
      (pre.orders[a.order] === "Draft" || pre.orders[a.order] === "Confirmed") &&
      !invoicesOf(pre, a.order).some(([, i]) => i.status === "Paid"),
    ensures: (_pre, post, a) =>
      post.orders[a.order] === "Cancelled" && invoicesOf(post, a.order).every(([, i]) => i.status === "Void"),
    run: (s, a) => s.cancelOrder(a.actor, a.order),
  },
};

// Mostly the right actor for the action (so sequences get somewhere),
// sometimes a wrong one (so role checks are exercised too).
const command = fc
  .record({
    action: fc.constantFrom(...Object.keys(contracts)),
    wrongActor: fc.option(fc.constantFrom<Actor>("Customer", "System", "Staff"), { freq: 8, nil: undefined }),
    order: fc.integer({ min: 1, max: 2 }),
    invoice: fc.integer({ min: 1, max: 3 }),
  })
  .map(({ wrongActor, ...c }) => ({ ...c, actor: wrongActor ?? contracts[c.action].role }));

test("every action honours its contract and every invariant survives", () => {
  let accepted = 0;
  let rejected = 0;
  fc.assert(
    fc.property(fc.array(command, { minLength: 20, maxLength: 40 }), (commands) => {
      const sys = new OrderSystem({ cancelVoidsInvoice: !buggyImpl });
      for (const { action, ...args } of commands) {
        const contract = contracts[action];
        const pre = snapshot(sys);
        const allowed = args.actor === contract.role && contract.requires(pre, args);
        let threw = false;
        try {
          contract.run(sys, args);
        } catch (e) {
          if (!(e instanceof Rejected)) throw e;
          threw = true;
        }
        const post = snapshot(sys);
        const where = `${action}(${JSON.stringify(args)})`;
        if (allowed) {
          assert.ok(!threw, `${where}: requires holds but the implementation rejected it`);
          assert.ok(contract.ensures(pre, post, args), `${where}: ensures does not hold`);
          accepted++;
        } else {
          assert.ok(threw, `${where}: requires fails but the implementation accepted it`);
          assert.deepEqual(post, pre, `${where}: a rejected action changed state`);
          rejected++;
        }
        assert.deepEqual(brokenInvariants(sys), [], `${where}: invariant broken`);
      }
    }),
    { numRuns: 2000, seed: 20261113 },
  );
  console.log(`checked ${accepted} accepted and ${rejected} rejected actions`);
});
