#!/bin/bash
#
# Applique UNE migration de ce depot a la base de production `trufflo-db`, sur le
# VPS du lab, puis recharge le schema de PostgREST et relit les droits.
#
#   tools/backend/apply-migration.sh 20261006180954_member_profiles.sql
#   tools/backend/apply-migration.sh 20261006180954_member_profiles.sql --dry-run
#
# Pourquoi un script plutot qu'une commande ssh : c'est le geste de production le
# plus repete du projet, et une regle d'autorisation sur `ssh lab ...` laisserait
# passer n'importe quel argument. Ce script, lui, refuse tout ce qui n'est pas :
#   * un nom de migration nu (14 chiffres, soulignement, mots en minuscules, .sql),
#   * d'un fichier qui existe dans backend/supabase/migrations,
#   * commite et inchange (on n'applique pas ce qu'on n'a pas relu),
#   * sans instruction destructive (drop, truncate, delete from, alter system),
#     commentaires SQL exclus. Une telle migration s'applique a la main.
#
# Les migrations ne sont pas tracees dans la base (README de stacks/trufflo-api) :
# rien ici ne sait si celle-ci a deja ete appliquee. Une migration deja passee
# echoue sur « already exists » et ON_ERROR_STOP arrete tout avant d'ecrire.

set -euo pipefail
cd "$(dirname "$0")/../.."

readonly DIR="backend/supabase/migrations"
readonly HOST="lab"
readonly CONTAINER="trufflo-db"

usage() { echo "usage: $0 <nom-de-migration>.sql [--dry-run]" >&2; exit 2; }

[ $# -ge 1 ] && [ $# -le 2 ] || usage
name="$1"
dry=false
if [ $# -eq 2 ]; then
    [ "$2" = "--dry-run" ] || usage
    dry=true
fi

[[ "$name" =~ ^[0-9]{14}_[a-z0-9_]+\.sql$ ]] || { echo "refuse : « $name » n'est pas un nom de migration nu" >&2; exit 2; }
file="$DIR/$name"
[ -f "$file" ] || { echo "refuse : $file n'existe pas" >&2; exit 2; }

git ls-files --error-unmatch "$file" >/dev/null 2>&1 || { echo "refuse : $file n'est pas commite" >&2; exit 2; }
git diff --quiet HEAD -- "$file" || { echo "refuse : $file differe du commit" >&2; exit 2; }

# Commentaires SQL retires avant de chercher : « -- TRUNCATE ignores row level security »
# est une phrase, pas une instruction.
if sed 's/--.*$//' "$file" | grep -n -i -E '\bdrop\b|\btruncate\b|\bdelete[[:space:]]+from\b|\balter[[:space:]]+system\b' >/dev/null; then
    echo "refuse : $file contient une instruction destructive. A appliquer a la main, en relisant." >&2
    exit 3
fi

echo "migration : $file ($(wc -l < "$file" | tr -d ' ') lignes, commit $(git rev-parse --short HEAD))"
if $dry; then
    echo "dry-run : rien n'est envoye. Il serait applique avec :"
    echo "  ssh $HOST docker exec -i $CONTAINER psql -v ON_ERROR_STOP=1 -q -U postgres -d postgres < $file"
    echo "  puis : notify pgrst, 'reload schema'"
    exit 0
fi

ssh "$HOST" "docker exec -i $CONTAINER psql -v ON_ERROR_STOP=1 -q -U postgres -d postgres" < "$file"
ssh "$HOST" "docker exec $CONTAINER psql -q -U postgres -c \"notify pgrst, 'reload schema'\""

echo "--- apres : droits de authenticated sur public, et publication Realtime"
ssh "$HOST" "docker exec $CONTAINER psql -U postgres -At \
  -c \"select table_name||'='||string_agg(privilege_type,',' order by privilege_type) from information_schema.role_table_grants where grantee='authenticated' and table_schema='public' group by table_name order by table_name\" \
  -c \"select 'realtime:'||coalesce(string_agg(tablename,',' order by tablename),'none') from pg_publication_tables where pubname='supabase_realtime'\""
echo "A comparer avec backend/supabase/tests/grants_test.sql."
