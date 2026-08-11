"""
generate_finance_data.py
------------------------------------------------------------------------------
Generates six related finance source tables for the Microsoft Fabric
Pipeline Orchestration PoC (Accounts Receivable / Revenue Analytics).

The data INTENTIONALLY contains realistic data-quality problems so the
Silver-layer cleansing, validation, and reconciliation steps have something
to fix and report on.

Output: six CSV files in ./output/ (one per source table).

No third-party libraries required (standard library only).
Run:  python generate_finance_data.py
"""

from __future__ import annotations

import csv
import os
import random
from datetime import date, datetime, timedelta

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SEED = 42                       # deterministic output for repeatable demos
N_CUSTOMERS = 120
N_INVOICES = 1000
MAX_LINES_PER_INVOICE = 5
PAYMENT_PROBABILITY = 0.80      # 80% of invoices have at least one payment
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "output")

# Deliberate data-quality issue rates (fraction of affected rows)
DQ = {
    "customer_null_name": 0.04,
    "customer_duplicate": 0.03,
    "customer_bad_country": 0.06,
    "invoice_null_date": 0.03,
    "invoice_future_date": 0.02,
    "invoice_duplicate_id": 0.02,
    "invoice_orphan_customer": 0.03,
    "line_negative_qty": 0.03,
    "line_null_price": 0.03,
    "line_orphan_invoice": 0.02,
    "payment_overpay": 0.04,
    "payment_null_method": 0.05,
    "payment_before_invoice": 0.02,
    "fx_missing": 0.05,
    "fx_zero": 0.02,
}

random.seed(SEED)

CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD"]
VALID_COUNTRIES = ["US", "GB", "DE", "FR", "JP", "CA", "AU", "NL", "IE"]
BAD_COUNTRIES = ["USA", "U.K.", "germany", "  FR ", "XX", ""]
PAYMENT_METHODS = ["Wire", "ACH", "Card", "Check", "SEPA"]
FIRST = ["Northwind", "Contoso", "Fabrikam", "Adventure", "Tailspin",
         "Wingtip", "Proseware", "Litware", "Coho", "Fourth", "Graphic",
         "Alpine", "Blue Yonder", "City Power", "Consolidated"]
LAST = ["Traders", "Ltd", "GmbH", "Industries", "Manufacturing", "Holdings",
        "Systems", "Logistics", "Foods", "Metals", "Components", "Group"]

START_DATE = date(2025, 1, 1)
END_DATE = date(2025, 12, 31)


def _rand_date(start: date, end: date) -> date:
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, delta))


def _hit(rate: float) -> bool:
    return random.random() < rate


def _write_csv(name: str, header: list[str], rows: list[list]) -> None:
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    path = os.path.join(OUTPUT_DIR, name)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"  wrote {len(rows):>5} rows -> {os.path.relpath(path)}")


# ---------------------------------------------------------------------------
# 1. Customers
# ---------------------------------------------------------------------------
def gen_customers() -> list[dict]:
    customers = []
    for i in range(1, N_CUSTOMERS + 1):
        name = f"{random.choice(FIRST)} {random.choice(LAST)}"

        # DQ: mixed casing + whitespace noise on some names
        if _hit(0.15):
            name = f"  {name.upper()}  " if _hit(0.5) else name.lower()

        # DQ: missing name
        if _hit(DQ["customer_null_name"]):
            name = ""

        country = random.choice(VALID_COUNTRIES)
        # DQ: bad / inconsistent country codes
        if _hit(DQ["customer_bad_country"]):
            country = random.choice(BAD_COUNTRIES)

        customers.append({
            "CustomerID": i,
            "CustomerName": name,
            "Country": country,
            "Currency": random.choice(CURRENCIES),
            "CreditLimit": random.choice([5000, 10000, 25000, 50000, 100000]),
            "IsActive": random.choice([1, 1, 1, 0]),
            "CreatedDate": _rand_date(date(2020, 1, 1), date(2024, 12, 31)).isoformat(),
        })

    # DQ: duplicate customer rows (same CustomerID)
    dupes = []
    for c in customers:
        if _hit(DQ["customer_duplicate"]):
            dupes.append(dict(c))
    customers.extend(dupes)

    rows = [[c["CustomerID"], c["CustomerName"], c["Country"], c["Currency"],
             c["CreditLimit"], c["IsActive"], c["CreatedDate"]] for c in customers]
    _write_csv("Customers.csv",
               ["CustomerID", "CustomerName", "Country", "Currency",
                "CreditLimit", "IsActive", "CreatedDate"], rows)
    return customers


