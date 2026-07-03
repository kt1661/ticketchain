#!/usr/bin/env bash
# Drives the full testnet demo scenario (Deploy -> FundActors -> 01..05) in
# order, one forge script invocation per named entrypoint. Some steps are
# EXPECTED to revert on-chain (the DENIED cases proving a guard works) --
# those are marked accordingly below and won't stop the run.
#
# Usage:
#   ./script/run-demo.sh                    # interactive: pause after each step
#   ./script/run-demo.sh --auto             # run straight through, no pauses
#   ./script/run-demo.sh --rpc <url> --auto # target a different RPC (e.g. local anvil)
#   ./script/run-demo.sh --reset            # wipe deployments/sepolia.json first
#
# Requires: .env filled in (see .env.example), jq installed.
set -uo pipefail

cd "$(dirname "$0")/.."

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

RPC_URL="sepolia"
MODE="interactive"
RESET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto) MODE="auto"; shift ;;
        --rpc) RPC_URL="$2"; shift 2 ;;
        --reset) RESET=true; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [ ! -f .env ]; then
    echo "Missing .env -- copy .env.example and fill in your values first." >&2
    exit 1
fi
source .env

if [ "$RESET" = true ]; then
    echo '{}' > deployments/sepolia.json
    echo "Reset deployments/sepolia.json"
fi

STEP_NUM=0

info()  { echo -e "  ${CYAN}->${NC} $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[DENIED]${NC} $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC} $1" >&2; }
state() { echo -e "  ${BOLD}Final state:${NC}"; }

pause() {
    if [ "$MODE" = "interactive" ]; then
        echo
        read -rp "Press Enter to continue to the next step..."
    fi
}

eth_balance() { cast balance "$1" --rpc-url "$RPC_URL" --ether; }

# label ADDRESS -- returns "Name (0xAddress)" for known demo actors, or just
# the bare address if it's not one of ours. Always keeps the address visible
# alongside the name -- this is a readability aid, not a replacement.
label() {
    local addr="$1"
    if [ "$addr" = "$ALICE_ADDRESS" ]; then
        echo "Alice (${addr})"
    elif [ "$addr" = "$BOB_ADDRESS" ]; then
        echo "Bob (${addr})"
    elif [ "$addr" = "$WALLET_ADDRESS" ]; then
        echo "Organizer (${addr})"
    else
        echo "$addr"
    fi
}

print_tx_links() {
    local script_file="$1"
    local dir="broadcast/${script_file}"
    [ -d "$dir" ] || return 0

    local chain_dir
    chain_dir=$(find "$dir" -maxdepth 1 -type d ! -path "$dir" | sort | tail -n1)
    [ -n "$chain_dir" ] || return 0

    local chain_id run_file
    chain_id=$(basename "$chain_dir")
    run_file="${chain_dir}/run-latest.json"
    [ -f "$run_file" ] || return 0

    local hashes
    hashes=$(jq -r '.transactions[].hash // empty' "$run_file")
    [ -n "$hashes" ] || return 0

    while IFS= read -r hash; do
        if [ "$chain_id" = "11155111" ]; then
            info "tx: https://sepolia.etherscan.io/tx/${hash}"
        else
            info "tx: ${hash}"
        fi
    done <<< "$hashes"
}

# run_step TITLE SCRIPT_FILE SIG EXPECT_FAIL [extra forge args...]
run_step() {
    local title="$1"; shift
    local script_file="$1"; shift
    local sig="$1"; shift
    local expect_fail="$1"; shift

    STEP_NUM=$((STEP_NUM + 1))
    local title_upper
    title_upper=$(echo "$title" | tr '[:lower:]' '[:upper:]')

    echo
    echo -e "${BOLD}${CYAN}==================================================================${NC}"
    echo -e "${BOLD}${CYAN}>>> STARTING STEP ${STEP_NUM}: ${title_upper}${NC}"
    if [ "$expect_fail" = "true" ]; then
        echo -e "${YELLOW}    (expected to revert on-chain -- this proves a guard works)${NC}"
    fi
    echo -e "${BOLD}${CYAN}==================================================================${NC}"

    forge script "script/${script_file}" --sig "$sig" --rpc-url "$RPC_URL" --broadcast "$@" \
        | grep -v -E "^(No files changed|Compiling|Solc |## Setting up|ONCHAIN EXECUTION COMPLETE|Transactions saved to:|Sensitive values saved to:)"
    local status=${PIPESTATUS[0]}

    print_tx_links "${script_file}"

    if [ $status -ne 0 ]; then
        if [ "$expect_fail" = "true" ]; then
            warn "reverted as expected -- guard is working"
        else
            fail "step ${STEP_NUM} failed unexpectedly (exit ${status}). Stopping."
            exit 1
        fi
    else
        ok "STEP ${STEP_NUM} COMPLETE"
    fi
}

