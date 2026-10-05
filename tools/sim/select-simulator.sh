#!/bin/bash
#
# Imprime le nom du simulateur iPhone a utiliser, sur stdout, et rien d'autre.
# Les jobs de CI l'appellent pour composer leur `-destination`, donc rien ici ne
# doit ecrire ailleurs : une ligne de diagnostic sur stdout casse le destination
# silencieusement, avec une erreur qui ne parle pas du script.
#
# L'ordre de preference suit la liste des appareils du projet: le plus petit
# iPhone recent d'abord, parce que c'est le plus rapide a demarrer et le plus
# proche des conditions reelles d'un telephonce.

set -euo pipefail

available="$(xcrun simctl list devices available)"

for candidate in "iPhone 17e" "iPhone 17" "iPhone 16e" "iPhone 16"; do
    # La parenthese fermante ancre la correspondance sur le nom exact de
    # l'appareil: sans elle, "iPhone 17" matcherait aussi "iPhone 17 Pro".
    if printf '%s\n' "$available" | grep -qF "$candidate ("; then
        printf '%s' "$candidate"
        exit 0
    fi
done

printf 'ERREUR : aucun iPhone disponible sur ce runner.\n' >&2
xcrun simctl list devices available >&2
printf 'Verifier que le runtime iOS est installe : xcrun simctl list runtimes\n' >&2
exit 2