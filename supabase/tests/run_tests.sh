#!/usr/bin/env bash
# Runs all migrations + tests on a throwaway local PostgreSQL. Usage: sudo -u postgres bash run_tests.sh
set -euo pipefail
DB=riverdale_test
cd "$(dirname "$0")"
psql -v ON_ERROR_STOP=1 -qc "drop database if exists $DB" postgres
psql -qc "drop role if exists anon" postgres; psql -qc "drop role if exists authenticated" postgres; psql -qc "drop role if exists service_role" postgres
psql -v ON_ERROR_STOP=1 -qc "create database $DB" postgres
for f in 00_supabase_shim.sql ../migrations/001_schema.sql ../migrations/002_functions_and_triggers.sql ../migrations/003_rls_and_grants.sql ../migrations/004_seed_reference_data.sql ../migrations/005_construction_storage.sql ../migrations/006_followups_amendments.sql ../migrations/007_notifications_free.sql ../migrations/009_csv_import.sql ../migrations/010_real_flow.sql; do
  echo "--- applying $f"; psql -v ON_ERROR_STOP=1 -q -d $DB -f "$f"
done
for t in 10_scenarios.sql 20_construction.sql 30_followups_amend.sql 40_notifications.sql 50_import.sql 60_real_flow.sql; do psql -v ON_ERROR_STOP=1 -d $DB -f $t 2>&1 | grep -E "PASS|FAIL|ERROR|ALL PHASE" || true; done
