// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {Ethereum as SkyPau} from "sky-pau-registry/Ethereum.sol";
import {SparkLend} from "spark-address-registry/SparkLend.sol";

import {RateLimitsHelper} from "./RateLimitsHelper.sol";

contract MockUSDSFacet {
    function mintRateLimitKey() external pure returns (bytes32) {
        return keccak256("mock.usds.mintRateLimitKey");
    }

    function burnRateLimitKey() external pure returns (bytes32) {
        return keccak256("mock.usds.burnRateLimitKey");
    }
}

contract MockAaveFacet {
    function getDepositRateLimitKey(address aToken, address pool, address underlyingAsset)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode("mock.aave.depositRateLimitKey", aToken, pool, underlyingAsset));
    }

    function getWithdrawRateLimitKey(address aToken, address pool) external pure returns (bytes32) {
        return keccak256(abi.encode("mock.aave.withdrawRateLimitKey", aToken, pool));
    }
}

contract MockRateLimits {
    bool public shouldRevert;

    uint256 public setRateLimitDataCallCount;
    uint256 public setUnlimitedRateLimitDataCallCount;

    bytes32 public lastKey;
    uint256 public lastMaxAmount;
    uint256 public lastSlope;

    function setShouldRevert(bool shouldRevert_) external {
        shouldRevert = shouldRevert_;
    }

    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external {
        require(!shouldRevert, "MockRateLimits/set-rate-limit-data-revert");
        ++setRateLimitDataCallCount;
        lastKey = key;
        lastMaxAmount = maxAmount;
        lastSlope = slope;
    }

    function setUnlimitedRateLimitData(bytes32 key) external {
        require(!shouldRevert, "MockRateLimits/set-unlimited-rate-limit-data-revert");
        ++setUnlimitedRateLimitDataCallCount;
        lastKey = key;
    }
}

// Exposes the internal library functions behind external calls so `vm.expectRevert`
// applies to the whole library call instead of the facet key read inlined into the test.
contract RateLimitsHelperHarness {
    function setUsdsMintRateLimit(address rateLimits, uint256 maxAmount, uint256 slope) external {
        RateLimitsHelper.setUsdsMintRateLimit(rateLimits, maxAmount, slope);
    }

    function setUnlimitedUsdsBurnRateLimit(address rateLimits) external {
        RateLimitsHelper.setUnlimitedUsdsBurnRateLimit(rateLimits);
    }

    function setSparkLendDepositRateLimit(
        address rateLimits,
        address spToken,
        address underlyingAsset,
        uint256 maxAmount,
        uint256 slope
    ) external {
        RateLimitsHelper.setSparkLendDepositRateLimit(rateLimits, spToken, underlyingAsset, maxAmount, slope);
    }

    function setUnlimitedSparkLendWithdrawRateLimit(address rateLimits, address spToken) external {
        RateLimitsHelper.setUnlimitedSparkLendWithdrawRateLimit(rateLimits, spToken);
    }
}

