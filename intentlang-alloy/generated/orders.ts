// Generated from Orders.intent
/**
 * Orders and their invoices: two entities, their lifecycles,
 * who may act, the side effects, and the invariants that tie them together.
 */

export type OrderStatus = "Draft" | "Confirmed" | "Fulfilled" | "Cancelled";

export function isValidOrderStatusTransition(from: OrderStatus, to: OrderStatus): boolean {
  const valid: Record<string, string[]> = {
    "Draft": ["Confirmed", "Cancelled"],
    "Confirmed": ["Fulfilled", "Cancelled"],
    "Fulfilled": [],
    "Cancelled": [],
  };
  return (valid[from] ?? []).includes(to);
}

export type InvoiceStatus = "Issued" | "Paid" | "Void";

export function isValidInvoiceStatusTransition(from: InvoiceStatus, to: InvoiceStatus): boolean {
  const valid: Record<string, string[]> = {
    "Issued": ["Paid", "Void"],
    "Paid": [],
    "Void": [],
  };
  return (valid[from] ?? []).includes(to);
}

export interface Order {
  id: string;
  status: OrderStatus;
}

export interface Invoice {
  id: string;
  order: Order;
  status: InvoiceStatus;
}

/**
 * Side effect: a message sent to the customer.
 */
export interface Notice {
  kind: "InvoiceEmail" | "Receipt";
  invoice: Invoice;
}

/**
 * The customer creates an order in Draft.
 *
 * @param id - string
 *
 * @requires
 *   - !exists o: Order => o.id == id
 *
 * @ensures
 *   - exists o: Order => o.id == id && o.status == Draft
 *
 * @properties
 *   - requires_role: "customer"
 */
export function createOrder(id: string): void {
  throw new Error("TODO: implement createOrder");
}

/**
 * The customer confirms a draft order.
 *
 * @param order - Order
 *
 * @requires
 *   - order.status == Draft
 *
 * @ensures
 *   - order.status == Confirmed
 *
 * @properties
 *   - requires_role: "customer"
 */
export function confirmOrder(order: Order): void {
  throw new Error("TODO: implement confirmOrder");
}

/**
 * The system issues an invoice for a confirmed order with no active invoice.
 * Side effect: invoice email.
 *
 * @param order - Order
 *
 * @requires
 *   - order.status == Confirmed
 *   - !exists i: Invoice => i.order == order && i.status != Void
 *
 * @ensures
 *   - exists i: Invoice => i.order == order && i.status == Issued
 *   - exists n: Notice => n.kind == InvoiceEmail && n.invoice.order == order
 *
 * @properties
 *   - requires_role: "system"
 *   - audit_logged: true
 */
export function issueInvoice(order: Order): void {
  throw new Error("TODO: implement issueInvoice");
}

/**
 * Staff void an unpaid invoice; the system may then reissue.
 *
 * @param invoice - Invoice
 *
 * @requires
 *   - invoice.status == Issued
 *
 * @ensures
 *   - invoice.status == Void
 *
 * @properties
 *   - requires_role: "staff"
 */
export function voidInvoice(invoice: Invoice): void {
  throw new Error("TODO: implement voidInvoice");
}

/**
 * The customer pays an issued invoice. Side effect: receipt.
 *
 * @param invoice - Invoice
 *
 * @requires
 *   - invoice.status == Issued
 *
 * @ensures
 *   - invoice.status == Paid
 *   - exists n: Notice => n.kind == Receipt && n.invoice == invoice
 *
 * @properties
 *   - requires_role: "customer"
 *   - idempotent: true
 *   - audit_logged: true
 */
export function payInvoice(invoice: Invoice): void {
  throw new Error("TODO: implement payInvoice");
}

/**
 * Staff fulfil a confirmed order once it is paid.
 *
 * @param order - Order
 *
 * @requires
 *   - order.status == Confirmed
 *   - exists i: Invoice => i.order == order && i.status == Paid
 *
 * @ensures
 *   - order.status == Fulfilled
 *
 * @properties
 *   - requires_role: "staff"
 */
export function fulfilOrder(order: Order): void {
  throw new Error("TODO: implement fulfilOrder");
}

/**
 * The customer cancels before payment. Any issued invoice is voided.
 * `invoice` is the order's issued invoice, if it has one.
 *
 * @param order - Order
 * @param invoice - Invoice | null
 *
 * @requires
 *   - order.status == Draft || order.status == Confirmed
 *   - !exists i: Invoice => i.order == order && i.status == Paid
 *
 * @ensures
 *   - order.status == Cancelled
 *   - when invoice != null => invoice.status == Void
 *   - forall i: Invoice => i.order == order => i.status == Void
 *
 * @properties
 *   - requires_role: "customer"
 *   - atomic: true
 */
export function cancelOrder(order: Order, invoice: Invoice | null): void {
  throw new Error("TODO: implement cancelOrder");
}

// Invariant: InvoiceHasOrder
// Every invoice refers to an existing order.
// forall i: Invoice => exists o: Order => o.id == i.order.id

// Invariant: OneActiveInvoice
// An order has at most one non-void invoice.
// forall a: Invoice => forall b: Invoice => a.order == b.order && a.status != Void && b.status != Void => a.id == b.id

// Invariant: FulfilledIsPaid
// A fulfilled order has a paid invoice.
// forall o: Order => o.status == Fulfilled => exists i: Invoice => i.order == o && i.status == Paid

// Invariant: CancelledHasNoLiveInvoice
// A cancelled order has no issued or paid invoice.
// forall o: Order => o.status == Cancelled => !exists i: Invoice => i.order == o && i.status != Void

// Invariant: NoticesAreTruthful
// A receipt exists only for a paid invoice.
// forall n: Notice => n.kind == Receipt => n.invoice.status == Paid

// Edge cases:
// when order.status == Fulfilled => reject()
// when order.status == Cancelled => reject()
// when invoice.status == Paid => reject()
// when invoice.status == Void => reject()

