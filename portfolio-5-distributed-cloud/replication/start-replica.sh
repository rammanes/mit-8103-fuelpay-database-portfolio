#!/bin/bash
# Starts the replica. On first start it copies the primary with pg_basebackup.
# -R writes the settings that make this server a read-only standby that keeps
# streaming changes (WAL) from the primary.
set -e
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  until pg_isready -q -h fuelpay-primary -U "$POSTGRES_USER"; do sleep 1; done
  PGPASSWORD="$POSTGRES_PASSWORD" pg_basebackup -h fuelpay-primary -U replicator -D "$PGDATA" -R -X stream
  chmod 700 "$PGDATA"
fi
exec postgres
