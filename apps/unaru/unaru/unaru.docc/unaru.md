# ``unaru``

The SwiftUI application for Unaru.

## Overview

On macOS, ``BundledBackend`` launches the helper embedded in the app bundle and waits
for an authorized response on loopback. The app generates a fresh internal credential
for each launch. It does not ask for an address, connection token, or pairing approval.
The helper exits when the app quits, crashes, or is force-quit. A port conflict produces
a startup error with Retry. Retry restarts a failed helper and reloads Kite configuration.

Kite credentials live in `.env` in the app's Application Support directory. The app
creates a private template on first launch. Missing credentials during sign-in show
Set Up Kite with Open Configuration Folder and Retry. Register
`http://127.0.0.1:8080/kite/callback` with Kite. The helper owns token exchange and keeps
validated Kite authorization in its own Keychain item. After quit, crash, or a compatible
signed rebuild, the helper restores and validates the saved account before exposing
identity. Expired or invalid authorization requires browser sign-in again. The app never
reads the token or shares its Keychain access.

Startup, sign-in, and recovery use a fixed-size, window-modal sheet over the native
split view. The sheet closes after the account is verified. Sign in with Kite opens
the default browser. The app polls an authorized attempt with a five-minute deadline
and cancellation. Cancelling sign-in shows progress until durable removal is confirmed.
Failure shows Couldn’t Finish Cancelling Sign-In with Retry Cancellation and blocks
another sign-in. Success returns to the sign-in action within the sheet.
The resizable sidebar shows an informational ``AccountFooter`` only while signed in.
It shows the avatar or initials, full name, and Kite user ID. A nonmodal Sign-In Not
Saved notice in the main area leaves the account usable and offers Retry Saving.
Saving uses the current helper-held session without another browser handoff. Successful
saving clears the notice. Older helper responses can omit persistence status.

``BackendConnection`` rejects obsolete verification and cancelled login responses.
Temporary login-status or profile errors offer Retry Sign-In for the same attempt.
Session verification fetches a fresh profile before displaying identity. Periodic
verification detects Kite authentication rejection and session loss. Temporary network
failures offer Retry without repeating browser login. Saved-session validation failures
show Can’t Verify Kite Session. Keychain read failures show Saved Session Unavailable.
Both keep identity hidden and retry existing authorization. Failed retries retain the
same recovery action, and successful validation closes the sheet. Credential rejection
offers a local service restart without discarding the saved Kite token. The app caches no profile or Kite credential. Redirects are
refused before credentials can be forwarded. Logout clears visible identity immediately,
but failed durable removal shows Couldn’t Finish Logging Out with Retry Log Out.
Sign-in stays blocked until the helper acknowledges deletion. A credential-free marker
in the app's configuration directory retains unfinished logout or cancellation across
app relaunches. Cancellation retains the attempt ID and never broadens into logout.
Startup retries deletion before any session-status or profile request. The marker is
removed only after durable deletion succeeds. A separate notice reports unconfirmed
provider revocation after successful local removal.

iOS and visionOS retain their initial content and deployment targets.

Each window opens Portfolio after sign-in or a change of account authority. Sign-out and
session expiry reset the destination. Routine profile revalidation of the same account
preserves each window's selection. Selecting the Portfolio label opens the overview. Its
disclosure triangle expands or collapses Holdings, Positions, and Funds. The Holdings child
lists securities and mutual funds reported by Kite in one native table. Search matches source names and symbols
without merging records. Investment Type filters the same list by Mutual Funds or Unknown.
Unknown preserves securities whose source supplies no verified asset classification.
A search or filter with no matches has its own state and reset action. Current Value,
Invested Cost, and Return support ascending and descending order. Current Value descending
is the default. Return compares backend unrealised return percentages. Unavailable values
sort last in either direction and stay distinct from zero. Return opens inspection for the
selected row. Inspection separates ordinary inventory, prices, financing, and source
limitations. Each inspection retains its selected source retrieval time and reports price
or NAV dates separately. A replacement source snapshot dismisses inspection and clears
selection, even when the helper reuses a row ID. A failed refresh keeps the same row
inspectable with its stale notice and source-specific Retry. Search and filter state
survive refreshes. Sign-out and confirmed expiry remove inspection content. The account control remains in the sidebar footer. The view covers the
connected Kite account's returned holdings without claiming complete demat inventory or
external-account coverage. Trading positions and combined investment calculations are
outside these source inspection views.

``PortfolioStore`` shares fetched holdings across windows in memory. Opening Portfolio
and Refresh Portfolio fetch both sources independently. The toolbar and menu offer
Refresh Portfolio with Command-R. Initial loading, an empty source, retrieval time,
missing price date, and read failures have separate visible states. Retry preserves the
valid Kite session and requests only the failed source. Each source has its own loading,
failure, empty, and retrieval state. A failed refresh retains that source's previous
rows with a stale notice while successful sources remain visible. Authority removal
clears holdings across every window. Obsolete success and failure cannot restore old
rows or invalidate a newer session. App relaunch fetches holdings again without
restoring a portfolio snapshot.

Mutual fund inspection retains fractional units, acquisition prices, latest available
NAVs, folios, and pledged units. NAV dates appear per holding, including different dates
within a source. Unavailable dates stay unavailable. Retrieval time never establishes a
current-day NAV. Missing cost, NAV, pledge relationships, and potential overlaps have
text explanations. Exact source prices remain available in inspection without treating
provider P&L as a verified return.

