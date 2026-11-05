# Analyse current holdings without retaining portfolio history

Unaru's first investment-analysis milestone uses current Kite holdings and keeps
fetched portfolio snapshots in memory. This provides invested cost, current value,
and unrealised gain or loss without introducing offline storage or implying a
transaction history that current-holdings endpoints do not supply. Historical
performance requires a separate decision and data source; this milestone does not
accumulate a history for later backfill.
