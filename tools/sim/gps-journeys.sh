#!/bin/bash
#
# Les parcours qui touchent la localisation ne peuvent pas etre executes par un
# simple `xcodebuild test` : ils exigent une position simulee, et la permission
# doit etre accordee au prealable. Ces deux etats se pilotent depuis la machine
# hote, jamais depuis le simulateur.
#
# Ce script est donc le point d'entree unique. Il isole chaque parcours dans sa
# propre invocation xcodebuild, ce qui supprime la dependance a l'ordre : le
# parcours de revocation revoque la permission pour tout le simulateur, donc un
# parcours lance apres lui n'a plus de signal.
#
#   tools/sim/gps-journeys.sh            les 5 parcours GPS, isoles
#   tools/sim/gps-journeys.sh manual     les 3 parcours sans localisation
#   tools/sim/gps-journeys.sh all        manual + les 5 GPS
#   tools/sim/gps-journeys.sh <nom>      un seul parcours
#
# Noms : manual, start_pause_resume, cold_relaunch, background, revocation, denied
#
# Lancement : le script demarre lui-meme un simulateur s'il n'y en a pas, et il
# suppose le projet compile avec TruffloFull (il utilise test-without-building).

set -uo pipefail

DESTINATION="${TRUFFLO_DESTINATION:-platform=iOS Simulator,name=iPhone 17e}"
BUNDLE_ID="dev.memolabs.trufflo"
REVOKE_MARKER="/tmp/trufflo-revoke-go"
LOG_DIR="${TRUFFLO_LOG_DIR:-/tmp}"

ORIGIN_LAT="48.8571"
ORIGIN_LON="2.3522"
STEP="0.00025"

log() { printf '%s\n' "$*"; }

device_id() {
    xcrun simctl list devices booted \
        | sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' \
        | head -1
}

