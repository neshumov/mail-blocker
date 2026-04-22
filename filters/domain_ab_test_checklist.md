# Domain A/B Test (if-domain / strip-domain)

## Preconditions
- Only your two extensions are enabled in Mail.app:
  - Mail Tracker Blocker Extension
  - Mail Tracker Blocker Extension 2
- Third-party Mail tracker extensions are disabled.
- Proxyman is running and capturing HTTPS.

## Test Artifact
- Email file: `filters/domain_ab_test_email.eml`
- OFF filter (with `$domain`): `filters/filter_domain_ab_off.txt`
- ON filter (stripped): `filters/filter_domain_ab_on.txt`

## Run A (OFF)
1. In app load `filter_domain_ab_off.txt`.
2. Set `Strip $domain = OFF`.
3. Run Pipeline.
4. Restart Mail.app.
5. Open `domain_ab_test_email.eml` in Mail.
6. In Proxyman inspect request to `track.customer.io`.

Expected for strict WebKit domain semantics:
- Request is NOT blocked by this rule (because `if-domain` depends on document domain, not `From:`).

## Run B (ON)
1. In app load `filter_domain_ab_on.txt`.
2. Set `Strip $domain = ON` (or keep ON, rule already stripped).
3. Run Pipeline.
4. Restart Mail.app.
5. Re-open the same `domain_ab_test_email.eml`.
6. Inspect `track.customer.io` in Proxyman.

Expected:
- Request IS blocked by the rule `||track.customer.io^$image`.

## Interpretation
- If A and B both block: in your environment `if-domain` is likely ignored or treated unexpectedly.
- If A doesn't block and B blocks: RFC decision "strip `$domain` for v1" is confirmed.
