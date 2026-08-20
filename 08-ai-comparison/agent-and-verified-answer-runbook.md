# Data Agent and Verified Answer runbook

## Apply Prep for AI to the prepared model

1. Open `SM_Finance_AI_Ready` in the Power BI service.
2. Select **Prep data for AI** from the semantic model ribbon.
3. In **AI data schema**, select the business objects marked `Visible` in `prepared-model/Copilot/schema.json`. Exclude the technical keys and raw converted amount columns marked `Hidden`.
4. In **AI instructions**, enter the content from `prepared-model/Copilot/Instructions/instructions.md`.
5. Apply the changes, close and reopen the Copilot pane, and test the six comparison questions below.
6. In semantic model settings, enable **Approved for Copilot** after testing is complete.

The Fabric definition API persisted the TMDL but omitted `Copilot/` parts during live create and update validation. The service UI is therefore the authoritative authoring path for these Prep-for-AI settings in this workspace.

## Deployed unprepared agent

- Name: `DA_Finance_AI_Unprepared`
- Fabric item ID: `929e9cab-963e-4def-b675-15765a337ac1`
- Status: Published
- Microsoft 365 Agent Store: Off
- Semantic model: `SM_Finance_AI_Unprepared`
- Selected tables: `DimCustomer`, `DimDate`, `DimGLAccount`, `FactRevenue`
- Published description: `Baseline finance agent connected to the intentionally unprepared semantic model for AI-readiness comparison testing.`
- Intentionally vague agent instruction:

  > Answer finance questions using the available model. Be helpful and concise.

This instruction deliberately does not define revenue currency, invoice grain, primary date, time logic, or preferred fields. It demonstrates that agent-level prose cannot repair an ambiguous semantic model.

## Deployed prepared agent

- Name: `DA_Finance_AI_Ready`
- Fabric item ID: `4cab8429-5bda-4973-b267-63962b515c46`
- Status: Published
- Microsoft 365 Agent Store: Off
- Semantic model: `SM_Finance_AI_Ready`
- Selected tables: `Date`, `Customer`, `GL Account`, `Revenue`
- Published description: `AI-ready finance agent with governed USD revenue, invoice-grain, customer, GL account, and calendar analysis guidance.`
- Agent instruction:

  > Answer only from the attached finance semantic model. Start with the direct answer, then show the relevant period, currency, and filters. Use concise tables for rankings and comparisons. Use charts for trends when available. Clearly label USD and percentages. If the requested result is unavailable, say what is missing instead of estimating. Keep technical keys and load details out of business answers.

Metric routing, currency rules, invoice grain, calendar definitions, and synonyms live in the prepared semantic model's Prep-for-AI artifacts. Agent instructions control presentation and response behavior; they are not a substitute for model semantics.

## Configure three verified answers

Verified Answers must be authored and tested in Power BI Desktop or the Power BI service. Configure them only on `SM_Finance_AI_Ready`.

### VA-01 Finance summary

- Primary trigger: `What is our total revenue and average revenue per invoice?`
- Additional triggers:
  - `Show the finance revenue summary.`
  - `What are total sales, invoice count, and average order value?`
- Visual: three cards.
- Measures:
  - `Revenue[Total Revenue USD]`
  - `Revenue[Invoice Count]`
  - `Revenue[Average Revenue per Invoice USD]`
- Filters: none.
- Expected current values:
  - Total Revenue USD: `$50,790,104.33`
  - Invoice Count: `887`
  - Average Revenue per Invoice USD: `$57,260.55`

### VA-02 Monthly revenue trend

- Primary trigger: `What is total revenue in USD by month?`
- Additional triggers:
  - `Show the monthly sales trend.`
  - `Chart revenue by month.`
- Visual: line chart.
- Axis: `Date[Calendar Hierarchy]`, Year and Month levels.
- Value: `Revenue[Total Revenue USD]`.
- Filters: none.
- Expected checks:
  - Grand total: `$50,790,104.33`
  - Peak month: August 2025, `$5,420,268.84`
  - Latest populated month: February 2027, `$467,054.96`

### VA-03 Top customers

- Primary trigger: `Who are the top 10 customers by total revenue in USD?`
- Additional triggers:
  - `Show our highest revenue customers.`
  - `Rank the top ten clients by sales.`
