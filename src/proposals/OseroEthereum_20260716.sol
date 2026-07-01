// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import {Ethereum as OseroEthereum} from "@osero/address-registry/Ethereum.sol";
import {Ethereum as SkyPau} from "sky-pau-registry/Ethereum.sol";
import {SparkLend} from "spark-address-registry/SparkLend.sol";

import {BaseSpell} from "../BaseSpell.sol";

/// @dev Controller dispatch selectors for the Beacon-wired USDSFacet and AaveFacet.
/// Sources:
/// - https://github.com/sky-ecosystem/diamond-pau/blob/5c5ad6ae174bf467081ca82342ced2bd42a5c732/src/facets/usds/USDSFacet.sol
/// - https://github.com/sky-ecosystem/diamond-pau/blob/5c5ad6ae174bf467081ca82342ced2bd42a5c732/src/facets/aave/AaveFacet.sol
interface IController {
    function usds_setVault(address vault) external;
    function aave_setMaxSlippage(address aToken, uint256 maxSlippage) external;
}

/// @dev Sky Allocator vault administration surface.
/// Source: https://github.com/sky-ecosystem/dss-allocator/blob/226584d3b179d98025497815adb4ea585ea0102d/src/AllocatorVault.sol
interface IAllocatorVault {
    function rely(address usr) external;
}

/// @dev Sky Allocator buffer approval surface.
/// Source: https://github.com/sky-ecosystem/dss-allocator/blob/226584d3b179d98025497815adb4ea585ea0102d/src/AllocatorBuffer.sol
interface IAllocatorBuffer {
    function approve(address asset, address spender, uint256 amount) external;
}

/// @dev PAU rate-limit administration surface.
/// Source: https://github.com/sky-ecosystem/diamond-pau/blob/5c5ad6ae174bf467081ca82342ced2bd42a5c732/src/RateLimits.sol
interface IRateLimits {
    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;
    function setUnlimitedRateLimitData(bytes32 key) external;
}

/// @dev USDSFacet rate-limit key surface.
/// Source: https://github.com/sky-ecosystem/diamond-pau/blob/5c5ad6ae174bf467081ca82342ced2bd42a5c732/src/facets/usds/IUSDSFacet.sol
interface IUSDSFacet {
    function mintRateLimitKey() external pure returns (bytes32);
    function burnRateLimitKey() external pure returns (bytes32);
}

/// @dev AaveFacet rate-limit key surface.
/// Source: https://github.com/sky-ecosystem/diamond-pau/blob/5c5ad6ae174bf467081ca82342ced2bd42a5c732/src/facets/aave/IAaveFacet.sol
interface IAaveFacet {
    function getDepositRateLimitKey(address aToken, address pool, address underlyingAsset)
        external
        pure
        returns (bytes32);
    function getWithdrawRateLimitKey(address aToken, address pool) external pure returns (bytes32);
}

