// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {SparkLend} from "spark-address-registry/SparkLend.sol";

import {
    IALMProxyLike,
    IATokenLike,
    IAccessControlsLike,
    IAdministeredAgentLike,
    IAllocatorBufferLike,
    IAllocatorVaultLike,
    IAutoLineLike,
    ILitePsmLike,
    IOseroPauControllerLike,
    ISpellLike,
    ISubProxyLike,
    IVatLike
} from "../test-harness/OseroTestBase.sol";
import {CommonPauSpellTests, ExpectedIntegration} from "../test-harness/CommonPauSpellTests.sol";

import {OseroEthereum_20260716} from "./OseroEthereum_20260716.sol";

contract OseroEthereum_20260716_Test is CommonPauSpellTests {
    // The spell was deployed at block 25,496,131; fork there so the deployed payload exists on the
    // fork. The PAU pre-state asserted below is unchanged since the forum readbacks at block 25,431,261.
    uint256 internal constant MAINNET_FORK_BLOCK = 25_496_131;

    // The on-chain 2026-07-16 payload; all tests, including the bytecode match, run against it.
    address internal constant DEPLOYED_PAYLOAD = 0x5D9311fcDda62c08EB9F1115Ca804881a6660445;

    // SparkLend addresses from the spark-address-registry. Independent verification source:
    // the approved technical-scope forum post,
    // https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-osero-for-upcoming-spell/28023.
    address internal constant SPARKLEND_POOL = SparkLend.POOL;
    address internal constant SPARKLEND_USDS_SPTOKEN = SparkLend.USDS_SPTOKEN;

    bytes32 internal constant USDS_FACET_INTEGRATION_ID = "USDS_FACET";
    bytes32 internal constant AAVE_FACET_INTEGRATION_ID = "AAVE_FACET";

    // Rate-limit keys derived as in the diamond-pau USDSFacet/AaveFacet the controller dispatches to:
    // https://github.com/sky-ecosystem/diamond-pau/tree/5c5ad6ae174bf467081ca82342ced2bd42a5c732/src/facets
    bytes32 internal constant USDS_MINT_RATE_LIMIT_KEY = keccak256("LIMIT_USDS_MINT");
    bytes32 internal constant USDS_BURN_RATE_LIMIT_KEY = keccak256("LIMIT_USDS_BURN");
    bytes32 internal constant SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_AAVE_DEPOSIT"), USDS, SPARKLEND_POOL, SPARKLEND_USDS_SPTOKEN));
    bytes32 internal constant SPARKLEND_USDS_WITHDRAW_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_AAVE_WITHDRAW"), SPARKLEND_POOL, SPARKLEND_USDS_SPTOKEN));

    uint256 internal constant USDS_MINT_MAX_LIMIT = 5_000_000e18;
    uint256 internal constant USDS_MINT_SLOPE = uint256(5_000_000e18) / 1 days;
    uint256 internal constant SPARKLEND_USDS_MAX_SLIPPAGE = 0.9999e18;
    uint256 internal constant SPARKLEND_USDS_DEPOSIT_MAX = 5_000_000e18;
    uint256 internal constant SPARKLEND_USDS_DEPOSIT_SLOPE = uint256(5_000_000e18) / 1 days;

    uint256 internal constant OPERATIONAL_TEST_AMOUNT = 100_000e18;
    // Short enough that the recovered amount stays below OPERATIONAL_TEST_AMOUNT (no max cap yet).
    uint256 internal constant PARTIAL_RECOVERY_TIME = 20 minutes;

    // ALLOCATOR-PRYSM-A DC-IAM target parameters from the coordinated Sky Core spell
    // (AutoLine values are denominated in rad): maxLine = 5,000,000 USDS, gap = 1,000,000 USDS.
    uint256 internal constant RAD = 1e45;
    uint256 internal constant ALLOCATOR_MAX_LINE = 5_000_000 * RAD;
    uint256 internal constant ALLOCATOR_GAP = 1_000_000 * RAD;
    uint256 internal constant ALLOCATOR_TTL = 1 days;

    IERC20 internal constant spUsds = IERC20(SPARKLEND_USDS_SPTOKEN);

    event ActorRemoved(address indexed account, address indexed caller);

    constructor() {
        spellId = "20260716";
    }

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), MAINNET_FORK_BLOCK);

        _simulateCoordinatedSkyCoreSpell();
        _setupPayload(DEPLOYED_PAYLOAD);
    }

    // The coordinated Sky Core action items are pending and planned to be included in the
    // 2026-07-16 Sky Core spell, so they are not yet on-chain at `MAINNET_FORK_BLOCK`. Replay the
    // two Osero-relevant actions (LitePSM whitelisting of the ALMProxy and the ALLOCATOR-PRYSM-A
    // DC-IAM parameters) by pranking the MCD Pause Proxy, which is ward on both targets.
    function _simulateCoordinatedSkyCoreSpell() internal {
        vm.startPrank(MCD_PAUSE_PROXY);

        // Whitelist the Osero ALMProxy on the LitePSM for USDC swaps.
        ILitePsmLike(MCD_LITE_PSM_USDC_A).kiss(OSERO_ALM_PROXY);

        // Set the ALLOCATOR-PRYSM-A DC-IAM target parameters
        // (BEFORE: maxLine 10M rad, gap 10M rad, the initial PAU deployment values).
        IAutoLineLike(MCD_IAM_AUTO_LINE).setIlk(OSERO_ILK, ALLOCATOR_MAX_LINE, ALLOCATOR_GAP, ALLOCATOR_TTL);

        vm.stopPrank();

        // Permissionless keeper action: rebases vat.ilks(ilk).line to min(debt + gap, maxLine).
        IAutoLineLike(MCD_IAM_AUTO_LINE).exec(OSERO_ILK);
    }

    function test_ETHEREUM_pauSystemPreconfiguration() public view {
        _assertContract(OSERO_PROXY, "osero-proxy");
        _assertContract(OSERO_STAR_GUARD, "osero-star-guard");
        _assertContract(OSERO_ACCESS_CONTROLS, "osero-access-controls");
        _assertContract(OSERO_ALM_PROXY, "osero-alm-proxy");
        _assertContract(OSERO_RATE_LIMITS, "osero-rate-limits");
        _assertContract(OSERO_CONTROLLER, "osero-controller");
        _assertContract(OSERO_ADMINISTERED_AGENT, "osero-administered-agent");
        _assertContract(OSERO_ALLOCATOR_VAULT, "osero-allocator-vault");
        _assertContract(OSERO_ALLOCATOR_BUFFER, "osero-allocator-buffer");
        _assertContract(SKY_PAU_BEACON, "sky-pau-beacon");
        _assertContract(SKY_PAU_USDS_FACET, "sky-pau-usds-facet");
        _assertContract(SKY_PAU_AAVE_FACET, "sky-pau-aave-facet");
        _assertContract(USDS, "usds");
        _assertContract(SPARKLEND_POOL, "spark-pool");
        _assertContract(SPARKLEND_USDS_SPTOKEN, "spark-usds-sptoken");

        assertEq(starGuard.subProxy(), OSERO_PROXY, "starguard-subproxy-mismatch");
        assertEq(starGuard.wards(MCD_PAUSE_PROXY), 1, "pause-proxy-not-starguard-ward");
        assertEq(ISubProxyLike(OSERO_PROXY).wards(OSERO_STAR_GUARD), 1, "starguard-not-subproxy-ward");
        assertEq(ISubProxyLike(OSERO_PROXY).wards(MCD_PAUSE_PROXY), 1, "pause-proxy-not-subproxy-ward");
        assertGt(starGuard.maxDelay(), 0, "starguard-max-delay-not-set");

        assertEq(controller.accessControls(), OSERO_ACCESS_CONTROLS, "controller-access-controls-mismatch");
        assertEq(controller.beacon(), SKY_PAU_BEACON, "controller-beacon-mismatch");
        assertEq(controller.proxy(), OSERO_ALM_PROXY, "controller-proxy-mismatch");
        assertEq(controller.rateLimits(), OSERO_RATE_LIMITS, "controller-rate-limits-mismatch");

        // The shared Beacon (source of the wired facet configs) is administered by the Pause Proxy only.
        IAccessControlsLike beacon = IAccessControlsLike(SKY_PAU_BEACON);
        assertTrue(beacon.hasRole(DEFAULT_ADMIN_ROLE, MCD_PAUSE_PROXY), "pause-proxy-missing-beacon-admin");
        assertEq(beacon.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1, "beacon-admin-count");

        // The USDSFacet's immutable USDS reference resolves to the Sky core USDS token.
        assertEq(controller.usds_usds(), USDS, "usds-facet-usds-mismatch");

        _assertDispatch(IOseroPauControllerLike.usds_setVault.selector, SKY_PAU_USDS_FACET, "usds-set-vault");
        _assertDispatch(IOseroPauControllerLike.usds_vault.selector, SKY_PAU_USDS_FACET, "usds-vault");
        _assertDispatch(IOseroPauControllerLike.usds_mint.selector, SKY_PAU_USDS_FACET, "usds-mint");
        _assertDispatch(IOseroPauControllerLike.usds_burn.selector, SKY_PAU_USDS_FACET, "usds-burn");
        _assertDispatch(IOseroPauControllerLike.usds_mintRateLimitKey.selector, SKY_PAU_USDS_FACET, "usds-mint-key");
        _assertDispatch(IOseroPauControllerLike.usds_burnRateLimitKey.selector, SKY_PAU_USDS_FACET, "usds-burn-key");

        _assertDispatch(IOseroPauControllerLike.aave_setMaxSlippage.selector, SKY_PAU_AAVE_FACET, "aave-set-slippage");
        _assertDispatch(IOseroPauControllerLike.aave_getMaxSlippage.selector, SKY_PAU_AAVE_FACET, "aave-get-slippage");
        _assertDispatch(
            IOseroPauControllerLike.aave_getDepositRateLimitKey.selector, SKY_PAU_AAVE_FACET, "aave-deposit-key"
        );
        _assertDispatch(
            IOseroPauControllerLike.aave_getWithdrawRateLimitKey.selector, SKY_PAU_AAVE_FACET, "aave-withdraw-key"
        );
        _assertDispatch(IOseroPauControllerLike.aave_deposit.selector, SKY_PAU_AAVE_FACET, "aave-deposit");
        _assertDispatch(IOseroPauControllerLike.aave_withdraw.selector, SKY_PAU_AAVE_FACET, "aave-withdraw");

        IAccessControlsLike accessControls = IAccessControlsLike(OSERO_ACCESS_CONTROLS);
        IAdministeredAgentLike agent = IAdministeredAgentLike(OSERO_ADMINISTERED_AGENT);

        assertTrue(accessControls.hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY), "subproxy-missing-access-admin");
        assertTrue(accessControls.hasRole(ALLOCATOR_ROLE, OSERO_ADMINISTERED_AGENT), "agent-missing-allocator-role");
        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1, "access-admin-count");
        assertEq(accessControls.getRoleMemberCount(ALLOCATOR_ROLE), 1, "allocator-role-count");

        IALMProxyLike almProxy = IALMProxyLike(OSERO_ALM_PROXY);
        assertTrue(almProxy.hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY), "subproxy-missing-almproxy-admin");
        assertFalse(
            almProxy.hasRole(DEFAULT_ADMIN_ROLE, SKY_PAU_DEFAULT_PAU_ASSEMBLER), "assembler-retains-almproxy-admin"
        );
        assertTrue(almProxy.hasRole(CONTROLLER, OSERO_CONTROLLER), "controller-missing-almproxy-role");
        assertTrue(rateLimits.hasRole(CONTROLLER, OSERO_CONTROLLER), "controller-missing-ratelimits-role");
        assertTrue(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY), "subproxy-missing-ratelimits-admin");
        assertFalse(
            rateLimits.hasRole(DEFAULT_ADMIN_ROLE, SKY_PAU_DEFAULT_PAU_ASSEMBLER), "assembler-retains-ratelimits-admin"
        );

        assertEq(agent.adminCount(), 1, "agent-admin-count");
        assertEq(agent.actorCount(), 2, "agent-actor-count");
        assertEq(agent.revokerCount(), 1, "agent-revoker-count");
        assertEq(agent.grantorCount(), 0, "agent-grantor-count");
        assertEq(agent.getAdmin(0), OSERO_PROXY, "agent-admin-0");
        assertTrue(agent.getIsActor(OSERO_OPERATOR), "osero-operator-not-agent-actor");
        assertTrue(agent.getIsActor(SOTER_OPERATOR), "soter-operator-not-agent-actor");
        assertEq(agent.getRevoker(0), SOTER_FREEZER, "agent-revoker-0");

        IAllocatorVaultLike vault = IAllocatorVaultLike(OSERO_ALLOCATOR_VAULT);
        assertEq(vault.buffer(), OSERO_ALLOCATOR_BUFFER, "vault-buffer-mismatch");
        assertEq(vault.ilk(), OSERO_ILK, "vault-ilk-mismatch");
        assertEq(vault.wards(OSERO_PROXY), 1, "subproxy-not-vault-ward");
        assertEq(IAllocatorBufferLike(OSERO_ALLOCATOR_BUFFER).wards(OSERO_PROXY), 1, "subproxy-not-buffer-ward");

        assertEq(IATokenLike(SPARKLEND_USDS_SPTOKEN).POOL(), SPARKLEND_POOL, "sptoken-pool-mismatch");
        assertEq(IATokenLike(SPARKLEND_USDS_SPTOKEN).UNDERLYING_ASSET_ADDRESS(), USDS, "sptoken-underlying-mismatch");
    }

    function test_ETHEREUM_coordinatedCoreSpellSimulationMatchesTargetParameters() public view {
        assertEq(ILitePsmLike(MCD_LITE_PSM_USDC_A).bud(OSERO_ALM_PROXY), 1, "almproxy-not-litepsm-bud");

        (uint256 maxLine, uint256 gap, uint48 ttl,,) = IAutoLineLike(MCD_IAM_AUTO_LINE).ilks(OSERO_ILK);
        assertEq(maxLine, ALLOCATOR_MAX_LINE, "autoline-max-line-mismatch");
        assertEq(gap, ALLOCATOR_GAP, "autoline-gap-mismatch");
        assertEq(ttl, ALLOCATOR_TTL, "autoline-ttl-mismatch");

        // With zero ilk debt at the fork block, AutoLine.exec() leaves the vat debt ceiling at the gap.
        (,,, uint256 vatLine,) = IVatLike(MCD_VAT).ilks(OSERO_ILK);
        assertEq(vatLine, ALLOCATOR_GAP, "vat-line-not-rebased-to-gap");
    }

    function test_ETHEREUM_scopeKeysAndEncodedParametersMatchTechnicalScope() public view {
        assertEq(controller.usds_mintRateLimitKey(), USDS_MINT_RATE_LIMIT_KEY, "mint-key-mismatch");
        assertEq(controller.usds_burnRateLimitKey(), USDS_BURN_RATE_LIMIT_KEY, "burn-key-mismatch");
        assertEq(
            controller.aave_getDepositRateLimitKey(SPARKLEND_USDS_SPTOKEN, SPARKLEND_POOL, USDS),
            SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY,
            "spark-deposit-key-mismatch"
        );
        assertEq(
            controller.aave_getWithdrawRateLimitKey(SPARKLEND_USDS_SPTOKEN, SPARKLEND_POOL),
            SPARKLEND_USDS_WITHDRAW_RATE_LIMIT_KEY,
            "spark-withdraw-key-mismatch"
        );

        OseroEthereum_20260716 spell = OseroEthereum_20260716(payload);
        assertEq(spell.USDS_MINT_MAX_LIMIT(), USDS_MINT_MAX_LIMIT, "payload-mint-max-amount");
        assertEq(spell.USDS_MINT_SLOPE(), USDS_MINT_SLOPE, "payload-mint-slope");
        assertEq(spell.SPARKLEND_USDS_DEPOSIT_MAX(), SPARKLEND_USDS_DEPOSIT_MAX, "payload-deposit-max-amount");
        assertEq(spell.SPARKLEND_USDS_DEPOSIT_SLOPE(), SPARKLEND_USDS_DEPOSIT_SLOPE, "payload-deposit-slope");
        assertEq(spell.SPARKLEND_USDS_MAX_SLIPPAGE(), SPARKLEND_USDS_MAX_SLIPPAGE, "payload-spark-slippage");
    }

    function test_ETHEREUM_spellExecutionConfiguresAllActions() public {
        // Preconditions: the PAU system is assembled but not yet hooked up to the allocator instance.
        assertEq(controller.usds_vault(), address(0), "controller-vault-already-set");
        assertEq(IAllocatorVaultLike(OSERO_ALLOCATOR_VAULT).wards(OSERO_ALM_PROXY), 0, "almproxy-already-vault-ward");
        assertEq(usds.allowance(OSERO_ALLOCATOR_BUFFER, OSERO_ALM_PROXY), 0, "almproxy-already-buffer-spender");
        assertEq(controller.aave_getMaxSlippage(SPARKLEND_USDS_SPTOKEN), 0, "spark-slippage-already-set");

        _assertUnsetRateLimit(USDS_MINT_RATE_LIMIT_KEY, "mint");
        _assertUnsetRateLimit(USDS_BURN_RATE_LIMIT_KEY, "burn");
        _assertUnsetRateLimit(SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY, "spark-deposit");
        _assertUnsetRateLimit(SPARKLEND_USDS_WITHDRAW_RATE_LIMIT_KEY, "spark-withdraw");

        _executeSpellViaStarGuard(payload);

        // Postconditions: every spell action is live.
        assertEq(controller.usds_vault(), OSERO_ALLOCATOR_VAULT, "controller-vault-not-set");
        assertEq(IAllocatorVaultLike(OSERO_ALLOCATOR_VAULT).wards(OSERO_ALM_PROXY), 1, "almproxy-not-vault-ward");
        assertEq(
            usds.allowance(OSERO_ALLOCATOR_BUFFER, OSERO_ALM_PROXY),
            type(uint256).max,
            "almproxy-buffer-allowance-not-max"
        );
        assertEq(
            controller.aave_getMaxSlippage(SPARKLEND_USDS_SPTOKEN),
            SPARKLEND_USDS_MAX_SLIPPAGE,
            "spark-slippage-not-set"
        );

        _assertRateLimit(USDS_MINT_RATE_LIMIT_KEY, USDS_MINT_MAX_LIMIT, USDS_MINT_SLOPE, "mint");
        _assertUnlimitedRateLimit(USDS_BURN_RATE_LIMIT_KEY, "burn");
        _assertRateLimit(
            SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY,
            SPARKLEND_USDS_DEPOSIT_MAX,
            SPARKLEND_USDS_DEPOSIT_SLOPE,
            "spark-deposit"
        );
        _assertUnlimitedRateLimit(SPARKLEND_USDS_WITHDRAW_RATE_LIMIT_KEY, "spark-withdraw");
    }

    function test_ETHEREUM_directPayloadExecutionRevertsWithoutSubProxyAuthority() public {
        // The first spell action calls the controller, which requires DEFAULT_ADMIN_ROLE on the
        // Osero AccessControls — held by the SubProxy only, so a direct execute() must revert.
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", payload, DEFAULT_ADMIN_ROLE)
        );
        ISpellLike(payload).execute();
    }

    function test_ETHEREUM_usdsMintBurnOperationalThroughAdministeredAgent() public {
        _executeSpellViaStarGuard(payload);

        uint256 proxyUsdsStart = usds.balanceOf(OSERO_ALM_PROXY);

        assertEq(rateLimits.getCurrentRateLimit(USDS_MINT_RATE_LIMIT_KEY), USDS_MINT_MAX_LIMIT, "mint-limit-not-full");
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_BURN_RATE_LIMIT_KEY), type(uint256).max, "burn-limit-not-unlimited"
        );

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_mint, (OPERATIONAL_TEST_AMOUNT)));

        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart + OPERATIONAL_TEST_AMOUNT, "proxy-usds-not-minted");
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_MINT_RATE_LIMIT_KEY),
            USDS_MINT_MAX_LIMIT - OPERATIONAL_TEST_AMOUNT,
            "mint-limit-not-decreased"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_BURN_RATE_LIMIT_KEY), type(uint256).max, "burn-limit-changed-after-mint"
        );

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_burn, (OPERATIONAL_TEST_AMOUNT)));

        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart, "proxy-usds-not-burned");
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_MINT_RATE_LIMIT_KEY), USDS_MINT_MAX_LIMIT, "mint-limit-not-refilled"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_BURN_RATE_LIMIT_KEY),
            type(uint256).max,
            "burn-limit-not-still-unlimited"
        );
    }

    function test_ETHEREUM_usdsMintRateLimitRejectsOversizedMint() public {
        _executeSpellViaStarGuard(payload);

        _expectCallAsOseroActorRevert(
            bytes("RateLimits/rate-limit-exceeded"),
            abi.encodeCall(IOseroPauControllerLike.usds_mint, (USDS_MINT_MAX_LIMIT + 1))
        );
    }

    function test_ETHEREUM_usdsMintRateLimitRecoversOverTime() public {
        _executeSpellViaStarGuard(payload);

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_mint, (OPERATIONAL_TEST_AMOUNT)));
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_MINT_RATE_LIMIT_KEY),
            USDS_MINT_MAX_LIMIT - OPERATIONAL_TEST_AMOUNT,
            "mint-limit-not-decreased"
        );

        vm.warp(block.timestamp + PARTIAL_RECOVERY_TIME);
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_MINT_RATE_LIMIT_KEY),
            USDS_MINT_MAX_LIMIT - OPERATIONAL_TEST_AMOUNT + USDS_MINT_SLOPE * PARTIAL_RECOVERY_TIME,
            "mint-limit-not-recovering-at-slope"
        );

        vm.warp(block.timestamp + 1 days);
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_MINT_RATE_LIMIT_KEY),
            USDS_MINT_MAX_LIMIT,
            "mint-limit-not-capped-at-max"
        );
    }

    function test_ETHEREUM_sparkUsdsDepositWithdrawOperationalThroughAdministeredAgent() public {
        _executeSpellViaStarGuard(payload);

        uint256 proxyUsdsStart = usds.balanceOf(OSERO_ALM_PROXY);
        uint256 proxySpUsdsStart = spUsds.balanceOf(OSERO_ALM_PROXY);
        assertEq(
            rateLimits.getCurrentRateLimit(SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY),
            SPARKLEND_USDS_DEPOSIT_MAX,
            "deposit-limit-not-full"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(SPARKLEND_USDS_WITHDRAW_RATE_LIMIT_KEY),
            type(uint256).max,
            "withdraw-limit-not-unlimited-before-deposit"
        );

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_mint, (OPERATIONAL_TEST_AMOUNT)));
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart + OPERATIONAL_TEST_AMOUNT, "proxy-usds-not-minted");

        _callAsOseroActor(
            abi.encodeCall(IOseroPauControllerLike.aave_deposit, (SPARKLEND_USDS_SPTOKEN, OPERATIONAL_TEST_AMOUNT))
        );

        uint256 minSpUsdsOut = OPERATIONAL_TEST_AMOUNT * SPARKLEND_USDS_MAX_SLIPPAGE / 1e18;
        uint256 proxySpUsdsAfterDeposit = spUsds.balanceOf(OSERO_ALM_PROXY);
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart, "proxy-usds-not-deposited");
        assertGe(proxySpUsdsAfterDeposit - proxySpUsdsStart, minSpUsdsOut, "proxy-spusds-received-too-low");
        assertEq(usds.allowance(OSERO_ALM_PROXY, SPARKLEND_POOL), 0, "spark-pool-usds-approval-not-cleared");
        assertEq(
            rateLimits.getCurrentRateLimit(SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY),
            SPARKLEND_USDS_DEPOSIT_MAX - OPERATIONAL_TEST_AMOUNT,
            "deposit-limit-not-decreased"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(SPARKLEND_USDS_WITHDRAW_RATE_LIMIT_KEY),
            type(uint256).max,
            "withdraw-limit-not-unlimited"
        );

        bytes memory withdrawResult = _callAsOseroActor(
            abi.encodeCall(IOseroPauControllerLike.aave_withdraw, (SPARKLEND_USDS_SPTOKEN, OPERATIONAL_TEST_AMOUNT))
        );
        assertEq(abi.decode(withdrawResult, (uint256)), OPERATIONAL_TEST_AMOUNT, "aave-withdraw-return-mismatch");

        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart + OPERATIONAL_TEST_AMOUNT, "proxy-usds-not-withdrawn");
        uint256 proxySpUsdsAfterWithdraw = spUsds.balanceOf(OSERO_ALM_PROXY);
        assertLt(proxySpUsdsAfterWithdraw, proxySpUsdsAfterDeposit, "proxy-spusds-not-decreased");
        assertLe(
            proxySpUsdsAfterWithdraw,
            proxySpUsdsStart + (OPERATIONAL_TEST_AMOUNT - minSpUsdsOut),
            "proxy-spusds-residual-too-high"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY),
            SPARKLEND_USDS_DEPOSIT_MAX,
            "deposit-limit-not-refilled"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(SPARKLEND_USDS_WITHDRAW_RATE_LIMIT_KEY),
            type(uint256).max,
            "withdraw-limit-changed"
        );

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_burn, (OPERATIONAL_TEST_AMOUNT)));

        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart, "proxy-usds-not-restored");
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_MINT_RATE_LIMIT_KEY),
            USDS_MINT_MAX_LIMIT,
            "mint-limit-not-refilled-after-burn"
        );
        assertEq(rateLimits.getCurrentRateLimit(USDS_BURN_RATE_LIMIT_KEY), type(uint256).max, "burn-limit-changed");
    }

    function test_ETHEREUM_sparkUsdsDepositRateLimitRejectsOversizedDeposit() public {
        _executeSpellViaStarGuard(payload);

        deal(USDS, OSERO_ALM_PROXY, SPARKLEND_USDS_DEPOSIT_MAX + 1);
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), SPARKLEND_USDS_DEPOSIT_MAX + 1, "proxy-usds-deal-failed");

        _expectCallAsOseroActorRevert(
            bytes("RateLimits/rate-limit-exceeded"),
            abi.encodeCall(
                IOseroPauControllerLike.aave_deposit, (SPARKLEND_USDS_SPTOKEN, SPARKLEND_USDS_DEPOSIT_MAX + 1)
            )
        );
    }

    function test_ETHEREUM_sparkUsdsDepositRateLimitRecoversOverTime() public {
        _executeSpellViaStarGuard(payload);

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_mint, (OPERATIONAL_TEST_AMOUNT)));
        _callAsOseroActor(
            abi.encodeCall(IOseroPauControllerLike.aave_deposit, (SPARKLEND_USDS_SPTOKEN, OPERATIONAL_TEST_AMOUNT))
        );
        assertEq(
            rateLimits.getCurrentRateLimit(SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY),
            SPARKLEND_USDS_DEPOSIT_MAX - OPERATIONAL_TEST_AMOUNT,
            "deposit-limit-not-decreased"
        );

        vm.warp(block.timestamp + PARTIAL_RECOVERY_TIME);
        assertEq(
            rateLimits.getCurrentRateLimit(SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY),
            SPARKLEND_USDS_DEPOSIT_MAX - OPERATIONAL_TEST_AMOUNT + SPARKLEND_USDS_DEPOSIT_SLOPE * PARTIAL_RECOVERY_TIME,
            "deposit-limit-not-recovering-at-slope"
        );

        vm.warp(block.timestamp + 1 days);
        assertEq(
            rateLimits.getCurrentRateLimit(SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY),
            SPARKLEND_USDS_DEPOSIT_MAX,
            "deposit-limit-not-capped-at-max"
        );
    }

    function test_ETHEREUM_revokerCanRemoveActorAndBlockFurtherCalls() public {
        _executeSpellViaStarGuard(payload);

        IAdministeredAgentLike agent = IAdministeredAgentLike(OSERO_ADMINISTERED_AGENT);
        uint256 actorCountBefore = agent.actorCount();

        // The actor is operational before the revocation.
        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_mint, (OPERATIONAL_TEST_AMOUNT)));

        // The SOTER freezer is the agent's emergency revoker and removes the Osero operator.
        assertEq(agent.getRevoker(0), SOTER_FREEZER, "agent-revoker-0");
        vm.expectEmit(OSERO_ADMINISTERED_AGENT);
        emit ActorRemoved(OSERO_OPERATOR, SOTER_FREEZER);
        vm.prank(SOTER_FREEZER);
        agent.removeActor(OSERO_OPERATOR);

        assertFalse(agent.getIsActor(OSERO_OPERATOR), "actor-not-removed");
        assertEq(agent.actorCount(), actorCountBefore - 1, "actor-count-not-decreased");

        // The removed actor can no longer execute calls through the agent.
        vm.prank(OSERO_OPERATOR);
        vm.expectRevert(abi.encodeWithSignature("NotActor()"));
        // Lint false positive: this is the agent's `call(address,bytes)` interface function, not
        // `address.call`, so there is no success flag to check — it reverts on failure instead.
        // forge-lint: disable-next-line(unchecked-call)
        agent.call(OSERO_CONTROLLER, abi.encodeCall(IOseroPauControllerLike.usds_mint, (OPERATIONAL_TEST_AMOUNT)));
    }

    /// @dev Config for the inherited `test_ETHEREUM_onlyExpectedControllerIntegrations`; update
    ///      only when the controller's integration config changes (e.g. a facet is onboarded).
    function _expectedControllerIntegrations() internal pure override returns (ExpectedIntegration[] memory expected) {
        expected = new ExpectedIntegration[](2);
        expected[0] = ExpectedIntegration(USDS_FACET_INTEGRATION_ID, SKY_PAU_USDS_FACET, 8, "usds");
        expected[1] = ExpectedIntegration(AAVE_FACET_INTEGRATION_ID, SKY_PAU_AAVE_FACET, 7, "aave");
    }
}