# run_offchain_step TITLE -- prints a matching step banner for a step that
# sends no transaction (a pure off-chain verification demonstration, e.g.
# re-hashing a file locally). Keeps step numbering/narration consistent with
# run_step even though there's nothing to broadcast here.
run_offchain_step() {
    local title="$1"

    STEP_NUM=$((STEP_NUM + 1))
    local title_upper
    title_upper=$(echo "$title" | tr '[:lower:]' '[:upper:]')

    echo
    echo -e "${BOLD}${CYAN}==================================================================${NC}"
    echo -e "${BOLD}${CYAN}>>> STARTING STEP ${STEP_NUM}: ${title_upper}${NC}"
    echo -e "${YELLOW}    (off-chain check -- no transaction is sent for this step)${NC}"
    echo -e "${BOLD}${CYAN}==================================================================${NC}"
}

# check LABEL EXPECTED ACTUAL -- prints PASS/FAIL, exits the whole run on a
# failure (a mismatch here means the contracts didn't do what the demo
# claims, which is worse than a step merely failing to broadcast).
check() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        ok "CHECK: ${label}"
    else
        fail "CHECK: ${label} -- expected [${expected}], got [${actual}]"
        exit 1
    fi
}

# check_differs LABEL A B -- the inverse of check(): passes when A and B are
# NOT equal. Used for the tampered-metadata demo, where success means the
# hashes fail to match.
check_differs() {
    local label="$1" a="$2" b="$3"
    if [ "$a" != "$b" ]; then
        ok "CHECK: ${label}"
    else
        fail "CHECK: ${label} -- expected these to differ, but both are [${a}]"
        exit 1
    fi
}

# Small readers over deployments/sepolia.json + live chain state, used by the
# inline checks/info lines below. Safe to call repeatedly; each does a fresh read.
factory_addr() { jq -r '.factory' deployments/sepolia.json; }
event_ticket() { jq -r '.eventTicket' deployments/sepolia.json; }
marketplace_addr() { jq -r '.marketplace' deployments/sepolia.json; }
alice_token() { jq -r '.aliceTokenId' deployments/sepolia.json; }
bob_token() { jq -r '.bobTokenId' deployments/sepolia.json; }
owner_of() { cast call "$(event_ticket)" "ownerOf(uint256)(address)" "$1" --rpc-url "$RPC_URL"; }
checked_in() { cast call "$(event_ticket)" "isCheckedIn(uint256)(bool)" "$1" --rpc-url "$RPC_URL"; }
seat_of() { cast call "$(event_ticket)" "seatOf(uint256)(string)" "$1" --rpc-url "$RPC_URL" | tr -d '"'; }

# getListing()/eventInfo() return a Solidity struct, not a flat list of
# return values -- ABI-decoding that requires wrapping the tuple type in an
# extra set of parens (e.g. "((address,uint256,bool))"), and since these
# structs contain dynamic fields elsewhere in this contract (strings), we
# decode via --json + jq rather than the human-readable text format, which
# annotates numbers with "[1.2e3]"-style hints that aren't safe to text-parse.
listing_json() {
    cast call "$(marketplace_addr)" "getListing(address,uint256)((address,uint256,bool))" \
        "$(event_ticket)" "$1" --rpc-url "$RPC_URL" --json
}
listing_active() { listing_json "$1" | jq -r '.[0][2]'; }
listing_price_eth() { cast from-wei "$(listing_json "$1" | jq -r '.[0][1]')"; }

# Prints the ticket's seat + current holder together, e.g.
# "seat A-1, held by Bob (0x9A5f...)" -- the human-readable summary used
# throughout the info lines below.
ticket_summary() {
    echo "seat $(seat_of "$1"), held by $(label "$(owner_of "$1")")"
}

echo -e "${BOLD}${CYAN}"
echo "=================================================================="
echo "  TICKETCHAIN TESTNET DEMO"
echo "=================================================================="
echo -e "${NC}"
info "RPC target:       ${RPC_URL}"
info "Organizer wallet: ${WALLET_ADDRESS}"
info "Alice wallet:     ${ALICE_ADDRESS}"
info "Bob wallet:       ${BOB_ADDRESS}"
pause

run_step "Deploy EventFactory + Marketplace" \
    "Deploy.s.sol" "run()" false --private-key "$PRIVATE_KEY"
state
info "EventFactory: $(factory_addr)"
info "Marketplace:  $(marketplace_addr)"
pause

run_step "Fund Alice & Bob from the deployer wallet" \
    "00_FundActors.s.sol" "run()" false --private-key "$PRIVATE_KEY"
