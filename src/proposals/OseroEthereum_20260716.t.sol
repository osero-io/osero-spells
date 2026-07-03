// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {Ethereum as OseroEthereum} from "@osero/address-registry/Ethereum.sol";
import {Ethereum as SkyPau} from "sky-pau-registry/Ethereum.sol";
import {SparkLend} from "spark-address-registry/SparkLend.sol";

import {OseroEthereum_20260716} from "./OseroEthereum_20260716.sol";

struct PauDispatch {
    address facet;
    bytes4 delegateSelector;
}

struct PauWire {
    bytes4 callSelector;
    bytes4 delegateSelector;
}

struct PauConfig {
    address facet;
    PauWire[] wires;
}

struct PauIntegration {
    bytes32 id;
    PauConfig config;
}

interface IStarGuardLike {
    function maxDelay() external view returns (uint256);
    function plot(address addr_, bytes32 tag_) external;
    function prob() external view returns (bool);
    function exec() external returns (address addr);
    function spellData() external view returns (address addr, bytes32 tag, uint256 deadline);
    function subProxy() external view returns (address);
    function wards(address usr) external view returns (uint256);
}

interface ISubProxyLike {
    function wards(address usr) external view returns (uint256);
}

interface IOseroPauControllerLike {
    function accessControls() external view returns (address);
    function beacon() external view returns (address);
    function getDispatch(bytes4 callSelector) external view returns (PauDispatch memory dispatch);
    function integrations() external view returns (PauIntegration[] memory integrations_);
    function proxy() external view returns (address);
    function rateLimits() external view returns (address);

    function usds_setVault(address vault) external;
    function usds_mint(uint256 usdsAmount) external;
    function usds_burn(uint256 usdsAmount) external;
    function usds_vault() external view returns (address);
    function usds_mintRateLimitKey() external view returns (bytes32);
    function usds_burnRateLimitKey() external view returns (bytes32);

    function aave_deposit(address aToken, uint256 amount) external;
    function aave_setMaxSlippage(address aToken, uint256 maxSlippage) external;
    function aave_withdraw(address aToken, uint256 amount) external returns (uint256 amountWithdrawn);
    function aave_getDepositRateLimitKey(address aToken, address pool, address underlyingAsset)
        external
        view
        returns (bytes32 key);
    function aave_getMaxSlippage(address aToken) external view returns (uint256 maxSlippage);
    function aave_getWithdrawRateLimitKey(address aToken, address pool) external view returns (bytes32 key);
}

interface IRateLimitsLike {
    struct RateLimitData {
        uint256 maxAmount;
        uint256 slope;
        uint256 lastAmount;
        uint256 lastUpdated;
    }

