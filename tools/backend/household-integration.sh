#!/bin/bash
#
# Le parcours du foyer a deux comptes, en vrai HTTP, contre un Supabase local
# construit depuis backend/supabase (chantier 3, AC-18). Le client de
# production tourne tel quel ; seule la connexion differe (comptes email
# locaux, Apple ne connecte pas un test de simulateur).
#
#   tools/backend/household-integration.sh
#
# Prerequis : Docker et la CLI supabase. La base locale est REINITIALISEE.
# Le verdict est lu dans le journal, pas dans le code de sortie : xcodebuild
# rend 0 quand il n'a rien execute.

set -uo pipefail
cd "$(dirname "$0")/../.."

DESTINATION="${TRUFFLO_DESTINATION:-platform=iOS Simulator,name=iPhone 17e}"
LOG="${TRUFFLO_LOG_DIR:-/tmp}/trufflo-household-integration.log"
TESTS=("-only-testing:truffloTests/twoPeopleShareAHouseholdOverRealHTTP()" "-only-testing:truffloTests/aMemberHearsAWalkChangeAndAnOutsiderDoesNot()")

(cd backend && supabase start >/dev/null) || { echo "supabase start a echoue"; exit 1; }
(cd backend && supabase db reset --local >/dev/null 2>&1) || { echo "supabase db reset a echoue"; exit 1; }

status=$(cd backend && supabase status -o env 2>/dev/null)
api_url=$(printf '%s\n' "$status" | sed -n 's/^API_URL="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')
anon_key=$(printf '%s\n' "$status" | sed -n 's/^ANON_KEY="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')
[ -n "$api_url" ] && [ -n "$anon_key" ] || { echo "adresse ou cle locale introuvable"; exit 1; }

# xcodebuild transmet au processus de test les variables prefixees TEST_RUNNER_.
export TEST_RUNNER_TRUFFLO_LOCAL_API_URL="$api_url"
export TEST_RUNNER_TRUFFLO_LOCAL_ANON_KEY="$anon_key"

xcodebuild build-for-testing -scheme trufflo -testPlan TruffloFast \
  -destination "$DESTINATION" -quiet >"$LOG.build" 2>&1 || { tail -20 "$LOG.build"; exit 1; }

xcodebuild test-without-building -scheme trufflo -testPlan TruffloFast \
  -destination "$DESTINATION" "${TESTS[@]}" >"$LOG" 2>&1 &
pid=$!
for _ in $(seq 1 300); do
  grep -qE "Test run with [0-9]+ test" "$LOG" && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
done
kill "$pid" 2>/dev/null

grep -E "✘|recorded an issue|skipped|Test run with" "$LOG"
if grep -q "Test run with 2 tests.*passed" "$LOG" && ! grep -q "skipped" "$LOG"; then
  echo "VERT : parcours du foyer a deux comptes, temps reel"
  exit 0
fi
echo "ROUGE ou non execute, journal : $LOG"
exit 1
