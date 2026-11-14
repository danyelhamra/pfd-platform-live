# Internal roadmap — excluded from current product UI and scope

Do not add these features, placeholders, marketing references or navigation to
this version. Revisit only after the development MVP is tested with multiple
clubs and the Australian business setup is complete.

- Club registration fee payments, with paid/unpaid tracking for each club.
- Online club subscription payments to PFD.
- Clothing orders for players, coaches and other club members.

Current priority: bug/security audit, essential authentication protections,
pilot testing, then source export and a separately controlled live deployment.
Test and live must use separate Supabase projects, keys, file buckets and email
redirect configuration; a separate frontend URL alone is not isolation.
