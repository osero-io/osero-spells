// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {Ethereum as OseroEthereum} from "osero-address-registry/Ethereum.sol";
import {SparkLend} from "spark-address-registry/SparkLend.sol";

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
/// @notice Osero PAU launch: initializes the PAU system on the existing ALLOCATOR-PRYSM-A allocator
///         instance, onboards USDS mint/burn and SparkLend USDS rate limits, and sets the spUSDS max slippage.
/// @custom:forum https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-osero-for-upcoming-spell/28023
contract OseroEthereum_20260716 is BaseSpell {
    // Contract: USDS / Source: https://chainlog.skyeco.com/ (key: USDS)
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    uint256 public constant USDS_MINT_MAX_LIMIT = 5_000_000e18;
    uint256 public constant USDS_MINT_SLOPE = uint256(5_000_000e18) / 1 days;

    // 1e18 precision: require at least 99.99% of supplied USDS back as spUSDS.
    uint256 public constant SPARKLEND_USDS_MAX_SLIPPAGE = 999_900_000_000_000_000;

    uint256 public constant SPARKLEND_USDS_DEPOSIT_MAX = 5_000_000e18;
    uint256 public constant SPARKLEND_USDS_DEPOSIT_SLOPE = uint256(5_000_000e18) / 1 days;

    function execute() external override {
        // [Ethereum] Initialize the PAU system: hook it up to the ALLOCATOR-PRYSM-A instance (USDS mint/burn)
        //   Forum : https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-osero-for-upcoming-spell/28023
        IControllerLike(OseroEthereum.OSERO_CONTROLLER).usds_setVault(OseroEthereum.OSERO_ALLOCATOR_VAULT); // BEFORE: address(0)
        IAllocatorVaultLike(OseroEthereum.OSERO_ALLOCATOR_VAULT).rely(OseroEthereum.OSERO_ALM_PROXY); // BEFORE: not a ward
        IAllocatorBufferLike(OseroEthereum.OSERO_ALLOCATOR_BUFFER)
            .approve(USDS, OseroEthereum.OSERO_ALM_PROXY, type(uint256).max); // BEFORE: 0 allowance

        // [Ethereum] Add USDS mint/burn and SparkLend USDS deposit/withdraw rate limits on the PAU rate limits
        //   Forum : https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-osero-for-upcoming-spell/28023
        _setupRateLimits();

        // [Ethereum] Set the SparkLend spUSDS max slippage
        //   Forum : https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-osero-for-upcoming-spell/28023
        IControllerLike(OseroEthereum.OSERO_CONTROLLER)
            .aave_setMaxSlippage(SparkLend.USDS_SPTOKEN, SPARKLEND_USDS_MAX_SLIPPAGE); // BEFORE: 0
    }

    function _setupRateLimits() private {
        // USDS mint:               BEFORE: unset. AFTER: 5,000,000 max, 5,000,000 / day slope.
        RateLimitsHelper.setUsdsMintRateLimit(OseroEthereum.OSERO_RATE_LIMITS, USDS_MINT_MAX_LIMIT, USDS_MINT_SLOPE);

        // USDS burn:               BEFORE: unset. AFTER: unlimited.
        RateLimitsHelper.setUnlimitedUsdsBurnRateLimit(OseroEthereum.OSERO_RATE_LIMITS);

        // SparkLend USDS deposit:  BEFORE: unset. AFTER: 5,000,000 max, 5,000,000 / day slope.
        RateLimitsHelper.setSparkLendDepositRateLimit(
            OseroEthereum.OSERO_RATE_LIMITS,
            SparkLend.USDS_SPTOKEN,
            USDS,
            SPARKLEND_USDS_DEPOSIT_MAX,
            SPARKLEND_USDS_DEPOSIT_SLOPE
        );

        // SparkLend USDS withdraw: BEFORE: unset. AFTER: unlimited.
        RateLimitsHelper.setUnlimitedSparkLendWithdrawRateLimit(OseroEthereum.OSERO_RATE_LIMITS, SparkLend.USDS_SPTOKEN);
    }
}