    function getCurrentRateLimit(bytes32 key) external view returns (uint256 rateLimit);
    function getRateLimitData(bytes32 key) external view returns (RateLimitData memory data);
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IAccessControlsLike {
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IAccessControlLike {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IAdministeredAgentLike {
    function actorCount() external view returns (uint256);
    function adminCount() external view returns (uint256);
    function call(address target, bytes memory data) external payable returns (bytes memory result);
    function getAdmin(uint256 index) external view returns (address);
    function getIsActor(address account) external view returns (bool);
    function getRevoker(uint256 index) external view returns (address);
    function grantorCount() external view returns (uint256);
    function revokerCount() external view returns (uint256);
}

interface IAllocatorVaultLike {
    function buffer() external view returns (address);
    function ilk() external view returns (bytes32);
    function wards(address usr) external view returns (uint256);
}

interface IAllocatorBufferLike {
    function wards(address usr) external view returns (uint256);
}

interface IATokenLike {
    function POOL() external view returns (address);
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

contract OseroEthereum_20260716_Test is Test {
    // Osero PAU stack was deployed at block 25,383,064; the forum pre-state readbacks use block 25,431,261.
    uint256 internal constant MAINNET_FORK_BLOCK = 25_431_261;

    address internal constant MCD_PAUSE_PROXY = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;
    address internal constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address internal constant PERMISSIONLESS_EXECUTOR = address(0xE2E);

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant CONTROLLER = keccak256("CONTROLLER");
    bytes32 internal constant EXPECTED_USDS_FACET_INTEGRATION_ID = "USDS_FACET";
    bytes32 internal constant EXPECTED_AAVE_FACET_INTEGRATION_ID = "AAVE_FACET";
    bytes32 internal constant EXPECTED_USDS_MINT_RATE_LIMIT_KEY =
        0xcb0537d5e5dba65a8edbac12555995860e5b8e1b70996011edb1ca8173e56d3c;
    bytes32 internal constant EXPECTED_USDS_BURN_RATE_LIMIT_KEY =
        0x844d35ae585cfdeed0a77b7724286a1d4b5718bf8663d85e55396062b1cbe38c;
    bytes32 internal constant EXPECTED_SPARK_USDS_DEPOSIT_RATE_LIMIT_KEY =
        0x5534da2f28b3dd200cb0042c0876cd6e2beca93d3232c366ec077018c82da73d;
    bytes32 internal constant EXPECTED_SPARK_USDS_WITHDRAW_RATE_LIMIT_KEY =
        0xf9ac1455c7ba8e0bacb7a3eca4a2cf412eda3cbc0f6aa1b071d73b37d49925d8;

    uint256 internal constant EXPECTED_BOUNDED_USDS_AMOUNT = 5_000_000_000_000_000_000_000_000;
    uint256 internal constant EXPECTED_BOUNDED_USDS_SLOPE = 57_870_370_370_370_370_370;
    uint256 internal constant EXPECTED_SPARK_USDS_MAX_SLIPPAGE = 999_900_000_000_000_000;

    uint256 internal constant USDS_MINT_MAX_LIMIT = EXPECTED_BOUNDED_USDS_AMOUNT;
    uint256 internal constant USDS_MINT_SLOPE = EXPECTED_BOUNDED_USDS_SLOPE;
    uint256 internal constant SPARK_USDS_MAX_SLIPPAGE = EXPECTED_SPARK_USDS_MAX_SLIPPAGE;
    uint256 internal constant SPARK_USDS_DEPOSIT_MAX = EXPECTED_BOUNDED_USDS_AMOUNT;
    uint256 internal constant SPARK_USDS_DEPOSIT_SLOPE = EXPECTED_BOUNDED_USDS_SLOPE;

    uint256 internal constant OPERATIONAL_TEST_AMOUNT = 100_000e18;
    uint256 internal constant MAX_EXECUTION_GAS = 30_000_000;

    IOseroPauControllerLike internal constant controller = IOseroPauControllerLike(OseroEthereum.OSERO_CONTROLLER);
    IRateLimitsLike internal constant rateLimits = IRateLimitsLike(OseroEthereum.OSERO_RATE_LIMITS);
    IStarGuardLike internal constant starGuard = IStarGuardLike(OseroEthereum.OSERO_STAR_GUARD);
    IERC20 internal constant usds = IERC20(USDS);
    IERC20 internal constant spUsds = IERC20(SparkLend.USDS_SPTOKEN);

    struct SpellState {
        address usdsVault;
        uint256 almProxyVaultWard;
        uint256 almProxyBufferAllowance;
        uint256 sparkUsdsMaxSlippage;
        IRateLimitsLike.RateLimitData mintData;
        IRateLimitsLike.RateLimitData burnData;
        IRateLimitsLike.RateLimitData depositData;
        IRateLimitsLike.RateLimitData withdrawData;
    }

    // Checklist action coverage:
    // - Controller.usds_setVault(OSERO_ALLOCATOR_VAULT):
    //   test_ETHEREUM_spellExecutionConfiguresAllActions,
    //   test_ETHEREUM_usdsMintBurnOperationalThroughAdministeredAgent.
    // - AllocatorVault.rely(OSERO_ALM_PROXY):
    //   test_ETHEREUM_spellExecutionConfiguresAllActions,
    //   test_ETHEREUM_usdsMintBurnOperationalThroughAdministeredAgent.
    // - AllocatorBuffer.approve(USDS, OSERO_ALM_PROXY, type(uint256).max):
    //   test_ETHEREUM_spellExecutionConfiguresAllActions,
    //   test_ETHEREUM_usdsMintBurnOperationalThroughAdministeredAgent.
    // - RateLimits.setRateLimitData(USDS mint key, 5M, 5M/day):
    //   test_ETHEREUM_spellExecutionConfiguresAllActions,
    //   test_ETHEREUM_usdsMintBurnOperationalThroughAdministeredAgent.
    // - RateLimits.setUnlimitedRateLimitData(USDS burn key):
    //   test_ETHEREUM_spellExecutionConfiguresAllActions,
    //   test_ETHEREUM_usdsMintBurnOperationalThroughAdministeredAgent.
    // - Controller.aave_setMaxSlippage(spUSDS, 0.9999e18):
    //   test_ETHEREUM_spellExecutionConfiguresAllActions,
    //   test_ETHEREUM_sparkUsdsDepositWithdrawOperationalThroughAdministeredAgent.
    // - RateLimits.setRateLimitData(Spark USDS deposit key, 5M, 5M/day):
    //   test_ETHEREUM_spellExecutionConfiguresAllActions,
    //   test_ETHEREUM_sparkUsdsDepositWithdrawOperationalThroughAdministeredAgent.
    // - RateLimits.setUnlimitedRateLimitData(Spark USDS withdraw key):
    //   test_ETHEREUM_spellExecutionConfiguresAllActions,
    //   test_ETHEREUM_sparkUsdsDepositWithdrawOperationalThroughAdministeredAgent.

    // TODO(core-spell): Replace this pre-Core fork (`MAINNET_FORK_BLOCK`) with a post-Core fork block or execute
    // the coordinated July 16 Sky Core spell fixture, then assert LitePSM.bud(OSERO_ALM_PROXY) == 1.
    // TODO(core-spell): In the same post-Core state, assert ALLOCATOR-PRYSM-A DC-IAM target parameters:
    // maxLine == 5_000_000e18 and gap == 1_000_000e18. This is the remaining Good-to-Deploy gate.

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), MAINNET_FORK_BLOCK);
    }

    function test_ETHEREUM_deploymentAndPauSystemPreconfiguration() public {
        OseroEthereum_20260716 payload = new OseroEthereum_20260716();

        assertGt(address(payload).code.length, 0, "payload-not-deployed");
        assertTrue(payload.isExecutable(), "payload-not-executable");
        assertEq(payload.USDS(), USDS, "payload-usds-mismatch");

        _assertContract(OseroEthereum.OSERO_PROXY, "osero-proxy");
        _assertContract(OseroEthereum.OSERO_STAR_GUARD, "osero-star-guard");
        _assertContract(OseroEthereum.OSERO_ACCESS_CONTROLS, "osero-access-controls");
        _assertContract(OseroEthereum.OSERO_ALM_PROXY, "osero-alm-proxy");
        _assertContract(OseroEthereum.OSERO_RATE_LIMITS, "osero-rate-limits");
        _assertContract(OseroEthereum.OSERO_CONTROLLER, "osero-controller");
        _assertContract(OseroEthereum.OSERO_ADMINISTERED_AGENT, "osero-administered-agent");
        _assertContract(OseroEthereum.OSERO_ALLOCATOR_VAULT, "osero-allocator-vault");
        _assertContract(OseroEthereum.OSERO_ALLOCATOR_BUFFER, "osero-allocator-buffer");
        _assertContract(SkyPau.BEACON, "sky-pau-beacon");
        _assertContract(SkyPau.USDS_FACET, "sky-pau-usds-facet");
        _assertContract(SkyPau.AAVE_FACET, "sky-pau-aave-facet");
        _assertContract(USDS, "usds");
        _assertContract(SparkLend.POOL, "spark-pool");
        _assertContract(SparkLend.USDS_SPTOKEN, "spark-usds-sptoken");

        assertEq(starGuard.subProxy(), OseroEthereum.OSERO_PROXY, "starguard-subproxy-mismatch");
        assertEq(starGuard.wards(MCD_PAUSE_PROXY), 1, "pause-proxy-not-starguard-ward");
        assertEq(
            ISubProxyLike(OseroEthereum.OSERO_PROXY).wards(OseroEthereum.OSERO_STAR_GUARD),
            1,
            "starguard-not-subproxy-ward"
        );
        assertEq(ISubProxyLike(OseroEthereum.OSERO_PROXY).wards(MCD_PAUSE_PROXY), 1, "pause-proxy-not-subproxy-ward");
        assertGt(starGuard.maxDelay(), 0, "starguard-max-delay-not-set");

        assertEq(
            controller.accessControls(), OseroEthereum.OSERO_ACCESS_CONTROLS, "controller-access-controls-mismatch"
        );
        assertEq(controller.beacon(), SkyPau.BEACON, "controller-beacon-mismatch");
        assertEq(controller.proxy(), OseroEthereum.OSERO_ALM_PROXY, "controller-proxy-mismatch");
        assertEq(controller.rateLimits(), OseroEthereum.OSERO_RATE_LIMITS, "controller-rate-limits-mismatch");

        _assertDispatch(IOseroPauControllerLike.usds_setVault.selector, SkyPau.USDS_FACET, "usds-set-vault");
        _assertDispatch(IOseroPauControllerLike.usds_vault.selector, SkyPau.USDS_FACET, "usds-vault");
        _assertDispatch(IOseroPauControllerLike.usds_mint.selector, SkyPau.USDS_FACET, "usds-mint");
        _assertDispatch(IOseroPauControllerLike.usds_burn.selector, SkyPau.USDS_FACET, "usds-burn");
        _assertDispatch(IOseroPauControllerLike.usds_mintRateLimitKey.selector, SkyPau.USDS_FACET, "usds-mint-key");
        _assertDispatch(IOseroPauControllerLike.usds_burnRateLimitKey.selector, SkyPau.USDS_FACET, "usds-burn-key");

        _assertDispatch(IOseroPauControllerLike.aave_setMaxSlippage.selector, SkyPau.AAVE_FACET, "aave-set-slippage");
        _assertDispatch(IOseroPauControllerLike.aave_getMaxSlippage.selector, SkyPau.AAVE_FACET, "aave-get-slippage");
        _assertDispatch(
            IOseroPauControllerLike.aave_getDepositRateLimitKey.selector, SkyPau.AAVE_FACET, "aave-deposit-key"
        );
        _assertDispatch(
            IOseroPauControllerLike.aave_getWithdrawRateLimitKey.selector, SkyPau.AAVE_FACET, "aave-withdraw-key"
        );
        _assertDispatch(IOseroPauControllerLike.aave_deposit.selector, SkyPau.AAVE_FACET, "aave-deposit");
        _assertDispatch(IOseroPauControllerLike.aave_withdraw.selector, SkyPau.AAVE_FACET, "aave-withdraw");

        _assertOnlyExpectedControllerIntegrations();

        IAccessControlsLike accessControls = IAccessControlsLike(OseroEthereum.OSERO_ACCESS_CONTROLS);
        IAdministeredAgentLike agent = IAdministeredAgentLike(OseroEthereum.OSERO_ADMINISTERED_AGENT);

        assertTrue(
            accessControls.hasRole(DEFAULT_ADMIN_ROLE, OseroEthereum.OSERO_PROXY), "subproxy-missing-access-admin"
        );
        assertTrue(
            accessControls.hasRole(ALLOCATOR_ROLE, OseroEthereum.OSERO_ADMINISTERED_AGENT),
            "agent-missing-allocator-role"
        );
        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1, "access-admin-count");
        assertEq(accessControls.getRoleMemberCount(ALLOCATOR_ROLE), 1, "allocator-role-count");

        IAccessControlLike almProxy = IAccessControlLike(OseroEthereum.OSERO_ALM_PROXY);
        assertTrue(almProxy.hasRole(DEFAULT_ADMIN_ROLE, OseroEthereum.OSERO_PROXY), "subproxy-missing-almproxy-admin");
        assertFalse(
            almProxy.hasRole(DEFAULT_ADMIN_ROLE, SkyPau.DEFAULT_PAU_ASSEMBLER), "assembler-retains-almproxy-admin"
        );
        assertTrue(almProxy.hasRole(CONTROLLER, OseroEthereum.OSERO_CONTROLLER), "controller-missing-almproxy-role");
        assertTrue(rateLimits.hasRole(CONTROLLER, OseroEthereum.OSERO_CONTROLLER), "controller-missing-ratelimits-role");
        assertTrue(
            rateLimits.hasRole(DEFAULT_ADMIN_ROLE, OseroEthereum.OSERO_PROXY), "subproxy-missing-ratelimits-admin"
        );
        assertFalse(
            rateLimits.hasRole(DEFAULT_ADMIN_ROLE, SkyPau.DEFAULT_PAU_ASSEMBLER), "assembler-retains-ratelimits-admin"
        );

        assertEq(agent.adminCount(), 1, "agent-admin-count");
        assertEq(agent.actorCount(), 2, "agent-actor-count");
        assertEq(agent.revokerCount(), 1, "agent-revoker-count");
        assertEq(agent.grantorCount(), 0, "agent-grantor-count");
        assertEq(agent.getAdmin(0), OseroEthereum.OSERO_PROXY, "agent-admin-0");
        assertTrue(agent.getIsActor(OseroEthereum.OSERO_OPERATOR), "osero-operator-not-agent-actor");
        assertTrue(agent.getIsActor(OseroEthereum.SOTER_OPERATOR), "soter-operator-not-agent-actor");
        assertEq(agent.getRevoker(0), OseroEthereum.SOTER_FREEZER, "agent-revoker-0");

        IAllocatorVaultLike vault = IAllocatorVaultLike(OseroEthereum.OSERO_ALLOCATOR_VAULT);
        assertEq(vault.buffer(), OseroEthereum.OSERO_ALLOCATOR_BUFFER, "vault-buffer-mismatch");
        assertEq(vault.ilk(), OseroEthereum.OSERO_ILK, "vault-ilk-mismatch");
        assertEq(vault.wards(OseroEthereum.OSERO_PROXY), 1, "subproxy-not-vault-ward");
        assertEq(
            IAllocatorBufferLike(OseroEthereum.OSERO_ALLOCATOR_BUFFER).wards(OseroEthereum.OSERO_PROXY),
            1,
            "subproxy-not-buffer-ward"
        );

        assertEq(IATokenLike(SparkLend.USDS_SPTOKEN).POOL(), SparkLend.POOL, "sptoken-pool-mismatch");
        assertEq(IATokenLike(SparkLend.USDS_SPTOKEN).UNDERLYING_ASSET_ADDRESS(), USDS, "sptoken-underlying-mismatch");
    }

