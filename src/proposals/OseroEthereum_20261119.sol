// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {Base} from "osero-address-registry/Base.sol";
import {Ethereum as OseroEthereum} from "osero-address-registry/Ethereum.sol";

import {CCTPForwarder} from "xchain-helpers/forwarders/CCTPForwarder.sol";

import {OseroPayloadEthereum} from "../OseroPayloadEthereum.sol";

interface IControllerLike {
    function updateIntegrations(bytes32[] calldata ids) external;
    function cctp_setDomainParameters(
        uint32 destinationDomain,
        bytes32 recipient,
        uint32 minFeeCapRate,
        uint32 maxFeeCapRate
    ) external;
    function cctp_toCCTPRateLimitKey() external pure returns (bytes32 key);
    function cctp_getToDomainRateLimitKey(uint32 destinationDomain) external pure returns (bytes32 key);
}

interface IRateLimitsLike {
    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;
    function setUnlimitedRateLimitData(bytes32 key) external;
}

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

    constructor() {
        // PAYLOAD_BASE: the Osero Base payload (OseroBase_20261119), deployed on Base during spell crafting.
        // It must be set here before this spell is deployed; while unset, `execute` skips the relay.
    }

    function _execute() internal override {
        // [Ethereum] Enable the CCTP integration on the Osero PAU controller
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        //   Proposed action #1
        _enableCctpIntegration();

        // [Ethereum] Set the CCTP domain parameters for Base
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        //   Proposed action #2
        _setBaseDomainParameters();

        // [Ethereum] Add the CCTP rate limits toward Base on the PAU rate limits
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        //   Proposed actions #3 and #4
        _setupCctpRateLimits();

        // [Ethereum] Relay the Osero Base payload to the Osero Receiver on Base
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        //   Proposed action #5: sent by `OseroPayloadEthereum.execute` after these actions
    }

    function _enableCctpIntegration() private {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = CCTP_FACET_INTEGRATION_ID; // BEFORE: not wired on the controller, AFTER: wired from the beacon config
        IControllerLike(OseroEthereum.OSERO_CONTROLLER).updateIntegrations(ids);
    }

    function _setBaseDomainParameters() private {
        IControllerLike(OseroEthereum.OSERO_CONTROLLER).cctp_setDomainParameters({
            destinationDomain: CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            recipient: bytes32(uint256(uint160(Base.OSERO_ALM_PROXY))), // BEFORE: bytes32(0), AFTER: Osero ALM Proxy on Base
            minFeeCapRate: CCTP_MIN_FEE_CAP_RATE, // BEFORE: 0, AFTER: 0
            maxFeeCapRate: CCTP_MAX_FEE_CAP_RATE // BEFORE: 0, AFTER: 0
        });
    }

    function _setupCctpRateLimits() private {
        IControllerLike controller = IControllerLike(OseroEthereum.OSERO_CONTROLLER);

        // Forum Proposed action #3
        IRateLimitsLike(OseroEthereum.OSERO_RATE_LIMITS).setUnlimitedRateLimitData(controller.cctp_toCCTPRateLimitKey()); // BEFORE: unset, AFTER: unlimited

        // Forum Proposed action #4
        IRateLimitsLike(OseroEthereum.OSERO_RATE_LIMITS).setRateLimitData({
            key: controller.cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),
            maxAmount: CCTP_TO_BASE_MAX, // BEFORE: unset, AFTER: 10_000_000e6
            slope: CCTP_TO_BASE_SLOPE // BEFORE: unset, AFTER: uint256(50_000_000e6) / 1 days
        });
    }
}
