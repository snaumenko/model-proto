// Quint is the only spec artifact.
// Order + Invoice: two entities, their lifecycles, who may act, side effects, invariants.
//
// Check it:
//   quint typecheck orders.qnt
//   quint run    orders.qnt --invariants invoiceHasOrder oneActiveInvoice fulfilledIsPaid cancelledHasNoLiveInvoice noticesAreTruthful
//   quint verify orders.qnt --invariants invoiceHasOrder oneActiveInvoice fulfilledIsPaid cancelledHasNoLiveInvoice noticesAreTruthful
module orders {
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
  action createOrder(actor: Actor, o: OrderId): bool = all {
    actor == Customer,
    not(o.in(orders.keys())),
    orders' = orders.put(o, Draft),
    invoices' = invoices,
    outbox' = outbox,
  }

  // Customer confirms a draft order.
  action confirmOrder(actor: Actor, o: OrderId): bool = all {
    actor == Customer,
    orderIs(o, Draft),
    orders' = orders.set(o, Confirmed),
    invoices' = invoices,
    outbox' = outbox,
  }

  // System issues an invoice for a confirmed order that has no active invoice.
  // Side effect: invoice email.
  action issueInvoice(actor: Actor, o: OrderId, i: InvoiceId): bool = all {
    actor == System,
    orderIs(o, Confirmed),
    activeInvoicesOf(o) == Set(),
    not(i.in(invoices.keys())),
    invoices' = invoices.put(i, { order: o, status: Issued }),
    outbox' = outbox.union(Set({ kind: InvoiceEmail, invoice: i })),
    orders' = orders,
  }

  // Staff voids an unpaid invoice (wrong details); the system may then reissue.
  action voidInvoice(actor: Actor, i: InvoiceId): bool = all {
    actor == Staff,
    i.in(invoices.keys()),
    invoices.get(i).status == Issued,
    invoices' = invoices.set(i, { ...invoices.get(i), status: Void }),
    orders' = orders,
    outbox' = outbox,
  }

  // Customer pays an issued invoice. Side effect: receipt.
  action payInvoice(actor: Actor, i: InvoiceId): bool = all {
    actor == Customer,
    i.in(invoices.keys()),
    invoices.get(i).status == Issued,
    invoices' = invoices.set(i, { ...invoices.get(i), status: Paid }),
    outbox' = outbox.union(Set({ kind: Receipt, invoice: i })),
    orders' = orders,
  }

  // Staff fulfils a confirmed order once it is paid.
  action fulfilOrder(actor: Actor, o: OrderId): bool = all {
    actor == Staff,
    orderIs(o, Confirmed),
    hasPaidInvoice(o),
    orders' = orders.set(o, Fulfilled),
    invoices' = invoices,
    outbox' = outbox,
  }

  // Customer cancels before payment. Any issued invoice is voided.
  action cancelOrder(actor: Actor, o: OrderId): bool = all {
    actor == Customer,
    orderIs(o, Draft) or orderIs(o, Confirmed),
    not(hasPaidInvoice(o)),
    orders' = orders.set(o, Cancelled),
    invoices' = invoices.keys().mapBy(i =>
      if (invoices.get(i).order == o and invoices.get(i).status == Issued)
        { ...invoices.get(i), status: Void }
      else
        invoices.get(i)
    ),
    outbox' = outbox,
  }

  // Any actor may attempt any action; the preconditions decide what happens.
  action step = {
    nondet actor = ACTORS.oneOf()
    nondet o = ORDER_IDS.oneOf()
    nondet i = INVOICE_IDS.oneOf()
    any {
      createOrder(actor, o),
      confirmOrder(actor, o),
      issueInvoice(actor, o, i),
      voidInvoice(actor, i),
      payInvoice(actor, i),
      fulfilOrder(actor, o),
      cancelOrder(actor, o),
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

  // 5. Side effects are truthful: every notice names a real invoice,
  //    and a receipt exists only for a paid invoice.
  val noticesAreTruthful: bool =
    outbox.forall(n => and {
      n.invoice.in(invoices.keys()),
      n.kind == Receipt implies invoices.get(n.invoice).status == Paid,
    })

  val allInvariants: bool = and {
    invoiceHasOrder,
    oneActiveInvoice,
    fulfilledIsPaid,
    cancelledHasNoLiveInvoice,
    noticesAreTruthful,
  }

  // ---------- Reachability ----------
  // These are stated as "never happens" so that a VIOLATION is the good result:
  // the checker's counterexample is a witness that the state is reachable.
  val neverFulfilled: bool = orders.keys().forall(o => orders.get(o) != Fulfilled)
  val neverCancelled: bool = orders.keys().forall(o => orders.get(o) != Cancelled)
  val neverReissued: bool =
    orders.keys().forall(o => size(invoicesOf(o)) <= 1)
}
