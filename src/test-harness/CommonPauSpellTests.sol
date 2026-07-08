// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {IAllocatorVaultLike, IJugLike, PauIntegration} from "./OseroTestBase.sol";
import {CommonSpellTests} from "./CommonSpellTests.sol";

struct ExpectedIntegration {
    bytes32 id;
    address facet;
    uint256 wireCount;
    string label;
}

/// @dev Always-run tests specific to the PAU controller system
///      (diamond-pau Controller + AccessControls + AdministeredAgent allocators).
abstract contract CommonPauSpellTests is CommonSpellTests {
    uint256 internal constant RAY = 1e27;

    /// @dev The PAU integrations expected to be wired on the controller; spell test
    ///      contracts override this as facets get onboarded.
    function _expectedControllerIntegrations() internal pure virtual returns (ExpectedIntegration[] memory expected);

    /// @dev The PAU mint/burn path draws debt against the ALLOCATOR-PRYSM-A ilk and assumes a
    ///      0% stability fee, so assert the ilk duty is RAY on the live jug.
    function test_ETHEREUM_pauAllocatorIlkHasZeroFee() public view {
        address jug = IAllocatorVaultLike(OSERO_ALLOCATOR_VAULT).jug();
        (uint256 duty,) = IJugLike(jug).ilks(OSERO_ILK);

        assertEq(duty, RAY, "ilk-duty-not-zero-fee");
    }

    function test_ETHEREUM_onlyExpectedControllerIntegrations() public view {
        ExpectedIntegration[] memory expected = _expectedControllerIntegrations();
        PauIntegration[] memory integrations = controller.integrations();
        assertEq(integrations.length, expected.length, "unexpected-controller-integration-count");

        for (uint256 i = 0; i < expected.length; ++i) {
            uint256 matches;
            for (uint256 j = 0; j < integrations.length; ++j) {
                if (integrations[j].id != expected[i].id) continue;
                matches++;
                assertEq(
                    integrations[j].config.facet,
                    expected[i].facet,
                    string.concat(expected[i].label, "-integration-facet")
                );
                assertEq(
                    integrations[j].config.wires.length,
                    expected[i].wireCount,
                    string.concat(expected[i].label, "-integration-wire-count")
                );
            }
            assertEq(matches, 1, string.concat(expected[i].label, "-integration-not-exactly-once"));
        }
    }
}
