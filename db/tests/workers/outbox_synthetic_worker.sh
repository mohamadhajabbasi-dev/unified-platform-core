#!/usr/bin/env bash
# Disposable CI fixture only. No external adapter, side effect or production credentials.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${PG_CONTAINER:-}" =~ ^[0-9a-f]{12,64}$ ]]
[[ "$#" == 4 ]]
tenant=$1; consumer=$2; mode=$3; lease=$4
# Accept only the explicit synthetic fixture namespace.
[[ "$tenant" =~ ^a1060000-0000-0000-0000-00000000000[345]$ ]]
[[ "$consumer" =~ ^c1060000-0000-0000-0000-00000000000[3456]$ ]]
[[ "$mode" == hold || "$mode" == complete || "$mode" == fail ]]
[[ "$lease" =~ ^[1-9][0-9]{0,2}$ ]] && (( lease <= 300 ))
sql() { timeout 20s docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 -c "SET statement_timeout='10s'; $1"; }
[[ "$(sql "SELECT current_database()='upc_greenfield_test'")" == t ]]
candidates=$(sql "SELECT event_id FROM ops.ready_synthetic_outbox_events('$tenant','$consumer',20)")
while IFS= read -r event; do
 [[ -n "$event" ]] || continue
 [[ "$event" =~ ^[0-9a-f-]{36}$ ]]
 token=$(sql "SELECT ops.claim_synthetic_outbox_event('$tenant','$consumer','$event',$lease)")
 [[ -n "$token" ]] || continue
 [[ "$token" =~ ^[0-9a-f-]{36}$ ]]
 # The previous psql has exited successfully: the claim transaction committed.
 count=$(sql "SELECT attempt_count FROM ops.outbox_claims WHERE tenant_id='$tenant' AND consumer_id='$consumer' AND event_id='$event' AND lease_token='$token'")
 [[ "$count" =~ ^[1-9][0-9]*$ ]]
 printf 'CLAIM %s %s %s\n' "$event" "$token" "$count"
 if [[ "$mode" == hold ]]; then
  # Replaced process is killed by its own test controller; no orphan child.
  exec sleep 120
 elif [[ "$mode" == fail ]]; then
  [[ "$(sql "SELECT ops.fail_synthetic_outbox_claim('$tenant','$consumer','$event','$token',10)")" == t ]]
  printf 'FAILED %s\n' "$event"
 else
  # Synthetic no-op work: receipt is not proof of delivery or a business effect.
  [[ "$(sql "SELECT ops.complete_synthetic_outbox_claim('$tenant','$consumer','$event','$token')")" == t ]]
  printf 'DONE %s\n' "$event"
 fi
 exit 0
done <<< "$candidates"
echo EMPTY
