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

`.env` must exist and be filled in (copy `.env.example` if you haven't):
```bash
cp .env.example .env
```
It needs: `SEPOLIA_RPC_URL`, `WALLET_ADDRESS` + `PRIVATE_KEY` (the organizer/
deployer), and `ALICE_ADDRESS`/`ALICE_PRIVATE_KEY` + `BOB_ADDRESS`/
`BOB_PRIVATE_KEY` (throwaway demo actors — generate with `cast wallet new`
if you don't have them yet).

`jq` must be installed (`brew install jq` on macOS).

---

## Option A: Local anvil (practice runs)

No real ETH, no waiting on block times, safe to run over and over.

**Terminal 1** — start a local node:
```bash
anvil
```
Leave it running.

**Terminal 2** — reset state and run the full demo against it:
```bash
echo '{}' > deployments/sepolia.json
./script/run-demo.sh --rpc http://127.0.0.1:8545 --auto
```

- Drop `--auto` to pause after each step (recommended once, to preview the
  actual pacing before doing it live).
- Every time you want a completely fresh run, reset the state file first
  (`echo '{}' > deployments/sepolia.json`) — otherwise later steps will try
  to reuse addresses from the previous run.
- `.env`'s `PRIVATE_KEY`/`ALICE_PRIVATE_KEY`/`BOB_PRIVATE_KEY` can safely be
  any valid keys here (even the real Sepolia ones) — anvil is a totally
  separate local chain, nothing here touches real funds.

---

## Option B: Real Sepolia (the actual demo)

**1. Check your deployer wallet has enough Sepolia ETH:**
```bash
source .env
cast balance "$WALLET_ADDRESS" --rpc-url "$SEPOLIA_RPC_URL" --ether
```
A full run (2 contract deployments + funding Alice/Bob + the full
lifecycle) costs a small fraction of typical faucet amounts (0.02–0.05 ETH
is comfortably enough).

**2. Reset the deployment-state file** (only if you want a brand-new event —
skip this if you're continuing a previous run):
```bash
echo '{}' > deployments/sepolia.json
```

**3. Run it:**
```bash
./script/run-demo.sh --reset
```
(`--reset` does step 2 for you automatically — safe to use every time you
want a fresh event.)

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
| `--reset` | Wipe `deployments/sepolia.json` before starting (fresh event) |

---

## Running a single step manually

Useful if a run stops partway and you want to resume from a specific step,
or you just want to re-demonstrate one guard without redoing everything
before it. Each step is its own `forge script` invocation — copy the exact
command for the step you need from the table below. All of these assume
`deployments/sepolia.json` already has the addresses from a prior
`Deploy.s.sol` + `01_CreateEventAndMint.s.sol` run.

`--rpc-url` below is written as `sepolia`; swap in `http://127.0.0.1:8545`
for local anvil.

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

Check current deployment state:
```bash
cat deployments/sepolia.json
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

Verifying metadata integrity by hand (what step 17 automates):
```bash
EVENT_TICKET=$(jq -r '.eventTicket' deployments/sepolia.json)
cast call "$EVENT_TICKET" "metadataHash()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL"
cast keccak "0x$(xxd -p metadata/demo-concert-v2.json | tr -d '\n')"
```
The two hashes should match. Swap in `metadata/demo-concert-tampered.json`
for the second command to see them *not* match — that's the tampering
demonstration.
