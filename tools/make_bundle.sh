#!/usr/bin/env bash
# Bundle guard: refuse to build gt2recomp.bundle if a submodule gitlink
# points anywhere but its pinned UPSTREAM SHA. A local-branch SHA in a
# gitlink breaks every user-side 'git submodule update' with
# "upload-pack: not our ref" (happened 2026-08-27 and again 2026-08-28) -
# carried changes must travel as patches/, never as gitlinks.
set -euo pipefail
cd "$(dirname "$0")/.."
declare -A PIN=(
    [psxrecomp]=afe9ab299aab0eeba1cc31f81bc4baf4e7fb2ab7
    [recomp-ui]=4eda65430a431e5685ae0c515ebcd912c7843bff
)
fail=0
for sub in "${!PIN[@]}"; do
    have=$(git ls-tree HEAD "$sub" | awk '{print $3}')
    if [ "$have" != "${PIN[$sub]}" ]; then
        echo "FATAL: gitlink $sub = $have, expected upstream pin ${PIN[$sub]}" >&2
        fail=1
    fi
done
[ $fail = 0 ] || exit 1
out="${1:-/root/gt2recomp.bundle}"
git bundle create "$out" --all
echo "bundle OK: $out (gitlinks verified)"
