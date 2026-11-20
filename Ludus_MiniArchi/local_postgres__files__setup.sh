#!/bin/bash
set -e
P="runuser -u postgres --"
$P psql -tc "SELECT 1 FROM pg_roles WHERE rolname='api'" | grep -q 1 || $P psql -c "CREATE ROLE api LOGIN PASSWORD 'Demo-Api-2026!'"
$P psql -tc "SELECT 1 FROM pg_database WHERE datname='mobilite'" | grep -q 1 || $P createdb mobilite
$P psql -d mobilite -f /tmp/init.sql
