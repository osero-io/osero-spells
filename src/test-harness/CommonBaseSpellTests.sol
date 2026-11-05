// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";

import {IExecutor} from "spark-gov-relay/src/interfaces/IExecutor.sol";

import {OptimismForwarder} from "xchain-helpers/forwarders/OptimismForwarder.sol";

import {CrossChainSpellRunner, IOseroPayloadEthereumLike} from "./CrossChainSpellRunner.sol";

interface IOptimismReceiverLike {
    function l1Authority() external view returns (address);
    function l2CrossDomain() external view returns (address);
    function target() external view returns (address);
}

interface ICrossDomainMessengerLike {
    function xDomainMessageSender() external view returns (address);
}

/// @dev Always-run tests for Osero spells that relay a payload to Base: Base payload deployment and
///      bytecode verification, the relay message, and the Osero Receiver and Executor lifecycle on Base.
abstract contract CommonBaseSpellTests is CrossChainSpellRunner {
    bytes32 internal constant SENT_MESSAGE_TOPIC = keccak256("SentMessage(address,address,bytes,uint256,uint256)");

    uint256 internal constant BASE_EXECUTOR_DELAY = 0;
    uint256 internal constant BASE_EXECUTOR_GRACE_PERIOD = 7 days;

    // Synthetic test actor for the Receiver authorization checks.
    address internal constant UNAUTHORIZED_L1_SENDER = address(0xBAD);

    function test_BASE_payloadDeploymentSanity() public onBase {
        _assertContract(basePayload, "base-payload");
    }

    /// @dev Compares the on-chain Base payload runtime bytecode against a fresh local build, ignoring
    ///      the trailing solc metadata. Skipped until the Base payload is deployed.
    function test_BASE_payloadBytecodeMatchesDeployedPayload() public onBase {
        vm.skip(deployedBasePayload == address(0));

        _assertContract(deployedBasePayload, "deployed-base-payload");
        _assertRuntimeBytecodeMatches(_deployBasePayload(), deployedBasePayload, "base-payload");
    }

    /// @dev Once the Ethereum spell is deployed it must relay the deployed Base payload.
    function test_ETHEREUM_deployedSpellRelaysDeployedBasePayload() public {
        vm.skip(deployedPayload == address(0));

        address relayedPayload = IOseroPayloadEthereumLike(payload).PAYLOAD_BASE();
        assertNotEq(relayedPayload, address(0), "deployed-spell-does-not-relay-base-payload");
        assertEq(relayedPayload, deployedBasePayload, "deployed-spell-relays-unexpected-base-payload");
    }

    /// @dev The spell sends exactly one Base message, the Executor queue call for `PAYLOAD_BASE`, once it is
    ///      set, and none while it is unset.
    function test_ETHEREUM_spellRelaysOnlyBasePayloadQueueMessage() public {
        address relayedPayload = IOseroPayloadEthereumLike(payload).PAYLOAD_BASE();

        vm.recordLogs();
        _executeSpellViaStarGuard(payload);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 sentMessages;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != SENT_MESSAGE_TOPIC) continue;
            sentMessages++;

            assertEq(logs[i].emitter, OptimismForwarder.L1_CROSS_DOMAIN_BASE, "sent-message-emitter");
            assertEq(address(uint160(uint256(logs[i].topics[1]))), BASE_OSERO_RECEIVER, "sent-message-target");
            (address sender, bytes memory message,, uint256 gasLimit) =
                abi.decode(logs[i].data, (address, bytes, uint256, uint256));
            assertEq(sender, OSERO_PROXY, "sent-message-sender");
            assertEq(message, _encodeBasePayloadQueue(relayedPayload), "sent-message-payload-queue");
            assertEq(gasLimit, BASE_RELAY_GAS_LIMIT, "sent-message-gas-limit");
        }

        assertEq(sentMessages, relayedPayload == address(0) ? 0 : 1, "sent-message-count");
    }

    function test_BASE_governanceRelayConfiguration() public onBase {
        _assertContract(BASE_OSERO_EXECUTOR, "base-executor");
        _assertContract(BASE_OSERO_RECEIVER, "base-receiver");

        IOptimismReceiverLike receiver = IOptimismReceiverLike(BASE_OSERO_RECEIVER);
        assertEq(receiver.l1Authority(), OSERO_PROXY, "base-receiver-l1-authority");
        assertEq(receiver.target(), BASE_OSERO_EXECUTOR, "base-receiver-target");
        assertEq(receiver.l2CrossDomain(), BASE_L2_CROSS_DOMAIN_MESSENGER, "base-receiver-l2-cross-domain");

        assertEq(baseExecutor.delay(), BASE_EXECUTOR_DELAY, "base-executor-delay");
        assertEq(baseExecutor.gracePeriod(), BASE_EXECUTOR_GRACE_PERIOD, "base-executor-grace-period");
        assertTrue(
            baseExecutor.hasRole(baseExecutor.SUBMISSION_ROLE(), BASE_OSERO_RECEIVER), "base-receiver-not-submitter"
        );
        assertTrue(baseExecutor.hasRole(DEFAULT_ADMIN_ROLE, BASE_OSERO_EXECUTOR), "base-executor-not-its-own-admin");
        assertFalse(baseExecutor.hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY), "subproxy-is-base-executor-admin");
    }

    function test_BASE_relayedActionsSetQueuesAndExecutesBasePayload() public {
        _executeSpellViaStarGuard(payload);
        uint256 actionsSetId = _relayBasePayload();

        IExecutor.ActionsSet memory actionsSet = baseExecutor.getActionsSetById(actionsSetId);
        assertEq(actionsSet.targets.length, 1, "actions-set-target-count");
        assertEq(actionsSet.targets[0], basePayload, "actions-set-target");
        assertEq(actionsSet.values[0], 0, "actions-set-value");
        assertEq(actionsSet.signatures[0], "execute()", "actions-set-signature");
        assertEq(actionsSet.calldatas[0], "", "actions-set-calldata");
        assertTrue(actionsSet.withDelegatecalls[0], "actions-set-not-delegatecall");
        assertEq(actionsSet.executionTime, block.timestamp + BASE_EXECUTOR_DELAY, "actions-set-execution-time");
        assertEq(
            uint256(baseExecutor.getCurrentState(actionsSetId)),
            uint256(IExecutor.ActionsSetState.Queued),
            "actions-set-not-queued"
        );

        _executeBaseActionsSet(actionsSetId);

        assertEq(
            uint256(baseExecutor.getCurrentState(actionsSetId)),
            uint256(IExecutor.ActionsSetState.Executed),
            "actions-set-not-executed"
        );
        vm.expectRevert(IExecutor.OnlyQueuedActions.selector);
        baseExecutor.execute(actionsSetId);
    }

    function test_BASE_relayedActionsSetExpiresAfterGracePeriod() public {
        _executeSpellViaStarGuard(payload);
        uint256 actionsSetId = _relayBasePayload();

        uint256 executionTime = baseExecutor.getActionsSetById(actionsSetId).executionTime;
        vm.warp(executionTime + baseExecutor.gracePeriod() + 1);

        assertEq(
            uint256(baseExecutor.getCurrentState(actionsSetId)),
            uint256(IExecutor.ActionsSetState.Expired),
            "actions-set-not-expired"
        );
        vm.expectRevert(IExecutor.OnlyQueuedActions.selector);
        baseExecutor.execute(actionsSetId);
    }

    /// @dev The relayed message only queues the actions set on Base; its gas must fit the relay gas limit.
    function test_BASE_relayedQueueCallFitsRelayGasLimit() public onBase {
        vm.mockCall(
            BASE_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(ICrossDomainMessengerLike.xDomainMessageSender, ()),
            abi.encode(OSERO_PROXY)
        );
        bytes memory message = _encodeBasePayloadQueue(basePayload);
        uint256 actionsSetCountBefore = baseExecutor.actionsSetCount();

        vm.prank(BASE_L2_CROSS_DOMAIN_MESSENGER);
        uint256 gasStart = gasleft();
        (bool success,) = BASE_OSERO_RECEIVER.call(message);
        uint256 gasUsed = gasStart - gasleft();

        assertTrue(success, "receiver-forward-failed");
        assertEq(baseExecutor.actionsSetCount(), actionsSetCountBefore + 1, "actions-set-not-queued");
        assertLt(gasUsed, BASE_RELAY_GAS_LIMIT, "relayed-queue-gas-above-relay-gas-limit");
    }

    function test_BASE_receiverRejectsMessagesNotFromSubProxy() public onBase {
        bytes memory message = _encodeBasePayloadQueue(basePayload);

        vm.mockCall(
            BASE_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(ICrossDomainMessengerLike.xDomainMessageSender, ()),
            abi.encode(UNAUTHORIZED_L1_SENDER)
        );
        vm.prank(BASE_L2_CROSS_DOMAIN_MESSENGER);
        vm.expectRevert(bytes("OptimismReceiver/invalid-l1Authority"));
        (bool success,) = BASE_OSERO_RECEIVER.call(message);
        success;

        vm.prank(UNAUTHORIZED_L1_SENDER);
        vm.expectRevert(bytes("OptimismReceiver/invalid-sender"));
        (success,) = BASE_OSERO_RECEIVER.call(message);

        vm.prank(OSERO_PROXY);
        vm.expectRevert(bytes("OptimismReceiver/invalid-sender"));
        (success,) = BASE_OSERO_RECEIVER.call(message);
    }

    function test_BASE_payloadExecutionGasWithinBlockLimit() public {
        _executeSpellViaStarGuard(payload);
        uint256 actionsSetId = _relayBasePayload();

        vm.prank(PERMISSIONLESS_EXECUTOR);
        uint256 gasStart = gasleft();
        baseExecutor.execute(actionsSetId);
        uint256 gasUsed = gasStart - gasleft();

        assertLe(gasUsed, MAX_EXECUTION_GAS, "base-payload-execution-gas-too-high");
    }
}
