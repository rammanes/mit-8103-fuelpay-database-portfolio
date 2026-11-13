-- Runs once, when the primary is created: a login that is only allowed to replicate.
-- The password is taken from the container environment (.env), not written here.
\getenv pw POSTGRES_PASSWORD
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD :'pw';
