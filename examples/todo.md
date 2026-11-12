# Todo queue, as `/todo` shows it

## acme/web

- [>] `c4w` Checkout: show the shipping cost before the payment step (added 2026-11-12T09:14:52Z) (session 3fa9c1d2)
- [~] `f8m` Footer: add the legal links (added 2026-11-12T09:31:07Z) (agent web-footer, branch claude/footer-legal-links, session 3fa9c1d2)
- [>] `h2x` Signup: validate the VAT number field (added 2026-11-12T09:40:21Z) (session 7be04a95)
- [ ] `s3b` Search: results stay on the old query after pressing Back (added 2026-11-12T10:02:40Z)
  - Seen on iPhone Safari only; screenshot in the issue tracker.
- [ ] `p7t` Pricing table: redo it in the new grid (added 2026-11-12T10:48:19Z) {sub-agent, model: sonnet, effort: medium}
- [?] `n5k` Pricing page: new plan names (added 2026-11-12T11:05:33Z) — question: keep "Pro" or rename it "Team"?
- [x] `k7q` Login: the "Forgot password" link opened a blank page (added 2026-11-11T08:20:11Z) (done 2026-11-11T15:47:26Z, PR https://github.com/acme/web/pull/42)
- [x] `d6r` Find out why the nightly export is slow (added 2026-11-11T08:31:54Z) (done 2026-11-11T17:02:09Z, no PR: the export query misses an index, see the note)
  - The `orders.created_at` filter does a full scan; adding the index is a migration, queued as `m4v`.

## acme/api

- [ ] `r9g` Rate-limit the `/export` endpoint (added 2026-11-12T11:26:58Z)