# ---------------------------------------------------------------------------
# 2. Invoices (header)
# ---------------------------------------------------------------------------
def gen_invoices(customers: list[dict]) -> list[dict]:
    valid_ids = sorted({c["CustomerID"] for c in customers})
    invoices = []
    for i in range(1, N_INVOICES + 1):
        cust = random.choice(valid_ids)
        # DQ: orphan customer reference
        if _hit(DQ["invoice_orphan_customer"]):
            cust = 999000 + i

        inv_date = _rand_date(START_DATE, END_DATE)
        inv_date_str = inv_date.isoformat()
        # DQ: null invoice date
        if _hit(DQ["invoice_null_date"]):
            inv_date_str = ""
        # DQ: future invoice date
        elif _hit(DQ["invoice_future_date"]):
            inv_date_str = (date.today() + timedelta(days=random.randint(30, 200))).isoformat()

        due = ""
        if inv_date_str:
            due = (date.fromisoformat(inv_date_str) + timedelta(days=30)).isoformat()

        invoices.append({
            "InvoiceID": i,
            "CustomerID": cust,
            "InvoiceDate": inv_date_str,
            "DueDate": due,
            "Currency": random.choice(CURRENCIES),
            "Status": random.choice(["Open", "Paid", "PartiallyPaid", "Overdue"]),
        })

    # DQ: duplicate invoice IDs
    dupes = [dict(inv) for inv in invoices if _hit(DQ["invoice_duplicate_id"])]
    invoices.extend(dupes)

    rows = [[v["InvoiceID"], v["CustomerID"], v["InvoiceDate"], v["DueDate"],
             v["Currency"], v["Status"]] for v in invoices]
    _write_csv("Invoices.csv",
               ["InvoiceID", "CustomerID", "InvoiceDate", "DueDate",
                "Currency", "Status"], rows)
    return invoices


# ---------------------------------------------------------------------------
# 3. Invoice line items
# ---------------------------------------------------------------------------
def gen_invoice_lines(invoices: list[dict]) -> list[dict]:
    valid_inv = sorted({v["InvoiceID"] for v in invoices})
    lines = []
    line_id = 1
    for inv in valid_inv:
        for ln in range(1, random.randint(1, MAX_LINES_PER_INVOICE) + 1):
            qty = random.randint(1, 50)
            # DQ: negative quantity
            if _hit(DQ["line_negative_qty"]):
                qty = -qty

            price = round(random.uniform(10, 2000), 2)
            price_str = f"{price:.2f}"
            # DQ: null unit price
            if _hit(DQ["line_null_price"]):
                price_str = ""

            target_inv = inv
            # DQ: orphan invoice reference
            if _hit(DQ["line_orphan_invoice"]):
                target_inv = 888000 + line_id

            lines.append({
                "LineID": line_id,
                "InvoiceID": target_inv,
                "LineNumber": ln,
                "GLAccountID": random.randint(4000, 4020),
                "Quantity": qty,
                "UnitPrice": price_str,
            })
            line_id += 1

    rows = [[l["LineID"], l["InvoiceID"], l["LineNumber"], l["GLAccountID"],
             l["Quantity"], l["UnitPrice"]] for l in lines]
    _write_csv("InvoiceLines.csv",
               ["LineID", "InvoiceID", "LineNumber", "GLAccountID",
                "Quantity", "UnitPrice"], rows)
    return lines