``PortfolioPerformanceView`` displays current-holdings invested cost, current value,
unrealised gain, and weighted return from the backend. It shows separate value, cost,
and return coverage, with matched cost and value for returns. Holding tables and
inspection sheets display the same backend row values. MTF stays outside ordinary
analysis. Unavailable values remain distinct from zero.

``PortfolioAllocationView`` shows the largest five valued holdings and supported
investment-type groups. The backend ranks holdings and supplies every percentage from
current value, including value with unusable acquisition cost. Unknown securities remain
visible without direct equity or ETF exposure assumptions. Text labels, currency values,
percentages, and group coverage provide an accessible equivalent to each allocation bar.
The panel scrolls at the minimum window size and uses native appearance styles.

Allocation identifies the valued subset when any ordinary valuation is unavailable.
MTF omission counts include mixed records with eligible ordinary inventory. Positions
and funds stay separate. An empty ordinary population and a missing or nonpositive
valued denominator have distinct messages. Holding inspection shows the backend share
only while the combined analysis is current. Refresh withholds both totals and allocation,
including inspection weights, until the contributing sources succeed again.

``PortfolioStore`` requests combined performance using the exact successful source
read IDs. A full refresh resets success for both sources and immediately withholds
totals. Retained stale rows never count as success in a new refresh. A source-specific
Retry can complete the current refresh without refetching its successful peer.
Delayed aggregate success and failure cannot replace a newer refresh or authority.
Source-qualified row projections use indexed lookups and apply only to their exact
retrievals. Backend-established overlap restrictions also follow the instrument identity
across replacement source reads, including changed row IDs. A partial refresh cannot
restore the affected calculations or remove the overlap warning. Only a new authoritative
row projection resolves that restriction. Unaffected source-only rows retain supported values.
The app formats Decimal values and performs no second financial calculation.

``SourceRequest`` owns cancellation, response ordering, decoding, and authority errors for
one source. Holdings, mutual funds, positions, funds, and combined analysis each use a
separate instance. ``inspectionField(_:_:fillsTrailingColumn:)`` and ``inspectionFields(content:)``
keep source inspection values copyable and wrapped with consistent group spacing.

The Positions child shows Current Net Positions and Closed Positions in separate
native tables. Return opens the selected row's broker details. Realised and unrealised
trading P&L remain separate from holdings returns, and delivery purchases do not alter
holdings. Prices without usable values are unavailable. Retrieval time is distinct
from the unavailable price valuation date.

``PositionsStore`` keeps this source in memory across windows, independently of holdings.
Opening Positions or refreshing requests a new read. Retry preserves successful
holdings and valid Kite authority. A failed refresh retains positions with a stale
notice. Authority removal clears positions and inspection across every window, and
obsolete successes or failures cannot replace newer source data or authority.

The Funds child opens ``FundsView``. ``FundsStore`` shares balances across windows in
memory and refreshes independently of holdings. Each enabled segment shows Kite's net
availability and total utilisation. Disabled or absent segments have explicit labels,
without invented zero availability. Native inspection sheets expose broker components
and explain their overlap. Funds never contribute to holdings performance or wealth.

Opening Funds or choosing Refresh Portfolio retrieves fresh balances. Retry Funds
recovers only this source. Initial loading, successful empty data, disabled segments,
retrieval time, failed retrieval, and stale balances remain distinct. Logout or confirmed
expiry clears balances across windows and dismisses inspection. Obsolete success and
failure cannot restore old balances or invalidate newer authority. Relaunch performs a
fresh read rather than restoring saved portfolio data.

``SourceInspectionStatus`` keeps retrieval time and source recovery visible inside
each inspection sheet. A refresh leaves the selected row inspectable and identifies
the previous retrieval while the request is pending. A temporary failure shows a
stale notice and a source-specific Retry action. Retry uses the valid Kite session.
A successful response replaces the retained source, including an empty response,
and dismisses inspection of the replaced row. Sign-out or confirmed session expiry
clears every source and dismisses inspection across windows.

Securities and mutual fund failures withhold combined investment totals until both
sources have succeeded. Positions and Funds failures affect only their supporting
source. Retrieval times remain separate from market-price and NAV dates. Separate
source reads do not establish an atomic account snapshot.

## Portfolio examples

These screens use sample account data. The overview identifies separate value, cost,
and return coverage. Holding details retain unavailable calculations when the source
cannot support them.

@Image(source: "portfolio-overview.png", alt: "Portfolio overview with invested cost, current value, unrealised gain and return, and separate coverage counts.")

Holdings lists securities and mutual funds together. Search, type filters, and sorting
use the current in-memory snapshot. This example uses Dark appearance.

@Image(source: "portfolio-holdings.png", alt: "Holdings in Dark appearance with search, type filters, current-value sorting, and unavailable acquisition cost and return for a transferred fund.")

## Topics

### Application and content

- ``unaruApp``
- ``ContentView``
- ``AccountFooter``

### Mac startup and sign-in

- ``BundledBackend``
- ``BackendConnection``
- ``BackendTransport``
- ``ConnectionStatusView``
