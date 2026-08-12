# Data Agent and Verified Answer runbook

## Apply Prep for AI to the prepared model

1. Open `SM_Finance_AI_Ready` in the Power BI service.
2. Select **Prep data for AI** from the semantic model ribbon.
3. In **AI data schema**, select the business objects marked `Visible` in `prepared-model/Copilot/schema.json`. Exclude the technical keys and raw converted amount columns marked `Hidden`.
4. In **AI instructions**, enter the content from `prepared-model/Copilot/Instructions/instructions.md`.
5. Apply the changes, close and reopen the Copilot pane, and test the six comparison questions below.
6. In semantic model settings, enable **Approved for Copilot** after testing is complete.

The Fabric definition API persisted the TMDL but omitted `Copilot/` parts during live create and update validation. The service UI is therefore the authoritative authoring path for these Prep-for-AI settings in this workspace.

## Create the unprepared agent

1. In `WS_Finance_POC`, select **New item** > **Data Agent**.
2. Name it `DA_Finance_AI_Unprepared`.
3. Add the Power BI semantic model `SM_Finance_AI_Unprepared`.
4. Select all four model tables.
5. Use this intentionally vague agent instruction:

   > Answer finance questions using the available model. Be helpful and concise.

6. Publish the agent.

This instruction deliberately does not define revenue currency, invoice grain, primary date, time logic, or preferred fields. It demonstrates that agent-level prose cannot repair an ambiguous semantic model.

## Create the prepared agent

1. In `WS_Finance_POC`, select **New item** > **Data Agent**.
2. Name it `DA_Finance_AI_Ready`.
3. Add the Power BI semantic model `SM_Finance_AI_Ready`.
4. Select `Date`, `Customer`, `GL Account`, and `Revenue`.
5. Use these agent instructions:

   > Answer only from the attached finance semantic model. Start with the direct answer, then show the relevant period, currency, and filters. Use concise tables for rankings and comparisons. Use charts for trends when available. Clearly label USD and percentages. If the requested result is unavailable, say what is missing instead of estimating. Keep technical keys and load details out of business answers.

6. Publish the agent.

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
