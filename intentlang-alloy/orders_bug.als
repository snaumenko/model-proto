/*
 * Alloy 6 model derived from orders.intent.
 *
 * orders.intent is the readable source of truth. This file is the checkable
 * twin: the same entities, actions and invariants, written so the Alloy
 * analyzer can explore every behaviour within the bounds below.
 *
 * Mapping (intent -> alloy):
 *   state OrderStatus / InvoiceStatus  -> the status sigs
 *   entity Order / Invoice             -> sig Order / Invoice
 *   entity Notice                      -> Emailed / Receipted (the outbox)
 *   action X { requires / ensures }    -> pred x[...] { guard; effect; frame }
 *   properties { requires_role }       -> the Actor argument of each pred
 *   invariant X                        -> assert X { always ... } + check
 *
 * Run:  java -jar alloy.jar exec -f -o out orders.als
 */
module orders_bug

// ---------- Entities ----------
abstract sig OrderStatus {}
one sig Draft, Confirmed, Fulfilled, Cancelled extends OrderStatus {}

abstract sig InvoiceStatus {}
one sig Issued, Paid, Void extends InvoiceStatus {}

// An atom with no status has not been created yet.
sig Order {
  var status: lone OrderStatus
}

sig Invoice {
  var order: lone Order,          // relationship: the order this invoice bills
  var istatus: lone InvoiceStatus
}

// ---------- Actors ----------
abstract sig Actor {}
one sig Customer, System, Staff extends Actor {}

// ---------- Side effects (the outbox) ----------
var sig Emailed in Invoice {}     // an invoice email was sent for these
var sig Receipted in Invoice {}   // a receipt was sent for these

// ---------- Derived views ----------
fun invoicesOf[o: Order]: set Invoice { order.o }
fun activeInvoicesOf[o: Order]: set Invoice { { i: invoicesOf[o] | some i.istatus and i.istatus != Void } }
pred hasPaidInvoice[o: Order] { some i: invoicesOf[o] | i.istatus = Paid }

// ---------- Frame conditions ----------
pred ordersUnchanged { status' = status }
pred invoicesUnchanged { order' = order and istatus' = istatus }
pred outboxUnchanged { Emailed' = Emailed and Receipted' = Receipted }

// ---------- Actions ----------
pred init {
  no status
  no order
  no istatus
  no Emailed
  no Receipted
}

pred createOrder[a: Actor, o: Order] {
  a = Customer
  no o.status
  status' = status + o->Draft
  invoicesUnchanged
  outboxUnchanged
}

pred confirmOrder[a: Actor, o: Order] {
  a = Customer
  o.status = Draft
  status' = status ++ o->Confirmed
  invoicesUnchanged
  outboxUnchanged
}

pred issueInvoice[a: Actor, o: Order, i: Invoice] {
  a = System
  o.status = Confirmed
  no activeInvoicesOf[o]
  no i.istatus
  order' = order + i->o
  istatus' = istatus + i->Issued
  Emailed' = Emailed + i
  Receipted' = Receipted
  ordersUnchanged
}

pred voidInvoice[a: Actor, i: Invoice] {
  a = Staff
  i.istatus = Issued
  istatus' = istatus ++ i->Void
  order' = order
  ordersUnchanged
  outboxUnchanged
}

pred payInvoice[a: Actor, i: Invoice] {
  a = Customer
  i.istatus = Issued
  istatus' = istatus ++ i->Paid
  order' = order
  Receipted' = Receipted + i
  Emailed' = Emailed
  ordersUnchanged
}

pred fulfilOrder[a: Actor, o: Order] {
  a = Staff
  o.status = Confirmed
  hasPaidInvoice[o]
  status' = status ++ o->Fulfilled
  invoicesUnchanged
  outboxUnchanged
}

pred cancelOrder[a: Actor, o: Order] {
  a = Customer
  o.status in Draft + Confirmed
  not hasPaidInvoice[o]
  status' = status ++ o->Cancelled
  istatus' = istatus   // BUG: the issued invoice is no longer voided
  order' = order
  outboxUnchanged
}

pred stutter { ordersUnchanged and invoicesUnchanged and outboxUnchanged }

pred step {
  some a: Actor, o: Order, i: Invoice {
    createOrder[a, o] or confirmOrder[a, o] or issueInvoice[a, o, i]
    or voidInvoice[a, i] or payInvoice[a, i]
    or fulfilOrder[a, o] or cancelOrder[a, o]
  }
}

fact behaviour {
  init
  always (step or stutter)
}

// ---------- Invariants ----------
assert InvoiceHasOrder {
  always all i: Invoice | some i.istatus implies some i.order.status
}

assert OneActiveInvoice {
  always all o: Order | lone activeInvoicesOf[o]
}

assert FulfilledIsPaid {
  always all o: Order | o.status = Fulfilled implies hasPaidInvoice[o]
}

assert CancelledHasNoLiveInvoice {
  always all o: Order | o.status = Cancelled implies no activeInvoicesOf[o]
}

assert NoticesAreTruthful {
  always (Emailed in istatus.InvoiceStatus and Receipted in istatus.Paid)
}

check InvoiceHasOrder           for exactly 2 Order, exactly 3 Invoice, 15 steps
check OneActiveInvoice          for exactly 2 Order, exactly 3 Invoice, 15 steps
check FulfilledIsPaid           for exactly 2 Order, exactly 3 Invoice, 15 steps
check CancelledHasNoLiveInvoice for exactly 2 Order, exactly 3 Invoice, 15 steps
check NoticesAreTruthful        for exactly 2 Order, exactly 3 Invoice, 15 steps

// ---------- Reachability (an instance is the good result) ----------
pred CanFulfil { eventually some o: Order | o.status = Fulfilled }
pred CanCancel { eventually some o: Order | o.status = Cancelled }
pred CanReissue { eventually some o: Order | #invoicesOf[o] > 1 }

run CanFulfil  for exactly 2 Order, exactly 3 Invoice, 15 steps
run CanCancel  for exactly 2 Order, exactly 3 Invoice, 15 steps
run CanReissue for exactly 2 Order, exactly 3 Invoice, 15 steps