- Visual: horizontal bar chart.
- Category: `Customer[Customer Name]`.
- Value: `Revenue[Total Revenue USD]`.
- Filter: Top N = 10 by `Revenue[Total Revenue USD]`.
- Sort: descending by `Revenue[Total Revenue USD]`.
- Expected first three:
  - Adventure Manufacturing: `$1,646,370.03`
  - Litware Holdings: `$1,205,835.42`
  - city power group: `$1,169,781.33`

After authoring each answer, test all trigger phrasings in the Copilot pane and save only after the returned visual, filters, and totals match.

## Six comparison questions

Ask each question unchanged in both agents and record: selected measure, currency, grain, filters, answer value, and whether clarification was needed.

| # | Question | Prepared-model intent | Verified |
|---|---|---|---|
| 1 | What is our total revenue and average revenue per invoice? | USD revenue, distinct invoices, and explicit average invoice measure. | VA-01 |
| 2 | What is total revenue in USD by month? | Calendar month trend using revenue date and Total Revenue USD. | VA-02 |
| 3 | Who are the top 10 customers by total revenue in USD? | Rank Customer Name by Total Revenue USD. | VA-03 |
| 4 | Show total revenue in USD by GL account type. | Group Total Revenue USD by Account Type. | No |
| 5 | How did revenue grow year over year by month? | Use Revenue Growth %, Total Revenue USD, and Revenue Previous Year USD. | No |
| 6 | How many active customers generated revenue by country? | Use Active Revenue Customer Count grouped by Customer Country. | No |

## Expected comparison

The unprepared agent may choose `LineAmount` instead of `LineAmountUSD`, confuse invoice rows with distinct invoices, aggregate IDs, or infer a date and currency rule. The prepared agent should consistently select explicit measures, use USD by default, distinguish invoice count from line count, and explain blank prior-year growth where no comparable period exists.

## Troubleshoot the monthly year-over-year question

The question `How did revenue grow year over year by month?` can return an empty result when the generated query selects only 2025. The dataset has no 2024 revenue, so `Revenue Previous Year USD` and `Revenue Growth %` are blank for every 2025 month. A visual containing only the growth measure may therefore contain no plotted values.

Use this explicit diagnostic prompt:

> Show monthly Total Revenue USD, Revenue Previous Year USD, and Revenue Growth % for 2026 compared with 2025. Use Year and Month from the Date table.

The expected result from the deployed Warehouse is:

| 2026 month | Total Revenue USD | Revenue Previous Year USD | Revenue Growth % |
|---|---:|---:|---:|
| January | Blank | $2,924,785.58 | -100.00% |
| February | Blank | $4,132,902.95 | -100.00% |
| March | Blank | $3,674,829.00 | -100.00% |
| April | Blank | $4,099,202.45 | -100.00% |
| May | Blank | $4,383,659.87 | -100.00% |
| June | Blank | $3,693,657.58 | -100.00% |
| July | Blank | $3,710,261.99 | -100.00% |
| August | Blank | $5,420,268.84 | -100.00% |
| September | $106,253.86 | $4,698,730.32 | -97.74% |
| October | $152,368.87 | $3,716,947.25 | -95.90% |
| November | Blank | $4,749,049.43 | -100.00% |
| December | $94,419.59 | $4,633,988.79 | -97.96% |

`Total Revenue USD` is blank, rather than a stored zero, for 2026 months with no fact rows. In the growth calculation, DAX treats that blank current-period amount as zero when subtracting the populated prior-period amount, resulting in `-100.00%`. For 2025, growth remains blank because the denominator from 2024 is blank. Always include `Date[Year]` with `Date[Month Name]`; grouping by month name alone combines the same month across different years.

If the explicit diagnostic prompt still returns no data, verify that **Prep data for AI** includes `Revenue[Total Revenue USD]`, `Revenue[Revenue Previous Year USD]`, `Revenue[Revenue Growth %]`, `Date[Year]`, and `Date[Month Name]`, and that the instructions in `prepared-model/Copilot/Instructions/instructions.md` have been applied in the service. The repository's `Copilot/` files are source specifications; the Fabric definition API did not persist them during deployment validation.

## Additional high-contrast comparison questions

Use the following questions unchanged in both agents. The ground truth was queried from `WH_Finance_Gold` on 20 August 2026 using `gold.FactRevenue` and its relationships to the Gold dimensions. Currency measures sum the stored line-level `LineAmountUSD`; invoice counts use distinct `InvoiceID`.