    function test_ETHEREUM_scopeKeysAndEncodedParametersMatchTechnicalScope() public {
        OseroEthereum_20260716 payload = new OseroEthereum_20260716();

        assertEq(controller.usds_mintRateLimitKey(), EXPECTED_USDS_MINT_RATE_LIMIT_KEY, "mint-key-mismatch");
        assertEq(controller.usds_burnRateLimitKey(), EXPECTED_USDS_BURN_RATE_LIMIT_KEY, "burn-key-mismatch");
        assertEq(
            controller.aave_getDepositRateLimitKey(SparkLend.USDS_SPTOKEN, SparkLend.POOL, USDS),
            EXPECTED_SPARK_USDS_DEPOSIT_RATE_LIMIT_KEY,
            "spark-deposit-key-mismatch"
        );
        assertEq(
            controller.aave_getWithdrawRateLimitKey(SparkLend.USDS_SPTOKEN, SparkLend.POOL),
            EXPECTED_SPARK_USDS_WITHDRAW_RATE_LIMIT_KEY,
            "spark-withdraw-key-mismatch"
        );

        assertEq(payload.USDS_MINT_MAX_LIMIT(), EXPECTED_BOUNDED_USDS_AMOUNT, "payload-mint-max-amount");
        assertEq(payload.USDS_MINT_SLOPE(), EXPECTED_BOUNDED_USDS_SLOPE, "payload-mint-slope");
        assertEq(payload.SPARK_USDS_DEPOSIT_MAX(), EXPECTED_BOUNDED_USDS_AMOUNT, "payload-deposit-max-amount");
        assertEq(payload.SPARK_USDS_DEPOSIT_SLOPE(), EXPECTED_BOUNDED_USDS_SLOPE, "payload-deposit-slope");
        assertEq(payload.SPARK_USDS_MAX_SLIPPAGE(), EXPECTED_SPARK_USDS_MAX_SLIPPAGE, "payload-spark-slippage");

        assertEq(EXPECTED_BOUNDED_USDS_AMOUNT, uint256(5_000_000e18), "scope-amount-decimal-encoding");
        assertEq(EXPECTED_BOUNDED_USDS_SLOPE, uint256(5_000_000e18) / 1 days, "scope-slope-decimal-encoding");
    }