contract RateLimitsHelper_Test is Test {
    MockRateLimits internal rateLimits;
    RateLimitsHelperHarness internal harness;

    function setUp() public {
        // Install mock facets at the registry addresses the library hardcodes.
        vm.etch(SkyPau.USDS_FACET, address(new MockUSDSFacet()).code);
        vm.etch(SkyPau.AAVE_FACET, address(new MockAaveFacet()).code);

        rateLimits = new MockRateLimits();
        harness = new RateLimitsHelperHarness();
    }

    function testFuzz_setUsdsMintRateLimit(uint256 maxAmount, uint256 slope) public {
        RateLimitsHelper.setUsdsMintRateLimit(address(rateLimits), maxAmount, slope);

        assertEq(rateLimits.setRateLimitDataCallCount(), 1, "set-rate-limit-data-call-count");
        assertEq(rateLimits.setUnlimitedRateLimitDataCallCount(), 0, "set-unlimited-rate-limit-data-call-count");
        assertEq(rateLimits.lastKey(), MockUSDSFacet(SkyPau.USDS_FACET).mintRateLimitKey(), "key");
        assertEq(rateLimits.lastMaxAmount(), maxAmount, "max-amount");
        assertEq(rateLimits.lastSlope(), slope, "slope");
    }

    function test_setUnlimitedUsdsBurnRateLimit() public {
        RateLimitsHelper.setUnlimitedUsdsBurnRateLimit(address(rateLimits));

        assertEq(rateLimits.setRateLimitDataCallCount(), 0, "set-rate-limit-data-call-count");
        assertEq(rateLimits.setUnlimitedRateLimitDataCallCount(), 1, "set-unlimited-rate-limit-data-call-count");
        assertEq(rateLimits.lastKey(), MockUSDSFacet(SkyPau.USDS_FACET).burnRateLimitKey(), "key");
    }

    function testFuzz_setSparkLendDepositRateLimit(
        address spToken,
        address underlyingAsset,
        uint256 maxAmount,
        uint256 slope
    ) public {
        RateLimitsHelper.setSparkLendDepositRateLimit(address(rateLimits), spToken, underlyingAsset, maxAmount, slope);

        // The expected key encodes SparkLend.POOL, proving the library passes the hardcoded pool to the facet.
        bytes32 expectedKey =
            MockAaveFacet(SkyPau.AAVE_FACET).getDepositRateLimitKey(spToken, SparkLend.POOL, underlyingAsset);

        assertEq(rateLimits.setRateLimitDataCallCount(), 1, "set-rate-limit-data-call-count");
        assertEq(rateLimits.setUnlimitedRateLimitDataCallCount(), 0, "set-unlimited-rate-limit-data-call-count");
        assertEq(rateLimits.lastKey(), expectedKey, "key");
        assertEq(rateLimits.lastMaxAmount(), maxAmount, "max-amount");
        assertEq(rateLimits.lastSlope(), slope, "slope");
    }

    function testFuzz_setUnlimitedSparkLendWithdrawRateLimit(address spToken) public {
        RateLimitsHelper.setUnlimitedSparkLendWithdrawRateLimit(address(rateLimits), spToken);

        bytes32 expectedKey = MockAaveFacet(SkyPau.AAVE_FACET).getWithdrawRateLimitKey(spToken, SparkLend.POOL);

        assertEq(rateLimits.setRateLimitDataCallCount(), 0, "set-rate-limit-data-call-count");
        assertEq(rateLimits.setUnlimitedRateLimitDataCallCount(), 1, "set-unlimited-rate-limit-data-call-count");
        assertEq(rateLimits.lastKey(), expectedKey, "key");
    }

    function test_setUsdsMintRateLimit_bubblesRateLimitsRevert() public {
        rateLimits.setShouldRevert(true);

        vm.expectRevert(bytes("MockRateLimits/set-rate-limit-data-revert"));
        harness.setUsdsMintRateLimit(address(rateLimits), 1, 1);
    }

    function test_setUnlimitedUsdsBurnRateLimit_bubblesRateLimitsRevert() public {
        rateLimits.setShouldRevert(true);

        vm.expectRevert(bytes("MockRateLimits/set-unlimited-rate-limit-data-revert"));
        harness.setUnlimitedUsdsBurnRateLimit(address(rateLimits));
    }

    function test_setSparkLendDepositRateLimit_bubblesRateLimitsRevert() public {
        rateLimits.setShouldRevert(true);

        vm.expectRevert(bytes("MockRateLimits/set-rate-limit-data-revert"));
        harness.setSparkLendDepositRateLimit(address(rateLimits), address(1), address(2), 1, 1);
    }

    function test_setUnlimitedSparkLendWithdrawRateLimit_bubblesRateLimitsRevert() public {
        rateLimits.setShouldRevert(true);

        vm.expectRevert(bytes("MockRateLimits/set-unlimited-rate-limit-data-revert"));
        harness.setUnlimitedSparkLendWithdrawRateLimit(address(rateLimits), address(1));
    }
}
