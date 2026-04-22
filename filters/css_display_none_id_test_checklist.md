# CSS display-none ID-based A/B Test

## Files
- Filter: `filters/filter_css_display_none_id_test.txt`
- HTML: `filters/css_display_none_id_test_mail.html`

## Preconditions
- `Test mode: disable MessageSecurityHandler` = ON
- `Include css-display-none rules` = ON for BLOCK run
- Restart Mail after each `Run Pipeline`

## Run EMPTY
1. Load empty/no-op filter (no css rules).
2. Run pipeline, restart Mail.
3. Open `css_display_none_id_test_mail.html`.
4. Expected: both blocks visible (`mtb-show-block` and `mtb-hide-block`).

## Run BLOCK
1. Load `filter_css_display_none_id_test.txt`.
2. Ensure `Include css-display-none rules` is ON.
3. Run pipeline, restart Mail.
4. Re-open same HTML.
5. Expected: `mtb-show-block` visible, `mtb-hide-block` hidden.

## Interpretation
- If EMPTY=both visible and BLOCK=hide-block hidden: css-display-none works in Mail rendering context.
- If hide-block visible in both: css-display-none not applied in this runtime path.
