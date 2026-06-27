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

| Contract | Owner | Status |
|----------|-------|--------|
| `EventTicket.sol` | Dev 1 | Happy path implemented; check-in authorization is a deliberate `TODO` |
| `EventFactory.sol` | Dev 1 | Complete |
| `Marketplace.sol` | Dev 2 | Resale path sketched; `buy()` hardening is the core `TODO` |

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

---

## Work division (5 people, 3 weeks)

- **Dev 1 — Core contracts:** `EventTicket`, `EventFactory`. Leads the day-2 interface freeze.
- **Dev 2 — Marketplace:** resale rules, price caps, royalties, harden `buy()`.
- **Dev 3 — Security & testing:** cross-cutting fuzz + invariant suite, reentrancy harness, security writeup.
- **Dev 4 — Frontend:** React + wagmi UI (browse, buy, resell, ownership lookup, QR).
- **Dev 5 — Verifier + deployment:** gate verifier (sign challenge → check `ownerOf` + check-in), deploy scripts, Sepolia, IPFS metadata.

### Week-by-week
- **Week 1:** freeze interfaces, core contracts pass unit tests.
- **Week 2:** marketplace complete, full buy→resell→check-in works locally, fuzz/invariant tests in.
- **Week 3:** deploy to Sepolia, frontend on real addresses, security writeup, demo + buffer.

---

## The `TODO`s are the assignment

The stubs compile and the happy path works so everyone can start in parallel. The
real work — and the security story for your writeup — lives in the marked `TODO`s,
especially:

1. **`Marketplace.buy()`** — enforce Checks-Effects-Interactions, split payments,
   refund overpayment. The reentrancy test in `test/Marketplace.t.sol` is there to
   prove your hardened version is safe (and to fail loudly if someone breaks it).
2. **`EventTicket.checkIn()`** — decide who is authorized to check tickets in.
   Right now it's open to anyone; that's a gap to close and document.

---

## Security properties under test

- Reentrancy on `buy()` is blocked (`test_ReentrancyOnBuyIsBlocked`).
- Supply is never exceeded (`invariant_SupplyNeverExceeded`).
- Check-ins are one-way / sticky (`invariant_CheckInsAreSticky`).
- Resale never exceeds the price cap (fuzzed).
- Overpayment is always refunded (fuzzed).
- Only the organizer can mint; only the owner can list.