# Une machine CI ne demarre avec aucun simulateur : en demarrer un fait partie du
# travail, sinon le premier `simctl privacy` echoue sans explication.
ensure_booted() {
    local id
    id="$(device_id)"
    if [ -n "$id" ]; then printf '%s' "$id"; return 0; fi

    local wanted udid
    wanted="$(printf '%s' "$DESTINATION" | sed -n 's/.*name=\(.*\)/\1/p')"
    if [ -n "$wanted" ]; then
        udid="$(xcrun simctl list devices available \
            | sed -n "s/.*${wanted} (\([0-9A-F-]\{36\}\)) (.*/\1/p" | head -1)"
    fi
    if [ -z "$udid" ]; then
        udid="$(xcrun simctl list devices available \
            | sed -n 's/.*iPhone[^ (]*[e ]*(\([0-9A-F-]\{36\}\)) (Shutdown)/\1/p' | head -1)"
    fi
    [ -n "$udid" ] || return 1

    log "  aucun simulateur demarre, demarrage de $udid" >&2
    xcrun simctl boot "$udid" >/dev/null 2>&1
    local i=0
    while [ "$i" -lt 60 ]; do
        id="$(device_id)"
        [ -n "$id" ] && { printf '%s' "$id"; return 0; }
        sleep 2
        i=$((i + 2))
    done
    return 1
}

require_booted() {
    local id
    id="$(ensure_booted)" && { printf '%s' "$id"; return 0; }
    log "ERREUR : aucun simulateur iOS disponible et aucun demarrage possible."
    log "  Sur un runner, verifier que le runtime iOS est installe :"
    log "  xcrun simctl list runtimes"
    return 2
}

reset_state() {
    local id="$1"
    rm -f "$REVOKE_MARKER"
    xcrun simctl privacy "$id" grant location "$BUNDLE_ID" >/dev/null 2>&1
    xcrun simctl location "$id" clear >/dev/null 2>&1
}

# Une position fixe suffit aux parcours qui demandent un signal, sans exiger que
# le trace avance.
pin_static_location() {
    local id="$1"
    xcrun simctl location "$id" set "${ORIGIN_LAT},${ORIGIN_LON}" >/dev/null 2>&1
}

# Route en mouvement, emise par le simulateur lui-meme, sans boucle externe.
# 0.00025 degres de latitude valent environ 27,8 metres.
start_moving_route() {
    local id="$1"
    local waypoints=() lat="$ORIGIN_LAT" i
    for i in $(seq 0 24); do
        waypoints+=("${lat},${ORIGIN_LON}")
        lat="$(awk -v l="$lat" -v s="$STEP" 'BEGIN { printf "%.5f", l + s }')"
    done
    xcrun simctl location "$id" start --speed=1.4 --interval=1 "${waypoints[@]}" \
        >/dev/null 2>&1 \
        || { log "ERREUR : impossible de demarrer la route simulee."; exit 2; }
    log "  route simulee demarree (25 points, ~700 m, ~8 min a 1,4 m/s)"
}

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

run_tests() {
    local logfile="$1" budget="$2" expected="$3"
    shift 3
    local -a selectors=()
    local test
    for test in "$@"; do
        selectors+=("-only-testing:truffloUITests/StarterUITests/$test")
    done

    xcodebuild test-without-building \
        -scheme trufflo \
        -testPlan TruffloFull \
        -destination "$DESTINATION" \
        "${selectors[@]}" \
        >"$logfile" 2>&1 &
    local pid=$! waited=0 decided="" reported=0
    while kill -0 "$pid" 2>/dev/null; do
        # Le verdict est dans le journal avant que xcodebuild ne rende la main :
        # inutile de payer toute l'attente quand les tests sont deja tranches.
        # Il faut however les attendre tous, sinon les suivants sont tues avant
        # d'avoir ete joues.
        # `grep -c` prints "0" and exits 1 when nothing matches, so `|| echo 0`
        # produced "0\n0" and broke the integer test below on every idle tick.
        reported="$(grep -cE "^Test Case .*\]' (passed|failed)" "$logfile" 2>/dev/null)"
        reported="${reported:-0}"
        if [ "$reported" -ge "$expected" ]; then
            decided=yes
            kill -TERM "$pid" 2>/dev/null
            sleep 2
            kill -KILL "$pid" 2>/dev/null
            break
        fi
        if [ "$waited" -ge "$budget" ]; then
            log "  (xcodebuild ne rend pas la main apres ${budget}s, arret)"
            kill -TERM "$pid" 2>/dev/null
            sleep 5
            kill -KILL "$pid" 2>/dev/null
            break
        fi
        sleep 2
        waited=$((waited + 2))
    done
    wait "$pid" 2>/dev/null
    [ -n "$decided" ] && log "  (verdict lu dans le journal, xcodebuild interrompu)"
}

run_journey() {
    local name="$1" logfile="$2" budget="${3:-300}"
    log ""
    log "=== $name ==="
    log "  journal : $logfile"
    run_tests "$logfile" "$budget" 1 "$name"
    if ! grep -qE "^Test Case .*$name\]' passed" "$logfile"; then
        log "  ECHEC : $name"
        grep -E "error:|Executed [0-9]+ tests" "$logfile" | tail -5 | sed 's/^/    /'
        return 1
    fi
    log "  OK : $(grep -E "^Test Case .*$name\]' passed" "$logfile" | tail -1 | sed -E 's/.*passed \((.*)\).*/\1/')"
    return 0
}

manual_journeys() {
    log ""
    log "=== parcours sans localisation ==="
    local logfile="$LOG_DIR/trufflo-journeys-manual.log"
    log "  journal : $logfile"
    run_tests "$logfile" 420 3 \
        testCreateDogAndRecordManualWalk \
        testEmptyJournalStateAndGlobalErasure \
        testEditDogProfileAndDeleteSingleWalk
    local failures=0 test
    for test in testCreateDogAndRecordManualWalk \
                testEmptyJournalStateAndGlobalErasure \
                testEditDogProfileAndDeleteSingleWalk; do
        if ! grep -qE "^Test Case .*$test\]' passed" "$logfile"; then
            log "  ECHEC : $test"
            failures=$((failures + 1))
        fi
    done
    if [ "$failures" -eq 0 ]; then
        log "  OK : 3 parcours sans localisation"
        return 0
    fi
    grep -E "error:" "$logfile" | tail -5 | sed 's/^/    /'
    return 1
}

