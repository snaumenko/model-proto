// Quint model derived from orders.allium.
//
// orders.allium is the readable source of truth. This file is its checkable
// twin, maintained by the agent: edit the .allium file first, then mirror the
// change here in the same commit. `node sync-check.mjs` fails if a rule or an
// invariant exists in one file and not in the other.
//
// Mapping (allium -> quint):
//   entity Order / Invoice, status enums   -> orders / invoices maps
//   entity Notice                          -> outbox
//   rule X                                 -> action x (same name, camelCase)
//   rule InvoiceEmailOnIssue               -> folded into systemIssuesInvoice
//                                             (creation and email are one step)
//   when: order: Order.awaiting_invoice    -> the guard of systemIssuesInvoice
//   actor Customer / Staff                 -> Actor values (+ System)
//   invariant X                            -> val x
//   `order: Order` being a required field  -> val invoiceHasOrder
//
// Not modelled: surfaces (who sees what, own orders only), Order.customer,
// Invoice.paid_at and time. The checker says nothing about those.
//
// Check it:
//   quint verify orders.qnt --backend tlc --invariants invoiceHasOrder oneActiveInvoice fulfilledIsPaid cancelledHasNoLiveInvoice receiptOnlyForPaidInvoice
module orders_bug {
  // ---------- Entities ----------
  type OrderId = int
  type InvoiceId = int

  type OrderStatus = Draft | Confirmed | Fulfilled | Cancelled
  type InvoiceStatus = Issued | Paid | Void

  // Relationship: every invoice points at exactly one order.
  type Invoice = { order: OrderId, status: InvoiceStatus }

  // ---------- Actors ----------
  // Quint has no actor construct. An actor is a value, and "who may do what"
  // is a precondition on each action.
  type Actor = Customer | System | Staff

  // ---------- Side effects ----------
  // Quint has no effect construct either. A side effect is state the system
  // appends to: here, an outbox of messages sent to the customer.
  type NoticeKind = InvoiceEmail | Receipt
  type Notice = { kind: NoticeKind, invoice: InvoiceId }

  // ---------- Bounds for checking ----------
  pure val ORDER_IDS: Set[OrderId] = Set(1, 2)
  pure val INVOICE_IDS: Set[InvoiceId] = Set(1, 2, 3)
  pure val ACTORS: Set[Actor] = Set(Customer, System, Staff)

  // ---------- State ----------
  var orders: OrderId -> OrderStatus
  var invoices: InvoiceId -> Invoice
  var outbox: Set[Notice]

  // ---------- Derived views ----------
  def invoicesOf(o: OrderId): Set[InvoiceId] =
    invoices.keys().filter(i => invoices.get(i).order == o)

  def activeInvoicesOf(o: OrderId): Set[InvoiceId] =
    invoicesOf(o).filter(i => invoices.get(i).status != Void)

  def hasPaidInvoice(o: OrderId): bool =
    invoicesOf(o).exists(i => invoices.get(i).status == Paid)

  def orderIs(o: OrderId, s: OrderStatus): bool =
    o.in(orders.keys()) and orders.get(o) == s

  // ---------- Actions ----------
  action init = all {
    orders' = Map(),
    invoices' = Map(),
    outbox' = Set(),
  }

  // Customer creates an order in Draft.
  action customerCreatesOrder(actor: Actor, o: OrderId): bool = all {
    actor == Customer,
    not(o.in(orders.keys())),
    orders' = orders.put(o, Draft),
    invoices' = invoices,
    outbox' = outbox,
  }

  // Customer confirms a draft order.
  action customerConfirmsOrder(actor: Actor, o: OrderId): bool = all {
    actor == Customer,
    orderIs(o, Draft),
    orders' = orders.set(o, Confirmed),
    invoices' = invoices,
    outbox' = outbox,
  }

  // System issues an invoice for a confirmed order that has no active invoice.
  // Side effect: invoice email.
  action systemIssuesInvoice(actor: Actor, o: OrderId, i: InvoiceId): bool = all {
    actor == System,
    orderIs(o, Confirmed),
    activeInvoicesOf(o) == Set(),
    not(i.in(invoices.keys())),
    invoices' = invoices.put(i, { order: o, status: Issued }),
    outbox' = outbox.union(Set({ kind: InvoiceEmail, invoice: i })),
    orders' = orders,
  }

