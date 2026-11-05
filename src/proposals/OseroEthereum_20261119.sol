// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {Base} from "osero-address-registry/Base.sol";
import {Ethereum as OseroEthereum} from "osero-address-registry/Ethereum.sol";

import {ICCTPController} from "diamond-pau/src/facets/cctp/ICCTPController.sol";
import {IController} from "diamond-pau/src/interfaces/IController.sol";
import {IRateLimits} from "diamond-pau/src/interfaces/IRateLimits.sol";

import {CCTPForwarder} from "xchain-helpers/forwarders/CCTPForwarder.sol";

import {OseroPayloadEthereum} from "../OseroPayloadEthereum.sol";

/// @title  November 19, 2026 Osero Ethereum Proposal
/// @notice Connects the Osero Liquidity Layer on Ethereum and Base through Circle CCTP: enables the CCTP
///         facet on the Osero PAU controller toward the Osero ALM Proxy on Base, adds the CCTP rate limits,
///         and relays the Osero Base payload to the Osero Executor on Base.
/// @custom:forum https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
contract OseroEthereum_20261119 is OseroPayloadEthereum {
    bytes32 internal constant CCTP_FACET_INTEGRATION_ID = "CCTP_FACET";

    // Fee caps in basis points: CCTP standard transfers are fee-free, so every transfer must pass a 0 fee cap.
    uint32 internal constant CCTP_MIN_FEE_CAP_RATE = 0;
    uint32 internal constant CCTP_MAX_FEE_CAP_RATE = 0;

    // USDC-denominated (6 decimals) limits.
    uint256 internal constant CCTP_TO_BASE_MAX = 10_000_000e6;
    uint256 internal constant CCTP_TO_BASE_SLOPE = uint256(50_000_000e6) / 1 days;

    function _execute() internal override {
        // [Ethereum] Proposed action #1: Enable the CCTP integration on the Osero `Controller` on Ethereum Mainnet
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        _enableCctpIntegration();

        // [Ethereum] Proposed action #2: Set the CCTP domain parameters for Base
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        _setBaseDomainParameters();

        // [Ethereum] Proposed action #3: Set the `LIMIT_USDC_TO_CCTP` rate limit on Ethereum Mainnet to unlimited
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        //   Note: there is no `RateLimitsHelper` function for CCTP keys; the key is read from the controller,
        //         which wires the CCTP facet in Proposed action #1.
        _setUnlimitedCctpRateLimit();

        // [Ethereum] Proposed action #4: Set the `LIMIT_USDC_TO_DOMAIN` rate limit for Base on Ethereum Mainnet to
        //   `maxAmount` `10,000,000 USDC` and `slope` `50,000,000 USDC/day`
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        _setCctpToBaseRateLimit();

        // [Ethereum] Proposed action #5: Relay the Osero Base payload to the Osero Receiver on Base
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        //   Note: sent by `OseroPayloadEthereum.execute` right after these actions, for `PAYLOAD_BASE`
        //         (`OseroBase_20261119`). As in Spark and Grove, the Base payload is deployed on Base first and its
        //         address is then set as `PAYLOAD_BASE` in a constructor here, before this spell is deployed; while
        //         `PAYLOAD_BASE` is unset, `execute` sends no message.
    }

    function _enableCctpIntegration() private {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = CCTP_FACET_INTEGRATION_ID; // BEFORE: not wired on the controller, AFTER: wired from the beacon config
        IController(OseroEthereum.OSERO_CONTROLLER).updateIntegrations(ids);
    }

    function _setBaseDomainParameters() private {
        ICCTPController(OseroEthereum.OSERO_CONTROLLER).cctp_setDomainParameters({
            destinationDomain: CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            recipient: bytes32(uint256(uint160(Base.OSERO_ALM_PROXY))), // BEFORE: bytes32(0), AFTER: Osero ALM Proxy on Base
            minFeeCapRate: CCTP_MIN_FEE_CAP_RATE, // BEFORE: 0, AFTER: 0
            maxFeeCapRate: CCTP_MAX_FEE_CAP_RATE // BEFORE: 0, AFTER: 0
        });
    }

    function _setUnlimitedCctpRateLimit() private {
        IRateLimits(OseroEthereum.OSERO_RATE_LIMITS)
            .setUnlimitedRateLimitData(ICCTPController(OseroEthereum.OSERO_CONTROLLER).cctp_toCCTPRateLimitKey()); // BEFORE: unset, AFTER: unlimited
    }

    function _setCctpToBaseRateLimit() private {
        IRateLimits(OseroEthereum.OSERO_RATE_LIMITS).setRateLimitData({
            key: ICCTPController(OseroEthereum.OSERO_CONTROLLER)
                .cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),
            maxAmount: CCTP_TO_BASE_MAX, // BEFORE: unset, AFTER: 10_000_000e6
            slope: CCTP_TO_BASE_SLOPE // BEFORE: unset, AFTER: uint256(50_000_000e6) / 1 days
        });
    }
}
