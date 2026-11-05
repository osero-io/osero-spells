// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {Ethereum as OseroEthereum} from "osero-address-registry/Ethereum.sol";
import {SparkLend} from "spark-address-registry/SparkLend.sol";

import {PASAuthorizeInPAU} from "pas/deploy/PASAuthorizeInPAU.sol";

import {BaseSpell} from "../BaseSpell.sol";
import {RateLimitsHelper} from "../libraries/RateLimitsHelper.sol";

/// @title  September 24, 2026 Osero Ethereum Proposal
/// @notice Authorizes the Sky PAS Configurator on the Osero PAU and raises the USDS mint and
///         SparkLend USDS deposit rate limits to 50,000,000 USDS max and 50,000,000 USDS per day.
/// @custom:forum https://forum.skyeco.com/t/september-24-2026-proposed-changes-to-osero-for-upcoming-spell/28224
contract OseroEthereum_20260924 is BaseSpell {
    // Contract: USDS / Source: https://chainlog.skyeco.com/ (key: USDS)
    address internal constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    // Contract: Sky PAS Configurator / Source: https://chainlog.skyeco.com/ (key: PAS_CONFIGURATOR)
    address internal constant PAS_CONFIGURATOR = 0xb7E61Df6CAb0A51E9A5dab1A7DD3f942dDe5b929;

    uint256 internal constant USDS_MINT_MAX_LIMIT = 50_000_000e18;
    uint256 internal constant USDS_MINT_SLOPE = uint256(50_000_000e18) / 1 days;

    uint256 internal constant SPARKLEND_USDS_DEPOSIT_MAX = 50_000_000e18;
    uint256 internal constant SPARKLEND_USDS_DEPOSIT_SLOPE = uint256(50_000_000e18) / 1 days;

    function execute() external override {
        // [Ethereum] Authorize the Sky PAS Configurator on the Osero AccessControls and RateLimits
        //   Forum : https://forum.skyeco.com/t/september-24-2026-proposed-changes-to-osero-for-upcoming-spell/28224
        //   Proposed actions #1 and #2
        _authorizePasConfigurator();

        // [Ethereum] Raise the USDS mint and SparkLend USDS deposit rate limits on the PAU rate limits
        //   Forum : https://forum.skyeco.com/t/september-24-2026-proposed-changes-to-osero-for-upcoming-spell/28224
        //   Proposed actions #3 and #4
        _setupRateLimits();
    }

    function _authorizePasConfigurator() private {
        // BEFORE: Configurator holds neither admin role.
        // AFTER:  Configurator holds both; SubProxy keeps both.
        PASAuthorizeInPAU.authorize({
            configurator: PAS_CONFIGURATOR,
            accessControls: OseroEthereum.OSERO_ACCESS_CONTROLS,
            rateLimits: OseroEthereum.OSERO_RATE_LIMITS
        });
    }

    function _setupRateLimits() private {
        // Forum Proposed action #3
        RateLimitsHelper.setUsdsMintRateLimit({
            rateLimits: OseroEthereum.OSERO_RATE_LIMITS,
            maxAmount: USDS_MINT_MAX_LIMIT, // BEFORE: 5_000_000e18, AFTER: 50_000_000e18
            slope: USDS_MINT_SLOPE // BEFORE: uint256(5_000_000e18) / 1 days, AFTER: uint256(50_000_000e18) / 1 days
        });

        // Forum Proposed action #4
        RateLimitsHelper.setSparkLendDepositRateLimit({
            rateLimits: OseroEthereum.OSERO_RATE_LIMITS,
            spToken: SparkLend.USDS_SPTOKEN,
            underlyingAsset: USDS,
            maxAmount: SPARKLEND_USDS_DEPOSIT_MAX, // BEFORE: 5_000_000e18, AFTER: 50_000_000e18
            slope: SPARKLEND_USDS_DEPOSIT_SLOPE // BEFORE: uint256(5_000_000e18) / 1 days, AFTER: uint256(50_000_000e18) / 1 days
        });
    }
}
