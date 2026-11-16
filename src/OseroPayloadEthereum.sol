// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {Base} from "osero-address-registry/Base.sol";

import {IExecutor} from "spark-gov-relay/src/interfaces/IExecutor.sol";

import {OptimismForwarder} from "xchain-helpers/forwarders/OptimismForwarder.sol";

import {BaseSpell} from "./BaseSpell.sol";

/// @dev Base contract for Osero Ethereum spells that relay a payload to Base, following
///      `SparkPayloadEthereum` / `GrovePayloadEthereum`: the spell's Ethereum actions run first,
///      then, if a Base payload is set, the Osero SubProxy sends an `Executor.queue` message for it
///      through the Base `L1CrossDomainMessenger` to the Osero Receiver on Base, which forwards it
///      to the Osero Executor on Base. Anyone can then `execute` the queued actions set on Base.
abstract contract OseroPayloadEthereum is BaseSpell {
    // These need to be immutable (delegatecall) and can only be set in constructor
    address public immutable PAYLOAD_BASE;

    function execute() external override {
        _execute();

        if (PAYLOAD_BASE != address(0)) {
            OptimismForwarder.sendMessageL1toL2({
                l1CrossDomain: OptimismForwarder.L1_CROSS_DOMAIN_BASE,
                target: Base.OSERO_RECEIVER,
                message: _encodePayloadQueue(PAYLOAD_BASE),
                gasLimit: 1_000_000
            });
        }
    }

    function _execute() internal virtual;

    function _encodePayloadQueue(address _payload) internal pure returns (bytes memory) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        bool[] memory withDelegatecalls = new bool[](1);

        targets[0] = _payload;
        values[0] = 0;
        signatures[0] = "execute()";
        calldatas[0] = "";
        withDelegatecalls[0] = true;

        return abi.encodeCall(IExecutor.queue, (targets, values, signatures, calldatas, withDelegatecalls));
    }
}
