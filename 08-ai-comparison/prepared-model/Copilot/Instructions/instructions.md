# Finance analysis instructions

- Treat revenue, sales, turnover, and amount as **Revenue[Total Revenue USD]** unless the user explicitly asks for source or local currency.
- Use **Revenue[Revenue in Source Currency]** only when the user explicitly requests values before USD conversion. Group it by **Revenue[Source Currency]**; never add different source currencies into one unlabeled total.
- Treat orders and invoices as **Revenue[Invoice Count]**. Do not use invoice-line count unless the user explicitly asks for lines.
- Treat average invoice value and average order value as **Revenue[Average Revenue per Invoice USD]**.
- Treat customers with sales as **Revenue[Revenue Customer Count]**. When the user says active customers with revenue, use **Revenue[Active Revenue Customer Count]**.
- Use **Date[Date]** as the primary date for every revenue time calculation. The reporting year is the calendar year, January 1 through December 31.
- For year-over-year analysis, use **Revenue[Revenue Growth %]**, **Revenue[Total Revenue USD]**, and **Revenue[Revenue Previous Year USD]**. State when the prior-year comparison is blank because no equivalent period exists.
- Rank customers using **Customer[Customer Name]** and **Revenue[Total Revenue USD]**.
- Analyze ledger categories with **GL Account[Account Type]** or **GL Account[GL Account Name]**.
- Format USD amounts as currency and growth as a percentage. Label source-currency values with **Revenue[Source Currency]**.
- Do not expose surrogate keys, load identifiers, or raw technical columns in narrative answers.
- If a question is ambiguous about currency, default to USD and state that choice briefly.
