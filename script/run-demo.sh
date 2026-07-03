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

# Small readers over deployments/sepolia.json + live chain state, used by the
# inline checks/info lines below. Safe to call repeatedly; each does a fresh read.
factory_addr() { jq -r '.factory' deployments/sepolia.json; }
event_ticket() { jq -r '.eventTicket' deployments/sepolia.json; }
marketplace_addr() { jq -r '.marketplace' deployments/sepolia.json; }
alice_token() { jq -r '.aliceTokenId' deployments/sepolia.json; }
bob_token() { jq -r '.bobTokenId' deployments/sepolia.json; }
owner_of() { cast call "$(event_ticket)" "ownerOf(uint256)(address)" "$1" --rpc-url "$RPC_URL"; }
checked_in() { cast call "$(event_ticket)" "isCheckedIn(uint256)(bool)" "$1" --rpc-url "$RPC_URL"; }
listing_active() {
    cast call "$(marketplace_addr)" "getListing(address,uint256)(address,uint256,bool)" \
        "$(event_ticket)" "$1" --rpc-url "$RPC_URL" | tail -n1
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
state
info "EventTicket:  $(event_ticket)"
info "Alice ticket: #$(alice_token)"
info "Bob ticket:   #$(bob_token)"
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
info "Alice lists ticket #$(alice_token) for resale"
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
info "New owner of ticket #$(alice_token): $(owner_of "$(alice_token)") (Bob)"
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
info "Ticket #$(bob_token): checked in (manual, by organizer)"
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
info "Ticket #$(alice_token): checked in (EIP-712 signature, by Bob)"
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
EXPECTED_V2_HASH=$(cast keccak "0x$(xxd -p metadata/demo-concert-v2.json | tr -d '\n')")
state
info "Metadata URI:  ${METADATA_URI}"
info "Metadata hash: ${METADATA_HASH}"
check "metadataURI == v2 artifact" "metadata/demo-concert-v2.json" "$METADATA_URI"
check "metadataHash matches demo-concert-v2.json bytes" "$EXPECTED_V2_HASH" "$METADATA_HASH"
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
