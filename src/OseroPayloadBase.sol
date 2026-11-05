// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

/// @dev Base contract for Osero Base payloads, following `SparkPayloadBase` / `GrovePayloadBase`.
///      The Ethereum spell queues `execute()` on the Osero Executor on Base with `withDelegatecall`
///      set, so the payload runs as the Executor, the admin of every Osero contract on Base.
abstract contract OseroPayloadBase {
    function execute() external virtual;
}
