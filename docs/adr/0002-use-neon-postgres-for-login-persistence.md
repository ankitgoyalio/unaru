# Use Neon Postgres for login persistence

The dashboard uses hosted Neon Postgres to persist dashboard sessions and Kite access tokens, even though the application initially runs locally. SQLite would avoid an external database dependency for login alone, but Neon is the chosen foundation because the application will expand beyond login. Each local installation supplies its own database connection configuration.
