# SLUGFEAST

**An Ethereum-based memecoin creation and trading platform with zero-liquidity token launches.**

SLUGFEAST lets anyone create a token and have it be immediately tradable — no initial liquidity required from the creator. A bonding-curve AMM inside the `SlugDex` contract acts as the counterparty for every trade until the token has enough volume to "graduate" onto a real, permanently-liquid Uniswap V4 pool.

> This repository hosts the on-chain contracts, the subgraph that indexes them, and a written article/analysis of the system. The web application (frontend + backend microservices) lives in a separate repo: [`SlugFeast-Web`](https://github.com/ramanshu-mishra/SlugFeast-Web).

---

## Table of Contents

- [How it works](#how-it-works)
- [Repository structure](#repository-structure)
- [Contracts](#contracts)
  - [`SlugDex.sol`](#slugdexsol--the-core-engine)
  - [`Pool.sol`](#poolsol--bonding-curve-state)
  - [`slugToken.sol`](#slugtokensol--the-erc20-template)
  - [`feecollector.sol`](#feecollectorsol--protocol-fees)
- [Bonding curve mechanics](#bonding-curve-mechanics)
- [Token graduation](#token-graduation)
- [Indexer (subgraph)](#indexer-subgraph)
- [Getting started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Setup](#setup)
  - [Testing](#testing)
  - [Deployment](#deployment)
- [Deployments](#deployments)
- [Security notes / known limitations](#security-notes--known-limitations)
- [Roadmap / open questions](#roadmap--open-questions)
- [License](#license)

---

## How it works

The platform is split into two phases:

1. **Coin Generation** — Anyone can create a token by supplying a name, symbol, and metadata. No upfront liquidity is needed.
2. **Coin Listing (Graduation)** — Once the token has sold through its tradable bonding-curve supply, the contract automatically deploys the remaining tokens and collected ETH into a real Uniswap V4 pool, making the token tradable on any DEX.

**The mechanism behind zero-liquidity launches:** `SlugDex` simulates liquidity using a constant-product bonding curve (`x * y = k`), acting as the buyer/seller for every trade itself. It holds incoming ETH and releases tokens against it (and vice-versa for sells) — there is no external liquidity provider until graduation.

**Rug-pull protection:** the liquidity minted at graduation is owned by the `SlugDex` contract itself (not the token creator), so there's no LP position for a creator to pull.

**Fixed supply:** every token has a hard-capped supply of **1,000,000,000** units.
- **800,000,000 (80%)** — held in the bonding-curve pool, tradable from day one.
- **200,000,000 (20%)** — locked inside the contract and used as the token side of the liquidity position at graduation.

**Virtual liquidity:** the curve starts every new token against **4 VETH** (virtual ETH) — this is what makes the initial price curve well-defined without any real ETH being deposited up front.

---

## Repository structure

```
SLUGFEAST/
├── slugfeast-contracts/     # Foundry project — the on-chain protocol
│   ├── src/
│   │   ├── systemDex.sol        # SlugDex — main trading/graduation engine
│   │   ├── pool.sol             # Pool — abstract bonding-curve state & accounting
│   │   ├── slugToken.sol        # ERC20 template minted per created coin
│   │   ├── interfaces/
│   │   │   ├── IsystemDex.sol   # ISlugDex — events, errors, external signatures
│   │   │   └── Ipool.sol        # IPool — pool-related events & views
│   │   └── utilities/
│   │       └── feecollector.sol # Protocol fee accounting
│   ├── test/
│   │   └── SlugDex.t.sol        # Foundry tests (mocked Uniswap V4 dependencies)
│   ├── script/
│   │   └── deploy.s.sol         # Deployment script
│   ├── broadcast/               # Forge deployment records (mainnet, Sepolia, Monad testnet)
│   ├── lib/                     # forge-std, OpenZeppelin, Uniswap v4-core / v4-periphery
│   └── foundry.toml
│
├── indexer/
│   └── slug-feast/              # The Graph subgraph indexing SlugDex events
│       ├── subgraph.yaml
│       ├── schema.graphql
│       ├── src/slug-dex.ts      # AssemblyScript event handlers
│       ├── abis/
│       └── tests/
│
├── slugfeast-article/           # LaTeX write-up of the project (CogSci paper format)
│
├── slugfeast-web                # → git submodule, points to SlugFeast-Web (frontend + backend)
│
└── README.md
```

---

## Contracts

### `SlugDex.sol` — the core engine

`SlugDex` is the single contract users interact with. It inherits from `Pool`, `feeCollector`, and OpenZeppelin's `ReentrancyGuard`.

**State**
| Variable | Purpose |
|---|---|
| `slugFee` | Protocol fee, in basis-points-like precision (see [Fees](#fee-model)) |
| `_poolManager` / `_positionManager` | Addresses of the Uniswap V4 `PoolManager` and `PositionManager`, used at graduation |
| `_POOL_FEE` (`1500`) | Fee tier used for the graduated Uniswap V4 pool |
| `_TICK_SPACING` (`30`) | Tick spacing matching that fee tier |
| `nonce_map` | Per-address nonce, used for replay protection |

**Key external functions**

| Function | Description |
|---|---|
| `createToken(name, symbol, metadata_uri, id, nonce, signature)` | Deploys a new `slugToken`, mints the full 1B supply to itself, locks 200M for the future LP, and initializes its bonding-curve pool. |
| `buy(token, nonce)` *(payable)* | Swaps sent ETH for tokens along the bonding curve. If the buy would exhaust the pool's remaining token supply, it partially fills at the exact remaining amount, refunds the excess ETH, and triggers `graduateToken`. |
| `sell(token, amount, nonce)` | Swaps tokens back for ETH along the same curve (requires prior `approve`). |
| `getTokenQuote(token)` / `getETHQuote(token)` | Read-only spot-price helpers derived from `k`. |
| `calculateFee(ETH)` | Computes the protocol fee for a given ETH amount. |
| `getSlugFee` / `setSlugFee` *(owner-only)* | Read/update the protocol fee. |

**Security mechanisms**
- `nonReentrant` on `buy` and `sell`.
- `checkReplay(nonce)` — a per-sender nonce that must strictly increase, guarding against replayed calls.
- `verifySignature(nonce, signature)` — an EIP-191 (`ecrecover`)-based modifier that checks a signature was produced by the contract owner. **Currently unused** (see [Known limitations](#security-notes--known-limitations)).
- `exists(token)` / `notGraduated(token)` (from `Pool`) — guard against operating on unknown or already-graduated tokens.

### `Pool.sol` — bonding-curve state

An abstract contract (inherited by `SlugDex`) holding all the per-token accounting:

```solidity
struct supply {
    uint256 _tokenSupply; // tokens remaining in the bonding-curve pool
    uint256 _VETH;        // virtual ETH currently backing that pool
}
```

- `pools[token]` — current curve reserves for each token.
- `storedETH[token]` — real ETH actually collected from trading (used at graduation).
- `locked_tokens[token]` — the 200M tokens reserved for the future LP.
- `graduated[token]` — whether the token has already been listed externally.
- `getInitialTokenSupply()` → `800,000,000 × 10^6`
- `getInitialVEthSupply()` → `4 × 10^18` (4 virtual ETH, 18-decimal precision)
- `getK()` → the constant product `tokenSupply × VETHSupply`, fixed at pool creation

> Note the 10⁶ scaling factor on token amounts — the effective on-chain "token unit" is scaled, separate from the ERC20's own decimals.

### `slugToken.sol` — the ERC20 template

A minimal `ERC20` + `Ownable` contract deployed fresh for every new coin:
- Constructor mints `10^9` tokens to the deployer (the `SlugDex` contract) and stores a metadata URI string.
- `mint(address, value)` is `onlyOwner` — only `SlugDex` can mint further, though in practice the full supply is minted once at creation.

### `feecollector.sol` — protocol fees

Abstract contract tracking accumulated protocol fees:
- `takeFee(amount)` — internal, adds to `generatedFee`.
- `getCollectedFee()` — owner-only view of the accumulated total.
- `withdrawFee(amount)` — owner-only withdrawal, gated by `hasEnoughFee`.

---

## Bonding curve mechanics

The curve is a standard constant-product AMM: `tokenSupply × VETHSupply = k`, where `k` is fixed at pool creation (`800M tokens × 4 VETH`).

**Buying** (`buy`):
1. Fee is deducted from the sent ETH: `fee = (ETH × slugFee) / 10000`.
2. Tokens out are computed as `tokenSupply - k / (VETHSupply + netETH)`.
3. If the computed tokens exceed what's left in the pool, the trade is **capped** at the remaining supply — the buyer only pays the ETH actually required for those tokens, gets refunded the difference, and the token **graduates** in the same transaction.
4. Otherwise, the pool state is updated and tokens are transferred to the buyer.

**Selling** (`sell`):
1. Requires the seller to have `approve`d `SlugDex` for the amount.
2. ETH out is computed as `VETHSupply - k / (tokenSupply + amount)`.
3. Fee is deducted from the ETH proceeds; the pool state is updated; tokens are pulled in via `safeTransferFrom`; net ETH is sent to the seller.

### Fee model
`slugFee` is a value pre-multiplied by 100 by the caller to preserve 2 decimal places of precision (e.g. a fee of `0.75%` is passed as `75`). `calculateFee` then divides by `10000` (100 × 100) to recover the actual fee amount. This is set to `75` (0.75%) in the current deployment script.

---

## Token graduation

When a `buy` fully exhausts the bonding-curve token supply, `graduateToken` runs automatically:

1. Pulls the accumulated real ETH (`storedETH[token]`) and the 200M locked tokens (`locked_tokens[token]`).
2. Builds a Uniswap V4 `PoolKey` — native ETH (`address(0)`) as `currency0`, the token as `currency1`, using the fixed `0.30%`-tier fee/tick-spacing pair.
3. Computes the initial `sqrtPriceX96` from the token/ETH ratio (`encodeSqrtRatioX96`) and calls `_poolManager.initialize`.
4. Computes a full-range liquidity position (`TickMath.MIN_TICK` → `MAX_TICK`) sized via `LiquidityAmounts.getLiquidityForAmounts`.
5. Approves the `PositionManager` for the token amount, then calls `modifyLiquidities` with a `MINT_POSITION` + `SETTLE_PAIR` + `SWEEP` action batch, sending the accumulated ETH as `msg.value`. The resulting LP position is owned by the `SlugDex` contract itself.
6. Clears `locked_tokens[token]` and emits `tokenDeployed(token)`.

From this point, `notGraduated` blocks any further `buy`/`sell` through the bonding curve — the token now trades exclusively on the Uniswap V4 pool.

---

## Indexer (subgraph)

`indexer/slug-feast` is a [The Graph](https://thegraph.com/) subgraph that indexes `SlugDex` on-chain events into a queryable GraphQL API, so the frontend/backend don't need to hit the chain directly for history.

**Indexed events**: `TokenCreated`, `TokenBought`, `TokenSold`, `poolcreated`, `tokenDeployed`, `tokenGraduated`, `OwnershipTransferred` — each mapped to its own immutable GraphQL entity in `schema.graphql`, with handlers in `src/slug-dex.ts`.

```bash
cd indexer/slug-feast
yarn install
yarn codegen        # generate types from schema.graphql + ABI
yarn build           # compile the subgraph
yarn deploy          # deploy to The Graph Studio
# or, for local development against a Graph Node:
yarn create-local
yarn deploy-local
```

Tests use [`matchstick-as`](https://github.com/LimeChain/matchstick) and live in `indexer/slug-feast/tests/`.

---

## Getting started

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)
- Node.js ≥ 18 and Yarn (for the indexer)
- Git (with submodule support, for `lib/v4-core`, `lib/v4-periphery`, and the `slugfeast-web` submodule)

### Setup

```bash
git clone --recurse-submodules https://github.com/ramanshu-mishra/SLUGFEAST.git
cd SLUGFEAST/slugfeast-contracts
forge install   # in case submodules didn't pull cleanly
forge build
```

### Testing

```bash
cd slugfeast-contracts
forge fmt --check
forge build --sizes
forge test -vvv
```

`test/SlugDex.t.sol` uses lightweight mock `IPoolManager`/`IPositionManager` contracts so the full test suite can run without a live Uniswap V4 deployment. CI runs this same sequence on every push/PR via `.github/workflows/test.yml`.

### Deployment

```bash
cd slugfeast-contracts
forge script script/deploy.s.sol:DeployDex \
  --rpc-url <RPC_URL> \
  --broadcast \
  --verify
```

`DeployDex` currently constructs `SlugDex` with:
- `dexFee = 75` (0.75%)
- A hardcoded Uniswap V4 `PoolManager` address
- A hardcoded Uniswap V4 `PositionManager` address

> Update these constants in `script/deploy.s.sol` for the target network before deploying.

---

## Deployments

Deployment broadcasts are recorded under `slugfeast-contracts/broadcast/deploy.s.sol/`, with folders for the following chain IDs:

| Chain ID | Network |
|---|---|
| `1` | Ethereum Mainnet |
| `11155111` | Sepolia (testnet) |
| `10143` | Monad Testnet |

> Consult the JSON files in the corresponding `broadcast/` folder for the exact deployed addresses and transaction hashes.

---

## Security notes / known limitations

This is an actively evolving project — the following are known, intentional gaps rather than bugs to be surprised by:

- **`createToken` signature validation is disabled.** The `signature` parameter is accepted but not checked (`signature; // I've put the signature validation logic on hold.`). The intent is to eventually gate token creation to prevent spam/low-quality listings — the `verifySignature` modifier exists in the contract and is ready to be wired in.
- **Ownership has not yet been revoked.** The contract retains an `Ownable` owner (fee changes, fee withdrawal). The original design intent is to revoke ownership at some point after launch/graduation, but the exact timing hasn't been finalized.
- **No slippage protection on `buy`/`sell`.** Callers don't currently pass a minimum-out parameter, so trades are vulnerable to price movement between submission and execution (including MEV/sandwich risk on public mempools).
- **Fee bypass via order-splitting.** `calculateFee` is applied per-transaction; splitting a large buy into many small ones does not proportionally reduce total fees paid in the current implementation, but the code comments flag this as something to revisit alongside a minimum-transaction-size guard.
- **Graduation is a single, non-reentrant but gas-heavy transaction.** A `buy` that triggers graduation must also succeed at initializing a Uniswap V4 pool and minting a full-range LP position in the same call — this increases the gas cost and failure surface of whichever trade happens to cross the graduation threshold.

## Roadmap / open questions

Carried over from the project's own README/notes:
- Finalize **when** contract ownership is revoked (at mint time vs. post-graduation).
- Confirm the **target chain(s)** for production deployment (L2 options were being weighed for throughput/cost; testnet activity so far spans Sepolia and Monad).
- Decide on the external DEX for graduation (currently implemented against **Uniswap V4** specifically).
- Wire up `createToken` signature verification.

---

## License

Contracts are marked `SPDX-License-Identifier: MIT`. No repository-wide `LICENSE` file is currently present — add one (e.g. MIT) at the root to make licensing terms explicit for the whole repo, including the indexer and article.