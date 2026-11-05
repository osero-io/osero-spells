// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {StdChains} from "forge-std/StdChains.sol";

import {Base as OseroBase} from "osero-address-registry/Base.sol";

import {IExecutor} from "spark-gov-relay/src/interfaces/IExecutor.sol";

import {OptimismForwarder} from "xchain-helpers/forwarders/OptimismForwarder.sol";
import {Bridge} from "xchain-helpers/testing/Bridge.sol";
import {Domain, DomainHelpers} from "xchain-helpers/testing/Domain.sol";
import {OptimismBridgeTesting} from "xchain-helpers/testing/bridges/OptimismBridgeTesting.sol";

import {IAdministeredAgentLike, IRateLimitsLike} from "./OseroTestBase.sol";
import {CommonPauSpellTests} from "./CommonPauSpellTests.sol";

interface IOseroPayloadEthereumLike {
    function PAYLOAD_BASE() external view returns (address);
}

/// @dev Multi-chain spell runner for Osero spells that relay a payload to Base, following the Spark and
///      Grove `SpellRunner`s. It forks Ethereum and Base, executes the Ethereum spell through the
///      StarGuard, relays the Base `L1CrossDomainMessenger` message to the Osero Receiver on Base, and
///      executes the queued actions set on the Osero Executor on Base.
///
///      While the Base payload is not deployed (the Ethereum spell's `PAYLOAD_BASE` is unset), the
///      relay is simulated: the Osero SubProxy sends the same `Executor.queue` message the spell will
///      send, for a freshly deployed Base payload, through the same messenger, Receiver and Executor.
abstract contract CrossChainSpellRunner is CommonPauSpellTests {
    using DomainHelpers for StdChains.Chain;
    using DomainHelpers for Domain;

    // Osero governance relay and Diamond PAU on Base, from the osero-address-registry. Independent
    // verification sources: the Osero deployment records referenced in osero-address-registry/Base.sol.
    address internal constant BASE_OSERO_EXECUTOR = OseroBase.OSERO_EXECUTOR;
    address internal constant BASE_OSERO_RECEIVER = OseroBase.OSERO_RECEIVER;
    address internal constant BASE_OSERO_OPERATOR = OseroBase.OSERO_OPERATOR;
    address internal constant BASE_OSERO_ACCESS_CONTROLS = OseroBase.OSERO_ACCESS_CONTROLS;
    address internal constant BASE_OSERO_ALM_PROXY = OseroBase.OSERO_ALM_PROXY;
    address internal constant BASE_OSERO_RATE_LIMITS = OseroBase.OSERO_RATE_LIMITS;
    address internal constant BASE_OSERO_CONTROLLER = OseroBase.OSERO_CONTROLLER;
    address internal constant BASE_OSERO_ADMINISTERED_AGENT = OseroBase.OSERO_ADMINISTERED_AGENT;

    // Base L2CrossDomainMessenger predeploy. Source: https://docs.base.org/base-chain/network-information/base-contracts
    address internal constant BASE_L2_CROSS_DOMAIN_MESSENGER = 0x4200000000000000000000000000000000000007;

    // Gas forwarded to the Osero Receiver on Base by the relayed message; covers only `Executor.queue`.
    uint32 internal constant BASE_RELAY_GAS_LIMIT = 1_000_000;

    IExecutor internal constant baseExecutor = IExecutor(BASE_OSERO_EXECUTOR);

    Domain internal ethereumDomain;
    Domain internal baseDomain;
    Bridge internal baseBridge;

    // The on-chain Base payload once deployed; address(0) while the spell is still in development.
    address internal deployedBasePayload;
    // Base payload under test: the deployed Base payload when given, otherwise a freshly deployed one.
    address internal basePayload;

    modifier onBase() {
        uint256 activeFork = vm.activeFork();
        baseDomain.selectFork();
        _;
        vm.selectFork(activeFork);
    }

    function _selectEthereum() internal {
        ethereumDomain.selectFork();
    }

    function _selectBase() internal {
        baseDomain.selectFork();
    }

    /// @dev Creates the Ethereum and Base forks and the Base native bridge, and leaves Ethereum selected.
    function _setupDomains(uint256 mainnetForkBlock, uint256 baseForkBlock) internal {
        ethereumDomain = getChain("mainnet").createFork(mainnetForkBlock);
        baseDomain = getChain("base").createFork(baseForkBlock);
        baseBridge = OptimismBridgeTesting.createNativeBridge(ethereumDomain, baseDomain);
        ethereumDomain.selectFork();
    }

    function _setupBasePayload(address deployedBasePayload_) internal onBase {
        deployedBasePayload = deployedBasePayload_;
        basePayload = deployedBasePayload_ == address(0) ? _deployBasePayload() : deployedBasePayload_;
    }

    /// @dev Deploys a fresh Base payload on the active fork.
    function _deployBasePayload() internal returns (address) {
        string memory slug = string.concat("OseroBase_", spellId);
        return deployCode(string.concat(slug, ".sol:", slug));
    }

    /// @dev Executes the Ethereum spell, relays its message to Base and executes the queued actions set on
    ///      the Osero Executor on Base. Restores the fork that was active.
    function _executeAllPayloadsAndBridges() internal {
        uint256 activeFork = vm.activeFork();

        ethereumDomain.selectFork();
        _executeSpellViaStarGuard(payload);

        uint256 actionsSetId = _relayBasePayload();
        _executeBaseActionsSet(actionsSetId);

        vm.selectFork(activeFork);
    }

    /// @dev Must be called with Ethereum selected, after the Ethereum spell executed. Relays the Base payload
    ///      queue message to Base and returns the queued actions set id, leaving Base selected.
    function _relayBasePayload() internal returns (uint256 actionsSetId) {
        address relayedPayload = IOseroPayloadEthereumLike(payload).PAYLOAD_BASE();

        if (relayedPayload == address(0)) {
            // Simulate the spell's relay (OseroPayloadEthereum.execute) for the Base payload under test.
            vm.prank(OSERO_PROXY);
            OptimismForwarder.sendMessageL1toL2({
                l1CrossDomain: OptimismForwarder.L1_CROSS_DOMAIN_BASE,
                target: BASE_OSERO_RECEIVER,
                message: _encodeBasePayloadQueue(basePayload),
                gasLimit: BASE_RELAY_GAS_LIMIT
            });
        } else {
            assertEq(relayedPayload, basePayload, "relayed-base-payload-not-base-payload-under-test");
        }

        baseDomain.selectFork();
        actionsSetId = baseExecutor.actionsSetCount();

        // The L2CrossDomainMessenger records a failed relay instead of reverting, so assert the queue landed.
        OptimismBridgeTesting.relayMessagesToDestination(baseBridge, true);
        assertEq(baseExecutor.actionsSetCount(), actionsSetId + 1, "base-actions-set-not-queued");
    }

    /// @dev Must be called with Base selected. Executes the actions set permissionlessly once executable.
    function _executeBaseActionsSet(uint256 actionsSetId) internal {
        uint256 executionTime = baseExecutor.getActionsSetById(actionsSetId).executionTime;
        if (block.timestamp < executionTime) vm.warp(executionTime);

        vm.prank(PERMISSIONLESS_EXECUTOR);
        baseExecutor.execute(actionsSetId);
    }

    /// @dev The `Executor.queue` message the Ethereum spell relays, rebuilt independently of the spell.
    function _encodeBasePayloadQueue(address basePayload_) internal pure returns (bytes memory) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        bool[] memory withDelegatecalls = new bool[](1);

        targets[0] = basePayload_;
        values[0] = 0;
        signatures[0] = "execute()";
        calldatas[0] = "";
        withDelegatecalls[0] = true;

        return abi.encodeCall(IExecutor.queue, (targets, values, signatures, calldatas, withDelegatecalls));
    }

    /// @dev Compares runtime bytecode ignoring the trailing solc metadata, as
    ///      `CommonSpellTests.test_ETHEREUM_payloadBytecodeMatchesDeployedSpell` does for the Ethereum payload.
    function _assertRuntimeBytecodeMatches(address expected, address actual, string memory label) internal view {
        uint256 expectedSize = expected.code.length;
        uint256 actualSize = actual.code.length;

        uint256 metadataLength = _getBytecodeMetadataLength(expected);
        assertLe(metadataLength, expectedSize, string.concat(label, "-expected-metadata-length-not-correct"));
        expectedSize -= metadataLength;

        metadataLength = _getBytecodeMetadataLength(actual);
        assertLe(metadataLength, actualSize, string.concat(label, "-actual-metadata-length-not-correct"));
        actualSize -= metadataLength;

        assertEq(actualSize, expectedSize, string.concat(label, "-bytecode-size-mismatch"));

        bytes32 expectedHash;
        bytes32 actualHash;

        assembly {
            let ptr := mload(0x40)

            extcodecopy(expected, ptr, 0, actualSize)
            expectedHash := keccak256(ptr, actualSize)

            extcodecopy(actual, ptr, 0, actualSize)
            actualHash := keccak256(ptr, actualSize)
        }

        assertEq(actualHash, expectedHash, string.concat(label, "-bytecode-hash-mismatch"));
    }

    function _callAsBaseOseroActor(bytes memory data) internal returns (bytes memory result) {
        IAdministeredAgentLike agent = IAdministeredAgentLike(BASE_OSERO_ADMINISTERED_AGENT);
        assertTrue(agent.getIsActor(BASE_OSERO_OPERATOR), "base-osero-operator-not-agent-actor");

        vm.prank(BASE_OSERO_OPERATOR);
        result = agent.call(BASE_OSERO_CONTROLLER, data);
    }

    function _expectCallAsBaseOseroActorRevert(bytes memory revertData, bytes memory data) internal {
        IAdministeredAgentLike agent = IAdministeredAgentLike(BASE_OSERO_ADMINISTERED_AGENT);
        assertTrue(agent.getIsActor(BASE_OSERO_OPERATOR), "base-osero-operator-not-agent-actor");

        vm.prank(BASE_OSERO_OPERATOR);
        vm.expectRevert(revertData);
        // Lint false positive: this is the agent's `call(address,bytes)` interface function, not
        // `address.call`, so there is no success flag to check — it reverts on failure instead.
        // forge-lint: disable-next-line(unchecked-call)
        agent.call(BASE_OSERO_CONTROLLER, data);
    }

    function _assertRateLimitOn(address rateLimits_, bytes32 key, uint256 maxAmount, uint256 slope, string memory label)
        internal
        view
    {
        IRateLimitsLike.RateLimitData memory data = IRateLimitsLike(rateLimits_).getRateLimitData(key);
        assertEq(data.maxAmount, maxAmount, string.concat(label, "-max-amount"));
        assertEq(data.slope, slope, string.concat(label, "-slope"));
        assertEq(data.lastAmount, maxAmount, string.concat(label, "-last-amount"));
        assertEq(data.lastUpdated, block.timestamp, string.concat(label, "-last-updated"));
        assertEq(
            IRateLimitsLike(rateLimits_).getCurrentRateLimit(key), maxAmount, string.concat(label, "-current-limit")
        );
    }

    function _assertUnlimitedRateLimitOn(address rateLimits_, bytes32 key, string memory label) internal view {
        _assertRateLimitOn(rateLimits_, key, type(uint256).max, 0, string.concat(label, "-unlimited"));
    }

    function _assertUnsetRateLimitOn(address rateLimits_, bytes32 key, string memory label) internal view {
        IRateLimitsLike.RateLimitData memory data = IRateLimitsLike(rateLimits_).getRateLimitData(key);
        assertEq(data.maxAmount, 0, string.concat(label, "-unset-max-amount"));
        assertEq(data.slope, 0, string.concat(label, "-unset-slope"));
        assertEq(data.lastAmount, 0, string.concat(label, "-unset-last-amount"));
        assertEq(data.lastUpdated, 0, string.concat(label, "-unset-last-updated"));
    }
}