start_pause_resume_journey() {
    local id="$1" failures=0
    reset_state "$id"; pin_static_location "$id"
    run_journey testStartPauseResumeFinishGpsWalk \
        "$LOG_DIR/trufflo-journey-start-pause-resume.log" || failures=$((failures + 1))
    xcrun simctl location "$id" clear >/dev/null 2>&1
    return $failures
}

cold_relaunch_journey() {
    local id="$1" failures=0
    reset_state "$id"; pin_static_location "$id"
    run_journey testColdRelaunchInterruptsTheWalkAndOffersThreeExits \
        "$LOG_DIR/trufflo-journey-cold-relaunch.log" || failures=$((failures + 1))
    xcrun simctl location "$id" clear >/dev/null 2>&1
    return $failures
}

background_journey() {
    local id="$1" failures=0
    reset_state "$id"
    start_moving_route "$id"
    run_journey testWalkKeepsCountingWhileTheAppIsInBackground \
        "$LOG_DIR/trufflo-journey-background.log" 480 || failures=$((failures + 1))
    xcrun simctl location "$id" clear >/dev/null 2>&1
    return $failures
}

revocation_journey() {
    local id="$1" failures=0
    reset_state "$id"; pin_static_location "$id"
    watch_and_revoke "$id" &
    local watcher=$!
    run_journey testRevokingLocationMidWalkInterruptsWithoutInventingDistance \
        "$LOG_DIR/trufflo-journey-revocation.log" || failures=$((failures + 1))
    wait "$watcher" 2>/dev/null
    xcrun simctl location "$id" clear >/dev/null 2>&1
    return $failures
}

denied_journey() {
    local id="$1" failures=0
    reset_state "$id"
    # Revoked before the launch: Core Location reports the refusal as soon as
    # the app asks, so no marker and no watcher are needed here.
    xcrun simctl privacy "$id" revoke location "$BUNDLE_ID" >/dev/null 2>&1
    run_journey testDeniedPermissionOffersSettingsAndManualEntry \
        "$LOG_DIR/trufflo-journey-denied.log" || failures=$((failures + 1))
    # The refusal outlives the app, so without this the next run of any GPS
    # journey inherits a revoked permission and fails for the wrong reason.
    xcrun simctl privacy "$id" grant location "$BUNDLE_ID" >/dev/null 2>&1
    return $failures
}

run_named() {
    local wanted="$1" id="$2"
    case "$wanted" in
        manual) manual_journeys ;;
        start_pause_resume) start_pause_resume_journey "$id" ;;
        cold_relaunch) cold_relaunch_journey "$id" ;;
        background) background_journey "$id" ;;
        revocation) revocation_journey "$id" ;;
        denied) denied_journey "$id" ;;
        *) return 2 ;;
    esac
}

main() {
    local wanted="${1:-all}" id status=0
    cd "$(dirname "$0")/../.." || exit 2

    id="$(require_booted)" || exit $?
    log "simulateur : $id"
    log "destination : $DESTINATION"

    case "$wanted" in
        all)
            manual_journeys || status=1
            for name in start_pause_resume cold_relaunch background revocation denied; do
                run_named "$name" "$id" || status=1
            done
            ;;
        manual|start_pause_resume|cold_relaunch|background|revocation|denied)
            run_named "$wanted" "$id" || status=1
            ;;
        *)
            log "usage : $0 [all|manual|start_pause_resume|cold_relaunch|background|revocation|denied]"
            exit 2
            ;;
    esac

    log ""
    if [ "$status" -eq 0 ]; then
        log "Parcours : OK"
    else
        log "Parcours : ECHEC, voir les journaux dans $LOG_DIR"
    fi
    return $status
}

main "$@"
