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

assert_count() {
	local file=$1
	local pattern=$2
	local expected=$3
	local description=$4
	local actual

	actual=$(grep -Ec "$pattern" "$file" || true)
	if [[ "$actual" -ne "$expected" ]]; then
		fail "$description (expected $expected, found $actual)"
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

assert_contains _main.cfg 'utils/merfolk\.cfg' \
	"shared merfolk rescue module is not included"
assert_contains utils/merfolk.cfg '\[filter_second\]' \
	"merfolk rescue has no killer filter"
assert_contains utils/merfolk.cfg 'side=1' \
	"merfolk rescue is not restricted to a side 1 serpent killer"
assert_contains utils/merfolk.cfg 'name=merfolk_rescued' \
	"merfolk rescue does not persist its completion state"
assert_contains utils/merfolk.cfg '\{VARIABLE merfolk_rescued yes\}' \
	"merfolk rescue does not record completion"
if ! awk '
	/^[[:space:]]*\[event\][[:space:]]*$/ {
		event_depth++
	}
	/^[[:space:]]*\[set_menu_item\][[:space:]]*$/ && event_depth == 0 {
		exit 1
	}
	/^[[:space:]]*\[\/event\][[:space:]]*$/ {
		event_depth--
	}
' utils/merfolk.cfg; then
	fail "merfolk village menu is registered at scenario top level"
fi
assert_contains scenarios/a_new_beginning.cfg '\{MERFOLK_RESCUE\}' \
	"initial spring does not enable the merfolk rescue"
assert_contains scenarios/spring_of_raindrops.cfg '\{MERFOLK_RESCUE\}' \
	"later springs do not enable the merfolk rescue"
assert_contains scenarios/summer_of_dreams.cfg '\{MERFOLK_RESCUE\}' \
	"summers do not enable the merfolk rescue"
assert_not_contains scenarios/autumn_of_gold.cfg '\{MERFOLK_RESCUE\}' \
	"autumn incorrectly enables the merfolk rescue"
assert_not_contains scenarios/winter_of_storms.cfg '\{MERFOLK_RESCUE\}' \
	"winter incorrectly enables the merfolk rescue"
pass "seasonal merfolk rescue"

assert_contains units/Envoy.cfg '\{AMLA_DEFAULT\}' \
	"Envoy does not have a standard AMLA advancement"
pass "Envoy AMLA"

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

assert_contains _main.cfg 'utils/iron\.cfg' \
	"the centralized iron module is not included"
assert_not_contains utils/general_macros.cfg '#define (CHECK_IRON|PAY_IRON|GAIN_IRON|SET_PROJECT_COST_TEXT|LOW_IRON)' \
	"iron economy macros have leaked back into general_macros.cfg"

assert_contains utils/iron.cfg '#define IRON_ENABLED' \
	"iron-enabled condition is missing"
assert_contains utils/iron.cfg 'VARIABLE_CONDITIONAL iron_enabled not_equals no' \
	"iron-enabled compatibility condition changed"
assert_contains utils/iron.cfg '#define IRON_DISABLED' \
	"iron-disabled condition is missing"
assert_contains utils/iron.cfg 'VARIABLE_CONDITIONAL iron_enabled equals no' \
	"gold-only condition changed"
assert_contains utils/iron.cfg '#define IRON_EXPLICITLY_ENABLED' \
	"explicit iron selection condition is missing"
assert_contains utils/iron.cfg 'VARIABLE_CONDITIONAL iron_enabled equals yes' \
	"kingdom-status iron condition changed"
assert_contains utils/iron.cfg 'greater_than_equal_to=\{AMOUNT\}' \
	"iron affordability check changed"
assert_contains utils/iron.cfg 'VARIABLE_OP playerIron sub \{AMOUNT\}' \
	"iron payment behavior changed"
assert_contains utils/iron.cfg 'VARIABLE_OP playerIron add \{AMOUNT\}' \
	"iron gain behavior changed"
assert_contains utils/game_parameters.cfg '#define IRON_WARNING_THRESHOLD' \
	"low-iron warning threshold is missing"
assert_contains utils/iron.cfg 'playerIron less_than \{IRON_WARNING_THRESHOLD\}' \
	"iron spending does not use the low-iron warning threshold"
assert_contains utils/iron.cfg 'playerIron greater_than_equal_to \{IRON_WARNING_THRESHOLD\}' \
	"iron gains do not re-arm the low-iron warning at the threshold"
assert_contains utils/iron.cfg '\{CLEAR_VARIABLE warnings\.low_iron\}' \
	"low-iron warning is not re-armed after reserves recover"
assert_contains utils/iron.cfg '#define IRON_WARNINGS' \
	"low-iron warning event is missing"
assert_contains utils/iron.cfg 'name=low_iron' \
	"low-iron warning event name changed"
assert_contains utils/iron.cfg 'first_time_only=no' \
	"low-iron warning cannot fire again after recovery"
assert_contains utils/iron.cfg 'VARIABLE_CONDITIONAL warnings\.low_iron not_equals yes' \
	"low-iron warning does not suppress repeats"
assert_contains utils/iron.cfg '\{VARIABLE warnings\.low_iron yes\}' \
	"low-iron warning does not record that it fired"
assert_contains utils/iron.cfg 'armorer=_"\{ARMORER_COST\} gold, \{ARMORER_IRON\} iron"' \
	"iron-mode project cost text changed"
assert_contains utils/iron.cfg 'armorer=_"\{ARMORER_COST\} gold"' \
	"gold-only project cost text changed"

for scenario in \
	scenarios/spring_of_raindrops.cfg \
	scenarios/summer_of_dreams.cfg \
	scenarios/autumn_of_gold.cfg \
	scenarios/winter_of_storms.cfg; do
	assert_count "$scenario" '\{PRODUCE_MINE_IRON\}' 1 \
		"$scenario does not use exactly one shared seasonal mine-production routine"
	assert_not_contains "$scenario" 'list_of_mines' \
		"$scenario contains a duplicate seasonal mine-production implementation"
done

assert_count utils/iron.cfg '\{GAIN_IRON 3\}' 1 \
	"Dwarvish Miner seasonal bonus changed"
assert_count utils/iron.cfg '\{GAIN_IRON 1\}' 1 \
	"peasant seasonal bonus changed"
assert_count utils/iron.cfg '\{GAIN_IRON 2\}' 1 \
	"base seasonal mine production changed"
assert_contains utils/iron.cfg 'type=CotF Dwarvish Miner' \
	"Dwarvish Miner staffing filter changed"
assert_contains utils/iron.cfg \
	'type=Peasant,Peasant Workers,Peasant_no_Advance,Peasant_to_Bowman,Peasant_to_Spearman' \
	"peasant staffing filter changed"

for scenario in scenarios/*.cfg; do
	assert_count "$scenario" '\{IRON_WARNINGS\}' 1 \
		"$scenario does not install exactly one low-iron warning handler"
done

assert_contains scenarios/a_new_beginning.cfg \
	'focused on modifying the terrain and managing resources' \
	"tutorial introduction is not appropriate to both economy modes"
assert_count scenarios/a_new_beginning.cfg \
	'\{TUTORIAL workers_recruit1 ' 2 \
	"worker tutorial does not provide separate classic and iron variants"
assert_contains scenarios/a_new_beginning.cfg \
	'\{IRON_DISABLED\}' \
	"worker tutorial is not selected by economy mode"
assert_contains scenarios/a_new_beginning.cfg \
	'build iron mines in the mountains' \
	"iron-mode worker tutorial does not explain mine construction"
assert_contains scenarios/a_new_beginning.cfg \
	'Farms generate \$farm_income\.spring gold per turn in spring, \$farm_income\.summer in summer, \$farm_income\.autumn in autumn, and \$farm_income\.winter in winter' \
	"first-farm tutorial does not use the configured seasonal income"
assert_contains scenarios/summer_of_dreams.cfg \
	'farms generate \$farm_income\.summer gold per turn' \
	"summer tutorial does not use the configured farm income"
assert_not_contains scenarios/a_new_beginning.cfg \
	'a number over each Workers unit will indicate' \
	"forge tutorial describes the removed floating countdown"
assert_contains scenarios/a_new_beginning.cfg \
	"select 'Project status\\.\\.\\.'" \
	"forge tutorial does not describe the current project-status menu"
pass "setting-aware tutorial checks"

assert_contains utils/game_parameters.cfg '#define GOLD_WARNING_THRESHOLD' \
	"low-gold warning threshold is missing"
assert_contains utils/general_macros.cfg \
	'side1_gold less_than \{GOLD_WARNING_THRESHOLD\}' \
	"low-gold checks do not use the configured threshold"
assert_contains utils/general_macros.cfg \
	'side1_gold greater_than_equal_to \{GOLD_WARNING_THRESHOLD\}' \
	"low-gold warning is not re-armed after recovery"
low_gold_warnings="$(
	sed -n '/^#define LOW_GOLD_WARNINGS$/,/^#enddef$/p' utils/general_macros.cfg
)"
if grep -q 'name=side 1 turn' <<<"$low_gold_warnings"; then
	fail "low-gold warning polls the treasury every turn"
fi
assert_contains utils/general_macros.cfg \
	'VARIABLE_CONDITIONAL warnings\.low_gold not_equals yes' \
	"low-gold warning does not suppress repeats"
assert_contains utils/general_macros.cfg \
	'\{VARIABLE warnings\.low_gold yes\}' \
	"low-gold warning does not record that it fired"
assert_contains utils/general_macros.cfg \
	'\{CLEAR_VARIABLE warnings\.low_gold\}' \
	"low-gold warning recovery does not clear its suppression flag"
assert_contains utils/general_macros.cfg \
	'\{REARM_LOW_GOLD_WARNING\}' \
	"gold refunds do not re-arm the low-gold warning"
assert_contains utils/diplomacy.cfg \
	'\{REARM_LOW_GOLD_WARNING\}' \
	"the heretic bribe does not re-arm the low-gold warning"
pass "low-gold warning lifecycle"

assert_contains utils/game_parameters.cfg '#define DIPLOMACY_REMINDER_LIMIT' \
	"completed-diplomacy reminder limit is missing"
assert_contains utils/general_macros.cfg \
	'\{VARIABLE diplomacy_completed_reminders 0\}' \
	"completed-diplomacy reminder count is not reset each season"
assert_contains utils/diplomacy.cfg \
	'diplomacy_completed_reminders less_than \{DIPLOMACY_REMINDER_LIMIT\}' \
	"completed-diplomacy reminders are not capped"
assert_contains utils/diplomacy.cfg \
	'\{VARIABLE_OP diplomacy_completed_reminders add 1\}' \
	"completed-diplomacy reminders do not increment their seasonal count"
assert_count utils/diplomacy.cfg \
	'we have already finished our diplomacy in this direction' 1 \
	"completed-diplomacy reminder text is duplicated"
pass "diplomacy reminder limit"

assert_contains scenarios/winter_of_storms.cfg \
	'Snow-covered terrain greatly restricts where your workers can construct buildings or alter the landscape' \
	"winter tutorial incorrectly describes worker availability"
assert_not_contains scenarios/winter_of_storms.cfg \
	'prevent your workers from constructing new buildings or altering the landscape' \
	"obsolete all-work-is-prevented winter guidance remains"
assert_contains utils/workers.cfg \
	'\$proj_list\[\$i_this\]\.turns work-shifts left' \
	"project status does not use the campaign's work-shift terminology"
assert_not_contains utils/workers.cfg 'sixth-days left of work' \
	"obsolete project-duration terminology remains"
assert_contains utils/workers.cfg 'recover the materials' \
	"project cancellation does not accurately describe its full refund"
assert_not_contains utils/workers.cfg 'recover most of the materials' \
	"project cancellation still claims only a partial refund"
pass "message accuracy regression checks"

assert_contains utils/diplomacy.cfg \
	'VARIABLE_CONDITIONAL warnings\.heretic_trespass not_equals yes' \
	"heretic trespass protest is not protected against repetition"
assert_contains utils/diplomacy.cfg \
	'\{VARIABLE warnings\.heretic_trespass yes\}' \
	"heretic trespass protest does not record that it was shown"
assert_contains utils/relics.cfg \
	'VARIABLE_CONDITIONAL relics\[\{INDEX\}\]\.leader_warned not_equals yes' \
	"leader relic warning is not protected against repetition"
assert_contains utils/relics.cfg \
	'\{VARIABLE relics\[\{INDEX\}\]\.leader_warned yes\}' \
	"leader relic warning does not record that it was shown"
pass "repeated dialogue suppression"

for feature_file in \
	scenarios/a_new_beginning.cfg \
	utils/build_menus.cfg \
	utils/diplomacy.cfg \
	utils/projects.cfg; do
	if [[ "$feature_file" == "scenarios/a_new_beginning.cfg" ]]; then
		assert_not_contains "$feature_file" 'VARIABLE_CONDITIONAL iron_enabled' \
			"$feature_file bypasses the centralized iron conditions"
	else
		assert_not_contains "$feature_file" 'iron_enabled' \
			"$feature_file bypasses the centralized iron conditions"
	fi
done
pass "optional iron economy regression checks"

crlf_files=$(git grep -Il $'\r' -- . || true)
if [[ -n "$crlf_files" ]]; then
	echo "Tracked text files contain CRLF or mixed line endings:" >&2
	printf '%s\n' "$crlf_files" >&2
	fail "tracked text uses LF line endings"
fi
pass "tracked text uses LF line endings"

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
