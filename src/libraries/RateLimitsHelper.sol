// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {Ethereum as SkyPau} from "sky-pau-registry/Ethereum.sol";
import {SparkLend} from "spark-address-registry/SparkLend.sol";

interface IRateLimitsLike {
    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;
    function setUnlimitedRateLimitData(bytes32 key) external;
}

interface IUSDSFacetLike {
    function mintRateLimitKey() external pure returns (bytes32);
    function burnRateLimitKey() external pure returns (bytes32);
}

interface IAaveFacetLike {
    function getDepositRateLimitKey(address aToken, address pool, address underlyingAsset)
        external
        pure
        returns (bytes32);
    function getWithdrawRateLimitKey(address aToken, address pool) external pure returns (bytes32);
}

library RateLimitsHelper {
    function setUsdsMintRateLimit(address rateLimits, uint256 maxAmount, uint256 slope) internal {
        IRateLimitsLike(rateLimits)
            .setRateLimitData(IUSDSFacetLike(SkyPau.USDS_FACET).mintRateLimitKey(), maxAmount, slope);
    }

    function setUnlimitedUsdsBurnRateLimit(address rateLimits) internal {
        IRateLimitsLike(rateLimits).setUnlimitedRateLimitData(IUSDSFacetLike(SkyPau.USDS_FACET).burnRateLimitKey());
    }

    function setSparkLendDepositRateLimit(
        address rateLimits,
        address spToken,
        address underlyingAsset,
        uint256 maxAmount,
        uint256 slope
    ) internal {
        IRateLimitsLike(rateLimits)
            .setRateLimitData(
                IAaveFacetLike(SkyPau.AAVE_FACET).getDepositRateLimitKey(spToken, SparkLend.POOL, underlyingAsset),
                maxAmount,
                slope
            );
    }

    function setUnlimitedSparkLendWithdrawRateLimit(address rateLimits, address spToken) internal {
        IRateLimitsLike(rateLimits)
            .setUnlimitedRateLimitData(
                IAaveFacetLike(SkyPau.AAVE_FACET).getWithdrawRateLimitKey(spToken, SparkLend.POOL)
            );
    }
}
