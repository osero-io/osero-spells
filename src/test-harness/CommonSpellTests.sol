// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {ISpellLike, OseroTestBase} from "./OseroTestBase.sol";

/// @dev Always-run tests that apply to every Osero spell: payload deployment sanity,
///      deployed-bytecode verification, and the StarGuard execution lifecycle.
abstract contract CommonSpellTests is OseroTestBase {
    function test_ETHEREUM_payloadDeploymentSanity() public view {
        _assertContract(payload, "payload");
        assertTrue(ISpellLike(payload).isExecutable(), "payload-not-executable");
    }

    /// @dev Compares the on-chain payload runtime bytecode against a fresh local build,
    ///      ignoring the trailing solc metadata. Skipped until the payload is deployed.
    function test_ETHEREUM_payloadBytecodeMatchesDeployedSpell() public {
        vm.skip(deployedPayload == address(0));

        _assertContract(deployedPayload, "deployed-payload");
        address expectedPayload = _deployPayload();

        uint256 expectedBytecodeSize = expectedPayload.code.length;
        uint256 actualBytecodeSize = deployedPayload.code.length;

        uint256 metadataLength = _getBytecodeMetadataLength(expectedPayload);
        assertLe(metadataLength, expectedBytecodeSize, "expected-metadata-length-not-correct");
        expectedBytecodeSize -= metadataLength;

        metadataLength = _getBytecodeMetadataLength(deployedPayload);
        assertLe(metadataLength, actualBytecodeSize, "actual-metadata-length-not-correct");
        actualBytecodeSize -= metadataLength;

        assertEq(actualBytecodeSize, expectedBytecodeSize, "bytecode-size-mismatch");

        address actualPayload = deployedPayload;
        uint256 size = actualBytecodeSize;
        bytes32 expectedHash;
        bytes32 actualHash;

        assembly {
            let ptr := mload(0x40)

            extcodecopy(expectedPayload, ptr, 0, size)
            expectedHash := keccak256(ptr, size)

            extcodecopy(actualPayload, ptr, 0, size)
            actualHash := keccak256(ptr, size)
        }

        assertEq(actualHash, expectedHash, "bytecode-hash-mismatch");
    }

    function test_ETHEREUM_starGuardLifecycleExecutesPlottedPayload() public {
        _executeSpellViaStarGuard(payload);
    }

    function test_ETHEREUM_starGuardExecutionWindowRejectsExpiredPayload() public {
        bytes32 codehash = payload.codehash;

        vm.prank(MCD_PAUSE_PROXY);
        starGuard.plot(payload, codehash);

        (,, uint256 deadline) = starGuard.spellData();
        assertEq(deadline, block.timestamp + starGuard.maxDelay(), "starguard-deadline-mismatch");
        assertTrue(ISpellLike(payload).isExecutable(), "payload-not-executable-before-deadline");
        assertTrue(starGuard.prob(), "starguard-not-probable-before-deadline");

        vm.warp(deadline + 1);

        assertFalse(starGuard.prob(), "starguard-prob-true-after-deadline");
        vm.expectRevert(bytes("StarGuard/expired-spell"));
        starGuard.exec();
    }

    function test_ETHEREUM_starGuardExecutionGasWithinBlockLimit() public {
        uint256 gasUsed = _executeSpellViaStarGuard(payload);

        assertLe(gasUsed, MAX_EXECUTION_GAS, "starguard-execution-gas-too-high");
    }
}
