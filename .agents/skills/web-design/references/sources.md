# Sources and authority

Refreshed 8 October 2026 against the sources below. Adapted from [ehmo/platform-design-skills web](https://github.com/ehmo/platform-design-skills/tree/dc2be825d8b439caea78e9eaa8fb3ac23b0ff3e9/skills/web), including its skill, metadata, and section index. Its MIT notice is preserved in [upstream-license.txt](upstream-license.txt).

## Resolve a claim

| Claim | Authority | Boundary |
| --- | --- | --- |
| Accessibility requirement | [WCAG 2.2](https://www.w3.org/TR/WCAG22/) | AA conformance includes A and AA. Understanding documents explain criteria; listed sufficient techniques offer approaches, not the only solutions. These skill references cover common task branches, not an exhaustive conformance audit. |
| Native semantics or behavior | [WHATWG HTML](https://html.spec.whatwg.org/multipage/), [W3C CSS](https://www.w3.org/Style/CSS/), [WAI-ARIA 1.2](https://www.w3.org/TR/wai-aria-1.2/) | Check the cited CSS document's status: a draft is distinguishable from a Recommendation. Specifications define behavior, not browser support. |
| Custom-widget interaction | [ARIA APG](https://www.w3.org/WAI/ARIA/apg/) | Informative keyboard/focus patterns; examples require browser/assistive-technology testing. |
| API usage or compatibility | [MDN](https://developer.mozilla.org/en-US/docs/Web) | API documentation and browser compatibility tables; support can change after this refresh. Apply compatibility checks through [platform compatibility](enhancement-installation.md#platform-compatibility). |
| Responsive layout or performance | [web.dev](https://web.dev/) | Engineering guidance applied to content failure or measured costs; Core Web Vitals are not accessibility conformance requirements. |
| Service-form interaction | [GOV.UK Design System](https://design-system.service.gov.uk/) | Researched service patterns; apply them where the workflow fits. Its styling and government-service conventions require a product choice. |