    function test_ETHEREUM_spellExecutionConfiguresAllActions() public {
        bytes32 mintKey = controller.usds_mintRateLimitKey();
        bytes32 burnKey = controller.usds_burnRateLimitKey();
        bytes32 depositKey = controller.aave_getDepositRateLimitKey(SparkLend.USDS_SPTOKEN, SparkLend.POOL, USDS);
        bytes32 withdrawKey = controller.aave_getWithdrawRateLimitKey(SparkLend.USDS_SPTOKEN, SparkLend.POOL);

        _assertSpellPreconditions(mintKey, burnKey, depositKey, withdrawKey);

        _executeSpellViaStarGuard(new OseroEthereum_20260716());

        _assertSpellPostconditions(mintKey, burnKey, depositKey, withdrawKey);
    }

    function test_ETHEREUM_directPayloadExecutionCannotBypassStarGuardSubProxy() public {
        OseroEthereum_20260716 payload = new OseroEthereum_20260716();

        bytes32 mintKey = controller.usds_mintRateLimitKey();
        bytes32 burnKey = controller.usds_burnRateLimitKey();
        bytes32 depositKey = controller.aave_getDepositRateLimitKey(SparkLend.USDS_SPTOKEN, SparkLend.POOL, USDS);
        bytes32 withdrawKey = controller.aave_getWithdrawRateLimitKey(SparkLend.USDS_SPTOKEN, SparkLend.POOL);

        _assertSpellPreconditions(mintKey, burnKey, depositKey, withdrawKey);
        SpellState memory stateBefore = _captureSpellState(mintKey, burnKey, depositKey, withdrawKey);

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", address(payload), DEFAULT_ADMIN_ROLE
            )
        );
        payload.execute();

        _assertSpellStateUnchanged(
            stateBefore, _captureSpellState(mintKey, burnKey, depositKey, withdrawKey), "direct-payload-execute"
        );
    }

    function test_ETHEREUM_starGuardExecutionWindowRejectsExpiredPayload() public {
        OseroEthereum_20260716 payload = new OseroEthereum_20260716();
        bytes32 codehash = keccak256(address(payload).code);

        vm.prank(MCD_PAUSE_PROXY);
        starGuard.plot(address(payload), codehash);

        (,, uint256 deadline) = starGuard.spellData();
        assertEq(deadline, block.timestamp + starGuard.maxDelay(), "starguard-deadline-mismatch");
        assertTrue(payload.isExecutable(), "payload-not-executable-before-deadline");
        assertTrue(starGuard.prob(), "starguard-not-probable-before-deadline");

        vm.warp(deadline + 1);

        assertFalse(starGuard.prob(), "starguard-prob-true-after-deadline");
        vm.expectRevert(bytes("StarGuard/expired-spell"));
        starGuard.exec();
    }

    function test_ETHEREUM_usdsMintBurnOperationalThroughAdministeredAgent() public {
        _executeSpellViaStarGuard(new OseroEthereum_20260716());

        bytes32 mintKey = controller.usds_mintRateLimitKey();
        bytes32 burnKey = controller.usds_burnRateLimitKey();
        uint256 proxyUsdsStart = usds.balanceOf(OseroEthereum.OSERO_ALM_PROXY);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), USDS_MINT_MAX_LIMIT, "mint-limit-not-full");
        assertEq(rateLimits.getCurrentRateLimit(burnKey), type(uint256).max, "burn-limit-not-unlimited");

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_mint, (OPERATIONAL_TEST_AMOUNT)));

        assertEq(
            usds.balanceOf(OseroEthereum.OSERO_ALM_PROXY),
            proxyUsdsStart + OPERATIONAL_TEST_AMOUNT,
            "proxy-usds-not-minted"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(mintKey),
            USDS_MINT_MAX_LIMIT - OPERATIONAL_TEST_AMOUNT,
            "mint-limit-not-decreased"
        );
        assertEq(rateLimits.getCurrentRateLimit(burnKey), type(uint256).max, "burn-limit-changed-after-mint");

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_burn, (OPERATIONAL_TEST_AMOUNT)));

        assertEq(usds.balanceOf(OseroEthereum.OSERO_ALM_PROXY), proxyUsdsStart, "proxy-usds-not-burned");
        assertEq(rateLimits.getCurrentRateLimit(mintKey), USDS_MINT_MAX_LIMIT, "mint-limit-not-refilled");
        assertEq(rateLimits.getCurrentRateLimit(burnKey), type(uint256).max, "burn-limit-not-still-unlimited");
    }

    function test_ETHEREUM_sparkUsdsDepositWithdrawOperationalThroughAdministeredAgent() public {
        _executeSpellViaStarGuard(new OseroEthereum_20260716());

        bytes32 mintKey = controller.usds_mintRateLimitKey();
        bytes32 burnKey = controller.usds_burnRateLimitKey();
        bytes32 depositKey = controller.aave_getDepositRateLimitKey(SparkLend.USDS_SPTOKEN, SparkLend.POOL, USDS);
        bytes32 withdrawKey = controller.aave_getWithdrawRateLimitKey(SparkLend.USDS_SPTOKEN, SparkLend.POOL);

        uint256 proxyUsdsStart = usds.balanceOf(OseroEthereum.OSERO_ALM_PROXY);
        uint256 proxySpUsdsStart = spUsds.balanceOf(OseroEthereum.OSERO_ALM_PROXY);
        assertEq(rateLimits.getCurrentRateLimit(depositKey), SPARK_USDS_DEPOSIT_MAX, "deposit-limit-not-full");
        assertEq(
            rateLimits.getCurrentRateLimit(withdrawKey),
            type(uint256).max,
            "withdraw-limit-not-unlimited-before-deposit"
        );

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_mint, (OPERATIONAL_TEST_AMOUNT)));
        assertEq(
            usds.balanceOf(OseroEthereum.OSERO_ALM_PROXY),
            proxyUsdsStart + OPERATIONAL_TEST_AMOUNT,
            "proxy-usds-not-minted"
        );

        _callAsOseroActor(
            abi.encodeCall(IOseroPauControllerLike.aave_deposit, (SparkLend.USDS_SPTOKEN, OPERATIONAL_TEST_AMOUNT))
        );

        uint256 minSpUsdsOut = OPERATIONAL_TEST_AMOUNT * SPARK_USDS_MAX_SLIPPAGE / 1e18;
        uint256 proxySpUsdsAfterDeposit = spUsds.balanceOf(OseroEthereum.OSERO_ALM_PROXY);
        assertEq(usds.balanceOf(OseroEthereum.OSERO_ALM_PROXY), proxyUsdsStart, "proxy-usds-not-deposited");
        assertGe(proxySpUsdsAfterDeposit - proxySpUsdsStart, minSpUsdsOut, "proxy-spusds-received-too-low");
        assertEq(
            usds.allowance(OseroEthereum.OSERO_ALM_PROXY, SparkLend.POOL), 0, "spark-pool-usds-approval-not-cleared"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(depositKey),
            SPARK_USDS_DEPOSIT_MAX - OPERATIONAL_TEST_AMOUNT,
            "deposit-limit-not-decreased"
        );
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max, "withdraw-limit-not-unlimited");

        bytes memory withdrawResult = _callAsOseroActor(
            abi.encodeCall(IOseroPauControllerLike.aave_withdraw, (SparkLend.USDS_SPTOKEN, OPERATIONAL_TEST_AMOUNT))
        );
        assertEq(abi.decode(withdrawResult, (uint256)), OPERATIONAL_TEST_AMOUNT, "aave-withdraw-return-mismatch");

        assertEq(
            usds.balanceOf(OseroEthereum.OSERO_ALM_PROXY),
            proxyUsdsStart + OPERATIONAL_TEST_AMOUNT,
            "proxy-usds-not-withdrawn"
        );
        uint256 proxySpUsdsAfterWithdraw = spUsds.balanceOf(OseroEthereum.OSERO_ALM_PROXY);
        assertLt(proxySpUsdsAfterWithdraw, proxySpUsdsAfterDeposit, "proxy-spusds-not-decreased");
        assertLe(
            proxySpUsdsAfterWithdraw,
            proxySpUsdsStart + (OPERATIONAL_TEST_AMOUNT - minSpUsdsOut),
            "proxy-spusds-residual-too-high"
        );
        assertEq(rateLimits.getCurrentRateLimit(depositKey), SPARK_USDS_DEPOSIT_MAX, "deposit-limit-not-refilled");
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max, "withdraw-limit-changed");

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_burn, (OPERATIONAL_TEST_AMOUNT)));

        assertEq(usds.balanceOf(OseroEthereum.OSERO_ALM_PROXY), proxyUsdsStart, "proxy-usds-not-restored");
        assertEq(rateLimits.getCurrentRateLimit(mintKey), USDS_MINT_MAX_LIMIT, "mint-limit-not-refilled-after-burn");
        assertEq(rateLimits.getCurrentRateLimit(burnKey), type(uint256).max, "burn-limit-changed");
    }

    function test_ETHEREUM_starGuardExecutionGasWithinBlockLimit() public {
        OseroEthereum_20260716 payload = new OseroEthereum_20260716();

        uint256 gasStart = gasleft();
        _executeSpellViaStarGuard(payload);
        uint256 gasUsed = gasStart - gasleft();

        assertLe(gasUsed, MAX_EXECUTION_GAS, "starguard-execution-gas-too-high");
    }

    function _executeSpellViaStarGuard(OseroEthereum_20260716 payload) internal {
        assertTrue(payload.isExecutable(), "payload-not-executable-before-plot");

        bytes32 codehash = keccak256(address(payload).code);

        vm.prank(MCD_PAUSE_PROXY);
        starGuard.plot(address(payload), codehash);

        (address plottedPayload, bytes32 plottedCodehash, uint256 deadline) = starGuard.spellData();
        assertEq(plottedPayload, address(payload), "starguard-plotted-payload-mismatch");
        assertEq(plottedCodehash, codehash, "starguard-plotted-codehash-mismatch");
        assertEq(deadline, block.timestamp + starGuard.maxDelay(), "starguard-deadline-mismatch");
        assertTrue(starGuard.prob(), "starguard-prob-false");

        vm.prank(PERMISSIONLESS_EXECUTOR);
        address returnedPayload = starGuard.exec();

        assertEq(returnedPayload, address(payload), "starguard-returned-payload-mismatch");
        (plottedPayload,,) = starGuard.spellData();
        assertEq(plottedPayload, address(0), "starguard-spell-data-not-cleared");
        assertEq(
            ISubProxyLike(OseroEthereum.OSERO_PROXY).wards(OseroEthereum.OSERO_STAR_GUARD),
            1,
            "starguard-removed-from-subproxy"
        );
    }

    function _assertSpellPreconditions(bytes32 mintKey, bytes32 burnKey, bytes32 depositKey, bytes32 withdrawKey)
        internal
        view
    {
        assertEq(controller.usds_vault(), address(0), "controller-vault-already-set");
        assertEq(
            IAllocatorVaultLike(OseroEthereum.OSERO_ALLOCATOR_VAULT).wards(OseroEthereum.OSERO_ALM_PROXY),
            0,
            "almproxy-already-vault-ward"
        );
        assertEq(
            usds.allowance(OseroEthereum.OSERO_ALLOCATOR_BUFFER, OseroEthereum.OSERO_ALM_PROXY),
            0,
            "almproxy-already-buffer-spender"
        );
        assertEq(controller.aave_getMaxSlippage(SparkLend.USDS_SPTOKEN), 0, "spark-slippage-already-set");

        _assertZeroRateLimit(mintKey, "mint");
        _assertZeroRateLimit(burnKey, "burn");
        _assertZeroRateLimit(depositKey, "spark-deposit");
        _assertZeroRateLimit(withdrawKey, "spark-withdraw");
    }

    function _assertSpellPostconditions(bytes32 mintKey, bytes32 burnKey, bytes32 depositKey, bytes32 withdrawKey)
        internal
        view
    {
        assertEq(controller.usds_vault(), OseroEthereum.OSERO_ALLOCATOR_VAULT, "controller-vault-not-set");
        assertEq(
            IAllocatorVaultLike(OseroEthereum.OSERO_ALLOCATOR_VAULT).wards(OseroEthereum.OSERO_ALM_PROXY),
            1,
            "almproxy-not-vault-ward"
        );
        assertEq(
            usds.allowance(OseroEthereum.OSERO_ALLOCATOR_BUFFER, OseroEthereum.OSERO_ALM_PROXY),
            type(uint256).max,
            "almproxy-buffer-allowance-not-max"
        );
        assertEq(
            controller.aave_getMaxSlippage(SparkLend.USDS_SPTOKEN), SPARK_USDS_MAX_SLIPPAGE, "spark-slippage-not-set"
        );

        _assertRateLimit(mintKey, USDS_MINT_MAX_LIMIT, USDS_MINT_SLOPE, "mint");
        _assertUnlimitedRateLimit(burnKey, "burn");
        _assertRateLimit(depositKey, SPARK_USDS_DEPOSIT_MAX, SPARK_USDS_DEPOSIT_SLOPE, "spark-deposit");
        _assertUnlimitedRateLimit(withdrawKey, "spark-withdraw");
    }

    function _captureSpellState(bytes32 mintKey, bytes32 burnKey, bytes32 depositKey, bytes32 withdrawKey)
        internal
        view
        returns (SpellState memory state)
    {
        state.usdsVault = controller.usds_vault();
        state.almProxyVaultWard =
            IAllocatorVaultLike(OseroEthereum.OSERO_ALLOCATOR_VAULT).wards(OseroEthereum.OSERO_ALM_PROXY);
        state.almProxyBufferAllowance =
            usds.allowance(OseroEthereum.OSERO_ALLOCATOR_BUFFER, OseroEthereum.OSERO_ALM_PROXY);
        state.sparkUsdsMaxSlippage = controller.aave_getMaxSlippage(SparkLend.USDS_SPTOKEN);
        state.mintData = rateLimits.getRateLimitData(mintKey);
        state.burnData = rateLimits.getRateLimitData(burnKey);
        state.depositData = rateLimits.getRateLimitData(depositKey);
        state.withdrawData = rateLimits.getRateLimitData(withdrawKey);
    }

    function _assertSpellStateUnchanged(
        SpellState memory beforeState,
        SpellState memory afterState,
        string memory label
    ) internal pure {
        assertEq(afterState.usdsVault, beforeState.usdsVault, string.concat(label, "-usds-vault-changed"));
        assertEq(
            afterState.almProxyVaultWard,
            beforeState.almProxyVaultWard,
            string.concat(label, "-almproxy-vault-ward-changed")
        );
        assertEq(
            afterState.almProxyBufferAllowance,
            beforeState.almProxyBufferAllowance,
            string.concat(label, "-almproxy-buffer-allowance-changed")
        );
        assertEq(
            afterState.sparkUsdsMaxSlippage,
            beforeState.sparkUsdsMaxSlippage,
            string.concat(label, "-spark-slippage-changed")
        );
        _assertRateLimitDataUnchanged(beforeState.mintData, afterState.mintData, string.concat(label, "-mint"));
        _assertRateLimitDataUnchanged(beforeState.burnData, afterState.burnData, string.concat(label, "-burn"));
        _assertRateLimitDataUnchanged(
            beforeState.depositData, afterState.depositData, string.concat(label, "-spark-deposit")
        );
        _assertRateLimitDataUnchanged(
            beforeState.withdrawData, afterState.withdrawData, string.concat(label, "-spark-withdraw")
        );
    }

    function _assertRateLimitDataUnchanged(
        IRateLimitsLike.RateLimitData memory beforeData,
        IRateLimitsLike.RateLimitData memory afterData,
        string memory label
    ) internal pure {
        assertEq(afterData.maxAmount, beforeData.maxAmount, string.concat(label, "-max-amount-changed"));
        assertEq(afterData.slope, beforeData.slope, string.concat(label, "-slope-changed"));
        assertEq(afterData.lastAmount, beforeData.lastAmount, string.concat(label, "-last-amount-changed"));
        assertEq(afterData.lastUpdated, beforeData.lastUpdated, string.concat(label, "-last-updated-changed"));
    }

    function _callAsOseroActor(bytes memory data) internal returns (bytes memory result) {
        IAdministeredAgentLike agent = IAdministeredAgentLike(OseroEthereum.OSERO_ADMINISTERED_AGENT);
        assertTrue(agent.getIsActor(OseroEthereum.OSERO_OPERATOR), "osero-operator-not-agent-actor");

        vm.prank(OseroEthereum.OSERO_OPERATOR);
        result = agent.call(OseroEthereum.OSERO_CONTROLLER, data);
    }

    function _assertContract(address target, string memory label) internal view {
        assertGt(target.code.length, 0, string.concat(label, "-not-deployed"));
    }

    function _assertDispatch(bytes4 callSelector, address expectedFacet, string memory label) internal view {
        PauDispatch memory dispatch = controller.getDispatch(callSelector);
        assertEq(dispatch.facet, expectedFacet, string.concat(label, "-facet-mismatch"));
        assertTrue(dispatch.delegateSelector != bytes4(0), string.concat(label, "-delegate-selector-not-set"));
    }

    function _assertOnlyExpectedControllerIntegrations() internal view {
        PauIntegration[] memory integrations = controller.integrations();
        assertEq(integrations.length, 2, "unexpected-controller-integration-count");

        bool sawUsds;
        bool sawAave;

        for (uint256 i = 0; i < integrations.length; ++i) {
            bytes32 id = integrations[i].id;

            if (id == EXPECTED_USDS_FACET_INTEGRATION_ID) {
                assertFalse(sawUsds, "duplicate-usds-integration");
                sawUsds = true;
                assertEq(integrations[i].config.facet, SkyPau.USDS_FACET, "usds-integration-facet");
                assertEq(integrations[i].config.wires.length, 8, "usds-integration-wire-count");
            } else if (id == EXPECTED_AAVE_FACET_INTEGRATION_ID) {
                assertFalse(sawAave, "duplicate-aave-integration");
                sawAave = true;
                assertEq(integrations[i].config.facet, SkyPau.AAVE_FACET, "aave-integration-facet");
                assertEq(integrations[i].config.wires.length, 7, "aave-integration-wire-count");
            } else {
                assertTrue(false, "unexpected-controller-integration");
            }
        }

        assertTrue(sawUsds, "missing-usds-integration");
        assertTrue(sawAave, "missing-aave-integration");
    }

    function _assertRateLimit(bytes32 key, uint256 maxAmount, uint256 slope, string memory label) internal view {
        IRateLimitsLike.RateLimitData memory data = rateLimits.getRateLimitData(key);
        assertEq(data.maxAmount, maxAmount, string.concat(label, "-max-amount"));
        assertEq(data.slope, slope, string.concat(label, "-slope"));
        assertEq(data.lastAmount, maxAmount, string.concat(label, "-last-amount"));
        assertEq(data.lastUpdated, block.timestamp, string.concat(label, "-last-updated"));
        assertEq(rateLimits.getCurrentRateLimit(key), maxAmount, string.concat(label, "-current-limit"));
    }

    function _assertUnlimitedRateLimit(bytes32 key, string memory label) internal view {
        IRateLimitsLike.RateLimitData memory data = rateLimits.getRateLimitData(key);
        assertEq(data.maxAmount, type(uint256).max, string.concat(label, "-unlimited-max-amount"));
        assertEq(data.slope, 0, string.concat(label, "-unlimited-slope"));
        assertEq(data.lastAmount, type(uint256).max, string.concat(label, "-unlimited-last-amount"));
        assertEq(data.lastUpdated, block.timestamp, string.concat(label, "-unlimited-last-updated"));
        assertEq(
            rateLimits.getCurrentRateLimit(key), type(uint256).max, string.concat(label, "-unlimited-current-limit")
        );
    }

    function _assertZeroRateLimit(bytes32 key, string memory label) internal view {
        IRateLimitsLike.RateLimitData memory data = rateLimits.getRateLimitData(key);
        assertEq(data.maxAmount, 0, string.concat(label, "-zero-max-amount"));
        assertEq(data.slope, 0, string.concat(label, "-zero-slope"));
        assertEq(data.lastAmount, 0, string.concat(label, "-zero-last-amount"));
        assertEq(data.lastUpdated, 0, string.concat(label, "-zero-last-updated"));
    }
}
