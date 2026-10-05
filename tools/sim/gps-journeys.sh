#!/bin/bash
#
# Les deux parcours GPS ne peuvent pas etre executes par un simple
# `xcodebuild test` : ils ont besoin que la position simulee bouge, et que la
# permission de localisation soit revoquee au milieu de la balade. Ces deux
# actions n'existent que sur la machine hote, jamais depuis le simulateur.
#
# Ce script est donc le point d'entree unique. Il isole chaque parcours dans
# sa propre invocation xcodebuild, ce qui supprime la dependance a l'ordre :
# le parcours de revocation revoque la permission pour tout le simulateur, donc
# un parcours lance apres lui n'a plus de signal.
#
#   tools/sim/gps-journeys.sh              les deux parcours
#   tools/sim/gps-journeys.sh background   parcours arriere-plan seul
#   tools/sim/gps-journeys.sh revocation   parcours revocation seul
#
# Lancement : le simulateur doit etre demarre et le projet deja compile avec
# `build-for-testing -testPlan TruffloFull` (ce script utilise
# test-without-building, donc il ne compile rien).

set -uo pipefail

DESTINATION="${TRUFFLO_DESTINATION:-platform=iOS Simulator,name=iPhone 17e}"
BUNDLE_ID="dev.memolabs.trufflo"
REVOKE_MARKER="/tmp/trufflo-revoke-go"
LOG_DIR="${TRUFFLO_LOG_DIR:-/tmp}"

# Position de depart : centre de Paris, coordonnees deja utilisees par les
# recettes. 0.00025 degres de latitude valent environ 27,8 metres.
ORIGIN_LAT="48.8571"
ORIGIN_LON="2.3522"
STEP="0.00025"

log() { printf '%s\n' "$*"; }

device_id() {
    xcrun simctl list devices booted \
        | sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' \
        | head -1
}

require_booted() {
    local id
    id="$(device_id)"
    if [ -z "$id" ]; then
        log "ERREUR : aucun simulateur iOS n'est demarre."
        log "  xcrun simctl boot 'iPhone 17e' && open -a Simulator"
        exit 2
    fi
    printf '%s' "$id"
}

# Une permission|location revoquee laisse le gestionnaire Core Location muet pour
# le prochain lancement aussi : on la rend avant chaque parcours.
reset_state() {
    local id="$1"
    xcrun simctl privacy "$id" grant location "$BUNDLE_ID" >/dev/null 2>&1
    xcrun simctl location "$id" clear >/dev/null 2>&1
    rm -f "$REVOKE_MARKER"
}

# Route en mouvement, emise par le simulateur lui-meme, sans boucle externe :
# c'est ce qui remplace l'ancien script /tmp/coord6.sh. La longueur est
# dimensionnee pour couvrir le lancement du test (~30 s) puis les 125 s
# d'arriere-plan, avec de la marge.
start_moving_route() {
    local id="$1"
    local waypoints=() lat="$ORIGIN_LAT" i
    for i in $(seq 0 24); do
        waypoints+=("${lat},${ORIGIN_LON}")
        lat="$(awk -v l="$lat" -v s="$STEP" 'BEGIN { printf "%.5f", l + s }')"
    done
    # 1,4 m/s : une vitesse de marche, pas un sprint.
    xcrun simctl location "$id" start --speed=1.4 --interval=1 "${waypoints[@]}" \
        >/dev/null 2>&1 \
        || {
            log "ERREUR : impossible de demarrer la route simulee."
            exit 2
        }
    log "  route simulee demarree (25 points, ~700 m, ~8 min a 1,4 m/s)"
}

# Surveille le marqueur ecrit par le test, puis revoque la permission. Reste
# necessaire : seule la machine hote peut revoquer, et le test doit declencher
# la revocation au milieu exact de la promenade.
watch_and_revoke() {
    local id="$1" i=0
    while [ ! -f "$REVOKE_MARKER" ] && [ "$i" -lt 600 ]; do
        sleep 1
        i=$((i + 1))
    done
    [ -f "$REVOKE_MARKER" ] || exit 0
    rm -f "$REVOKE_MARKER"
    xcrun simctl privacy "$id" revoke location "$BUNDLE_ID" >/dev/null 2>&1
}

run_journey() {
    local name="$1" logfile="$2"
    log ""
    log "=== $name ==="
    log "  journal : $logfile"
    xcodebuild test-without-building \
        -scheme trufflo \
        -testPlan TruffloFull \
        -destination "$DESTINATION" \
        -only-testing:"truffloUITests/StarterUITests/$name" \
        >"$logfile" 2>&1
    local status=$?

    # xcodebuild quitte 0 meme quand aucun test ne tourne : on lit la ligne de
    # synthese, jamais le code de sortie.
    if ! grep -qE "^Test Case .*$name\]' passed" "$logfile"; then
        log "  ECHEC : $name"
        grep -E "error:|Executed [0-9]+ tests" "$logfile" | tail -5 | sed 's/^/    /'
        return 1
    fi
    log "  OK : $(grep -E "^Test Case .*$name\]' passed" "$logfile" | tail -1 | sed -E 's/.*passed \((.*)\).*/\1/')"
    return 0
}

background_journey() {
    local id="$1" failures=0
    reset_state "$id"
    start_moving_route "$id"
    run_journey testWalkKeepsCountingWhileTheAppIsInBackground \
        "$LOG_DIR/trufflo-journey-background.log" || failures=$((failures + 1))
    xcrun simctl location "$id" clear >/dev/null 2>&1
    return $failures
}

revocation_journey() {
    local id="$1" failures=0
    reset_state "$id"
    xcrun simctl location "$id" set "${ORIGIN_LAT},${ORIGIN_LON}" >/dev/null 2>&1
    watch_and_revoke "$id" &
    local watcher=$!
    run_journey testRevokingLocationMidWalkInterruptsWithoutInventingDistance \
        "$LOG_DIR/trufflo-journey-revocation.log" || failures=$((failures + 1))
    wait "$watcher" 2>/dev/null
    return $failures
}

main() {
    local wanted="${1:-all}" id status=0
    cd "$(dirname "$0")/../.." || exit 2

    id="$(require_booted)"
    log "simulateur : $id"
    log "destination : $DESTINATION"

    case "$wanted" in
        background) background_journey "$id" || status=1 ;;
        revocation) revocation_journey "$id" || status=1 ;;
        all)
            background_journey "$id" || status=1
            revocation_journey "$id" || status=1
            ;;
        *)
            log "usage : $0 [all|background|revocation]"
            exit 2
            ;;
    esac

    log ""
    if [ "$status" -eq 0 ]; then
        log "Parcours GPS : OK"
    else
        log "Parcours GPS : ECHEC, voir les journaux dans $LOG_DIR"
    fi
    return $status
}

main "$@"
