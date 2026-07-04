# Running the Demo

Command reference for `script/run-demo.sh`, on both a local `anvil` node
(free, instant, safe to rerun as many times as you want) and real Sepolia.

---

## Prerequisites (once)

```bash
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
forge build
```

`jq` must be installed (`brew install jq` on macOS).

### Two `.env` files, one active `.env`

Keep two filled-in env files around instead of one:

- `.env.sepolia` — real Sepolia RPC + real deployer/actor keys, and
  `STATE_FILE=deployments/sepolia.json`
- `.env.anvil` — anything for the keys (anvil's default test accounts work
  fine), and `STATE_FILE=deployments/anvil.json`

Copy `.env.example` to create either one if you don't have them yet. Each
needs: `SEPOLIA_RPC_URL` (anvil ignores this), `WALLET_ADDRESS` +
`PRIVATE_KEY` (the organizer/deployer), `ALICE_ADDRESS`/`ALICE_PRIVATE_KEY` +
`BOB_ADDRESS`/`BOB_PRIVATE_KEY` (throwaway demo actors — generate with
`cast wallet new` if needed), and `STATE_FILE`.

**Before every run, copy the right one into `.env`:**
```bash
cp .env.sepolia .env    # for Sepolia
# or
cp .env.anvil .env      # for local anvil
```

The scripts and `run-demo.sh` both read `STATE_FILE` from `.env` to decide
which deployment record to read/write. This is what keeps the two networks'
addresses from ever clobbering each other — running against anvil can never
overwrite `deployments/sepolia.json`, and vice versa.

---

## Option A: Local anvil (practice runs)

No real ETH, no waiting on block times, safe to run over and over.

**Terminal 1** — start a local node:
```bash
anvil
```
Leave it running.

**Terminal 2** — copy the anvil env and run the full demo against it:
```bash
cp .env.anvil .env
./script/run-demo.sh --reset --rpc http://127.0.0.1:8545 --auto
```

- Drop `--auto` to pause after each step (recommended once, to preview the
  actual pacing before doing it live).
- `--reset` wipes `deployments/anvil.json` (not `sepolia.json`) back to `{}`
  before starting, so you always get a fresh event/tickets.
- **Every time you restart the `anvil` process itself**, the whole chain
  resets to genesis — any contracts from a previous session no longer exist,
  even though `deployments/anvil.json` still remembers their addresses. Pass
  `--reset` on the first run after restarting anvil so the script redeploys
  instead of trying to call dead addresses. (`run-demo.sh` also checks real
  on-chain bytecode via `is_deployed()` at steps 1 and 3, so this failure
  mode shows up as a clear check failure rather than a silent bad call.)
- This never touches your real Sepolia keys or `deployments/sepolia.json` —
  totally separate local chain, totally separate state file.

---

## Option B: Real Sepolia (the actual demo)

**1. Make sure `.env` is the Sepolia one:**
```bash
cp .env.sepolia .env
```

**2. Check your deployer wallet has enough Sepolia ETH:**
```bash
source .env
cast balance "$WALLET_ADDRESS" --rpc-url "$SEPOLIA_RPC_URL" --ether
```
A full run (2 contract deployments + funding Alice/Bob + the full
lifecycle) costs a small fraction of typical faucet amounts (0.02–0.05 ETH
is comfortably enough). Resuming from a later step with `--from N` (see
below) is much cheaper since it skips the already-deployed contracts.

**3. Run it:**
```bash
./script/run-demo.sh --reset
```
(`--reset` wipes `deployments/sepolia.json` for a brand-new event — omit it
to continue an existing deployment. Unlike anvil, Sepolia never resets on
its own, so `deployments/sepolia.json` stays valid indefinitely; you only
need `--reset` when you actually want to pay for a fresh deployment.)

- Default mode is **interactive** — it pauses after each step so you can
  narrate before continuing. This is what you want for the actual demo.
- Default RPC target is `sepolia` (resolved from `SEPOLIA_RPC_URL` via
  `foundry.toml`) — no `--rpc` flag needed.
- Each step prints real transaction hashes as `https://sepolia.etherscan.io/tx/...`
  links (via `print_tx_links`) — click through during the demo to show the
  grader the mined transaction.

---

## Flags reference

| Flag | Effect |
|---|---|
| (none) | Interactive: pause after each step, target `sepolia` |
| `--auto` | Run straight through with no pauses |
| `--rpc <url>` | Target a different RPC (e.g. local anvil) instead of `sepolia` |
| `--reset` | Wipe the active `STATE_FILE` before starting (fresh event) |
| `--from N` | Resume from step N, skipping (not re-broadcasting) earlier steps |

**Don't combine `--reset` with `--from N`.** `--reset` wipes the state file
that `--from N`'s skipped steps would have populated, so step N ends up
reading addresses that were never written. `--reset` implies starting over
from step 1.

---

## Running a single step manually

Useful if a run stops partway and you want to resume from a specific step,
or you just want to re-demonstrate one guard without redoing everything
before it. Each step is its own `forge script` invocation — copy the exact
command for the step you need from the table below. All of these assume the
active `STATE_FILE` already has the addresses from a prior `Deploy.s.sol` +
`01_CreateEventAndMint.s.sol` run.

