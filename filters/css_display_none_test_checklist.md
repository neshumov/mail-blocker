# CSS display-none Test (Mail.app)

## Artifacts
- Filter: `filters/filter_css_display_none_test.txt`
- HTML: `filters/css_display_none_test_mail.html`

## Preconditions
- In app: `Test mode: disable MessageSecurityHandler` = ON
- In app: `Include css-display-none rules` = ON
- Mail restarted after `Run Pipeline`

## Steps
1. Load `filter_css_display_none_test.txt` and run pipeline.
2. Open `css_display_none_test_mail.html` in Mail.
3. Visual check:
   - Green block (`data-mtb-css="show"`) must be visible.
   - Red block (`data-mtb-css="hide"`) must be absent.
4. Proxyman check:
   - `https://httpbin.org/image/png?...` should still be requested (hide rule does not block network).
5. Self-test check in app:
   - `css-display-none rules` > 0
   - `CSS selector probe 'data-mtb-css="hide"'` > 0

## Expected conclusion
- `css-display-none` is applied in Mail rendering context.
- It affects visibility only and is not a network blocking mechanism.
