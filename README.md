# Osero Spells

Spells (governance payloads) for the Osero Prime Agent in the Sky ecosystem.

Spells live in `src/proposals/`, one `OseroEthereum_YYYYMMDD.sol` payload plus its
`OseroEthereum_YYYYMMDD.t.sol` fork tests per target date. Payloads are executed by the Osero
SubProxy through the [StarGuard](https://github.com/sky-ecosystem/star-guard): governance plots the
payload address and codehash, then anyone can `exec()` it. Shared, always-run tests and helpers live
in `src/test-harness/`.

## Setup

The repo ships a [devenv](https://devenv.sh/) environment with Foundry preinstalled:

```shell
devenv shell
```

Alternatively, install [Foundry](https://getfoundry.sh/) yourself.

Tests fork Ethereum mainnet, so an archive-capable RPC endpoint is required in `.env`:

```shell
MAINNET_RPC_URL=<your-ethereum-mainnet-archive-rpc-url>
```

## Build

```shell
forge build
```

## Test

Spell tests only (what matters for a spell review — the library tests don't count toward spell
coverage):

```shell
forge test --match-path "src/proposals/*"
```

Everything, including library unit tests (CI runs this):

```shell
forge test
```

## Format

```shell
forge fmt
```

CI enforces `forge fmt --check`, `forge build --sizes`, and the full test suite.