`--rpc-url` below is written as `sepolia`; swap in `http://127.0.0.1:8545`
for local anvil (and make sure `.env` is the matching `.env.anvil`/
`.env.sepolia` copy first, so `STATE_FILE` points at the right record).

| # | What it does | Command |
|---|---|---|
| 1 | Deploy EventFactory + Marketplace | `forge script script/Deploy.s.sol --sig "run()" --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY` |
| 2 | Fund Alice & Bob | `forge script script/00_FundActors.s.sol --sig "run()" --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY` |
| 3 | Create event + mint tickets | `forge script script/01_CreateEventAndMint.s.sol --sig "runCreateAndMint()" --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY` |
| 4 | DENIED: Bob mints without authorization | `forge script script/01_CreateEventAndMint.s.sol --sig "runDeniedMint()" --rpc-url sepolia --broadcast --skip-simulation` |
| 5 | DENIED: list above price cap | `forge script script/02_ResaleFlow.s.sol --sig "runDeniedOverCap()" --rpc-url sepolia --broadcast --skip-simulation` |
| 6 | DENIED: list unregistered event contract | `forge script script/02_ResaleFlow.s.sol --sig "runDeniedUnknownEvent()" --rpc-url sepolia --broadcast --skip-simulation` |
| 7 | Alice approves + lists ticket | `forge script script/02_ResaleFlow.s.sol --sig "runListing()" --rpc-url sepolia --broadcast` |
| 8 | DENIED: Bob underpays | `forge script script/02_ResaleFlow.s.sol --sig "runDeniedUnderpay()" --rpc-url sepolia --broadcast --skip-simulation` |
| 9 | Bob buys the ticket | `forge script script/02_ResaleFlow.s.sol --sig "runPurchase()" --rpc-url sepolia --broadcast` |
| 10 | DENIED: Bob checks himself in | `forge script script/03_ManualCheckIn.s.sol --sig "runDeniedSelfCheckIn()" --rpc-url sepolia --broadcast --skip-simulation` |
| 11 | Organizer checks Bob's ticket in | `forge script script/03_ManualCheckIn.s.sol --sig "runCheckIn()" --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY` |
| 12 | DENIED: check-in replay | `forge script script/03_ManualCheckIn.s.sol --sig "runDeniedReplay()" --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY --skip-simulation` |
| 13 | DENIED: signature from former owner | `forge script script/04_SignatureCheckIn.s.sol --sig "runDeniedWrongSigner()" --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY --skip-simulation` |
| 14 | Bob signs + gets checked in (EIP-712) | `forge script script/04_SignatureCheckIn.s.sol --sig "runCheckIn()" --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY` |
| 15 | DENIED: expired signature | `forge script script/04_SignatureCheckIn.s.sol --sig "runDeniedExpiredSignature()" --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY --skip-simulation` |
| 16 | Organizer sets + updates metadata | `forge script script/05_MetadataUpdate.s.sol --sig "runSetMetadata()" --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY` |
| 17 | Tampering check (off-chain, no tx) | See "Verifying metadata integrity by hand" below |
| 18 | DENIED: Bob sets metadata | `forge script script/05_MetadataUpdate.s.sol --sig "runDeniedSetMetadata()" --rpc-url sepolia --broadcast --skip-simulation` |

**Important:** steps marked DENIED must always be the *last* transaction of
their own invocation — `forge script` stops broadcasting the rest of a
batch after the first reverted transaction, so a DENIED entrypoint can never
be safely combined with a legitimate call in the same script run. That's
why each is its own function/invocation rather than folded into the
adjacent legitimate step. `--skip-simulation` is required on all of them:
without it, Foundry refuses to even attempt sending a transaction it
predicts will revert.

---

## Useful diagnostic commands

Check current deployment state (swap the filename for whichever network you
just ran against):
```bash
cat deployments/sepolia.json
cat deployments/anvil.json
```

Check a wallet's Sepolia ETH balance:
```bash
source .env
cast balance <address> --rpc-url "$SEPOLIA_RPC_URL" --ether
```

Check who currently owns a ticket:
```bash
EVENT_TICKET=$(jq -r '.eventTicket' deployments/sepolia.json)
cast call "$EVENT_TICKET" "ownerOf(uint256)(address)" <tokenId> --rpc-url "$SEPOLIA_RPC_URL"
```

Confirm an address actually has bytecode on the target chain (not just an
address recorded on paper — useful after restarting anvil, or any time a
step behaves unexpectedly):
```bash
cast code <address> --rpc-url "$SEPOLIA_RPC_URL"
```
`0x` means nothing is deployed there on this chain.

Verifying metadata integrity by hand (what step 17 automates):
```bash
EVENT_TICKET=$(jq -r '.eventTicket' deployments/sepolia.json)
cast call "$EVENT_TICKET" "metadataHash()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL"
cast keccak "0x$(xxd -p metadata/demo-concert-v2.json | tr -d '\n')"
```
The two hashes should match. Swap in `metadata/demo-concert-tampered.json`
for the second command to see them *not* match — that's the tampering
demonstration.
