// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";

import {Ethereum as SparkEthereum} from "spark-address-registry/Ethereum.sol";
import {SparkLend} from "spark-address-registry/SparkLend.sol";

import {
    IAccessControlsLike,
    IAdministeredAgentLike,
    IALMProxyLike,
    IBeaconLike,
    ILitePsmLike,
    IOseroPauControllerLike,
    IRateLimitsLike,
    ISpellLike,
    ISubProxyLike,
    PauConfig,
    PauDispatch,
    PauWire
} from "../test-harness/OseroTestBase.sol";
import {CommonPauSpellTests, ExpectedIntegration} from "../test-harness/CommonPauSpellTests.sol";

import {OseroEthereum_20261008} from "./OseroEthereum_20261008.sol";

interface IVaultV2Like {
    function asset() external view returns (address);
    function decimals() external view returns (uint8);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function balanceOf(address account) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function owner() external view returns (address);
    function curator() external view returns (address);
    function isAllocator(address account) external view returns (bool);
    function isSentinel(address account) external view returns (bool);
    function liquidityAdapter() external view returns (address);
    function adaptersLength() external view returns (uint256);
    function adapters(uint256 index) external view returns (address);
    function receiveSharesGate() external view returns (address);
    function sendAssetsGate() external view returns (address);
    function sendSharesGate() external view returns (address);
    function receiveAssetsGate() external view returns (address);
    function canReceiveShares(address account) external view returns (bool);
    function canSendShares(address account) external view returns (bool);
    function canReceiveAssets(address account) external view returns (bool);
    function canSendAssets(address account) external view returns (bool);
    function maxRate() external view returns (uint256);
    function virtualShares() external view returns (uint256);
    function performanceFee() external view returns (uint256);
    function managementFee() external view returns (uint256);
}

interface IMorphoAdapterLike {
    function parentVault() external view returns (address);
    function realAssets() external view returns (uint256);
}

interface IVaultV2FactoryLike {
    function isVaultV2(address vault) external view returns (bool);
}

interface IMorphoAdapterFactoryLike {
    function isMorphoMarketV1AdapterV2(address adapter) external view returns (bool);
}

interface IPsmFacetLike {
    function VERSION() external view returns (string memory);
    function dai() external view returns (address);
    function daiUSDS() external view returns (address);
    function psm() external view returns (address);
    function usdc() external view returns (address);
    function usds() external view returns (address);
    function to18ConversionFactor() external view returns (uint256);
    function usdcToUSDSSwapRateLimitKey() external pure returns (bytes32);
    function usdsToUSDCSwapRateLimitKey() external pure returns (bytes32);
}

interface IERC4626FacetLike {
    function VERSION() external view returns (string memory);
    function EXCHANGE_RATE_PRECISION() external view returns (uint256);
    function getDepositRateLimitKey(address token, address asset) external pure returns (bytes32);
    function getWithdrawRateLimitKey(address token) external pure returns (bytes32);
}

