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
///         the Test NFAT Facility ALM Proxy, and onboards the Test NFAT Facility: enables the NFAT Prime facet,
///         adds the facility's subscribe rate limit and sets its withdraw and collect rate limits to unlimited.
/// @custom:forum https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID>
contract OseroEthereum_20261203 is BaseSpell {
    // Contract: USDS / Source: https://chainlog.skyeco.com/ (key: USDS)
    address internal constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    // Contract: Test NFAT Facility ALM Proxy (`ALMProxy`, Sky-owned), the ALM Proxy of the Test NFAT Facility Diamond
    //   PAU and the facility's `recipient` / Source: `proxy()` of the Test NFAT Facility Diamond PAU `Controller`
    //   0x37F628D95ceC5aDA038A1cca734573dbcb79d1cB; https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID> (Trusted addresses, Pre-requirements #4)
    address internal constant TEST_NFAT_FACILITY_ALM_PROXY = 0xBEE5C2E8436e9834e6890A528E5B294D93b2Eec7;

    // Contract: Test NFAT Facility (`NFATFacility`), deployed by Test Halo at block 26,443,860 / Source: https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID> (Pre-deployed contracts #2)
    address internal constant TEST_NFAT_FACILITY = 0x02Cb9629B0806b11202C59433eCe4e664C521128;

    bytes32 internal constant TRANSFER_ASSET_FACET_INTEGRATION_ID = "TRANSFER_ASSET_FACET";
    bytes32 internal constant NFAT_PRIME_FACET_INTEGRATION_ID = "NFAT_PRIME_FACET";

    // USDS-denominated (18 decimals) limits. The withdraw and collect keys are unlimited.
    uint256 internal constant USDS_TRANSFER_MAX = 1_000_000e18;
    uint256 internal constant USDS_TRANSFER_SLOPE = uint256(1_000_000e18) / 1 days;

    uint256 internal constant NFAT_SUBSCRIBE_MAX = 5_000_000e18;
    uint256 internal constant NFAT_SUBSCRIBE_SLOPE = uint256(1_000_000e18) / 1 days;

    function execute() external override {
        // [Ethereum] Proposed action #1: Enable the Transfer Asset integration on the Osero `Controller`
        //   Forum : https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID>
        _enableTransferAssetIntegration();

        // [Ethereum] Proposed action #2: Set the USDS transfer rate limit to the Test NFAT Facility ALM Proxy to
        //   `maxAmount` `1,000,000 USDS` and `slope` `1,000,000 USDS/day`
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
        //   `5,000,000 USDS` and `slope` `1,000,000 USDS/day`
        //   Forum : https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID>
        //   Note: as in Proposed action #2, the NFAT Prime keys below are read from the controller, which wires the
        //         NFAT Prime facet in Proposed action #3.
        _setNfatSubscribeRateLimit();

        // [Ethereum] Proposed action #5: Set the withdraw rate limit for the Test NFAT Facility to unlimited
        //   Forum : https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID>
        _setUnlimitedNfatWithdrawRateLimit();

        // [Ethereum] Proposed action #6: Set the collect rate limit for the Test NFAT Facility to unlimited
        //   Forum : https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-osero-for-upcoming-spell/<TOPIC_ID>
        _setUnlimitedNfatCollectRateLimit();
    }

    function _enableTransferAssetIntegration() private {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = TRANSFER_ASSET_FACET_INTEGRATION_ID; // BEFORE: not wired on the controller, AFTER: wired from the beacon config
        IController(OseroEthereum.OSERO_CONTROLLER).updateIntegrations(ids);
    }

    function _setUsdsTransferRateLimit() private {
        IRateLimits(OseroEthereum.OSERO_RATE_LIMITS).setRateLimitData({
            key: ITransferAssetController(OseroEthereum.OSERO_CONTROLLER)
                .transferAsset_getTransferRateLimitKey(USDS, TEST_NFAT_FACILITY_ALM_PROXY),
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
            maxAmount: NFAT_SUBSCRIBE_MAX, // BEFORE: unset, AFTER: 5_000_000e18
            slope: NFAT_SUBSCRIBE_SLOPE // BEFORE: unset, AFTER: uint256(1_000_000e18) / 1 days
        });
    }

    function _setUnlimitedNfatWithdrawRateLimit() private {
        IRateLimits(OseroEthereum.OSERO_RATE_LIMITS)
            .setUnlimitedRateLimitData(
                INFATPrimeController(OseroEthereum.OSERO_CONTROLLER)
                    .nfatPrime_getWithdrawRateLimitKey(TEST_NFAT_FACILITY)
            ); // BEFORE: unset, AFTER: unlimited
    }

    function _setUnlimitedNfatCollectRateLimit() private {
        IRateLimits(OseroEthereum.OSERO_RATE_LIMITS)
            .setUnlimitedRateLimitData(
                INFATPrimeController(OseroEthereum.OSERO_CONTROLLER)
                    .nfatPrime_getCollectRateLimitKey(TEST_NFAT_FACILITY)
            ); // BEFORE: unset, AFTER: unlimited
    }
}