state
info "Alice balance: $(eth_balance "$ALICE_ADDRESS") ETH"
info "Bob balance:   $(eth_balance "$BOB_ADDRESS") ETH"
pause

run_step "Organizer creates the event and mints tickets to Alice & Bob" \
    "01_CreateEventAndMint.s.sol" "runCreateAndMint()" false --private-key "$PRIVATE_KEY"
EVENT_INFO_JSON=$(cast call "$(event_ticket)" \
    "eventInfo()((string,uint256,string,uint256,uint256))" --rpc-url "$RPC_URL" --json)
EVENT_NAME=$(echo "$EVENT_INFO_JSON" | jq -r '.[0][0]')
EVENT_DATE_TS=$(echo "$EVENT_INFO_JSON" | jq -r '.[0][1]')
EVENT_VENUE=$(echo "$EVENT_INFO_JSON" | jq -r '.[0][2]')
EVENT_FACE_VALUE_WEI=$(echo "$EVENT_INFO_JSON" | jq -r '.[0][3]')
EVENT_DATE_HUMAN=$(date -r "$EVENT_DATE_TS" 2>/dev/null || date -d "@${EVENT_DATE_TS}" 2>/dev/null || echo "$EVENT_DATE_TS")
state
info "Event:        \"${EVENT_NAME}\" at ${EVENT_VENUE}, ${EVENT_DATE_HUMAN}"
info "Face value:   $(cast from-wei "$EVENT_FACE_VALUE_WEI") ETH"
info "EventTicket:  $(event_ticket)"
info "Alice ticket: #$(alice_token), $(ticket_summary "$(alice_token)")"
info "Bob ticket:   #$(bob_token), $(ticket_summary "$(bob_token)")"
check "ownerOf(aliceTokenId) == Alice" "$ALICE_ADDRESS" "$(owner_of "$(alice_token)")"
check "ownerOf(bobTokenId) == Bob" "$BOB_ADDRESS" "$(owner_of "$(bob_token)")"
pause

run_step "DENIED: Bob (non-organizer) tries to mint himself a ticket" \
    "01_CreateEventAndMint.s.sol" "runDeniedMint()" true --skip-simulation
check "Bob's ticket ownership unaffected by his own denied mint" "$BOB_ADDRESS" "$(owner_of "$(bob_token)")"
pause

run_step "DENIED: Alice tries to list above the 110% price cap" \
    "02_ResaleFlow.s.sol" "runDeniedOverCap()" true --skip-simulation
check "no listing created by the denied over-cap attempt" "false" "$(listing_active "$(alice_token)")"
pause

run_step "DENIED: Alice tries to list a ticket from an unregistered event contract" \
    "02_ResaleFlow.s.sol" "runDeniedUnknownEvent()" true --skip-simulation
check "no listing created by the denied unknown-event attempt" "false" "$(listing_active "$(alice_token)")"
pause

run_step "Alice approves and lists her ticket for resale" \
    "02_ResaleFlow.s.sol" "runListing()" false
state
info "Alice lists ticket #$(alice_token) (seat $(seat_of "$(alice_token)")) for $(listing_price_eth "$(alice_token)") ETH"
check "listing is now active" "true" "$(listing_active "$(alice_token)")"
pause

run_step "DENIED: Bob tries to buy while underpaying" \
    "02_ResaleFlow.s.sol" "runDeniedUnderpay()" true --skip-simulation
check "listing still active (underpay attempt didn't consume it)" "true" "$(listing_active "$(alice_token)")"
check "ticket still owned by Alice (underpay attempt didn't transfer it)" "$ALICE_ADDRESS" "$(owner_of "$(alice_token)")"
pause

run_step "Bob buys Alice's listed ticket" \
    "02_ResaleFlow.s.sol" "runPurchase()" false
state
info "Ticket #$(alice_token) now $(ticket_summary "$(alice_token)")"
info "Alice balance: $(eth_balance "$ALICE_ADDRESS") ETH (received sale proceeds)"
info "Bob balance:   $(eth_balance "$BOB_ADDRESS") ETH (paid the listed price)"
check "ownerOf(aliceTokenId) == Bob after purchase" "$BOB_ADDRESS" "$(owner_of "$(alice_token)")"
check "listing deactivated after purchase" "false" "$(listing_active "$(alice_token)")"
pause

run_step "DENIED: Bob tries to check himself in" \
    "03_ManualCheckIn.s.sol" "runDeniedSelfCheckIn()" true --skip-simulation
check "bobTokenId still NOT checked in" "false" "$(checked_in "$(bob_token)")"
pause

run_step "Organizer checks Bob's original ticket in" \
    "03_ManualCheckIn.s.sol" "runCheckIn()" false --private-key "$PRIVATE_KEY"
