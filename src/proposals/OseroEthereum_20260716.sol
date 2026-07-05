// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {BaseSpell} from "../BaseSpell.sol";
import {RateLimitsHelper} from "../libraries/RateLimitsHelper.sol";

interface IControllerLike {
    function usds_setVault(address vault) external;
    function aave_setMaxSlippage(address aToken, uint256 maxSlippage) external;
}

interface IAllocatorVaultLike {
    function rely(address usr) external;
}

interface IAllocatorBufferLike {
    function approve(address asset, address spender, uint256 amount) external;
}

/// @title  July 16, 2026 Osero Ethereum Proposal
/// @notice Osero PAU launch: wires the USDS facet to the Osero Sky Allocator instance,
///         onboards USDS mint/burn and SparkLend USDS rate limits, and sets the spUSDS max slippage.
/// @custom:forum https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-osero-for-upcoming-spell/28023
contract OseroEthereum_20260716 is BaseSpell {
    // Osero PAU addresses. Source: https://github.com/osero-io/osero-address-registry
    address public constant OSERO_ALLOCATOR_BUFFER = 0xD0BB61b34771146e31055f20f329cDf97429F889;
    address public constant OSERO_ALLOCATOR_VAULT = 0x146181Aa9B362EaEC2eC3aDd7429a06D53B43d1a;
    address public constant OSERO_ALM_PROXY = 0x6d370e359e9cbd0Fd35Bb38fAF705D84238CB884;
    address public constant OSERO_CONTROLLER = 0x24169Afb34fAe4D4356BC54Bd80319131e35ca38;
    address public constant OSERO_RATE_LIMITS = 0xE9a78f34fe497e2186f81B8c014cd93B308BC62a;

    // SparkLend addresses. Source: https://github.com/sparkdotfi/spark-address-registry
    address public constant SPARKLEND_USDS_SPTOKEN = 0xC02aB1A5eaA8d1B114EF786D9bde108cD4364359;

    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    uint256 public constant USDS_MINT_MAX_LIMIT = 5_000_000e18;
    uint256 public constant USDS_MINT_SLOPE = uint256(5_000_000e18) / 1 days;

    // 1e18 precision: require at least 99.99% of supplied USDS back as spUSDS.
    uint256 public constant SPARKLEND_USDS_MAX_SLIPPAGE = 999_900_000_000_000_000;

    uint256 public constant SPARKLEND_USDS_DEPOSIT_MAX = 5_000_000e18;
    uint256 public constant SPARKLEND_USDS_DEPOSIT_SLOPE = uint256(5_000_000e18) / 1 days;

    // TODO: Replace the action descriptions below with the Executive Sheet instruction text once published.
    function execute() external override {
        // [Ethereum] Initialize the PAU system: hook it up to the ALLOCATOR-PRYSM-A instance (USDS mint/burn)
        //   Forum : https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-osero-for-upcoming-spell/28023
        IControllerLike(OSERO_CONTROLLER).usds_setVault(OSERO_ALLOCATOR_VAULT); // BEFORE: address(0)
        IAllocatorVaultLike(OSERO_ALLOCATOR_VAULT).rely(OSERO_ALM_PROXY); // BEFORE: not a ward
        IAllocatorBufferLike(OSERO_ALLOCATOR_BUFFER).approve(USDS, OSERO_ALM_PROXY, type(uint256).max); // BEFORE: 0 allowance

        // [Ethereum] Add USDS mint/burn and SparkLend USDS deposit/withdraw rate limits on the PAU rate limits
        //   Forum : https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-osero-for-upcoming-spell/28023
        _setupRateLimits();

        // [Ethereum] Set the SparkLend spUSDS max slippage
        //   Forum : https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-osero-for-upcoming-spell/28023
        IControllerLike(OSERO_CONTROLLER).aave_setMaxSlippage(SPARKLEND_USDS_SPTOKEN, SPARKLEND_USDS_MAX_SLIPPAGE); // BEFORE: 0
    }

    function _setupRateLimits() private {
        // USDS mint:               BEFORE: unset. AFTER: 5,000,000 max, 5,000,000 / day slope.
        RateLimitsHelper.setUsdsMintRateLimit(OSERO_RATE_LIMITS, USDS_MINT_MAX_LIMIT, USDS_MINT_SLOPE);

        // USDS burn:               BEFORE: unset. AFTER: unlimited.
        RateLimitsHelper.setUnlimitedUsdsBurnRateLimit(OSERO_RATE_LIMITS);

        // SparkLend USDS deposit:  BEFORE: unset. AFTER: 5,000,000 max, 5,000,000 / day slope.
        RateLimitsHelper.setSparkLendDepositRateLimit(
            OSERO_RATE_LIMITS, SPARKLEND_USDS_SPTOKEN, USDS, SPARKLEND_USDS_DEPOSIT_MAX, SPARKLEND_USDS_DEPOSIT_SLOPE
        );

        // SparkLend USDS withdraw: BEFORE: unset. AFTER: unlimited.
        RateLimitsHelper.setUnlimitedSparkLendWithdrawRateLimit(OSERO_RATE_LIMITS, SPARKLEND_USDS_SPTOKEN);
    }
}
