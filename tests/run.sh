#!/usr/bin/env bash
# Host-side unit tests (no game, no GPU). Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."
gcc -std=c99 -O1 -Wall -Wextra -I psxrecomp/runtime/include -o /tmp/gameshark_vm_test tests/gameshark_vm_test.c gameshark_vm.c
/tmp/gameshark_vm_test
