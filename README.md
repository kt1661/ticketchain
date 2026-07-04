# TicketChain

A transparent, verifiable event-ticketing platform on Ethereum. Each ticket is an
ERC-721 token; ownership and transfer history live on-chain so anyone can verify who
owns a ticket without trusting a central platform.

Built with **Solidity + Foundry**. Blockchain Security course project.

---

## Architecture

```
EventFactory                         # deploys + registers events (anti-counterfeit anchor)
    └── creates EventTicket (ERC-721) # one contract per event
                └── mints Token #N    # one token per ticket
Marketplace                          # rule-bound resale: price caps + organizer royalties
```

| Contract | Status |
|----------|--------|
| `EventTicket.sol` | Complete — minting, one-way check-in (manual + EIP-712 signature-verified) restricted to organizer/authorized verifiers, off-chain metadata integrity hash |
| `EventFactory.sol` | Complete — event registry / anti-counterfeit anchor |
| `Marketplace.sol` | Complete — hardened resale: CEI + `nonReentrant`, royalty split, refunds, registry + approval checks |

---

## Prerequisites

Install Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## Setup

```bash
# from the project root
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
forge build
forge test -vvv
```

> Note: the contracts are written against **OpenZeppelin v5.1.0** and compile with
> **solc 0.8.24** targeting the **cancun** EVM (both pinned in `foundry.toml`).

Copy the env template before deploying:

```bash
cp .env.example .env   # then fill in your values
```

## Common commands

```bash
forge build                       # compile
forge test                        # run all tests
forge test --match-contract Marketplace -vvv   # one suite, verbose
forge test --match-test testFuzz  # just the fuzz tests
forge coverage                    # coverage report
forge fmt                         # format

# local node + deploy
anvil                             # terminal 1
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 \
    --broadcast --private-key $PRIVATE_KEY   # terminal 2

# Sepolia deploy
forge script script/Deploy.s.sol --rpc-url sepolia \
    --broadcast --private-key $PRIVATE_KEY --verify
```

## Running the full demo

To run the full usage scenario end-to-end (deploy, create an event, mint,
resale, check-in, metadata update) via `script/run-demo.sh` against either a
local `anvil` node or real Sepolia, see [`RUNNING_THE_DEMO.md`](RUNNING_THE_DEMO.md).

---

## Security hardening implemented

- **`Marketplace.buy()`** — enforces Checks-Effects-Interactions, splits payment
  (royalty → organizer, remainder → seller), refunds overpayment, and is guarded
  with `nonReentrant`. The reentrancy test in `test/Marketplace.t.sol` proves a
  reentrant call is blocked (and fails loudly if the guard or CEI ordering breaks).
- **`Marketplace.list()`** — rejects tickets from event contracts that aren't
  registered in `EventFactory` (blocks counterfeit look-alike contracts), and
  requires marketplace approval before a listing can be created.
- **`Marketplace.buy()`** also re-verifies the seller still owns the token before
  moving any funds, so a listing that went stale (seller transferred the ticket
  away directly) fails fast with a clear reason.
- **`EventTicket.checkIn()`** — restricted to the organizer or an address granted
  verifier status via `setVerifier`; no longer open to anyone.
- **`EventTicket.checkInWithSignature()`** — cryptographic holder-presence proof.
  The ticket holder signs an EIP-712 `CheckIn(tokenId, deadline)` message with
  their own wallet at the gate; the verifier submits it and the contract recovers
  the signer via `ECDSA.recover` and checks it matches the *current* `ownerOf`.
  This proves the presenter controls the owning private key, not just that gate
  staff eyeballed an ID. The EIP-712 domain (chainId + this contract's address)
  plus the `deadline` stop a captured signature from being replayed on another
  event, another ticket, or after the gate window closes; "already checked in"
  makes it single-use. Plain `checkIn()` still exists for manual/no-wallet gate
  flows, but only the signature path cryptographically proves wallet control.

---

## Off-chain metadata + on-chain integrity hash

Event art, seat-map images, long descriptions, and other display content don't
belong on-chain (expensive, and doesn't need trustless verification the way
ownership does). Instead, `EventTicket` stores a pointer + hash:

- `metadataURI` — where to fetch the off-chain file (e.g. `metadata/demo-concert.json`
  in this repo, or an IPFS URI in a real deployment).
- `metadataHash` — `keccak256` of that file's exact bytes at the time the organizer
  committed it.

Anyone can independently check integrity: fetch the file at `metadataURI`, hash it,
and compare to `metadataHash`. A match proves the content hasn't been swapped since
the organizer committed it; a mismatch proves tampering
(`test_TamperedArtifactFailsIntegrityCheck`).

**Important:** this hash is a content-integrity check only — it does **not**
determine ticket validity or ownership. Those are already fully established
on-chain via `EventFactory.isLegitimate`, `ownerOf`, and `isCheckedIn`, completely
independent of this mechanism.

`setMetadata(uri, hash)` is restricted to the organizer (`onlyOwner`) and is
re-callable, so a legitimate change (e.g. a venue change) is just the organizer
calling it again. Every call emits `MetadataUpdated`, giving a full on-chain audit
trail of every change, not just the current value (`test_OrganizerCanLegitimatelyUpdateMetadata`).

> **Known limitation:** this design puts full trust in a single organizer private
> key. Anyone who controls that key can push a `setMetadata` update that looks
> "legitimate" on-chain — e.g. announcing a fraudulent last-minute venue change —
> and the audit trail would faithfully record it as an authorized change, because
> cryptographically it *was* signed by the organizer's key. The contract cannot
> distinguish "the real organizer decided to change the venue" from "the
> organizer's key was phished and someone else did." A production system would
> likely want a timelock (so changes are visible before they take effect) and/or
> multisig control over the organizer role to reduce single-key risk. This is
> called out here deliberately as a disclosed limitation rather than solved.

---

## Security properties under test

- Reentrancy on `buy()` is blocked (`test_ReentrancyOnBuyIsBlocked`).
- Supply is never exceeded (`invariant_SupplyNeverExceeded`).
- Check-ins are one-way / sticky (`invariant_CheckInsAreSticky`).
- Resale never exceeds the price cap (fuzzed).
- Overpayment is always refunded (fuzzed).
- Only the organizer can mint; only the owner can list.
- `checkInWithSignature` rejects signatures from anyone but the current ticket
  owner, expired signatures, and signatures replayed against a different tokenId
  (`test_CheckInWithWrongSignerReverts`, `test_CheckInSignatureExpiredReverts`,
  `test_CheckInSignatureBoundToTokenId`).
- Only the organizer can update off-chain metadata (`test_NonOrganizerCannotSetMetadata`);
  a tampered artifact fails re-hash comparison (`test_TamperedArtifactFailsIntegrityCheck`).
