// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {Ethereum as OseroEthereum} from "osero-address-registry/Ethereum.sol";

import {INFATPrimeController} from "diamond-pau/src/facets/nfat-prime/INFATPrimeController.sol";
import {ITransferAssetController} from "diamond-pau/src/facets/transfer-asset/ITransferAssetController.sol";
import {IController} from "diamond-pau/src/interfaces/IController.sol";
import {IRateLimits} from "diamond-pau/src/interfaces/IRateLimits.sol";

import {BaseSpell} from "../BaseSpell.sol";

/// @title  December 3, 2026 Osero Ethereum Proposal
/// @notice Enables the Transfer Asset facet on the Osero PAU controller with a USDS transfer rate limit to
///         `<DESTINATION_NAME>`, and onboards the Test NFAT Facility: enables the NFAT Prime facet and adds the
///         facility's subscribe, withdraw and collect rate limits.
/// @custom:forum https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID>
contract OseroEthereum_20261203 is BaseSpell {
    // Contract: USDS / Source: https://chainlog.skyeco.com/ (key: USDS)
    address internal constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    // TODO: placeholder for `<DESTINATION_ADDRESS>`, set once a Core Facilitator confirms it (Pre-requirements #4).
    // Contract: `<DESTINATION_NAME>`, the Sky-owned USDS destination / Source: https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID> (Trusted addresses)
    address internal constant USDS_TRANSFER_DESTINATION = 0x1111111111111111111111111111111111111111;

    // TODO: placeholder for `<FACILITY_ADDRESS>`, set once the facility owner deploys it (Pre-requirements #3).
    // Contract: Test NFAT Facility (`NFATFacility`) / Source: https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID> (Pre-deployed contracts #2)
    address internal constant TEST_NFAT_FACILITY = 0x2222222222222222222222222222222222222222;

    bytes32 internal constant TRANSFER_ASSET_FACET_INTEGRATION_ID = "TRANSFER_ASSET_FACET";
    bytes32 internal constant NFAT_PRIME_FACET_INTEGRATION_ID = "NFAT_PRIME_FACET";

    // USDS-denominated (18 decimals) limits.
    // TODO: placeholders for the values the Core Council Risk Advisor confirms (Pre-requirements #5).
    uint256 internal constant USDS_TRANSFER_MAX = 1_000_000e18; // `<MAX_AMOUNT>`
    uint256 internal constant USDS_TRANSFER_SLOPE = uint256(1_000_000e18) / 1 days; // `<SLOPE>`

    uint256 internal constant NFAT_SUBSCRIBE_MAX = 2_000_000e18; // `<SUBSCRIBE_MAX_AMOUNT>`
    uint256 internal constant NFAT_SUBSCRIBE_SLOPE = uint256(1_000_000e18) / 1 days; // `<SUBSCRIBE_SLOPE>`

    uint256 internal constant NFAT_WITHDRAW_MAX = 3_000_000e18; // `<WITHDRAW_MAX_AMOUNT>`
    uint256 internal constant NFAT_WITHDRAW_SLOPE = uint256(3_000_000e18) / 1 days; // `<WITHDRAW_SLOPE>`

    uint256 internal constant NFAT_COLLECT_MAX = 4_000_000e18; // `<COLLECT_MAX_AMOUNT>`
    uint256 internal constant NFAT_COLLECT_SLOPE = uint256(4_000_000e18) / 1 days; // `<COLLECT_SLOPE>`

    function execute() external override {
        // [Ethereum] Proposed action #1: Enable the Transfer Asset integration on the Osero `Controller`
        //   Forum : https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID>
        _enableTransferAssetIntegration();

        // [Ethereum] Proposed action #2: Set the USDS transfer rate limit to `<DESTINATION_NAME>` to `maxAmount`
        //   `<MAX_AMOUNT>` USDS and `slope` `<SLOPE>` USDS/day
        //   Forum : https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID>
        //   Note: there is no `RateLimitsHelper` function for Transfer Asset keys; the key is read from the
        //         controller, which wires the Transfer Asset facet in Proposed action #1.
        _setUsdsTransferRateLimit();

        // [Ethereum] Proposed action #3: Enable the NFAT Prime integration on the Osero `Controller`
        //   Forum : https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID>
        //   Note: Sky Core registers `NFAT_PRIME_FACET` on the Sky PAU Beacon in the same Sky Core spell that plots
        //         this payload (Pre-requirements #1). Until then `updateIntegrations` reverts with
        //         `IntegrationNotFound`, so the whole payload reverts, including Proposed actions #1-2.
        _enableNfatPrimeIntegration();

        // [Ethereum] Proposed action #4: Set the subscribe rate limit for the Test NFAT Facility to `maxAmount`
        //   `<SUBSCRIBE_MAX_AMOUNT>` USDS and `slope` `<SUBSCRIBE_SLOPE>` USDS/day
        //   Forum : https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID>
        //   Note: as in Proposed action #2, the NFAT Prime keys below are read from the controller, which wires the
        //         NFAT Prime facet in Proposed action #3.
        _setNfatSubscribeRateLimit();

        // [Ethereum] Proposed action #5: Set the withdraw rate limit for the Test NFAT Facility to `maxAmount`
        //   `<WITHDRAW_MAX_AMOUNT>` USDS and `slope` `<WITHDRAW_SLOPE>` USDS/day
        //   Forum : https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID>
        _setNfatWithdrawRateLimit();

        // [Ethereum] Proposed action #6: Set the collect rate limit for the Test NFAT Facility to `maxAmount`
        //   `<COLLECT_MAX_AMOUNT>` USDS and `slope` `<COLLECT_SLOPE>` USDS/day
        //   Forum : https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID>
        _setNfatCollectRateLimit();
    }

    function _enableTransferAssetIntegration() private {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = TRANSFER_ASSET_FACET_INTEGRATION_ID; // BEFORE: not wired on the controller, AFTER: wired from the beacon config
        IController(OseroEthereum.OSERO_CONTROLLER).updateIntegrations(ids);
    }

    function _setUsdsTransferRateLimit() private {
        IRateLimits(OseroEthereum.OSERO_RATE_LIMITS).setRateLimitData({
            key: ITransferAssetController(OseroEthereum.OSERO_CONTROLLER)
                .transferAsset_getTransferRateLimitKey(USDS, USDS_TRANSFER_DESTINATION),
            maxAmount: USDS_TRANSFER_MAX, // BEFORE: unset, AFTER: 1_000_000e18
            slope: USDS_TRANSFER_SLOPE // BEFORE: unset, AFTER: uint256(1_000_000e18) / 1 days
        });
    }

    function _enableNfatPrimeIntegration() private {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = NFAT_PRIME_FACET_INTEGRATION_ID; // BEFORE: not wired on the controller, AFTER: wired from the beacon config
        IController(OseroEthereum.OSERO_CONTROLLER).updateIntegrations(ids);
    }

    function _setNfatSubscribeRateLimit() private {
        IRateLimits(OseroEthereum.OSERO_RATE_LIMITS).setRateLimitData({
            key: INFATPrimeController(OseroEthereum.OSERO_CONTROLLER)
                .nfatPrime_getSubscribeRateLimitKey(TEST_NFAT_FACILITY, USDS),
            maxAmount: NFAT_SUBSCRIBE_MAX, // BEFORE: unset, AFTER: 2_000_000e18
            slope: NFAT_SUBSCRIBE_SLOPE // BEFORE: unset, AFTER: uint256(1_000_000e18) / 1 days
        });
    }

    function _setNfatWithdrawRateLimit() private {
        IRateLimits(OseroEthereum.OSERO_RATE_LIMITS).setRateLimitData({
            key: INFATPrimeController(OseroEthereum.OSERO_CONTROLLER)
                .nfatPrime_getWithdrawRateLimitKey(TEST_NFAT_FACILITY),
            maxAmount: NFAT_WITHDRAW_MAX, // BEFORE: unset, AFTER: 3_000_000e18
            slope: NFAT_WITHDRAW_SLOPE // BEFORE: unset, AFTER: uint256(3_000_000e18) / 1 days
        });
    }

    function _setNfatCollectRateLimit() private {
        IRateLimits(OseroEthereum.OSERO_RATE_LIMITS).setRateLimitData({
            key: INFATPrimeController(OseroEthereum.OSERO_CONTROLLER)
                .nfatPrime_getCollectRateLimitKey(TEST_NFAT_FACILITY),
            maxAmount: NFAT_COLLECT_MAX, // BEFORE: unset, AFTER: 4_000_000e18
            slope: NFAT_COLLECT_SLOPE // BEFORE: unset, AFTER: uint256(4_000_000e18) / 1 days
        });
    }
}