  // Staff voids an unpaid invoice (wrong details); the system may then reissue.
  action staffVoidsInvoice(actor: Actor, i: InvoiceId): bool = all {
    actor == Staff,
    i.in(invoices.keys()),
    invoices.get(i).status == Issued,
    invoices' = invoices.set(i, { ...invoices.get(i), status: Void }),
    orders' = orders,
    outbox' = outbox,
  }

  // Customer pays an issued invoice. Side effect: receipt.
  action customerPaysInvoice(actor: Actor, i: InvoiceId): bool = all {
    actor == Customer,
    i.in(invoices.keys()),
    invoices.get(i).status == Issued,
    invoices' = invoices.set(i, { ...invoices.get(i), status: Paid }),
    outbox' = outbox.union(Set({ kind: Receipt, invoice: i })),
    orders' = orders,
  }

  // Staff fulfils a confirmed order once it is paid.
  action staffFulfilsOrder(actor: Actor, o: OrderId): bool = all {
    actor == Staff,
    orderIs(o, Confirmed),
    hasPaidInvoice(o),
    orders' = orders.set(o, Fulfilled),
    invoices' = invoices,
    outbox' = outbox,
  }

  // Customer cancels before payment. Any issued invoice is voided.
  action customerCancelsOrder(actor: Actor, o: OrderId): bool = all {
    actor == Customer,
    orderIs(o, Draft) or orderIs(o, Confirmed),
    not(hasPaidInvoice(o)),
    orders' = orders.set(o, Cancelled),
    invoices' = invoices, // BUG: mirrors orders_bug.allium
    outbox' = outbox,
  }

  // Any actor may attempt any action; the preconditions decide what happens.
  action step = {
    nondet actor = ACTORS.oneOf()
    nondet o = ORDER_IDS.oneOf()
    nondet i = INVOICE_IDS.oneOf()
    any {
      customerCreatesOrder(actor, o),
      customerConfirmsOrder(actor, o),
      systemIssuesInvoice(actor, o, i),
      staffVoidsInvoice(actor, i),
      customerPaysInvoice(actor, i),
      staffFulfilsOrder(actor, o),
      customerCancelsOrder(actor, o),
    }
  }

  // ---------- Invariants ----------
  // 1. Every invoice refers to an existing order.
  val invoiceHasOrder: bool =
    invoices.keys().forall(i => invoices.get(i).order.in(orders.keys()))

  // 2. An order has at most one non-void invoice.
  val oneActiveInvoice: bool =
    orders.keys().forall(o => size(activeInvoicesOf(o)) <= 1)

  // 3. A fulfilled order has a paid invoice.
  val fulfilledIsPaid: bool =
    orders.keys().forall(o => orders.get(o) == Fulfilled implies hasPaidInvoice(o))

  // 4. A cancelled order has no issued or paid invoice.
  val cancelledHasNoLiveInvoice: bool =
    orders.keys().forall(o => orders.get(o) == Cancelled implies activeInvoicesOf(o) == Set())

  // 5. A receipt exists only for a paid invoice.
  val receiptOnlyForPaidInvoice: bool =
    outbox.forall(n => and {
      n.invoice.in(invoices.keys()),
      n.kind == Receipt implies invoices.get(n.invoice).status == Paid,
    })

  val allInvariants: bool = and {
    invoiceHasOrder,
    oneActiveInvoice,
    fulfilledIsPaid,
    cancelledHasNoLiveInvoice,
    receiptOnlyForPaidInvoice,
  }

  // ---------- Reachability ----------
  // These are stated as "never happens" so that a VIOLATION is the good result:
  // the checker's counterexample is a witness that the state is reachable.
  val neverFulfilled: bool = orders.keys().forall(o => orders.get(o) != Fulfilled)
  val neverCancelled: bool = orders.keys().forall(o => orders.get(o) != Cancelled)
  val neverReissued: bool =
    orders.keys().forall(o => size(invoicesOf(o)) <= 1)
}