/// @title Osero Ethereum PAU launch spell
/// @notice Configures the Osero PAU USDS facet, Sky Allocator permissions, and SparkLend spUSDS limits.
/// @dev Expected execution context is the Osero SubProxy delegatecalling this spell.
contract OseroEthereum_20260716 is BaseSpell {
    /// @dev Sky USDS token. Source: https://github.com/sky-ecosystem/dss-chain-log
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    /// @dev After: 5,000,000 USDS mint cap.
    uint256 public constant USDS_MINT_MAX_LIMIT = 5_000_000e18;
    /// @dev After: 5,000,000 USDS per day mint refill rate.
    uint256 public constant USDS_MINT_SLOPE = uint256(5_000_000e18) / 1 days;

    /// @dev AaveFacet slippage floor uses 1e18 precision. After: require at least 99.99% of supplied USDS as spUSDS.
    uint256 public constant SPARK_USDS_MAX_SLIPPAGE = 0.9999e18;

    /// @dev After: 5,000,000 USDS SparkLend deposit cap.
    uint256 public constant SPARK_USDS_DEPOSIT_MAX = 5_000_000e18;
    /// @dev After: 5,000,000 USDS per day SparkLend deposit refill rate.
    uint256 public constant SPARK_USDS_DEPOSIT_SLOPE = uint256(5_000_000e18) / 1 days;

    function execute() external override {
        // Set USDSFacet.vault to the Osero Sky Allocation Vault.
        // Before: Controller.usds_vault() == address(0). After: Controller.usds_vault() == OseroEthereum.OSERO_ALLOCATOR_VAULT.
        // Source: https://github.com/sky-ecosystem/diamond-pau/blob/5c5ad6ae174bf467081ca82342ced2bd42a5c732/src/facets/usds/USDSFacet.sol
        IController(OseroEthereum.OSERO_CONTROLLER).usds_setVault(OseroEthereum.OSERO_ALLOCATOR_VAULT);

        // Authorize the PAU ALMProxy on the Osero Sky Allocation Vault.
        // Before: AllocatorVault.wards(ALMProxy) == 0. After: wards(ALMProxy) == 1.
        // Source: https://github.com/sky-ecosystem/dss-allocator/blob/226584d3b179d98025497815adb4ea585ea0102d/src/AllocatorVault.sol
        IAllocatorVault(OseroEthereum.OSERO_ALLOCATOR_VAULT).rely(OseroEthereum.OSERO_ALM_PROXY);

        // Allow the ALMProxy to pull USDS from the Osero Sky Allocation Buffer for USDSFacet.burn().
        // Before: USDS.allowance(buffer, ALMProxy) == 0. After: allowance == type(uint256).max.
        // Source: https://github.com/sky-ecosystem/dss-allocator/blob/226584d3b179d98025497815adb4ea585ea0102d/src/AllocatorBuffer.sol
        IAllocatorBuffer(OseroEthereum.OSERO_ALLOCATOR_BUFFER)
            .approve(USDS, OseroEthereum.OSERO_ALM_PROXY, type(uint256).max);

        IRateLimits rateLimits = IRateLimits(OseroEthereum.OSERO_RATE_LIMITS);
        IUSDSFacet usdsFacet = IUSDSFacet(SkyPau.USDS_FACET);
        IAaveFacet aaveFacet = IAaveFacet(SkyPau.AAVE_FACET);

        // Set USDS mint rate limit.
        // Before: maxAmount = 0, slope = 0. After: maxAmount = 5,000,000e18, slope = 5,000,000e18 / 1 days.
        // Source: https://github.com/sky-ecosystem/diamond-pau/blob/5c5ad6ae174bf467081ca82342ced2bd42a5c732/src/facets/usds/USDSFacet.sol
        rateLimits.setRateLimitData(usdsFacet.mintRateLimitKey(), USDS_MINT_MAX_LIMIT, USDS_MINT_SLOPE);
        // Set USDS burn rate limit to unlimited.
        // Before: maxAmount = 0, slope = 0. After: maxAmount = type(uint256).max, slope = 0.
        // Source: https://github.com/sky-ecosystem/diamond-pau/blob/5c5ad6ae174bf467081ca82342ced2bd42a5c732/src/facets/usds/USDSFacet.sol
        rateLimits.setUnlimitedRateLimitData(usdsFacet.burnRateLimitKey());

        // Set SparkLend spUSDS max slippage.
        // Before: maxSlippage = 0. After: require received spUSDS >= supplied USDS * 0.9999e18 / 1e18.
        // Source: https://github.com/sky-ecosystem/diamond-pau/blob/5c5ad6ae174bf467081ca82342ced2bd42a5c732/src/facets/aave/AaveFacet.sol
        IController(OseroEthereum.OSERO_CONTROLLER).aave_setMaxSlippage(SparkLend.USDS_SPTOKEN, SPARK_USDS_MAX_SLIPPAGE);

        // Set SparkLend USDS deposit rate limit.
        // Before: maxAmount = 0, slope = 0. After: maxAmount = 5,000,000e18, slope = 5,000,000e18 / 1 days.
        // Source: https://github.com/sky-ecosystem/diamond-pau/blob/5c5ad6ae174bf467081ca82342ced2bd42a5c732/src/facets/aave/AaveFacet.sol
        rateLimits.setRateLimitData(
            aaveFacet.getDepositRateLimitKey(SparkLend.USDS_SPTOKEN, SparkLend.POOL, USDS),
            SPARK_USDS_DEPOSIT_MAX,
            SPARK_USDS_DEPOSIT_SLOPE
        );
        // Set SparkLend USDS withdraw rate limit to unlimited.
        // Before: maxAmount = 0, slope = 0. After: maxAmount = type(uint256).max, slope = 0.
        // Source: https://github.com/sky-ecosystem/diamond-pau/blob/5c5ad6ae174bf467081ca82342ced2bd42a5c732/src/facets/aave/AaveFacet.sol
        rateLimits.setUnlimitedRateLimitData(aaveFacet.getWithdrawRateLimitKey(SparkLend.USDS_SPTOKEN, SparkLend.POOL));
    }
}
