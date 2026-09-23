// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {Ethereum as OseroEthereum} from "osero-address-registry/Ethereum.sol";

import {BaseSpell} from "../BaseSpell.sol";
import {RateLimitsHelper} from "../libraries/RateLimitsHelper.sol";

interface IControllerLike {
    function updateIntegrations(bytes32[] calldata ids) external;
    function erc4626_setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets) external;
}

/// @title  October 8, 2026 Osero Ethereum Proposal
/// @notice Onboards the Osero x Gauntlet USDC Prime Vault (Morpho Vault V2): enables the ERC-4626 and PSM
///         facets on the Osero PAU controller, sets the vault max exchange rate to 2 USDC per share, and adds
///         the PSM USDS<>USDC swap and vault deposit/withdraw rate limits.
/// @custom:forum TBD (https://forum.skyeco.com/t/october-8-2026-proposed-changes-to-osero-for-upcoming-spell/<post-id>)
contract OseroEthereum_20261008 is BaseSpell {
    // Contract: USDC / Source: https://chainlog.skyeco.com/ (key: USDC)
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Contract: Osero x Gauntlet USDC Prime Vault (Morpho Vault V2, ogusdcp) / Source: technical-scope forum post (TBD)
    address internal constant OGUSDCP_VAULT = 0x802148D518A6De2aF866f9A61ffB5e5C39156dB2;

    bytes32 internal constant ERC4626_FACET_INTEGRATION_ID = "ERC4626_FACET";
    bytes32 internal constant PSM_FACET_INTEGRATION_ID = "PSM_FACET";

    // Max exchange rate: at most 2 USDC (6 decimals) per 1e18 vault shares; stored as 1e36 * 2e6 / 1e18 = 2e24.
    uint256 internal constant OGUSDCP_MAX_EXCHANGE_RATE_SHARES = 1e18;
    uint256 internal constant OGUSDCP_MAX_EXCHANGE_RATE_ASSETS = 2e6;

    // USDC-denominated (6 decimals) limits.
    uint256 internal constant PSM_USDS_TO_USDC_MAX = 50_000_000e6;
    uint256 internal constant PSM_USDS_TO_USDC_SLOPE = uint256(50_000_000e6) / 1 days;

    // Zero slope: the deposit capacity only refills through vault withdrawals, never over time.
    uint256 internal constant OGUSDCP_DEPOSIT_MAX = 5_000_000e6;
    uint256 internal constant OGUSDCP_DEPOSIT_SLOPE = 0;

    function execute() external override {
        // [Ethereum] Enable the ERC-4626 and PSM integrations on the Osero PAU controller
        //   Forum : TBD
        //   Proposed action #1
        _enableIntegrations();

        // [Ethereum] Set the Osero x Gauntlet USDC Prime Vault max exchange rate
        //   Forum : TBD
        //   Proposed action #2
        _setOgusdcpMaxExchangeRate();

        // [Ethereum] Add the PSM USDS<>USDC swap and Osero x Gauntlet USDC Prime Vault deposit/withdraw rate limits on the PAU rate limits
        //   Forum : TBD
        //   Proposed actions #3 to #6
        _setupRateLimits();
    }

    function _enableIntegrations() private {
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = ERC4626_FACET_INTEGRATION_ID; // BEFORE: not wired on the controller, AFTER: wired from the beacon config
        ids[1] = PSM_FACET_INTEGRATION_ID; // BEFORE: not wired on the controller, AFTER: wired from the beacon config
        IControllerLike(OseroEthereum.OSERO_CONTROLLER).updateIntegrations(ids);
    }

    function _setOgusdcpMaxExchangeRate() private {
        IControllerLike(OseroEthereum.OSERO_CONTROLLER).erc4626_setMaxExchangeRate({
            token: OGUSDCP_VAULT,
            shares: OGUSDCP_MAX_EXCHANGE_RATE_SHARES,
            maxExpectedAssets: OGUSDCP_MAX_EXCHANGE_RATE_ASSETS // BEFORE: 0 (unset), AFTER: 2e6 (stored as 2e24)
        });
    }

    function _setupRateLimits() private {
        // Forum Proposed action #3
        RateLimitsHelper.setPsmUsdsToUsdcSwapRateLimit({
            rateLimits: OseroEthereum.OSERO_RATE_LIMITS,
            maxAmount: PSM_USDS_TO_USDC_MAX, // BEFORE: unset, AFTER: 50_000_000e6
            slope: PSM_USDS_TO_USDC_SLOPE // BEFORE: unset, AFTER: uint256(50_000_000e6) / 1 days
        });

        // Forum Proposed action #4
        RateLimitsHelper.setUnlimitedPsmUsdcToUsdsSwapRateLimit(OseroEthereum.OSERO_RATE_LIMITS); // BEFORE: unset, AFTER: unlimited

        // Forum Proposed action #5
        RateLimitsHelper.setErc4626DepositRateLimit({
            rateLimits: OseroEthereum.OSERO_RATE_LIMITS,
            token: OGUSDCP_VAULT,
            asset: USDC,
            maxAmount: OGUSDCP_DEPOSIT_MAX, // BEFORE: unset, AFTER: 5_000_000e6
            slope: OGUSDCP_DEPOSIT_SLOPE // BEFORE: unset, AFTER: 0
        });

        // Forum Proposed action #6
        RateLimitsHelper.setUnlimitedErc4626WithdrawRateLimit(OseroEthereum.OSERO_RATE_LIMITS, OGUSDCP_VAULT); // BEFORE: unset, AFTER: unlimited
    }
}
