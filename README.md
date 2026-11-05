# Osero Spells

Spells (governance payloads) for the Osero Prime Agent in the Sky ecosystem.

Spells live in `src/proposals/`, one `OseroEthereum_YYYYMMDD.sol` payload plus its
`OseroEthereum_YYYYMMDD.t.sol` fork tests per target date. Payloads are executed by the Osero
SubProxy through the [StarGuard](https://github.com/sky-ecosystem/star-guard): governance plots the
payload address and codehash, then anyone can `exec()` it. Shared, always-run tests and helpers live
in `src/test-harness/`.

## Cross-chain spells (Base)

Following [spark-spells](https://github.com/sparkdotfi/spark-spells) and
[grove-spells](https://github.com/grove-labs/grove-spells), a spell with actions on Base has two
payloads for the same date:

- `OseroEthereum_YYYYMMDD.sol` inherits `OseroPayloadEthereum`. It runs the Ethereum actions in
  `_execute()`, then, when `PAYLOAD_BASE` is set in its constructor, relays an `Executor.queue` message
  for the Base payload through the Base `L1CrossDomainMessenger` to the Osero Receiver on Base.
- `OseroBase_YYYYMMDD.sol` inherits `OseroPayloadBase`. Once the message arrives, anyone can
  `execute` the queued actions set on the Osero Executor on Base, which delegatecalls the payload.

All tests, including the Base ones, stay in the Ethereum test file, which extends
`CommonBaseSpellTests` (`src/test-harness/CrossChainSpellRunner.sol` forks both chains, executes the
Ethereum spell, relays the message and executes the actions set on Base).

Deployment order: deploy the Base payload on Base, set its address as `PAYLOAD_BASE` in the Ethereum
spell constructor and as `DEPLOYED_BASE_PAYLOAD` in the tests, then deploy the Ethereum spell and set
`DEPLOYED_PAYLOAD`. While `PAYLOAD_BASE` is unset the Ethereum spell does not relay anything, and the
tests simulate the relay from the SubProxy for a freshly deployed Base payload.

## Setup

The repo ships a [devenv](https://devenv.sh/) environment with Foundry preinstalled:

```shell
devenv shell
```

Alternatively, install [Foundry](https://getfoundry.sh/) yourself.

Tests fork Ethereum mainnet and Base, so archive-capable RPC endpoints are required in `.env`:

```shell
MAINNET_RPC_URL=<your-ethereum-mainnet-archive-rpc-url>
BASE_RPC_URL=<your-base-archive-rpc-url>
```

`BASE_RPC_URL` falls back to the public `https://mainnet.base.org` endpoint when unset.

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
