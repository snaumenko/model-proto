// Shared implementation used as the conformance target by every stack.
// Plain TypeScript, no framework: the point is the spec tooling, not the code.

export type OrderStatus = "Draft" | "Confirmed" | "Fulfilled" | "Cancelled";
export type InvoiceStatus = "Issued" | "Paid" | "Void";
export type Actor = "Customer" | "System" | "Staff";
export type NoticeKind = "InvoiceEmail" | "Receipt";

export interface Invoice {
  order: number;
  status: InvoiceStatus;
}

export interface Notice {
  kind: NoticeKind;
  invoice: number;
}

export class Rejected extends Error {
  constructor(reason: string) {
    super(reason);
    this.name = "Rejected";
  }
}

export interface Options {
  /** Set to false to reproduce the planted bug in the implementation. */
  cancelVoidsInvoice?: boolean;
}

export class OrderSystem {
  readonly orders = new Map<number, OrderStatus>();
  readonly invoices = new Map<number, Invoice>();
  readonly outbox: Notice[] = [];
  private readonly cancelVoidsInvoice: boolean;

  constructor(options: Options = {}) {
    this.cancelVoidsInvoice = options.cancelVoidsInvoice ?? true;
  }

  // ---------- queries ----------
  invoicesOf(order: number): number[] {
    return [...this.invoices].filter(([, inv]) => inv.order === order).map(([id]) => id);
  }

  activeInvoicesOf(order: number): number[] {
    return this.invoicesOf(order).filter((id) => this.invoices.get(id)!.status !== "Void");
  }

  hasPaidInvoice(order: number): boolean {
    return this.invoicesOf(order).some((id) => this.invoices.get(id)!.status === "Paid");
  }

  // ---------- commands ----------
  createOrder(actor: Actor, order: number): void {
    this.require(actor === "Customer", "only the customer creates orders");
    this.require(!this.orders.has(order), "order already exists");
    this.orders.set(order, "Draft");
  }

  confirmOrder(actor: Actor, order: number): void {
    this.require(actor === "Customer", "only the customer confirms orders");
    this.require(this.orders.get(order) === "Draft", "order is not a draft");
    this.orders.set(order, "Confirmed");
  }

  issueInvoice(actor: Actor, order: number, invoice: number): void {
    this.require(actor === "System", "only the system issues invoices");
    this.require(this.orders.get(order) === "Confirmed", "order is not confirmed");
    this.require(this.activeInvoicesOf(order).length === 0, "order already has an active invoice");
    this.require(!this.invoices.has(invoice), "invoice id already used");
    this.invoices.set(invoice, { order, status: "Issued" });
    this.outbox.push({ kind: "InvoiceEmail", invoice });
  }

  voidInvoice(actor: Actor, invoice: number): void {
    this.require(actor === "Staff", "only staff void invoices");
    this.require(this.invoices.get(invoice)?.status === "Issued", "invoice is not issued");
    this.invoices.get(invoice)!.status = "Void";
  }

  payInvoice(actor: Actor, invoice: number): void {
    this.require(actor === "Customer", "only the customer pays invoices");
    this.require(this.invoices.get(invoice)?.status === "Issued", "invoice is not issued");
    this.invoices.get(invoice)!.status = "Paid";
    this.outbox.push({ kind: "Receipt", invoice });
  }

  fulfilOrder(actor: Actor, order: number): void {
    this.require(actor === "Staff", "only staff fulfil orders");
    this.require(this.orders.get(order) === "Confirmed", "order is not confirmed");
    this.require(this.hasPaidInvoice(order), "order has no paid invoice");
    this.orders.set(order, "Fulfilled");
  }

  cancelOrder(actor: Actor, order: number): void {
    this.require(actor === "Customer", "only the customer cancels orders");
    const status = this.orders.get(order);
    this.require(status === "Draft" || status === "Confirmed", "order cannot be cancelled now");
    this.require(!this.hasPaidInvoice(order), "order is already paid");
    this.orders.set(order, "Cancelled");
    if (this.cancelVoidsInvoice) {
      for (const id of this.invoicesOf(order)) {
        const inv = this.invoices.get(id)!;
        if (inv.status === "Issued") inv.status = "Void";
      }
    }
  }

  private require(condition: boolean, reason: string): void {
    if (!condition) throw new Rejected(reason);
  }
}

// ---------- invariants, stated once for every test suite ----------
export const invariants: Record<string, (s: OrderSystem) => boolean> = {
  invoiceHasOrder: (s) => [...s.invoices.values()].every((inv) => s.orders.has(inv.order)),
  oneActiveInvoice: (s) => [...s.orders.keys()].every((o) => s.activeInvoicesOf(o).length <= 1),
  fulfilledIsPaid: (s) =>
    [...s.orders].every(([o, status]) => status !== "Fulfilled" || s.hasPaidInvoice(o)),
  cancelledHasNoLiveInvoice: (s) =>
    [...s.orders].every(([o, status]) => status !== "Cancelled" || s.activeInvoicesOf(o).length === 0),
  noticesAreTruthful: (s) =>
    s.outbox.every((n) => {
      const inv = s.invoices.get(n.invoice);
      return inv !== undefined && (n.kind !== "Receipt" || inv.status === "Paid");
    }),
};

export function brokenInvariants(s: OrderSystem): string[] {
  return Object.entries(invariants)
    .filter(([, holds]) => !holds(s))
    .map(([name]) => name);
}