state
info "Ticket #$(bob_token) ($(seat_of "$(bob_token)")) checked in (manual) -- holder: $(label "$(owner_of "$(bob_token)")")"
check "bobTokenId now checked in" "true" "$(checked_in "$(bob_token)")"
pause

run_step "DENIED: replaying check-in on the same (already-used) ticket" \
    "03_ManualCheckIn.s.sol" "runDeniedReplay()" true --private-key "$PRIVATE_KEY" --skip-simulation
check "bobTokenId still checked in (replay had no effect)" "true" "$(checked_in "$(bob_token)")"
pause

run_step "DENIED: signature from Alice, the former owner of the resold ticket" \
    "04_SignatureCheckIn.s.sol" "runDeniedWrongSigner()" true --private-key "$PRIVATE_KEY" --skip-simulation
check "aliceTokenId still NOT checked in" "false" "$(checked_in "$(alice_token)")"
pause

run_step "Bob (current owner) signs and gets checked in via EIP-712" \
    "04_SignatureCheckIn.s.sol" "runCheckIn()" false --private-key "$PRIVATE_KEY"
state
info "Ticket #$(alice_token) ($(seat_of "$(alice_token)")) checked in (EIP-712 signature) -- holder: $(label "$(owner_of "$(alice_token)")")"
check "aliceTokenId now checked in (via Bob's signature)" "true" "$(checked_in "$(alice_token)")"
pause

run_step "DENIED: an expired signature is rejected" \
    "04_SignatureCheckIn.s.sol" "runDeniedExpiredSignature()" true --private-key "$PRIVATE_KEY" --skip-simulation
check "aliceTokenId still checked in (expired attempt had no effect)" "true" "$(checked_in "$(alice_token)")"
pause

run_step "Organizer sets metadata, then legitimately updates it (venue change)" \
    "05_MetadataUpdate.s.sol" "runSetMetadata()" false --private-key "$PRIVATE_KEY"
METADATA_URI=$(cast call "$(event_ticket)" "metadataURI()(string)" --rpc-url "$RPC_URL" | tr -d '"')
METADATA_HASH=$(cast call "$(event_ticket)" "metadataHash()(bytes32)" --rpc-url "$RPC_URL")
# Independently re-hash the actual file on disk -- this is the verification
# step anyone could run themselves, not just trust our own commit.
EXPECTED_V2_HASH=$(cast keccak "0x$(xxd -p metadata/demo-concert-v2.json | tr -d '\n')")
state
info "Metadata URI:         ${METADATA_URI}"
info "On-chain hash:        ${METADATA_HASH}"
info "Re-hashed from file:  ${EXPECTED_V2_HASH}"
if [ "$METADATA_HASH" = "$EXPECTED_V2_HASH" ]; then
    info "Match: YES -- file content verified against the on-chain commitment"
else
    info "Match: NO -- file content does NOT match the on-chain commitment"
fi
check "metadataURI == v2 artifact" "metadata/demo-concert-v2.json" "$METADATA_URI"
check "metadataHash matches demo-concert-v2.json bytes" "$EXPECTED_V2_HASH" "$METADATA_HASH"
pause

run_offchain_step "Tampering check: hashing a swapped-in fake artifact"
# Simulates an attacker swapping the file hosted at the same nominal URI
# (e.g. a compromised host or a re-pinned IPFS CID) -- metadata/demo-concert-tampered.json
# looks superficially similar (same filename convention, same JSON shape)
# but has a different venue and a swapped image link.
TAMPERED_HASH=$(cast keccak "0x$(xxd -p metadata/demo-concert-tampered.json | tr -d '\n')")
state
info "On-chain hash (unchanged):     ${METADATA_HASH}"
info "Hash of the swapped-in file:   ${TAMPERED_HASH}"
if [ "$METADATA_HASH" = "$TAMPERED_HASH" ]; then
    info "Match: YES -- this would mean tampering went UNDETECTED (should not happen)"
else
    info "Match: NO -- tampering DETECTED. Anyone re-hashing the file themselves would catch this."
fi
check_differs "tampered file hash does not match the on-chain commitment" "$TAMPERED_HASH" "$METADATA_HASH"
pause

run_step "DENIED: Bob (non-organizer) tries to set metadata" \
    "05_MetadataUpdate.s.sol" "runDeniedSetMetadata()" true --skip-simulation
check "metadata unchanged by Bob's denied attempt" "$METADATA_HASH" "$(cast call "$(event_ticket)" "metadataHash()(bytes32)" --rpc-url "$RPC_URL")"
pause

echo
echo -e "${BOLD}${GREEN}"
echo "=================================================================="
echo "  DEMO COMPLETE -- ALL STEPS AND CHECKS PASSED"
echo "=================================================================="
echo -e "${NC}"
cat deployments/sepolia.json
