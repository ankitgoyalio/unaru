# Enhancement and installation

## Platform compatibility

Use native HTML behavior as the baseline for links, form submission, and disclosure when the product supports it, then layer enhancements onto that path. For a capability required by a browser-dependent interaction, consult its MDN compatibility table and test the target browser; a standards document defines behavior but does not establish browser support. Feature-detect optional capabilities and expose a usable fallback when unavailable. For an intentionally JavaScript-dependent application, check startup failure and failed chunk recovery against its supported experience rather than promising universal no-JavaScript operation.

## Requested installation or offline behavior

Add PWA facilities only when installation or offline use is in scope. Consult [MDN installability](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable) for the current browser/platform criteria. Browser promotion, manual installation, and offline support are distinct capabilities: a service worker with a fetch handler is not a universal installability requirement.

Provide a linked manifest appropriate to the target install flow, with name, icons, start URL, scope, and display behavior; verify it through the target browser's tooling. Check theme/background colors as rendered rather than assuming every browser uses them identically.

If offline use is requested, define which data and actions remain available, how stale data is labeled, and how pending operations retry safely. Choose caching by resource and user-data sensitivity instead of a blanket cache-first handler. Check service-worker upgrade/activation, old-client assets, logout/account changes, and network failure; clear or partition user-specific cached data appropriately. Test installed launch, deep links, updates, and an offline-to-online transition on supported platforms.