# ---------------------------------------------------------------------------
# 4. Payments
# ---------------------------------------------------------------------------
def gen_payments(invoices: list[dict], lines: list[dict]) -> None:
    # rough invoice totals for realistic payments
    totals: dict[int, float] = {}
    for l in lines:
        try:
            amt = int(l["Quantity"]) * float(l["UnitPrice"])
        except (ValueError, TypeError):
            amt = 0.0
        totals[l["InvoiceID"]] = totals.get(l["InvoiceID"], 0.0) + max(amt, 0.0)

    payments = []
    pay_id = 1
    for inv in invoices:
        if not _hit(PAYMENT_PROBABILITY):
            continue
        base = totals.get(inv["InvoiceID"], round(random.uniform(100, 5000), 2))
        amount = round(base * random.uniform(0.4, 1.0), 2)
        # DQ: overpayment
        if _hit(DQ["payment_overpay"]):
            amount = round(base * random.uniform(1.1, 1.5), 2)

        pay_date = inv["InvoiceDate"] or START_DATE.isoformat()
        try:
            base_d = date.fromisoformat(pay_date)
            pay_d = base_d + timedelta(days=random.randint(1, 45))
            # DQ: payment before invoice date
            if _hit(DQ["payment_before_invoice"]):
                pay_d = base_d - timedelta(days=random.randint(1, 20))
            pay_date = pay_d.isoformat()
        except ValueError:
            pay_date = START_DATE.isoformat()

        method = random.choice(PAYMENT_METHODS)
        # DQ: null payment method
        if _hit(DQ["payment_null_method"]):
            method = ""

        payments.append([pay_id, inv["InvoiceID"], pay_date,
                         f"{amount:.2f}", inv["Currency"], method])
        pay_id += 1

    _write_csv("Payments.csv",
               ["PaymentID", "InvoiceID", "PaymentDate", "Amount",
                "Currency", "PaymentMethod"], payments)


# ---------------------------------------------------------------------------
# 5. Exchange rates
# ---------------------------------------------------------------------------
def gen_exchange_rates() -> None:
    rows = []
    d = START_DATE
    base_rates = {"USD": 1.0, "EUR": 1.08, "GBP": 1.27, "JPY": 0.0067,
                  "CAD": 0.74, "AUD": 0.66}
    while d <= END_DATE:
        for ccy in CURRENCIES:
            rate = round(base_rates[ccy] * random.uniform(0.97, 1.03), 6)
            # DQ: missing rate rows (skip)
            if _hit(DQ["fx_missing"]):
                continue
            # DQ: zero rate
            if _hit(DQ["fx_zero"]):
                rate = 0.0
            rows.append([d.isoformat(), ccy, "USD", f"{rate:.6f}"])
        d += timedelta(days=1)
    _write_csv("ExchangeRates.csv",
               ["RateDate", "FromCurrency", "ToCurrency", "Rate"], rows)


# ---------------------------------------------------------------------------
# 6. GL accounts (chart of accounts)
# ---------------------------------------------------------------------------
def gen_gl_accounts() -> None:
    names = {
        4000: "Product Revenue", 4001: "Service Revenue", 4002: "Spare Parts",
        4003: "Maintenance Revenue", 4004: "Licensing", 4005: "Consulting",
        4006: "Training Revenue", 4007: "Freight Recovered",
        4008: "Warranty Revenue", 4009: "Rebates", 4010: "Discounts Given",
        4011: "Export Sales", 4012: "Domestic Sales", 4013: "Returns",
        4014: "Other Income", 4015: "Interest Income", 4016: "FX Gains",
        4017: "Scrap Sales", 4018: "Royalties", 4019: "Subscriptions",
        4020: "Miscellaneous",
    }
    rows = []
    for acc, nm in names.items():
        # DQ: null account name / inactive accounts
        if _hit(0.05):
            nm = ""
        active = 0 if _hit(0.10) else 1
        rows.append([acc, nm, "Revenue", active])
    _write_csv("GLAccounts.csv",
               ["GLAccountID", "AccountName", "AccountType", "IsActive"], rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    print(f"Generating finance source data (seed={SEED}) -> {OUTPUT_DIR}")
    customers = gen_customers()
    invoices = gen_invoices(customers)
    lines = gen_invoice_lines(invoices)
    gen_payments(invoices, lines)
    gen_exchange_rates()
    gen_gl_accounts()
    print("Done. Upload ./output/*.csv to the LH_Finance_Bronze Files area,")
    print("or point a Copy activity / Dataflow Gen2 at them for the Bronze load.")


if __name__ == "__main__":
    main()
