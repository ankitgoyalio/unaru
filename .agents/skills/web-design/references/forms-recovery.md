# Forms and recovery

## Input contract

Associate visible labels with inputs and group related choices with `fieldset`/`legend`. Place constraints and examples beside the field, connected with `aria-describedby`. Explain required versus optional inputs in text and expose required state programmatically.

Choose `type` for the data's meaning and `inputmode` for the keyboard: a postal code or card identifier is text, not a mathematical number. Use applicable `autocomplete` tokens, including `current-password`, `new-password`, and `one-time-code`. Preserve leading zeros and international formats. See [HTML autofill and constraint validation](https://html.spec.whatwg.org/multipage/form-control-infrastructure.html).

## Validation and submission

Validate on submission and retain entered values after errors. Earlier validation should help completed input rather than interrupt typing; select its timing for the field and the project's established behavior. Server-side validation remains necessary when client validation is bypassed.

Identify each error in text with a correction the person can act on. Associate it with its input and set `aria-invalid` for an invalid value. For a service-style form with multiple errors, consider a focused summary whose links move to each invalid field, with the same error wording beside the field. [GOV.UK error summaries](https://design-system.service.gov.uk/components/error-summary/) and [validation](https://design-system.service.gov.uk/patterns/validation/) provide researched service patterns; adopting their visual styling is a separate product choice.

Leave a discoverable route to submission so users can obtain errors. When preventing duplicate submissions, communicate the pending state and restore a retry path on failure. If an action is unavailable, explain its prerequisite where users can perceive it.

For a multistep process, reuse information already provided or offer selection rather than requiring redundant entry, subject to WCAG 3.3.7 exceptions. For legal commitments, financial transactions, or modifying/deleting user-controlled data, provide the applicable reversal, checking, or confirmation mechanism (3.3.4).

## Authentication

Support password managers and paste, including verification-code paste. At each authentication step, avoid cognitive-function tests without an allowed alternative or assistance; apply the exceptions in [WCAG 3.3.8](https://www.w3.org/TR/WCAG22/#accessible-authentication-minimum) rather than declaring every CAPTCHA categorically forbidden.

Verify keyboard submission, invalid input, correction, pending, failure/retry, and successful completion. Test the summary-to-field path when used, autofill and paste for authentication, and persistence between steps.