contract OseroEthereum_20261008_Test is CommonPauSpellTests {
    // Technical-scope readback block (September 16, 2026).
    uint256 internal constant MAINNET_FORK_BLOCK = 25_989_692;
    address internal constant DEPLOYED_PAYLOAD = address(0);

    address internal constant OGUSDCP_VAULT = 0x802148D518A6De2aF866f9A61ffB5e5C39156dB2;
    address internal constant GAUNTLET_OWNER_CURATOR_MULTISIG = 0x9E33faAE38ff641094fa68c65c2cE600b3410585;
    address internal constant OGUSDCP_ALLOCATOR = 0x6939A35d32E9bE623e08aA0bceD96D4baC170bB3;
    address internal constant OGUSDCP_SENTINEL = 0x6a0dC94d80429dd4B03E8838CE8d6BEE725bE39B;
    address internal constant MORPHO_ADAPTER = 0x9DD0Ceb7caC214777014d2f664dB3C20f0838D53;
    address internal constant MORPHO_VAULT_V2_FACTORY = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    address internal constant MORPHO_ADAPTER_FACTORY = 0x32BB1c0D48D8b1B3363e86eeB9A0300BAd61ccc1;
    address internal constant PAS_CONFIGURATOR = 0xb7E61Df6CAb0A51E9A5dab1A7DD3f942dDe5b929;

    bytes32 internal constant USDS_FACET_INTEGRATION_ID = "USDS_FACET";
    bytes32 internal constant AAVE_FACET_INTEGRATION_ID = "AAVE_FACET";
    bytes32 internal constant ERC4626_FACET_INTEGRATION_ID = "ERC4626_FACET";
    bytes32 internal constant PSM_FACET_INTEGRATION_ID = "PSM_FACET";

    bytes32 internal constant PSM_USDS_TO_USDC_RATE_LIMIT_KEY =
        0x00d4cb8ac2838f11d95b0136a919a13b994f920024aba35eee16dc433c65851c;
    bytes32 internal constant PSM_USDC_TO_USDS_RATE_LIMIT_KEY =
        0x87835797fec2ad9575bc1a7035e3c27b8a8b7db2c3d7118513baf081b3af06b3;
    bytes32 internal constant OGUSDCP_DEPOSIT_RATE_LIMIT_KEY =
        0xfc26a91cf7b79b531d45dcc431ee59e4f2504f51cb33e2b67960808a104c92ef;
    bytes32 internal constant OGUSDCP_WITHDRAW_RATE_LIMIT_KEY =
        0xcab6bfa8f90f2360ea56d52b48e71b2b98ee14414a2fd578d01dcfeb41cf97ca;

    bytes32 internal constant DERIVED_PSM_USDS_TO_USDC_RATE_LIMIT_KEY = keccak256("LIMIT_USDS_TO_USDC");
    bytes32 internal constant DERIVED_PSM_USDC_TO_USDS_RATE_LIMIT_KEY = keccak256("LIMIT_USDC_TO_USDS");
    bytes32 internal constant DERIVED_OGUSDCP_DEPOSIT_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_4626_DEPOSIT"), USDC, OGUSDCP_VAULT));
    bytes32 internal constant DERIVED_OGUSDCP_WITHDRAW_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_4626_WITHDRAW"), OGUSDCP_VAULT));

    bytes32 internal constant USDS_MINT_RATE_LIMIT_KEY = keccak256("LIMIT_USDS_MINT");
    bytes32 internal constant USDS_BURN_RATE_LIMIT_KEY = keccak256("LIMIT_USDS_BURN");
    bytes32 internal constant SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_AAVE_DEPOSIT"), USDS, SparkLend.POOL, SparkLend.USDS_SPTOKEN));
    bytes32 internal constant SPARKLEND_USDS_WITHDRAW_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_AAVE_WITHDRAW"), SparkLend.POOL, SparkLend.USDS_SPTOKEN));

    uint256 internal constant OGUSDCP_MAX_EXCHANGE_RATE = 2e24;
    uint256 internal constant PSM_USDS_TO_USDC_MAX = 50_000_000e6;
    uint256 internal constant PSM_USDS_TO_USDC_SLOPE = uint256(50_000_000e6) / 1 days;
    uint256 internal constant OGUSDCP_DEPOSIT_MAX = 5_000_000e6;
    uint256 internal constant OGUSDCP_DEPOSIT_SLOPE = 0;
    uint256 internal constant ROUND_TRIP_USDS_AMOUNT = 1_000e18;
    uint256 internal constant ROUND_TRIP_USDC_AMOUNT = 1_000e6;
    uint256 internal constant OPERATIONAL_TEST_USDS_AMOUNT = 1_000_000e18;
    uint256 internal constant OPERATIONAL_TEST_USDC_AMOUNT = 1_000_000e6;
    uint256 internal constant PARTIAL_RECOVERY_TIME = 20 minutes;
    uint256 internal constant EXCHANGE_RATE_PRECISION = 1e36;
    uint256 internal constant ERC4626_FACET_WIRE_COUNT = 9;
    uint256 internal constant PSM_FACET_WIRE_COUNT = 11;

    bytes32 internal constant INTEGRATION_SET_TOPIC =
        0x5d055c4f05bd18deea319d5a3203b45d847aedd23073a618067b95ddd537c946;
    bytes32 internal constant INTEGRATION_REMOVED_TOPIC =
        0x043c2a2fce5883ae183cf4a77a5b7883a31824c8f21570b619972fbe500b79e6;
    bytes32 internal constant ERC4626_MAX_EXCHANGE_RATE_SET_TOPIC =
        0x0357b338178e1b6a462ee13d8e266e1317ac9a1ed1ca355a5a74aaad21ab5726;
    bytes32 internal constant RATE_LIMIT_DATA_SET_TOPIC =
        0x356822943b80f809508a684c67d901d5c13b6a22161bf07d510e50a6cb727028;
    bytes32 internal constant ROLE_GRANTED_TOPIC = keccak256("RoleGranted(bytes32,address,address)");
    bytes32 internal constant ROLE_REVOKED_TOPIC = keccak256("RoleRevoked(bytes32,address,address)");

    IERC20 internal constant usdc = IERC20(USDC);
    IERC20 internal constant dai = IERC20(MCD_DAI);
    IERC20 internal constant ogusdcp = IERC20(OGUSDCP_VAULT);

    event IntegrationRemoved(bytes32 indexed id);
    event ERC4626MaxExchangeRateSet(address indexed token, uint256 maxExchangeRate);
    event PSMSwapUSDSToUSDC(uint256 usdcAmount);
    event PSMSwapUSDCToUSDS(uint256 usdcAmount);

    struct ExistingRateLimitsSnapshot {
        IRateLimitsLike.RateLimitData mint;
        IRateLimitsLike.RateLimitData burn;
        IRateLimitsLike.RateLimitData sparklendDeposit;
        IRateLimitsLike.RateLimitData sparklendWithdraw;
    }

    struct LaunchConfigurationSnapshot {
        bool subProxyAccessAdmin;
        bool subProxyRateLimitsAdmin;
        bool subProxyAlmProxyAdmin;
        bool agentAllocator;
        bool controllerRateLimits;
        bool controllerAlmProxy;
        bool pasAccessAdmin;
        bool pasRateLimitsAdmin;
        uint256 accessAdminCount;
        uint256 agentAdminCount;
        uint256 agentActorCount;
        uint256 agentRevokerCount;
        uint256 agentGrantorCount;
        address usdsVault;
        uint256 sparklendMaxSlippage;
        uint256 litePsmBud;
        uint256 starGuardWard;
    }

    constructor() {
        spellId = "20261008";
    }

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), MAINNET_FORK_BLOCK);
        _setupPayload(DEPLOYED_PAYLOAD);
    }

    function test_ETHEREUM_scopeKeysAndEncodedParametersMatchTechnicalScope() public view {
        assertEq(
            DERIVED_PSM_USDS_TO_USDC_RATE_LIMIT_KEY, PSM_USDS_TO_USDC_RATE_LIMIT_KEY, "psm-usds-to-usdc-derived-key"
        );
        assertEq(
            DERIVED_PSM_USDC_TO_USDS_RATE_LIMIT_KEY, PSM_USDC_TO_USDS_RATE_LIMIT_KEY, "psm-usdc-to-usds-derived-key"
        );
        assertEq(DERIVED_OGUSDCP_DEPOSIT_RATE_LIMIT_KEY, OGUSDCP_DEPOSIT_RATE_LIMIT_KEY, "ogusdcp-deposit-derived-key");
        assertEq(
            DERIVED_OGUSDCP_WITHDRAW_RATE_LIMIT_KEY, OGUSDCP_WITHDRAW_RATE_LIMIT_KEY, "ogusdcp-withdraw-derived-key"
        );

        IPsmFacetLike psmFacet = IPsmFacetLike(SKY_PAU_PSM_FACET);
        IERC4626FacetLike erc4626Facet = IERC4626FacetLike(SKY_PAU_ERC4626_FACET);
        assertEq(psmFacet.usdsToUSDCSwapRateLimitKey(), PSM_USDS_TO_USDC_RATE_LIMIT_KEY, "psm-usds-to-usdc-facet-key");
        assertEq(psmFacet.usdcToUSDSSwapRateLimitKey(), PSM_USDC_TO_USDS_RATE_LIMIT_KEY, "psm-usdc-to-usds-facet-key");
        assertEq(
            erc4626Facet.getDepositRateLimitKey(OGUSDCP_VAULT, USDC),
            OGUSDCP_DEPOSIT_RATE_LIMIT_KEY,
            "ogusdcp-deposit-facet-key"
        );
        assertEq(
            erc4626Facet.getWithdrawRateLimitKey(OGUSDCP_VAULT),
            OGUSDCP_WITHDRAW_RATE_LIMIT_KEY,
            "ogusdcp-withdraw-facet-key"
        );
        assertEq(PSM_USDS_TO_USDC_SLOPE, 578_703_703, "psm-usds-to-usdc-slope-literal");
        assertEq(OGUSDCP_DEPOSIT_SLOPE, 0, "ogusdcp-deposit-slope-literal");

        OseroEthereum_20261008 spell = OseroEthereum_20261008(payload);
        assertEq(spell.USDC(), USDC, "payload-usdc");
        assertEq(spell.OGUSDCP_VAULT(), OGUSDCP_VAULT, "payload-ogusdcp-vault");
        assertEq(spell.ERC4626_FACET_INTEGRATION_ID(), ERC4626_FACET_INTEGRATION_ID, "payload-erc4626-id");
        assertEq(spell.PSM_FACET_INTEGRATION_ID(), PSM_FACET_INTEGRATION_ID, "payload-psm-id");
        assertEq(spell.OGUSDCP_MAX_EXCHANGE_RATE_SHARES(), 1e18, "payload-max-exchange-rate-shares");
        assertEq(spell.OGUSDCP_MAX_EXCHANGE_RATE_ASSETS(), 2e6, "payload-max-exchange-rate-assets");
        assertEq(spell.PSM_USDS_TO_USDC_MAX(), PSM_USDS_TO_USDC_MAX, "payload-psm-max");
        assertEq(spell.PSM_USDS_TO_USDC_SLOPE(), PSM_USDS_TO_USDC_SLOPE, "payload-psm-slope");
        assertEq(spell.OGUSDCP_DEPOSIT_MAX(), OGUSDCP_DEPOSIT_MAX, "payload-ogusdcp-deposit-max");
        assertEq(spell.OGUSDCP_DEPOSIT_SLOPE(), OGUSDCP_DEPOSIT_SLOPE, "payload-ogusdcp-deposit-slope");
        assertEq(
            EXCHANGE_RATE_PRECISION * spell.OGUSDCP_MAX_EXCHANGE_RATE_ASSETS()
                / spell.OGUSDCP_MAX_EXCHANGE_RATE_SHARES(),
            OGUSDCP_MAX_EXCHANGE_RATE,
            "payload-max-exchange-rate-encoded"
        );
    }

    function test_ETHEREUM_pauPreconfigurationForVaultOnboarding() public view {
        _assertOnboardingContracts();

        _assertBeaconConfig(ERC4626_FACET_INTEGRATION_ID, SKY_PAU_ERC4626_FACET, _expectedErc4626Wires(), "erc4626");
        _assertBeaconConfig(PSM_FACET_INTEGRATION_ID, SKY_PAU_PSM_FACET, _expectedPsmWires(), "psm");

        IERC4626FacetLike erc4626Facet = IERC4626FacetLike(SKY_PAU_ERC4626_FACET);
        IPsmFacetLike psmFacet = IPsmFacetLike(SKY_PAU_PSM_FACET);
        assertEq(erc4626Facet.VERSION(), "1.0.0", "erc4626-version");
        assertEq(erc4626Facet.EXCHANGE_RATE_PRECISION(), EXCHANGE_RATE_PRECISION, "erc4626-exchange-rate-precision");
        assertEq(psmFacet.VERSION(), "1.0.0", "psm-version");
        assertEq(psmFacet.dai(), MCD_DAI, "psm-dai");
        assertEq(psmFacet.daiUSDS(), DAI_USDS, "psm-dai-usds");
        assertEq(psmFacet.psm(), MCD_LITE_PSM_USDC_A, "psm-lite-psm");
        assertEq(psmFacet.usdc(), USDC, "psm-usdc");
        assertEq(psmFacet.usds(), USDS, "psm-usds");
        assertEq(psmFacet.to18ConversionFactor(), 1e12, "psm-to-18-conversion-factor");

        _assertVaultPreconfiguration();
        assertEq(ILitePsmLike(MCD_LITE_PSM_USDC_A).bud(OSERO_ALM_PROXY), 1, "almproxy-not-litepsm-bud");

        _assertNewRateLimitsUnset();
        assertEq(
            controller.getDispatch(IOseroPauControllerLike.erc4626_deposit.selector).facet,
            address(0),
            "erc4626-deposit-already-wired"
        );
        assertEq(
            controller.getDispatch(IOseroPauControllerLike.psm_swapUSDSToUSDC.selector).facet,
            address(0),
            "psm-swap-already-wired"
        );
    }

    function test_ETHEREUM_spellExecutionEnablesIntegrations() public {
        assertEq(controller.integrations().length, 2, "unexpected-pre-spell-integration-count");
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("CallSelectorNotWired(bytes4)")),
                IOseroPauControllerLike.erc4626_getMaxExchangeRate.selector
            )
        );
        controller.erc4626_getMaxExchangeRate(OGUSDCP_VAULT);

        _executeSpellViaStarGuard(payload);

        ExpectedIntegration[] memory expected = new ExpectedIntegration[](4);
        expected[0] = ExpectedIntegration(USDS_FACET_INTEGRATION_ID, SKY_PAU_USDS_FACET, 8, "usds");
        expected[1] = ExpectedIntegration(AAVE_FACET_INTEGRATION_ID, SKY_PAU_AAVE_FACET, 7, "aave");
        expected[2] = ExpectedIntegration(ERC4626_FACET_INTEGRATION_ID, SKY_PAU_ERC4626_FACET, 9, "erc4626");
        expected[3] = ExpectedIntegration(PSM_FACET_INTEGRATION_ID, SKY_PAU_PSM_FACET, 11, "psm");
        _assertControllerIntegrations(expected);

        _assertControllerConfigMatchesBeacon(ERC4626_FACET_INTEGRATION_ID, "erc4626");
        _assertControllerConfigMatchesBeacon(PSM_FACET_INTEGRATION_ID, "psm");
        _assertControllerWires(_expectedErc4626Wires(), SKY_PAU_ERC4626_FACET, "erc4626");
        _assertControllerWires(_expectedPsmWires(), SKY_PAU_PSM_FACET, "psm");

        assertEq(controller.erc4626_VERSION(), "1.0.0", "controller-erc4626-version");
        assertEq(controller.erc4626_EXCHANGE_RATE_PRECISION(), EXCHANGE_RATE_PRECISION, "controller-erc4626-precision");
        assertEq(controller.psm_VERSION(), "1.0.0", "controller-psm-version");
        assertEq(controller.psm_dai(), MCD_DAI, "controller-psm-dai");
        assertEq(controller.psm_daiUSDS(), DAI_USDS, "controller-psm-dai-usds");
        assertEq(controller.psm_psm(), MCD_LITE_PSM_USDC_A, "controller-psm-lite-psm");
        assertEq(controller.psm_usdc(), USDC, "controller-psm-usdc");
        assertEq(controller.psm_usds(), USDS, "controller-psm-usds");
        assertEq(controller.psm_to18ConversionFactor(), 1e12, "controller-psm-conversion-factor");
        assertEq(
            controller.psm_usdsToUSDCSwapRateLimitKey(),
            PSM_USDS_TO_USDC_RATE_LIMIT_KEY,
            "controller-psm-usds-to-usdc-key"
        );
        assertEq(
            controller.psm_usdcToUSDSSwapRateLimitKey(),
            PSM_USDC_TO_USDS_RATE_LIMIT_KEY,
            "controller-psm-usdc-to-usds-key"
        );
        assertEq(
            controller.erc4626_getDepositRateLimitKey(OGUSDCP_VAULT, USDC),
            OGUSDCP_DEPOSIT_RATE_LIMIT_KEY,
            "controller-ogusdcp-deposit-key"
        );
        assertEq(
            controller.erc4626_getWithdrawRateLimitKey(OGUSDCP_VAULT),
            OGUSDCP_WITHDRAW_RATE_LIMIT_KEY,
            "controller-ogusdcp-withdraw-key"
        );
    }

    function test_ETHEREUM_spellExecutionSetsMaxExchangeRateAndRateLimits() public {
        _assertNewRateLimitsUnset();

        _executeSpellViaStarGuard(payload);

        assertEq(
            controller.erc4626_getMaxExchangeRate(OGUSDCP_VAULT), OGUSDCP_MAX_EXCHANGE_RATE, "ogusdcp-max-exchange-rate"
        );
        _assertRateLimit(
            PSM_USDS_TO_USDC_RATE_LIMIT_KEY, PSM_USDS_TO_USDC_MAX, PSM_USDS_TO_USDC_SLOPE, "psm-usds-to-usdc"
        );
        _assertUnlimitedRateLimit(PSM_USDC_TO_USDS_RATE_LIMIT_KEY, "psm-usdc-to-usds");
        _assertRateLimit(OGUSDCP_DEPOSIT_RATE_LIMIT_KEY, OGUSDCP_DEPOSIT_MAX, OGUSDCP_DEPOSIT_SLOPE, "ogusdcp-deposit");
        _assertUnlimitedRateLimit(OGUSDCP_WITHDRAW_RATE_LIMIT_KEY, "ogusdcp-withdraw");
    }

    function test_ETHEREUM_existingRateLimitsPermissionsAndLaunchConfigurationUnchanged() public {
        ExistingRateLimitsSnapshot memory limitsBefore = _snapshotExistingRateLimits();
        LaunchConfigurationSnapshot memory launchBefore = _snapshotLaunchConfiguration();

        _executeSpellViaStarGuard(payload);

        _assertExistingRateLimitsUnchanged(limitsBefore);
        _assertLaunchConfigurationUnchanged(launchBefore);
        assertTrue(
            IAccessControlsLike(OSERO_ACCESS_CONTROLS).hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY),
            "subproxy-missing-access-admin"
        );
        assertTrue(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY), "subproxy-missing-ratelimits-admin");
        assertTrue(
            IALMProxyLike(OSERO_ALM_PROXY).hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY), "subproxy-missing-almproxy-admin"
        );
    }

    function test_ETHEREUM_spellEmitsOnlyExpectedEvents() public {
        vm.recordLogs();
        _executeSpellViaStarGuard(payload);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 erc4626IntegrationSets;
        uint256 psmIntegrationSets;
        uint256 maxExchangeRateSets;
        uint256 psmUsdsToUsdcRateLimits;
        uint256 psmUsdcToUsdsRateLimits;
        uint256 ogusdcpDepositRateLimits;
        uint256 ogusdcpWithdrawRateLimits;
        uint256 integrationRemovals;
        uint256 roleChanges;

        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic == INTEGRATION_SET_TOPIC) {
                assertEq(logs[i].emitter, OSERO_CONTROLLER, "integration-set-emitter");
                bytes32 id = logs[i].topics[1];
                if (id == ERC4626_FACET_INTEGRATION_ID) erc4626IntegrationSets++;
                else if (id == PSM_FACET_INTEGRATION_ID) psmIntegrationSets++;
                else fail("unexpected-integration-set-id");
            } else if (topic == ERC4626_MAX_EXCHANGE_RATE_SET_TOPIC) {
                assertEq(logs[i].emitter, OSERO_CONTROLLER, "max-exchange-rate-emitter");
                assertEq(address(uint160(uint256(logs[i].topics[1]))), OGUSDCP_VAULT, "max-exchange-rate-token");
                assertEq(
                    abi.decode(logs[i].data, (uint256)), OGUSDCP_MAX_EXCHANGE_RATE, "max-exchange-rate-event-value"
                );
                maxExchangeRateSets++;
            } else if (topic == RATE_LIMIT_DATA_SET_TOPIC) {
                assertEq(logs[i].emitter, OSERO_RATE_LIMITS, "rate-limit-event-emitter");
                bytes32 key = logs[i].topics[1];
                if (key == PSM_USDS_TO_USDC_RATE_LIMIT_KEY) psmUsdsToUsdcRateLimits++;
                else if (key == PSM_USDC_TO_USDS_RATE_LIMIT_KEY) psmUsdcToUsdsRateLimits++;
                else if (key == OGUSDCP_DEPOSIT_RATE_LIMIT_KEY) ogusdcpDepositRateLimits++;
                else if (key == OGUSDCP_WITHDRAW_RATE_LIMIT_KEY) ogusdcpWithdrawRateLimits++;
                else fail("unexpected-rate-limit-key");
            } else if (topic == INTEGRATION_REMOVED_TOPIC) {
                integrationRemovals++;
            } else if (topic == ROLE_GRANTED_TOPIC || topic == ROLE_REVOKED_TOPIC) {
                roleChanges++;
            }
        }

        assertEq(erc4626IntegrationSets, 1, "erc4626-integration-set-count");
        assertEq(psmIntegrationSets, 1, "psm-integration-set-count");
        assertEq(maxExchangeRateSets, 1, "max-exchange-rate-set-count");
        assertEq(psmUsdsToUsdcRateLimits, 1, "psm-usds-to-usdc-rate-limit-event-count");
        assertEq(psmUsdcToUsdsRateLimits, 1, "psm-usdc-to-usds-rate-limit-event-count");
        assertEq(ogusdcpDepositRateLimits, 1, "ogusdcp-deposit-rate-limit-event-count");
        assertEq(ogusdcpWithdrawRateLimits, 1, "ogusdcp-withdraw-rate-limit-event-count");
        assertEq(integrationRemovals, 0, "integration-removed-event-count");
        assertEq(roleChanges, 0, "role-change-event-count");
    }

    function test_ETHEREUM_directPayloadExecutionRevertsWithoutSubProxyAuthority() public {
        // The first action is updateIntegrations, whose onlyAdmin check requires SubProxy authority.
        vm.expectRevert(abi.encodeWithSignature("NotAdmin(address)", payload));
        ISpellLike(payload).execute();
    }

    function test_ETHEREUM_actorCannotChangeMaxExchangeRateOrIntegrations() public {
        _executeSpellViaStarGuard(payload);

        _expectCallAsOseroActorRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", OSERO_ADMINISTERED_AGENT, DEFAULT_ADMIN_ROLE
            ),
            abi.encodeCall(IOseroPauControllerLike.erc4626_setMaxExchangeRate, (OGUSDCP_VAULT, 1e18, 1e6))
        );
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = ERC4626_FACET_INTEGRATION_ID;
        _expectCallAsOseroActorRevert(
            abi.encodeWithSignature("NotAdmin(address)", OSERO_ADMINISTERED_AGENT),
            abi.encodeCall(IOseroPauControllerLike.removeIntegrations, (ids))
        );

        assertEq(
            controller.erc4626_getMaxExchangeRate(OGUSDCP_VAULT), OGUSDCP_MAX_EXCHANGE_RATE, "max-exchange-rate-changed"
        );
        assertEq(controller.integrations().length, 4, "integration-count-changed");
    }

    function test_ETHEREUM_ogusdcpRoundTripOperationalThroughAdministeredAgent() public {
        _executeSpellViaStarGuard(payload);

        uint256 proxyUsdsStart = usds.balanceOf(OSERO_ALM_PROXY);
        uint256 proxyUsdcStart = usdc.balanceOf(OSERO_ALM_PROXY);
        uint256 proxySharesStart = ogusdcp.balanceOf(OSERO_ALM_PROXY);
        uint256 mintBefore = rateLimits.getCurrentRateLimit(USDS_MINT_RATE_LIMIT_KEY);

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_mint, (ROUND_TRIP_USDS_AMOUNT)));
        vm.expectEmit(OSERO_CONTROLLER);
        emit PSMSwapUSDSToUSDC(ROUND_TRIP_USDC_AMOUNT);
        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.psm_swapUSDSToUSDC, (ROUND_TRIP_USDC_AMOUNT)));

        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart, "proxy-usds-not-swapped");
        assertEq(usdc.balanceOf(OSERO_ALM_PROXY), proxyUsdcStart + ROUND_TRIP_USDC_AMOUNT, "proxy-usdc-not-received");
        assertEq(
            rateLimits.getCurrentRateLimit(PSM_USDS_TO_USDC_RATE_LIMIT_KEY),
            PSM_USDS_TO_USDC_MAX - ROUND_TRIP_USDC_AMOUNT,
            "psm-usds-to-usdc-limit-not-decreased"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(PSM_USDC_TO_USDS_RATE_LIMIT_KEY),
            type(uint256).max,
            "psm-usdc-to-usds-limit-changed"
        );

        IVaultV2Like vault = IVaultV2Like(OGUSDCP_VAULT);
        uint256 minSharesOut = vault.previewDeposit(ROUND_TRIP_USDC_AMOUNT) * 999 / 1000;
        bytes memory depositResult = _callAsOseroActor(
            abi.encodeCall(
                IOseroPauControllerLike.erc4626_deposit, (OGUSDCP_VAULT, ROUND_TRIP_USDC_AMOUNT, minSharesOut)
            )
        );
        uint256 shares = abi.decode(depositResult, (uint256));
        assertGe(shares, minSharesOut, "ogusdcp-shares-below-minimum");
        assertEq(ogusdcp.balanceOf(OSERO_ALM_PROXY), proxySharesStart + shares, "proxy-shares-not-received");
        assertEq(usdc.balanceOf(OSERO_ALM_PROXY), proxyUsdcStart, "proxy-usdc-not-deposited");
        assertEq(
            rateLimits.getCurrentRateLimit(OGUSDCP_DEPOSIT_RATE_LIMIT_KEY),
            OGUSDCP_DEPOSIT_MAX - ROUND_TRIP_USDC_AMOUNT,
            "ogusdcp-deposit-limit-not-decreased"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(OGUSDCP_WITHDRAW_RATE_LIMIT_KEY),
            type(uint256).max,
            "ogusdcp-withdraw-limit-changed"
        );
        assertEq(usdc.allowance(OSERO_ALM_PROXY, OGUSDCP_VAULT), 0, "ogusdcp-usdc-approval-not-cleared");

        bytes memory redeemResult =
            _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.erc4626_redeem, (OGUSDCP_VAULT, shares, 999e6)));
        uint256 assets = abi.decode(redeemResult, (uint256));
        assertGe(assets, 999e6, "ogusdcp-assets-below-minimum");
        assertLe(assets, ROUND_TRIP_USDC_AMOUNT, "ogusdcp-assets-above-deposit");
        assertEq(ogusdcp.balanceOf(OSERO_ALM_PROXY), proxySharesStart, "proxy-shares-not-redeemed");
        assertEq(usdc.balanceOf(OSERO_ALM_PROXY), proxyUsdcStart + assets, "proxy-usdc-not-redeemed");
        assertEq(
            rateLimits.getCurrentRateLimit(OGUSDCP_DEPOSIT_RATE_LIMIT_KEY),
            OGUSDCP_DEPOSIT_MAX - ROUND_TRIP_USDC_AMOUNT + assets,
            "ogusdcp-deposit-limit-not-refilled"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(OGUSDCP_WITHDRAW_RATE_LIMIT_KEY),
            type(uint256).max,
            "ogusdcp-withdraw-limit-not-unlimited"
        );

        vm.expectEmit(OSERO_CONTROLLER);
        emit PSMSwapUSDCToUSDS(assets);
        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.psm_swapUSDCToUSDS, (assets)));
        assertEq(usdc.balanceOf(OSERO_ALM_PROXY), proxyUsdcStart, "proxy-usdc-not-swapped-back");
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart + assets * 1e12, "proxy-usds-not-received-back");
        assertEq(
            rateLimits.getCurrentRateLimit(PSM_USDS_TO_USDC_RATE_LIMIT_KEY),
            PSM_USDS_TO_USDC_MAX - ROUND_TRIP_USDC_AMOUNT + assets,
            "psm-usds-to-usdc-limit-not-refilled"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(PSM_USDC_TO_USDS_RATE_LIMIT_KEY),
            type(uint256).max,
            "psm-usdc-to-usds-limit-not-unlimited"
        );

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_burn, (assets * 1e12)));
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart, "proxy-usds-not-burned");
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_MINT_RATE_LIMIT_KEY),
            mintBefore - ROUND_TRIP_USDS_AMOUNT + assets * 1e12,
            "mint-limit-after-round-trip"
        );
        assertEq(rateLimits.getCurrentRateLimit(USDS_BURN_RATE_LIMIT_KEY), type(uint256).max, "burn-limit-changed");
        assertEq(usds.allowance(OSERO_ALM_PROXY, DAI_USDS), 0, "dai-usds-usds-approval-not-cleared");
        assertEq(dai.allowance(OSERO_ALM_PROXY, MCD_LITE_PSM_USDC_A), 0, "lite-psm-dai-approval-not-cleared");
        assertEq(usdc.allowance(OSERO_ALM_PROXY, MCD_LITE_PSM_USDC_A), 0, "lite-psm-usdc-approval-not-cleared");
        assertEq(dai.allowance(OSERO_ALM_PROXY, DAI_USDS), 0, "dai-usds-dai-approval-not-cleared");
        assertEq(usdc.allowance(OSERO_ALM_PROXY, OGUSDCP_VAULT), 0, "ogusdcp-usdc-final-approval-not-cleared");
    }

    function test_ETHEREUM_psmUsdsToUsdcSwapRateLimitRejectsOversizedSwap() public {
        _executeSpellViaStarGuard(payload);
        uint256 oversizedAmount = PSM_USDS_TO_USDC_MAX + 1;
        deal(USDS, OSERO_ALM_PROXY, oversizedAmount * 1e12);
        _expectCallAsOseroActorRevert(
            bytes("RateLimits/rate-limit-exceeded"),
            abi.encodeCall(IOseroPauControllerLike.psm_swapUSDSToUSDC, (oversizedAmount))
        );
    }

    function test_ETHEREUM_ogusdcpDepositRateLimitRejectsOversizedDeposit() public {
        _executeSpellViaStarGuard(payload);
        deal(USDC, OSERO_ALM_PROXY, OGUSDCP_DEPOSIT_MAX + 1);
        _expectCallAsOseroActorRevert(
            bytes("RateLimits/rate-limit-exceeded"),
            abi.encodeCall(IOseroPauControllerLike.erc4626_deposit, (OGUSDCP_VAULT, OGUSDCP_DEPOSIT_MAX + 1, 0))
        );
    }

    function test_ETHEREUM_ogusdcpDepositRejectsUnconfiguredVault() public {
        _executeSpellViaStarGuard(payload);
        deal(USDS, OSERO_ALM_PROXY, 1_000e18);
        // Only the configured Osero x Gauntlet vault deposit key exists.
        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(IOseroPauControllerLike.erc4626_deposit, (SparkEthereum.SUSDS, 1_000e18, 0))
        );
    }

    function test_ETHEREUM_psmAndOgusdcpRateLimitsRecoverOverTime() public {
        _executeSpellViaStarGuard(payload);

        // Test funding bypasses the mint limit, which only has about 254k capacity at the fork block.
        deal(USDS, OSERO_ALM_PROXY, usds.balanceOf(OSERO_ALM_PROXY) + OPERATIONAL_TEST_USDS_AMOUNT);
        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.psm_swapUSDSToUSDC, (OPERATIONAL_TEST_USDC_AMOUNT)));
        uint256 minSharesOut = IVaultV2Like(OGUSDCP_VAULT).previewDeposit(OPERATIONAL_TEST_USDC_AMOUNT) * 999 / 1000;
        _callAsOseroActor(
            abi.encodeCall(
                IOseroPauControllerLike.erc4626_deposit, (OGUSDCP_VAULT, OPERATIONAL_TEST_USDC_AMOUNT, minSharesOut)
            )
        );

        assertEq(
            rateLimits.getCurrentRateLimit(PSM_USDS_TO_USDC_RATE_LIMIT_KEY),
            PSM_USDS_TO_USDC_MAX - OPERATIONAL_TEST_USDC_AMOUNT,
            "psm-limit-not-decreased"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(OGUSDCP_DEPOSIT_RATE_LIMIT_KEY),
            OGUSDCP_DEPOSIT_MAX - OPERATIONAL_TEST_USDC_AMOUNT,
            "ogusdcp-limit-not-decreased"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(PSM_USDC_TO_USDS_RATE_LIMIT_KEY),
            type(uint256).max,
            "psm-unlimited-key-changed"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(OGUSDCP_WITHDRAW_RATE_LIMIT_KEY),
            type(uint256).max,
            "ogusdcp-unlimited-key-changed"
        );

        vm.warp(block.timestamp + PARTIAL_RECOVERY_TIME);
        assertEq(
            rateLimits.getCurrentRateLimit(PSM_USDS_TO_USDC_RATE_LIMIT_KEY),
            PSM_USDS_TO_USDC_MAX - OPERATIONAL_TEST_USDC_AMOUNT + PSM_USDS_TO_USDC_SLOPE * PARTIAL_RECOVERY_TIME,
            "psm-limit-not-recovering"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(OGUSDCP_DEPOSIT_RATE_LIMIT_KEY),
            OGUSDCP_DEPOSIT_MAX - OPERATIONAL_TEST_USDC_AMOUNT,
            "ogusdcp-limit-recovered-with-zero-slope"
        );

        vm.warp(block.timestamp + 1 days);
        assertEq(
            rateLimits.getCurrentRateLimit(PSM_USDS_TO_USDC_RATE_LIMIT_KEY),
            PSM_USDS_TO_USDC_MAX,
            "psm-limit-not-capped"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(OGUSDCP_DEPOSIT_RATE_LIMIT_KEY),
            OGUSDCP_DEPOSIT_MAX - OPERATIONAL_TEST_USDC_AMOUNT,
            "ogusdcp-limit-recovered-with-zero-slope-after-day"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(PSM_USDC_TO_USDS_RATE_LIMIT_KEY),
            type(uint256).max,
            "psm-unlimited-key-not-unchanged"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(OGUSDCP_WITHDRAW_RATE_LIMIT_KEY),
            type(uint256).max,
            "ogusdcp-unlimited-key-not-unchanged"
        );
    }

    function test_ETHEREUM_ogusdcpDepositRejectsExchangeRateAboveCeiling() public {
        _executeSpellViaStarGuard(payload);

        deal(USDC, OGUSDCP_VAULT, usdc.balanceOf(OGUSDCP_VAULT) + 10e6);
        // VaultV2 caps accrual at maxRate (about 100%/year linear), so the share price exceeds the
        // 2 USDC ceiling only after about one year even with a donation.
        vm.warp(block.timestamp + 366 days);
        assertGt(IVaultV2Like(OGUSDCP_VAULT).convertToAssets(1e18), 2e6, "ogusdcp-exchange-rate-not-above-ceiling");

        deal(USDC, OSERO_ALM_PROXY, usdc.balanceOf(OSERO_ALM_PROXY) + 1_000e6);
        _expectCallAsOseroActorRevert(
            bytes("ERC4626Facet/exchange-rate-too-high"),
            abi.encodeCall(IOseroPauControllerLike.erc4626_deposit, (OGUSDCP_VAULT, 1_000e6, 0))
        );
    }

    function test_ETHEREUM_subProxyCanRemoveIntegrationsAsEmergencyAction() public {
        _executeSpellViaStarGuard(payload);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = ERC4626_FACET_INTEGRATION_ID;
        vm.expectEmit(OSERO_CONTROLLER);
        emit IntegrationRemoved(ERC4626_FACET_INTEGRATION_ID);
        vm.prank(OSERO_PROXY);
        controller.removeIntegrations(ids);

        assertEq(controller.integrations().length, 3, "integration-count-after-removal");
        assertEq(
            controller.getDispatch(IOseroPauControllerLike.erc4626_deposit.selector).facet,
            address(0),
            "erc4626-deposit-still-wired"
        );
        _expectCallAsOseroActorRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("CallSelectorNotWired(bytes4)")), IOseroPauControllerLike.erc4626_deposit.selector
            ),
            abi.encodeCall(IOseroPauControllerLike.erc4626_deposit, (OGUSDCP_VAULT, 1e6, 0))
        );
        _assertWire(
            IOseroPauControllerLike.psm_swapUSDSToUSDC.selector,
            SKY_PAU_PSM_FACET,
            bytes4(keccak256("swapUSDSToUSDC(uint256)")),
            "psm-swap-usds-to-usdc"
        );
        _assertRateLimit(OGUSDCP_DEPOSIT_RATE_LIMIT_KEY, OGUSDCP_DEPOSIT_MAX, OGUSDCP_DEPOSIT_SLOPE, "ogusdcp-deposit");
        _assertUnlimitedRateLimit(OGUSDCP_WITHDRAW_RATE_LIMIT_KEY, "ogusdcp-withdraw");
    }

    function _assertOnboardingContracts() internal view {
        _assertContract(SKY_PAU_BEACON, "sky-pau-beacon");
        _assertContract(SKY_PAU_ERC4626_FACET, "sky-pau-erc4626-facet");
        _assertContract(SKY_PAU_PSM_FACET, "sky-pau-psm-facet");
        _assertContract(MCD_DAI, "dai");
        _assertContract(DAI_USDS, "dai-usds");
        _assertContract(USDC, "usdc");
        _assertContract(OGUSDCP_VAULT, "ogusdcp-vault");
        _assertContract(MORPHO_ADAPTER, "morpho-adapter");
        _assertContract(MORPHO_VAULT_V2_FACTORY, "morpho-vault-v2-factory");
        _assertContract(MORPHO_ADAPTER_FACTORY, "morpho-adapter-factory");
    }

    function _assertVaultPreconfiguration() internal view {
        IVaultV2Like vault = IVaultV2Like(OGUSDCP_VAULT);
        assertEq(vault.asset(), USDC, "ogusdcp-asset");
        assertEq(vault.decimals(), 18, "ogusdcp-decimals");
        assertEq(vault.name(), "Osero x Gauntlet USDC Prime", "ogusdcp-name");
        assertEq(vault.symbol(), "ogusdcp", "ogusdcp-symbol");
        assertEq(vault.totalAssets(), 1_000_048, "ogusdcp-total-assets");
        assertEq(vault.totalSupply(), 1_000_001e12, "ogusdcp-total-supply");
        assertEq(vault.convertToAssets(1e18), 1_000_046, "ogusdcp-convert-to-assets");
        assertEq(vault.owner(), GAUNTLET_OWNER_CURATOR_MULTISIG, "ogusdcp-owner");
        assertEq(vault.curator(), GAUNTLET_OWNER_CURATOR_MULTISIG, "ogusdcp-curator");
        assertTrue(vault.isAllocator(OGUSDCP_ALLOCATOR), "ogusdcp-allocator-not-authorized");
        assertTrue(vault.isSentinel(OGUSDCP_SENTINEL), "ogusdcp-sentinel-not-authorized");
        assertEq(vault.liquidityAdapter(), MORPHO_ADAPTER, "ogusdcp-liquidity-adapter");
        assertEq(vault.adaptersLength(), 1, "ogusdcp-adapter-count");
        assertEq(vault.adapters(0), MORPHO_ADAPTER, "ogusdcp-adapter-zero");
        assertEq(IMorphoAdapterLike(MORPHO_ADAPTER).parentVault(), OGUSDCP_VAULT, "morpho-adapter-parent-vault");
        assertTrue(IVaultV2FactoryLike(MORPHO_VAULT_V2_FACTORY).isVaultV2(OGUSDCP_VAULT), "ogusdcp-not-factory-vault");
        assertTrue(
            IMorphoAdapterFactoryLike(MORPHO_ADAPTER_FACTORY).isMorphoMarketV1AdapterV2(MORPHO_ADAPTER),
            "morpho-adapter-not-factory-adapter"
        );
        assertEq(vault.receiveSharesGate(), address(0), "ogusdcp-receive-shares-gate");
        assertEq(vault.sendAssetsGate(), address(0), "ogusdcp-send-assets-gate");
        assertEq(vault.sendSharesGate(), address(0), "ogusdcp-send-shares-gate");
        assertEq(vault.receiveAssetsGate(), address(0), "ogusdcp-receive-assets-gate");
        assertTrue(vault.canReceiveShares(OSERO_ALM_PROXY), "almproxy-cannot-receive-shares");
        assertTrue(vault.canSendShares(OSERO_ALM_PROXY), "almproxy-cannot-send-shares");
        assertTrue(vault.canReceiveAssets(OSERO_ALM_PROXY), "almproxy-cannot-receive-assets");
        assertTrue(vault.canSendAssets(OSERO_ALM_PROXY), "almproxy-cannot-send-assets");
        assertEq(vault.maxRate(), 31_709_791_983, "ogusdcp-max-rate");
        assertEq(vault.virtualShares(), 1e12, "ogusdcp-virtual-shares");
        assertEq(vault.performanceFee(), 0, "ogusdcp-performance-fee");
        assertEq(vault.managementFee(), 0, "ogusdcp-management-fee");
    }

    function _assertNewRateLimitsUnset() internal view {
        _assertUnsetRateLimit(PSM_USDS_TO_USDC_RATE_LIMIT_KEY, "psm-usds-to-usdc");
        _assertUnsetRateLimit(PSM_USDC_TO_USDS_RATE_LIMIT_KEY, "psm-usdc-to-usds");
        _assertUnsetRateLimit(OGUSDCP_DEPOSIT_RATE_LIMIT_KEY, "ogusdcp-deposit");
        _assertUnsetRateLimit(OGUSDCP_WITHDRAW_RATE_LIMIT_KEY, "ogusdcp-withdraw");
    }

    function _assertBeaconConfig(bytes32 id, address expectedFacet, PauWire[] memory expectedWires, string memory label)
        internal
        view
    {
        PauConfig memory config = IBeaconLike(SKY_PAU_BEACON).getConfig(id);
        assertEq(config.facet, expectedFacet, string.concat(label, "-beacon-facet"));
        assertEq(config.wires.length, expectedWires.length, string.concat(label, "-beacon-wire-count"));
        for (uint256 i = 0; i < expectedWires.length; ++i) {
            assertEq(
                config.wires[i].callSelector,
                expectedWires[i].callSelector,
                string.concat(label, "-beacon-call-selector")
            );
            assertEq(
                config.wires[i].delegateSelector,
                expectedWires[i].delegateSelector,
                string.concat(label, "-beacon-delegate-selector")
            );
        }
    }

    function _assertControllerConfigMatchesBeacon(bytes32 id, string memory label) internal view {
        PauConfig memory actual = controller.getConfig(id);
        PauConfig memory expected = IBeaconLike(SKY_PAU_BEACON).getConfig(id);
        assertEq(actual.facet, expected.facet, string.concat(label, "-controller-config-facet"));
        assertEq(actual.wires.length, expected.wires.length, string.concat(label, "-controller-config-wire-count"));
        for (uint256 i = 0; i < expected.wires.length; ++i) {
            assertEq(
                actual.wires[i].callSelector,
                expected.wires[i].callSelector,
                string.concat(label, "-controller-config-call-selector")
            );
            assertEq(
                actual.wires[i].delegateSelector,
                expected.wires[i].delegateSelector,
                string.concat(label, "-controller-config-delegate-selector")
            );
        }
    }

    function _assertControllerWires(PauWire[] memory wires, address facet, string memory label) internal view {
        for (uint256 i = 0; i < wires.length; ++i) {
            _assertWire(wires[i].callSelector, facet, wires[i].delegateSelector, label);
        }
    }

    function _expectedErc4626Wires() internal pure returns (PauWire[] memory wires) {
        wires = new PauWire[](ERC4626_FACET_WIRE_COUNT);
        wires[0] = PauWire(IOseroPauControllerLike.erc4626_VERSION.selector, bytes4(keccak256("VERSION()")));
        wires[1] = PauWire(
            IOseroPauControllerLike.erc4626_setMaxExchangeRate.selector,
            bytes4(keccak256("setMaxExchangeRate(address,uint256,uint256)"))
        );
        wires[2] = PauWire(
            IOseroPauControllerLike.erc4626_deposit.selector, bytes4(keccak256("deposit(address,uint256,uint256)"))
        );
        wires[3] = PauWire(
            IOseroPauControllerLike.erc4626_withdraw.selector, bytes4(keccak256("withdraw(address,uint256,uint256)"))
        );
        wires[4] = PauWire(
            IOseroPauControllerLike.erc4626_redeem.selector, bytes4(keccak256("redeem(address,uint256,uint256)"))
        );
        wires[5] = PauWire(
            IOseroPauControllerLike.erc4626_EXCHANGE_RATE_PRECISION.selector,
            bytes4(keccak256("EXCHANGE_RATE_PRECISION()"))
        );
        wires[6] = PauWire(
            IOseroPauControllerLike.erc4626_getMaxExchangeRate.selector,
            bytes4(keccak256("getMaxExchangeRate(address)"))
        );
        wires[7] = PauWire(
            IOseroPauControllerLike.erc4626_getDepositRateLimitKey.selector,
            bytes4(keccak256("getDepositRateLimitKey(address,address)"))
        );
        wires[8] = PauWire(
            IOseroPauControllerLike.erc4626_getWithdrawRateLimitKey.selector,
            bytes4(keccak256("getWithdrawRateLimitKey(address)"))
        );
    }

    function _expectedPsmWires() internal pure returns (PauWire[] memory wires) {
        wires = new PauWire[](PSM_FACET_WIRE_COUNT);
        wires[0] = PauWire(IOseroPauControllerLike.psm_VERSION.selector, bytes4(keccak256("VERSION()")));
        wires[1] = PauWire(IOseroPauControllerLike.psm_dai.selector, bytes4(keccak256("dai()")));
        wires[2] = PauWire(IOseroPauControllerLike.psm_daiUSDS.selector, bytes4(keccak256("daiUSDS()")));
        wires[3] = PauWire(IOseroPauControllerLike.psm_psm.selector, bytes4(keccak256("psm()")));
        wires[4] = PauWire(IOseroPauControllerLike.psm_usdc.selector, bytes4(keccak256("usdc()")));
        wires[5] = PauWire(IOseroPauControllerLike.psm_usds.selector, bytes4(keccak256("usds()")));
        wires[6] =
            PauWire(IOseroPauControllerLike.psm_swapUSDSToUSDC.selector, bytes4(keccak256("swapUSDSToUSDC(uint256)")));
        wires[7] =
            PauWire(IOseroPauControllerLike.psm_swapUSDCToUSDS.selector, bytes4(keccak256("swapUSDCToUSDS(uint256)")));
        wires[8] = PauWire(
            IOseroPauControllerLike.psm_to18ConversionFactor.selector, bytes4(keccak256("to18ConversionFactor()"))
        );
        wires[9] = PauWire(
            IOseroPauControllerLike.psm_usdcToUSDSSwapRateLimitKey.selector,
            bytes4(keccak256("usdcToUSDSSwapRateLimitKey()"))
        );
        wires[10] = PauWire(
            IOseroPauControllerLike.psm_usdsToUSDCSwapRateLimitKey.selector,
            bytes4(keccak256("usdsToUSDCSwapRateLimitKey()"))
        );
    }

    function _snapshotExistingRateLimits() internal view returns (ExistingRateLimitsSnapshot memory snapshot) {
        snapshot.mint = rateLimits.getRateLimitData(USDS_MINT_RATE_LIMIT_KEY);
        snapshot.burn = rateLimits.getRateLimitData(USDS_BURN_RATE_LIMIT_KEY);
        snapshot.sparklendDeposit = rateLimits.getRateLimitData(SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY);
        snapshot.sparklendWithdraw = rateLimits.getRateLimitData(SPARKLEND_USDS_WITHDRAW_RATE_LIMIT_KEY);
    }

    function _snapshotLaunchConfiguration() internal view returns (LaunchConfigurationSnapshot memory snapshot) {
        IAccessControlsLike accessControls = IAccessControlsLike(OSERO_ACCESS_CONTROLS);
        IALMProxyLike almProxy = IALMProxyLike(OSERO_ALM_PROXY);
        IAdministeredAgentLike agent = IAdministeredAgentLike(OSERO_ADMINISTERED_AGENT);
        snapshot.subProxyAccessAdmin = accessControls.hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY);
        snapshot.subProxyRateLimitsAdmin = rateLimits.hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY);
        snapshot.subProxyAlmProxyAdmin = almProxy.hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY);
        snapshot.agentAllocator = accessControls.hasRole(ALLOCATOR_ROLE, OSERO_ADMINISTERED_AGENT);
        snapshot.controllerRateLimits = rateLimits.hasRole(CONTROLLER, OSERO_CONTROLLER);
        snapshot.controllerAlmProxy = almProxy.hasRole(CONTROLLER, OSERO_CONTROLLER);
        snapshot.pasAccessAdmin = accessControls.hasRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR);
        snapshot.pasRateLimitsAdmin = rateLimits.hasRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR);
        snapshot.accessAdminCount = accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE);
        snapshot.agentAdminCount = agent.adminCount();
        snapshot.agentActorCount = agent.actorCount();
        snapshot.agentRevokerCount = agent.revokerCount();
        snapshot.agentGrantorCount = agent.grantorCount();
        snapshot.usdsVault = controller.usds_vault();
        snapshot.sparklendMaxSlippage = controller.aave_getMaxSlippage(SparkLend.USDS_SPTOKEN);
        snapshot.litePsmBud = ILitePsmLike(MCD_LITE_PSM_USDC_A).bud(OSERO_ALM_PROXY);
        snapshot.starGuardWard = ISubProxyLike(OSERO_PROXY).wards(OSERO_STAR_GUARD);
    }

    function _assertExistingRateLimitsUnchanged(ExistingRateLimitsSnapshot memory before_) internal view {
        _assertRateLimitDataUnchanged(before_.mint, rateLimits.getRateLimitData(USDS_MINT_RATE_LIMIT_KEY), "mint");
        _assertRateLimitDataUnchanged(before_.burn, rateLimits.getRateLimitData(USDS_BURN_RATE_LIMIT_KEY), "burn");
        _assertRateLimitDataUnchanged(
            before_.sparklendDeposit,
            rateLimits.getRateLimitData(SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY),
            "sparklend-deposit"
        );
        _assertRateLimitDataUnchanged(
            before_.sparklendWithdraw,
            rateLimits.getRateLimitData(SPARKLEND_USDS_WITHDRAW_RATE_LIMIT_KEY),
            "sparklend-withdraw"
        );
    }

    function _assertRateLimitDataUnchanged(
        IRateLimitsLike.RateLimitData memory before_,
        IRateLimitsLike.RateLimitData memory after_,
        string memory label
    ) internal pure {
        assertEq(after_.maxAmount, before_.maxAmount, string.concat(label, "-max-amount-changed"));
        assertEq(after_.slope, before_.slope, string.concat(label, "-slope-changed"));
        assertEq(after_.lastAmount, before_.lastAmount, string.concat(label, "-last-amount-changed"));
        assertEq(after_.lastUpdated, before_.lastUpdated, string.concat(label, "-last-updated-changed"));
    }

    function _assertLaunchConfigurationUnchanged(LaunchConfigurationSnapshot memory before_) internal view {
        LaunchConfigurationSnapshot memory after_ = _snapshotLaunchConfiguration();
        assertEq(after_.subProxyAccessAdmin, before_.subProxyAccessAdmin, "subproxy-access-admin-changed");
        assertEq(after_.subProxyRateLimitsAdmin, before_.subProxyRateLimitsAdmin, "subproxy-ratelimits-admin-changed");
        assertEq(after_.subProxyAlmProxyAdmin, before_.subProxyAlmProxyAdmin, "subproxy-almproxy-admin-changed");
        assertEq(after_.agentAllocator, before_.agentAllocator, "agent-allocator-role-changed");
        assertEq(after_.controllerRateLimits, before_.controllerRateLimits, "controller-ratelimits-role-changed");
        assertEq(after_.controllerAlmProxy, before_.controllerAlmProxy, "controller-almproxy-role-changed");
        assertEq(after_.pasAccessAdmin, before_.pasAccessAdmin, "pas-access-admin-changed");
        assertEq(after_.pasRateLimitsAdmin, before_.pasRateLimitsAdmin, "pas-ratelimits-admin-changed");
        assertEq(after_.accessAdminCount, before_.accessAdminCount, "access-admin-count-changed");
        assertEq(after_.agentAdminCount, before_.agentAdminCount, "agent-admin-count-changed");
        assertEq(after_.agentActorCount, before_.agentActorCount, "agent-actor-count-changed");
        assertEq(after_.agentRevokerCount, before_.agentRevokerCount, "agent-revoker-count-changed");
        assertEq(after_.agentGrantorCount, before_.agentGrantorCount, "agent-grantor-count-changed");
        assertEq(after_.usdsVault, before_.usdsVault, "usds-vault-changed");
        assertEq(after_.sparklendMaxSlippage, before_.sparklendMaxSlippage, "sparklend-max-slippage-changed");
        assertEq(after_.litePsmBud, before_.litePsmBud, "lite-psm-bud-changed");
        assertEq(after_.starGuardWard, before_.starGuardWard, "star-guard-ward-changed");
    }

    /// @dev Config for the inherited pre-spell integration test; the fork has only the launch facets wired.
    function _expectedControllerIntegrations() internal pure override returns (ExpectedIntegration[] memory expected) {
        expected = new ExpectedIntegration[](2);
        expected[0] = ExpectedIntegration(USDS_FACET_INTEGRATION_ID, SKY_PAU_USDS_FACET, 8, "usds");
        expected[1] = ExpectedIntegration(AAVE_FACET_INTEGRATION_ID, SKY_PAU_AAVE_FACET, 7, "aave");
    }
}