### Revenue, invoice grain, and average value

**Question**

> What were total revenue in USD, distinct invoice count, and average revenue per invoice?

**Expected prepared answer**

| Metric | Ground truth |
|---|---:|
| Total Revenue USD | $50,790,104.33 |
| Distinct Invoice Count | 887 |
| Average Revenue per Invoice USD | $57,260.55 |
| Invoice Line Count, for validation only | 2,550 |

**Unprepared failure indicators:** reports 2,550 as invoice count; uses average `UnitPrice`; or reports the mixed-currency sum of source amounts, `64,525,480.12`, as revenue.

### Top customers

**Question**

> Rank the top 10 customers by total revenue in USD.

**Expected prepared answer**

| Rank | Customer | Total Revenue USD |
|---:|---|---:|
| 1 | Adventure Manufacturing | $1,646,370.03 |
| 2 | Litware Holdings | $1,205,835.42 |
| 3 | city power group | $1,169,781.33 |
| 4 | Contoso Foods | $1,163,448.88 |
| 5 | Fabrikam Foods | $1,124,846.97 |
| 6 | Contoso Systems | $1,082,390.23 |
| 7 | Contoso Industries | $1,046,852.70 |
| 8 | Litware Logistics | $972,214.86 |
| 9 | City Power Components | $964,500.10 |
| 10 | Contoso Components | $950,464.94 |

**Unprepared failure indicators:** ranks by source-currency `LineAmount`, `UnitPrice`, customer ID, or invoice-line count instead of USD revenue.

### Active customers with revenue

**Question**

> How many active customers generated revenue in each country?

**Expected prepared answer**

| Country | Active Revenue Customer Count |
|---|---:|
| AU | 5 |
| CA | 9 |
| DE | 9 |
| FR | 11 |
| GB | 7 |
| IE | 7 |
| JP | 10 |
| NL | 9 |
| US | 8 |
| XX | 2 |

**Unprepared failure indicators:** counts fact rows, sums `CustomerID` or `CustomerKey`, includes inactive customers, or counts all active dimension customers without requiring revenue.

### Average invoice value by source currency

**Question**

> What is the average revenue per invoice in USD by source currency?

**Expected prepared answer**

| Source Currency | Total Revenue USD | Invoice Count | Average Revenue per Invoice USD |
|---|---:|---:|---:|
| AUD | $7,936,724.11 | 159 | $49,916.50 |
| CAD | $7,769,178.76 | 152 | $51,113.02 |
| EUR | $9,447,260.42 | 132 | $71,570.15 |
| GBP | $13,468,307.88 | 162 | $83,137.70 |
| JPY | $452,482.83 | 132 | $3,427.90 |
| USD | $11,716,150.33 | 150 | $78,107.67 |

**Unprepared failure indicators:** uses average unit price, divides by 2,550 invoice lines, or returns unlabeled values in the source currencies.

### Source-currency value versus USD value

**Question**

> Compare revenue in source currency with revenue in USD for each source currency. Do not combine currencies into one source-currency total.

**Expected prepared answer**

| Source Currency | Revenue in Source Currency | Total Revenue USD |
|---|---:|---:|
| AUD | 11,626,252.61 AUD | $7,936,724.11 |
| CAD | 10,247,507.31 CAD | $7,769,178.76 |
| EUR | 9,069,257.02 EUR | $9,447,260.42 |
| GBP | 11,104,677.61 GBP | $13,468,307.88 |
| JPY | 10,686,154.85 JPY | $452,482.83 |
| USD | 11,791,630.72 USD | $11,716,150.33 |

**Unprepared failure indicators:** adds the source-currency column into the meaningless combined total `64,525,480.12`, labels that number as USD, or fails to distinguish `LineAmount` from `LineAmountUSD`.

### Revenue from active customers

**Question**

> What percentage of total revenue in USD came from active customers?

**Expected prepared answer:** `$35,174,118.16`, or `69.25%` of the `$50,790,104.33` total.

**Unprepared failure indicators:** calculates the percentage of customer rows rather than revenue, omits the active-customer filter, or uses mixed source-currency amounts.

These values are a fixed demo baseline, not permanent constants. Re-run the benchmark queries and update this section whenever the Gold fact data is reloaded from a different source snapshot.
