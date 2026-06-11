#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WESNOTH=${WESNOTH:-}

if [[ -z "$WESNOTH" ]]; then
	for candidate in wesnoth-1.18 wesnoth; do
		if command -v "$candidate" >/dev/null 2>&1; then
			WESNOTH=$(command -v "$candidate")
			break
		fi
	done
fi

if [[ -z "$WESNOTH" ]]; then
	echo "FAIL: Wesnoth was not found. Set WESNOTH=/path/to/wesnoth-1.18." >&2
	exit 1
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cotf-tests.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

pass() {
	echo "PASS: $1"
}

fail() {
	echo "FAIL: $1" >&2
	exit 1
}

assert_contains() {
	local file=$1
	local pattern=$2
	local description=$3

	if ! grep -Eq "$pattern" "$file"; then
		fail "$description"
	fi
}

assert_not_contains() {
	local file=$1
	local pattern=$2
	local description=$3

	if grep -Eq "$pattern" "$file"; then
		fail "$description"
	fi
}

cd "$ROOT"

version=$("$WESNOTH" --version 2>/dev/null | head -n 1)
echo "Using $version"

userdata="$TMP_DIR/userdata"
addon="$userdata/data/add-ons/Cities_of_the_Frontier"
mkdir -p "$(dirname "$addon")"
ln -s "$ROOT" "$addon"

for difficulty in EASY NORMAL HARD; do
	output="$TMP_DIR/${difficulty,,}"
	log="$TMP_DIR/${difficulty,,}.log"

	if ! "$WESNOTH" \
		--userdata-dir="$userdata" \
		--no-log-to-file \
		--preprocess-defines="CAMPAIGN_CITIES_OF_THE_FRONTIER,$difficulty" \
		--preprocess "$addon" "$output" >"$log" 2>&1; then
		tail -n 40 "$log" >&2
		fail "$difficulty preprocessing"
	fi

	assert_contains "$output/_main.cfg" 'id="?A_New_Beginning"?' \
		"$difficulty preprocessing did not include the campaign scenarios"
	pass "$difficulty preprocessing"
done

default_line=$(grep -n '{DEFAULT_DIFFICULTY}' _main.cfg | cut -d: -f1)
normal_line=$(grep -n 'CAMPAIGN_DIFFICULTY NORMAL' _main.cfg | cut -d: -f1)
hard_line=$(grep -n 'CAMPAIGN_DIFFICULTY HARD' _main.cfg | cut -d: -f1)
if [[ -z "$default_line" || -z "$normal_line" || -z "$hard_line" ]] ||
	(( default_line <= normal_line || default_line >= hard_line )); then
	fail "Normal is not the default campaign difficulty"
fi
pass "Normal is the default difficulty"

assert_contains utils/enemies.cfg \
	'ADD_ANIMAL_LURKER \(Wolf,Great Wolf,Direwolf,Giant Spider\)' \
	"Giant Spider is missing from the animal lurker AI"
assert_not_contains utils/enemies.cfg 'Great Spider' \
	"obsolete Great Spider unit id is present"
pass "animal AI unit ids"

assert_contains utils/projects.cfg 'id=cotf_working_state' \
	"worker projects do not install the persistent working object"
assert_contains utils/workers.cfg 'object_id=cotf_working_state' \
	"worker completion does not remove the persistent working object"
assert_not_contains utils/workers.cfg 'id=exhaust_working_peasants' \
	"obsolete turn-refresh worker event has returned"
assert_not_contains utils/workers.cfg '\{SCROLL_TO \$proj_list' \
	"project queue scroll animation has returned"
assert_not_contains utils/workers.cfg '\[floating_text\]' \
	"project queue floating text has returned"
pass "worker project regression checks"

whitespace_errors=$(
	{
		git diff --cached --no-color --unified=0 --
		git diff --no-color --unified=0 --
	} | awk '
		/^\+\+\+/ { next }
		/^\+/ {
			line = substr($0, 2)
			sub(/\r$/, "", line)
			if (line ~ /[ \t]+$/) {
				print $0
			}
		}
	'
)
if [[ -n "$whitespace_errors" ]]; then
	echo "Changed lines contain trailing spaces or tabs:" >&2
	printf '%s\n' "$whitespace_errors" >&2
	fail "changed-line whitespace"
fi
pass "changed-line whitespace"

echo "All tests passed."
