// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";

import {Base as SparkBase} from "spark-address-registry/Base.sol";
import {SparkLend} from "spark-address-registry/SparkLend.sol";

import {Ethereum as SkyPau} from "sky-pau-registry/Ethereum.sol";

import {BeaconConfig} from "diamond-pau/src/libraries/BeaconConfig.sol";

import {IExecutor} from "spark-gov-relay/src/interfaces/IExecutor.sol";

import {CCTPForwarder} from "xchain-helpers/forwarders/CCTPForwarder.sol";
import {Bridge} from "xchain-helpers/testing/Bridge.sol";
import {CCTPV2BridgeTesting} from "xchain-helpers/testing/bridges/CCTPV2BridgeTesting.sol";

import {
    IAccessControlsLike,
    IAdministeredAgentLike,
    IALMProxyLike,
    IBeaconLike,
    IOseroPauControllerLike,
    IRateLimitsLike,
    ISpellLike,
    ISubProxyLike,
    IVatLike,
    PauConfig,
    PauIntegration,
    PauWire
} from "../test-harness/OseroTestBase.sol";
import {ExpectedIntegration} from "../test-harness/CommonPauSpellTests.sol";
import {CommonBaseSpellTests} from "../test-harness/CommonBaseSpellTests.sol";

import {OseroEthereum_20261119} from "./OseroEthereum_20261119.sol";

/// @dev Test-only: `OseroEthereum_20261119` as it will be deployed, with `PAYLOAD_BASE` set in the constructor.
///      Until the Base payload is deployed, the tests run it with `PAYLOAD_BASE` set to a freshly deployed Base
///      payload (`CrossChainSpellRunner._setupBaseRelay`); `test_ETHEREUM_payloadWithBasePayloadMatchesSpellBytecode`
///      checks it has the spell's runtime code.
contract OseroEthereum_20261119_WithBasePayload is OseroEthereum_20261119 {
    constructor(address payloadBase) {
        PAYLOAD_BASE = payloadBase;
    }
}

interface ICCTPControllerLike {
    function cctp_VERSION() external view returns (string memory);
    function cctp_DESTINATION_CALLER() external view returns (bytes32);
    function cctp_MIN_FINALITY_THRESHOLD() external view returns (uint32);
    function cctp_cctp() external view returns (address);
    function cctp_usdc() external view returns (address);
    function cctp_setDomainParameters(
        uint32 destinationDomain,
        bytes32 recipient,
        uint32 minFeeCapRate,
        uint32 maxFeeCapRate
    ) external;
    function cctp_transfer(uint256 amount, uint32 destinationDomain, uint64 feeCapRate) external;
    function cctp_toCCTPRateLimitKey() external view returns (bytes32);
    function cctp_getDomainParameters(uint32 destinationDomain)
        external
        view
        returns (bytes32 mintRecipient, uint32 minFeeCapRate, uint32 maxFeeCapRate);
    function cctp_getToDomainRateLimitKey(uint32 destinationDomain) external view returns (bytes32);
}

interface ICCTPFacetLike {
    function VERSION() external view returns (string memory);
    function DESTINATION_CALLER() external view returns (bytes32);
    function MIN_FINALITY_THRESHOLD() external view returns (uint32);
    function cctp() external view returns (address);
    function usdc() external view returns (address);
    function toCCTPRateLimitKey() external pure returns (bytes32);
    function getToDomainRateLimitKey(uint32 destinationDomain) external pure returns (bytes32);
}

interface IERC4626FacetLike {
    function VERSION() external view returns (string memory);
    function EXCHANGE_RATE_PRECISION() external view returns (uint256);
    function getDepositRateLimitKey(address token, address asset) external pure returns (bytes32);
    function getWithdrawRateLimitKey(address token) external pure returns (bytes32);
}

interface IBeaconAdminLike {
    function getConfig(bytes32 id) external view returns (PauConfig memory);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function removeIntegration(bytes32 id) external;
}

interface IEnumerableAccessControlsLike {
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IAdministeredAgentRolesLike {
    function getActor(uint256 index) external view returns (address);
    function getIsAdmin(address account) external view returns (bool);
    function getIsGrantor(address account) external view returns (bool);
    function getIsRevoker(address account) external view returns (bool);
}

interface IRateLimitsAdminLike {
    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;
}

interface IPASConfiguratorLike {
    function beamState() external view returns (address);
    function setRateLimit(address rateLimits, bytes32 key, uint256 maxAmount, uint256 slope) external;
    function callControllerAction(address controller, bytes calldata data) external returns (bytes memory ret);
}

interface IPASBeamStateLike {
    function wards(address usr) external view returns (uint256);
    function stopped() external view returns (bool);
    function rateLimits(address rateLimits_) external view returns (uint256);
    function controllers(address controller) external view returns (uint256);
    function cBeams(address cBeam) external view returns (uint256);
    function rateLimitsCBeams(address rateLimits_, address cBeam) external view returns (uint256);
    function controllersCBeams(address controller, address cBeam) external view returns (uint256);
    function getHop(address rateLimits_) external view returns (uint256);
    function getMaxChange(address rateLimits_) external view returns (uint256);
    function addRateLimits(address rateLimits_) external;
    function addController(address controller) external;
    function addCBeam(address cBeam) external;
    function setCBeamForRateLimits(address rateLimits_, address cBeam) external;
    function setCBeamForController(address controller, address cBeam) external;
    function addInitRateLimits(bytes32 key, address rateLimits_, uint256 maxAmount, uint256 slope) external;
    function addInitControllerActions(bytes calldata data, address controller) external returns (bytes32 key);
}

interface IVaultV2Like {
    function adapters(uint256 index) external view returns (address);
    function adaptersLength() external view returns (uint256);
    function asset() external view returns (address);
    function canReceiveAssets(address account) external view returns (bool);
    function canReceiveShares(address account) external view returns (bool);
    function canSendAssets(address account) external view returns (bool);
    function canSendShares(address account) external view returns (bool);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function curator() external view returns (address);
    function decimals() external view returns (uint8);
    function isAllocator(address account) external view returns (bool);
    function isSentinel(address account) external view returns (bool);
    function liquidityAdapter() external view returns (address);
    function managementFee() external view returns (uint256);
    function maxRate() external view returns (uint256);
    function name() external view returns (string memory);
    function owner() external view returns (address);
    function performanceFee() external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function receiveAssetsGate() external view returns (address);
    function receiveSharesGate() external view returns (address);
    function sendAssetsGate() external view returns (address);
    function sendSharesGate() external view returns (address);
    function symbol() external view returns (string memory);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function virtualShares() external view returns (uint256);
}

interface IMorphoAdapterLike {
    function parentVault() external view returns (address);
}

interface IVaultV2FactoryLike {
    function isVaultV2(address vault) external view returns (bool);
}

interface IMorphoAdapterFactoryLike {
    function isMorphoMarketV1AdapterV2(address adapter) external view returns (bool);
}

interface ISafeLike {
    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory modules, address next);
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
}

contract OseroEthereum_20261119_Test is CommonBaseSpellTests {
    // Forks at blocks with aligned timestamps (November 5, 2026 15:30 UTC), after the technical-scope
    // readbacks. The Sky PAU Beacon on Base does not register the ERC-4626 facet yet: the November 19, 2026
    // Sky Core spell registers it (Pre-requirements #1). Until BASE_FORK_BLOCK is moved past the registration,
    // `setUp` simulates it (`_registerErc4626FacetOnBaseBeaconAsSkyCore`), so the Base payload executes against the
    // Diamond PAU on Base as if the ERC-4626 facet were enabled.
    uint256 internal constant MAINNET_FORK_BLOCK = 26_349_341;
    uint256 internal constant BASE_FORK_BLOCK = 53_550_442;

    // The on-chain payloads once deployed; address(0) while the spell is in development.
    address internal constant DEPLOYED_PAYLOAD = address(0);
    address internal constant DEPLOYED_BASE_PAYLOAD = address(0);

    // Circle CCTP V2 (same addresses on Ethereum and Base). Source: https://developers.circle.com/cctp/evm-smart-contracts
    address internal constant CCTP_TOKEN_MESSENGER_V2 = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;

    // Sky PAS Configurator on Ethereum. Source: https://chainlog.skyeco.com/ (key: PAS_CONFIGURATOR)
    address internal constant PAS_CONFIGURATOR = 0xb7E61Df6CAb0A51E9A5dab1A7DD3f942dDe5b929;
    // Osero x Gauntlet USDC Prime Vault on Ethereum, onboarded in the October 8, 2026 spell.
    address internal constant OGUSDCP_VAULT = 0x802148D518A6De2aF866f9A61ffB5e5C39156dB2;

    // Base addresses. Source: the technical scope (Trusted addresses, Pre-deployed contracts).
    address internal constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant BASE_SKY_PAU_BEACON = 0x7ac96180C4d6b2A328D3a19ac059D0E7Fc3C6d41;
    address internal constant BASE_SKY_PAU_CCTP_FACET = 0xb22d50c393c6E1D13E3e05B172448dD8BF8DdC32;
    address internal constant BASE_SKY_PAU_ERC4626_FACET = 0xC6Fb54348feCdb2790Fa9130D1fc35d6E101C97D;
    address internal constant BASE_PAS_CONFIGURATOR = 0x458Acd38fD749F6325039e63e8Bc496dBc286D11;
    address internal constant BASE_PAS_BEAM_STATE = 0x29840a8519013F483d94781b5C1671b552A109e1;
    address internal constant BASE_SKY_GOV_RELAY = 0xdD0BCc201C9E47c6F6eE68E4dB05b652Bb6aC255;
    address internal constant BASE_SPARK_EXECUTOR = 0xF93B7122450A50AF3e5A76E1d546e95Ac1d0F579;
    address internal constant BASE_SOTER_OPERATOR = 0x3dE688267Cf099307aBdd85F64D8efe03D0b2b26;
    address internal constant BASE_SOTER_FREEZER = 0xF61F90907551a8A23f0f8EEE9658Fa53326de603;
    // Osero Operator Multisig on Base, the cBEAM Sky Core pairs to Osero on the Base PAS (Pre-requirements #5); the
    // same address and owners as on Ethereum. Source: the technical scope (Pre-deployed contracts #14).
    address internal constant BASE_OSERO_CBEAM = 0x42D1038017E466b413aa44Ae798E30FB80b2E180;

    address internal constant OGUSDCB_VAULT = 0x8c1e205C408b90A0dDDbD53594049a379557c651;
    address internal constant OGUSDCB_CURATOR_MULTISIG = 0x256DaC8fad2788F4182A42cE8F26029F0DEd7cf9;
    address internal constant GAUNTLET_CO_CURATOR_MULTISIG = 0x9E33faAE38ff641094fa68c65c2cE600b3410585;
    address internal constant SOTER_LABS_CO_CURATOR_MULTISIG = 0x037A8456FB92dB66590C0060eE4174cC6812f518;
    address internal constant OGUSDCB_ALLOCATOR = 0x6939A35d32E9bE623e08aA0bceD96D4baC170bB3;
    address internal constant OGUSDCB_SENTINEL = 0x6a0dC94d80429dd4B03E8838CE8d6BEE725bE39B;
    address internal constant SOTER_LABS_SENTINEL_MULTISIG = 0xf51A112fB2cB63E3CB3eeB7feA8c7c58625868C7;
    address internal constant BASE_MORPHO_ADAPTER = 0x8BA35B5303c5B2550fFE76dC9764458A1cE2ba8a;
    address internal constant BASE_MORPHO_VAULT_V2_FACTORY = 0x4501125508079A99ebBebCE205DeC9593C2b5857;
    address internal constant BASE_MORPHO_ADAPTER_FACTORY = 0x9a1B378C43BA535cDB89934230F0D3890c51C0EB;
    // An ERC-4626 vault on Base with USDC as asset that Osero does not onboard (Spark sUSDC on Base).
    address internal constant UNCONFIGURED_BASE_USDC_VAULT = SparkBase.SUSDC;

    bytes32 internal constant USDS_FACET_INTEGRATION_ID = "USDS_FACET";
    bytes32 internal constant AAVE_FACET_INTEGRATION_ID = "AAVE_FACET";
    bytes32 internal constant ERC4626_FACET_INTEGRATION_ID = "ERC4626_FACET";
    bytes32 internal constant PSM_FACET_INTEGRATION_ID = "PSM_FACET";
    bytes32 internal constant CCTP_FACET_INTEGRATION_ID = "CCTP_FACET";

    // Keys and encoded arguments as written in the technical scope (Proposed actions).
    bytes32 internal constant CCTP_RATE_LIMIT_KEY = 0x0476a9fd902eafdb5bcdabd9f0523dd7aacf7aa0c38c0e6ab912f5fed00f8e11;
    bytes32 internal constant CCTP_TO_BASE_RATE_LIMIT_KEY =
        0xbab34b58275e6736d9a866c36a2d88d671ed8b627228e6bd17efb1b076a59881;
    bytes32 internal constant CCTP_TO_ETHEREUM_RATE_LIMIT_KEY =
        0x90b598dae614822d554ec4f627bb5feab505106473a7911f34b36c0b3b9695c7;
    bytes32 internal constant OGUSDCB_DEPOSIT_RATE_LIMIT_KEY =
        0x4530b5750e1bd4febbd736da62648a217afd5809f6d9f626fdae219ba97adf32;
    bytes32 internal constant OGUSDCB_WITHDRAW_RATE_LIMIT_KEY =
        0x6962440fb603fec4e7a4a755188471e31b1701e8f60323358e62b6e0f0c596aa;
    bytes32 internal constant BASE_ALM_PROXY_RECIPIENT =
        0x00000000000000000000000061ee4c5157ac876d1f5132dc6832ac4896f533c9;
    bytes32 internal constant ETHEREUM_ALM_PROXY_RECIPIENT =
        0x0000000000000000000000006d370e359e9cbd0fd35bb38faf705d84238cb884;

    bytes32 internal constant DERIVED_CCTP_RATE_LIMIT_KEY = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 internal constant DERIVED_CCTP_TO_BASE_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_USDC_TO_DOMAIN"), uint32(6)));
    bytes32 internal constant DERIVED_CCTP_TO_ETHEREUM_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_USDC_TO_DOMAIN"), uint32(0)));
    bytes32 internal constant DERIVED_OGUSDCB_DEPOSIT_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_4626_DEPOSIT"), BASE_USDC, OGUSDCB_VAULT));
    bytes32 internal constant DERIVED_OGUSDCB_WITHDRAW_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_4626_WITHDRAW"), OGUSDCB_VAULT));

    // Existing Ethereum keys (technical scope, Post-checks #2).
    bytes32 internal constant USDS_MINT_RATE_LIMIT_KEY = keccak256("LIMIT_USDS_MINT");
    bytes32 internal constant USDS_BURN_RATE_LIMIT_KEY = keccak256("LIMIT_USDS_BURN");
    bytes32 internal constant PSM_USDS_TO_USDC_RATE_LIMIT_KEY = keccak256("LIMIT_USDS_TO_USDC");
    bytes32 internal constant PSM_USDC_TO_USDS_RATE_LIMIT_KEY = keccak256("LIMIT_USDC_TO_USDS");
    bytes32 internal constant SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_AAVE_DEPOSIT"), USDS, SparkLend.POOL, SparkLend.USDS_SPTOKEN));
    bytes32 internal constant SPARKLEND_USDS_WITHDRAW_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_AAVE_WITHDRAW"), SparkLend.POOL, SparkLend.USDS_SPTOKEN));
    bytes32 internal constant OGUSDCP_DEPOSIT_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_4626_DEPOSIT"), USDC, OGUSDCP_VAULT));
    bytes32 internal constant OGUSDCP_WITHDRAW_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_4626_WITHDRAW"), OGUSDCP_VAULT));

    uint256 internal constant CCTP_TO_DOMAIN_MAX = 10_000_000e6;
    uint256 internal constant CCTP_TO_DOMAIN_SLOPE = uint256(50_000_000e6) / 1 days;
    uint256 internal constant OGUSDCB_DEPOSIT_MAX = 15_000_000e6;
    uint256 internal constant OGUSDCB_DEPOSIT_SLOPE = uint256(10_000_000e6) / 1 days;
    uint256 internal constant OGUSDCB_MAX_EXCHANGE_RATE = 2e24;
    uint256 internal constant EXCHANGE_RATE_PRECISION = 1e36;
    uint32 internal constant CCTP_MIN_FINALITY_THRESHOLD = 2_000;

    uint256 internal constant CCTP_FACET_WIRE_COUNT = 10;
    uint256 internal constant ERC4626_FACET_WIRE_COUNT = 9;

    uint256 internal constant ROUND_TRIP_USDS_AMOUNT = 1_000e18;
    uint256 internal constant ROUND_TRIP_USDC_AMOUNT = 1_000e6;
    uint256 internal constant OPERATIONAL_TEST_USDC_AMOUNT = 1_000_000e6;
    uint256 internal constant PARTIAL_RECOVERY_TIME = 20 minutes;

    // --- Base PAS fixture (NOT part of this spell) ---
    // Sky Core registers Osero on the Base PAS and pairs the Osero Operator Multisig on Base in the November 19,
    // 2026 Sky Core spell (Pre-requirements #5). The fixture registers the spell's CCTP-to-Ethereum limit as the
    // BeamState default and `removeIntegrations([ERC4626_FACET])` as a controller action, then lowers the limit.
    uint256 internal constant PAS_FIXTURE_LOWERED_CCTP_MAX = 5_000_000e6;
    uint256 internal constant PAS_FIXTURE_LOWERED_CCTP_SLOPE = uint256(25_000_000e6) / 1 days;

    // Safe storage slot of the transaction guard: keccak256("guard_manager.guard.address").
    bytes32 internal constant SAFE_GUARD_STORAGE_SLOT =
        0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;
    address internal constant SAFE_SENTINEL_MODULES = address(0x1);

    bytes32 internal constant INTEGRATION_SET_TOPIC = keccak256("IntegrationSet(bytes32,(address,(bytes4,bytes4)[]))");
    bytes32 internal constant INTEGRATION_REMOVED_TOPIC = keccak256("IntegrationRemoved(bytes32)");
    bytes32 internal constant CCTP_DOMAIN_PARAMETERS_SET_TOPIC =
        keccak256("CCTPDomainParametersSet(uint32,bytes32,uint32,uint32)");
    bytes32 internal constant RATE_LIMIT_DATA_SET_TOPIC =
        keccak256("RateLimitDataSet(bytes32,uint256,uint256,uint256,uint256)");
    bytes32 internal constant ERC4626_MAX_EXCHANGE_RATE_SET_TOPIC =
        keccak256("ERC4626MaxExchangeRateSet(address,uint256)");
    bytes32 internal constant ROLE_GRANTED_TOPIC = keccak256("RoleGranted(bytes32,address,address)");
    bytes32 internal constant ROLE_REVOKED_TOPIC = keccak256("RoleRevoked(bytes32,address,address)");
    bytes32 internal constant ACTOR_ADDED_TOPIC = keccak256("ActorAdded(address,address)");
    bytes32 internal constant REVOKER_ADDED_TOPIC = keccak256("RevokerAdded(address,address)");
    bytes32 internal constant ADMIN_ADDED_TOPIC = keccak256("AdminAdded(address,address)");
    bytes32 internal constant GRANTOR_ADDED_TOPIC = keccak256("GrantorAdded(address,address)");
    bytes32 internal constant ACTIONS_SET_EXECUTED_TOPIC = keccak256("ActionsSetExecuted(uint256,address,bytes[])");

    IERC20 internal constant usdc = IERC20(USDC);
    IERC20 internal constant baseUsdc = IERC20(BASE_USDC);
    IERC20 internal constant ogusdcb = IERC20(OGUSDCB_VAULT);

    ICCTPControllerLike internal constant cctpController = ICCTPControllerLike(OSERO_CONTROLLER);
    ICCTPControllerLike internal constant baseCctpController = ICCTPControllerLike(BASE_OSERO_CONTROLLER);
    IOseroPauControllerLike internal constant baseController = IOseroPauControllerLike(BASE_OSERO_CONTROLLER);
    IRateLimitsLike internal constant baseRateLimits = IRateLimitsLike(BASE_OSERO_RATE_LIMITS);

    Bridge internal cctpBridge;

    event CCTPTransferInitiated(
        uint32 indexed destinationDomain, bytes32 indexed mintRecipient, uint256 amount, uint256 maxFee
    );
    event IntegrationRemoved(bytes32 indexed id);
    event SetRateLimit(address indexed rateLimits, bytes32 indexed key, uint256 maxAmount, uint256 slope);
    event CallControllerAction(address indexed controller, bytes data);

    struct ExistingRateLimitsSnapshot {
        IRateLimitsLike.RateLimitData[8] data;
    }

    struct LaunchConfigurationSnapshot {
        bool subProxyAccessAdmin;
        bool subProxyRateLimitsAdmin;
        bool subProxyAlmProxyAdmin;
        bool pasAccessAdmin;
        bool pasRateLimitsAdmin;
        bool agentAllocator;
        bool controllerRateLimits;
        bool controllerAlmProxy;
        uint256 accessAdminCount;
        uint256 allocatorCount;
        uint256 agentAdminCount;
        uint256 agentActorCount;
        uint256 agentRevokerCount;
        uint256 agentGrantorCount;
        uint256 starGuardWard;
    }

    constructor() {
        spellId = "20261119";
    }

    function setUp() public {
        _setupDomains(MAINNET_FORK_BLOCK, BASE_FORK_BLOCK);
        _registerErc4626FacetOnBaseBeaconAsSkyCore();
        _setupPayload(DEPLOYED_PAYLOAD);
        _setupBasePayload(DEPLOYED_BASE_PAYLOAD);
        _setupBaseRelay();
    }

    /**********************************************************************************************/
    /*** Technical scope                                                                        ***/
    /**********************************************************************************************/

    function test_ETHEREUM_scopeKeysAndEncodedParametersMatchTechnicalScope() public {
        assertEq(DERIVED_CCTP_RATE_LIMIT_KEY, CCTP_RATE_LIMIT_KEY, "cctp-derived-key");
        assertEq(DERIVED_CCTP_TO_BASE_RATE_LIMIT_KEY, CCTP_TO_BASE_RATE_LIMIT_KEY, "cctp-to-base-derived-key");
        assertEq(
            DERIVED_CCTP_TO_ETHEREUM_RATE_LIMIT_KEY, CCTP_TO_ETHEREUM_RATE_LIMIT_KEY, "cctp-to-ethereum-derived-key"
        );
        assertEq(DERIVED_OGUSDCB_DEPOSIT_RATE_LIMIT_KEY, OGUSDCB_DEPOSIT_RATE_LIMIT_KEY, "ogusdcb-deposit-derived-key");
        assertEq(
            DERIVED_OGUSDCB_WITHDRAW_RATE_LIMIT_KEY, OGUSDCB_WITHDRAW_RATE_LIMIT_KEY, "ogusdcb-withdraw-derived-key"
        );
        assertEq(bytes32(uint256(uint160(BASE_OSERO_ALM_PROXY))), BASE_ALM_PROXY_RECIPIENT, "base-recipient");
        assertEq(bytes32(uint256(uint160(OSERO_ALM_PROXY))), ETHEREUM_ALM_PROXY_RECIPIENT, "ethereum-recipient");
        assertEq(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM, 0, "ethereum-cctp-domain");
        assertEq(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE, 6, "base-cctp-domain");
        assertEq(CCTP_TO_DOMAIN_SLOPE, 578_703_703, "cctp-to-domain-slope-literal");
        assertEq(OGUSDCB_DEPOSIT_SLOPE, 115_740_740, "ogusdcb-deposit-slope-literal");
        assertEq(CCTP_TO_DOMAIN_MAX, 10_000_000_000_000, "cctp-to-domain-max-literal");
        assertEq(OGUSDCB_DEPOSIT_MAX, 15_000_000_000_000, "ogusdcb-deposit-max-literal");

        ICCTPFacetLike cctpFacet = ICCTPFacetLike(SkyPau.CCTP_FACET);
        assertEq(cctpFacet.toCCTPRateLimitKey(), CCTP_RATE_LIMIT_KEY, "cctp-facet-key");
        assertEq(cctpFacet.getToDomainRateLimitKey(6), CCTP_TO_BASE_RATE_LIMIT_KEY, "cctp-facet-to-base-key");

        _selectBase();
        ICCTPFacetLike baseCctpFacet = ICCTPFacetLike(BASE_SKY_PAU_CCTP_FACET);
        IERC4626FacetLike baseErc4626Facet = IERC4626FacetLike(BASE_SKY_PAU_ERC4626_FACET);
        assertEq(baseCctpFacet.toCCTPRateLimitKey(), CCTP_RATE_LIMIT_KEY, "base-cctp-facet-key");
        assertEq(
            baseCctpFacet.getToDomainRateLimitKey(0), CCTP_TO_ETHEREUM_RATE_LIMIT_KEY, "base-cctp-facet-to-ethereum-key"
        );
        assertEq(
            baseErc4626Facet.getDepositRateLimitKey(OGUSDCB_VAULT, BASE_USDC),
            OGUSDCB_DEPOSIT_RATE_LIMIT_KEY,
            "base-erc4626-facet-deposit-key"
        );
        assertEq(
            baseErc4626Facet.getWithdrawRateLimitKey(OGUSDCB_VAULT),
            OGUSDCB_WITHDRAW_RATE_LIMIT_KEY,
            "base-erc4626-facet-withdraw-key"
        );
    }

    /**********************************************************************************************/
    /*** Ethereum                                                                               ***/
    /**********************************************************************************************/

    function test_ETHEREUM_cctpPreconfiguration() public view {
        _assertContract(SkyPau.CCTP_FACET, "sky-pau-cctp-facet");
        _assertContract(CCTP_TOKEN_MESSENGER_V2, "cctp-token-messenger-v2");
        _assertConfigWires(
            IBeaconLike(SKY_PAU_BEACON).getConfig(CCTP_FACET_INTEGRATION_ID),
            SkyPau.CCTP_FACET,
            _expectedCctpWires(),
            "ethereum-beacon-cctp"
        );

        ICCTPFacetLike cctpFacet = ICCTPFacetLike(SkyPau.CCTP_FACET);
        assertEq(cctpFacet.VERSION(), "1.0.0", "cctp-version");
        assertEq(cctpFacet.cctp(), CCTP_TOKEN_MESSENGER_V2, "cctp-token-messenger");
        assertEq(cctpFacet.usdc(), USDC, "cctp-usdc");
        assertEq(cctpFacet.MIN_FINALITY_THRESHOLD(), CCTP_MIN_FINALITY_THRESHOLD, "cctp-min-finality-threshold");
        assertEq(cctpFacet.DESTINATION_CALLER(), bytes32(0), "cctp-destination-caller");

        assertEq(controller.integrations().length, 4, "unexpected-pre-spell-integration-count");
        assertEq(
            controller.getDispatch(ICCTPControllerLike.cctp_transfer.selector).facet,
            address(0),
            "cctp-transfer-already-wired"
        );
        _assertUnsetRateLimit(CCTP_RATE_LIMIT_KEY, "cctp");
        _assertUnsetRateLimit(CCTP_TO_BASE_RATE_LIMIT_KEY, "cctp-to-base");
    }

    function test_ETHEREUM_spellExecutionEnablesCctpIntegration() public {
        _executeSpellViaStarGuard(payload);

        ExpectedIntegration[] memory expected = new ExpectedIntegration[](5);
        expected[0] = ExpectedIntegration(USDS_FACET_INTEGRATION_ID, SKY_PAU_USDS_FACET, 8, "usds");
        expected[1] = ExpectedIntegration(AAVE_FACET_INTEGRATION_ID, SKY_PAU_AAVE_FACET, 7, "aave");
        expected[2] = ExpectedIntegration(ERC4626_FACET_INTEGRATION_ID, SKY_PAU_ERC4626_FACET, 9, "erc4626");
        expected[3] = ExpectedIntegration(PSM_FACET_INTEGRATION_ID, SKY_PAU_PSM_FACET, 11, "psm");
        expected[4] = ExpectedIntegration(CCTP_FACET_INTEGRATION_ID, SkyPau.CCTP_FACET, CCTP_FACET_WIRE_COUNT, "cctp");
        _assertControllerIntegrations(expected);

        _assertConfigEquals(
            controller.getConfig(CCTP_FACET_INTEGRATION_ID),
            IBeaconLike(SKY_PAU_BEACON).getConfig(CCTP_FACET_INTEGRATION_ID),
            "ethereum-cctp"
        );
        _assertWiresDispatched(OSERO_CONTROLLER, _expectedCctpWires(), SkyPau.CCTP_FACET, "ethereum-cctp");

        assertEq(cctpController.cctp_VERSION(), "1.0.0", "controller-cctp-version");
        assertEq(cctpController.cctp_cctp(), CCTP_TOKEN_MESSENGER_V2, "controller-cctp-token-messenger");
        assertEq(cctpController.cctp_usdc(), USDC, "controller-cctp-usdc");
        assertEq(
            cctpController.cctp_MIN_FINALITY_THRESHOLD(), CCTP_MIN_FINALITY_THRESHOLD, "controller-cctp-min-finality"
        );
        assertEq(cctpController.cctp_DESTINATION_CALLER(), bytes32(0), "controller-cctp-destination-caller");
        assertEq(cctpController.cctp_toCCTPRateLimitKey(), CCTP_RATE_LIMIT_KEY, "controller-cctp-key");
        assertEq(
            cctpController.cctp_getToDomainRateLimitKey(6), CCTP_TO_BASE_RATE_LIMIT_KEY, "controller-cctp-to-base-key"
        );
    }

    function test_ETHEREUM_spellExecutionSetsBaseDomainParametersAndRateLimits() public {
        _executeSpellViaStarGuard(payload);

        (bytes32 recipient, uint32 minFeeCapRate, uint32 maxFeeCapRate) = cctpController.cctp_getDomainParameters(6);
        assertEq(recipient, BASE_ALM_PROXY_RECIPIENT, "base-domain-recipient");
        assertEq(minFeeCapRate, 0, "base-domain-min-fee-cap-rate");
        assertEq(maxFeeCapRate, 0, "base-domain-max-fee-cap-rate");

        // Base is the only domain with parameters.
        (recipient,,) = cctpController.cctp_getDomainParameters(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
        assertEq(recipient, bytes32(0), "ethereum-domain-configured");
        (recipient,,) = cctpController.cctp_getDomainParameters(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
        assertEq(recipient, bytes32(0), "arbitrum-domain-configured");

        _assertUnlimitedRateLimit(CCTP_RATE_LIMIT_KEY, "cctp");
        _assertRateLimit(CCTP_TO_BASE_RATE_LIMIT_KEY, CCTP_TO_DOMAIN_MAX, CCTP_TO_DOMAIN_SLOPE, "cctp-to-base");
    }

    function test_ETHEREUM_existingRateLimitsPermissionsAndIntegrationsUnchanged() public {
        ExistingRateLimitsSnapshot memory limitsBefore = _snapshotExistingRateLimits();
        LaunchConfigurationSnapshot memory launchBefore = _snapshotLaunchConfiguration();
        PauConfig[4] memory configsBefore = _snapshotExistingIntegrationConfigs();

        _executeSpellViaStarGuard(payload);

        ExistingRateLimitsSnapshot memory limitsAfter = _snapshotExistingRateLimits();
        for (uint256 i = 0; i < 8; ++i) {
            _assertRateLimitDataUnchanged(limitsBefore.data[i], limitsAfter.data[i], vm.toString(i));
        }
        _assertLaunchConfigurationUnchanged(launchBefore);

        PauConfig[4] memory configsAfter = _snapshotExistingIntegrationConfigs();
        for (uint256 i = 0; i < 4; ++i) {
            _assertConfigEquals(
                configsAfter[i], configsBefore[i], string.concat("existing-integration-", vm.toString(i))
            );
        }
    }

    function test_ETHEREUM_spellEmitsOnlyExpectedEvents() public {
        vm.recordLogs();
        _executeSpellViaStarGuard(payload);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 cctpIntegrationSets;
        uint256 domainParametersSets;
        uint256 cctpRateLimitSets;
        uint256 cctpToBaseRateLimitSets;
        uint256 integrationRemovals;
        uint256 roleChanges;

        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic == INTEGRATION_SET_TOPIC) {
                assertEq(logs[i].emitter, OSERO_CONTROLLER, "integration-set-emitter");
                assertEq(logs[i].topics[1], CCTP_FACET_INTEGRATION_ID, "unexpected-integration-set-id");
                cctpIntegrationSets++;
            } else if (topic == CCTP_DOMAIN_PARAMETERS_SET_TOPIC) {
                assertEq(logs[i].emitter, OSERO_CONTROLLER, "domain-parameters-emitter");
                assertEq(uint256(logs[i].topics[1]), 6, "domain-parameters-domain");
                assertEq(logs[i].topics[2], BASE_ALM_PROXY_RECIPIENT, "domain-parameters-recipient");
                (uint32 minFeeCapRate, uint32 maxFeeCapRate) = abi.decode(logs[i].data, (uint32, uint32));
                assertEq(minFeeCapRate, 0, "domain-parameters-min-fee-cap-rate");
                assertEq(maxFeeCapRate, 0, "domain-parameters-max-fee-cap-rate");
                domainParametersSets++;
            } else if (topic == RATE_LIMIT_DATA_SET_TOPIC) {
                assertEq(logs[i].emitter, OSERO_RATE_LIMITS, "rate-limit-event-emitter");
                bytes32 key = logs[i].topics[1];
                if (key == CCTP_RATE_LIMIT_KEY) cctpRateLimitSets++;
                else if (key == CCTP_TO_BASE_RATE_LIMIT_KEY) cctpToBaseRateLimitSets++;
                else fail("unexpected-rate-limit-key");
            } else if (topic == INTEGRATION_REMOVED_TOPIC) {
                integrationRemovals++;
            } else if (topic == ROLE_GRANTED_TOPIC || topic == ROLE_REVOKED_TOPIC) {
                roleChanges++;
            }
        }

        assertEq(cctpIntegrationSets, 1, "cctp-integration-set-count");
        assertEq(domainParametersSets, 1, "domain-parameters-set-count");
        assertEq(cctpRateLimitSets, 1, "cctp-rate-limit-event-count");
        assertEq(cctpToBaseRateLimitSets, 1, "cctp-to-base-rate-limit-event-count");
        assertEq(integrationRemovals, 0, "integration-removed-event-count");
        assertEq(roleChanges, 0, "role-change-event-count");
    }

    function test_ETHEREUM_directPayloadExecutionRevertsWithoutSubProxyAuthority() public {
        // The first action is updateIntegrations, whose onlyAdmin check requires SubProxy authority.
        vm.expectRevert(abi.encodeWithSignature("NotAdmin(address)", payload));
        ISpellLike(payload).execute();
    }

    function test_ETHEREUM_actorCannotChangeCctpConfiguration() public {
        _executeSpellViaStarGuard(payload);

        _expectCallAsOseroActorRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", OSERO_ADMINISTERED_AGENT, DEFAULT_ADMIN_ROLE
            ),
            abi.encodeCall(ICCTPControllerLike.cctp_setDomainParameters, (6, bytes32(uint256(0xBAD)), 0, 0))
        );
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = CCTP_FACET_INTEGRATION_ID;
        _expectCallAsOseroActorRevert(
            abi.encodeWithSignature("NotAdmin(address)", OSERO_ADMINISTERED_AGENT),
            abi.encodeCall(IOseroPauControllerLike.removeIntegrations, (ids))
        );

        (bytes32 recipient,,) = cctpController.cctp_getDomainParameters(6);
        assertEq(recipient, BASE_ALM_PROXY_RECIPIENT, "base-domain-recipient-changed");
        assertEq(controller.integrations().length, 5, "integration-count-changed");
    }

    function test_ETHEREUM_cctpTransferToBaseThroughAdministeredAgent() public {
        _executeSpellViaStarGuard(payload);

        deal(USDC, OSERO_ALM_PROXY, usdc.balanceOf(OSERO_ALM_PROXY) + ROUND_TRIP_USDC_AMOUNT);
        uint256 proxyUsdcStart = usdc.balanceOf(OSERO_ALM_PROXY);

        vm.expectEmit(OSERO_CONTROLLER);
        emit CCTPTransferInitiated(6, BASE_ALM_PROXY_RECIPIENT, ROUND_TRIP_USDC_AMOUNT, 0);
        _callAsOseroActor(abi.encodeCall(ICCTPControllerLike.cctp_transfer, (ROUND_TRIP_USDC_AMOUNT, 6, 0)));

        assertEq(usdc.balanceOf(OSERO_ALM_PROXY), proxyUsdcStart - ROUND_TRIP_USDC_AMOUNT, "proxy-usdc-not-burned");
        assertEq(usdc.allowance(OSERO_ALM_PROXY, CCTP_TOKEN_MESSENGER_V2), 0, "cctp-usdc-approval-not-cleared");
        assertEq(
            rateLimits.getCurrentRateLimit(CCTP_TO_BASE_RATE_LIMIT_KEY),
            CCTP_TO_DOMAIN_MAX - ROUND_TRIP_USDC_AMOUNT,
            "cctp-to-base-limit-not-decreased"
        );
        assertEq(rateLimits.getCurrentRateLimit(CCTP_RATE_LIMIT_KEY), type(uint256).max, "cctp-limit-changed");
    }

    function test_ETHEREUM_cctpTransferRejectsOversizedTransferFeeCapAndUnconfiguredDomain() public {
        _executeSpellViaStarGuard(payload);
        deal(USDC, OSERO_ALM_PROXY, CCTP_TO_DOMAIN_MAX + 1);

        _expectCallAsOseroActorRevert(
            bytes("RateLimits/rate-limit-exceeded"),
            abi.encodeCall(ICCTPControllerLike.cctp_transfer, (CCTP_TO_DOMAIN_MAX + 1, 6, 0))
        );
        _expectCallAsOseroActorRevert(
            bytes("CCTPFacet/fee-cap-rate-too-high"),
            abi.encodeCall(ICCTPControllerLike.cctp_transfer, (ROUND_TRIP_USDC_AMOUNT, 6, 1))
        );
        // No other domain has a rate limit or parameters.
        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(
                ICCTPControllerLike.cctp_transfer,
                (ROUND_TRIP_USDC_AMOUNT, CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE, 0)
            )
        );
    }

    function test_ETHEREUM_cctpToBaseRateLimitRecoversOverTime() public {
        _executeSpellViaStarGuard(payload);
        deal(USDC, OSERO_ALM_PROXY, OPERATIONAL_TEST_USDC_AMOUNT);

        _callAsOseroActor(abi.encodeCall(ICCTPControllerLike.cctp_transfer, (OPERATIONAL_TEST_USDC_AMOUNT, 6, 0)));
        assertEq(
            rateLimits.getCurrentRateLimit(CCTP_TO_BASE_RATE_LIMIT_KEY),
            CCTP_TO_DOMAIN_MAX - OPERATIONAL_TEST_USDC_AMOUNT,
            "cctp-to-base-limit-not-decreased"
        );

        vm.warp(block.timestamp + PARTIAL_RECOVERY_TIME);
        assertEq(
            rateLimits.getCurrentRateLimit(CCTP_TO_BASE_RATE_LIMIT_KEY),
            CCTP_TO_DOMAIN_MAX - OPERATIONAL_TEST_USDC_AMOUNT + CCTP_TO_DOMAIN_SLOPE * PARTIAL_RECOVERY_TIME,
            "cctp-to-base-limit-not-recovering"
        );

        vm.warp(block.timestamp + 1 days);
        assertEq(
            rateLimits.getCurrentRateLimit(CCTP_TO_BASE_RATE_LIMIT_KEY), CCTP_TO_DOMAIN_MAX, "cctp-to-base-not-capped"
        );
        assertEq(rateLimits.getCurrentRateLimit(CCTP_RATE_LIMIT_KEY), type(uint256).max, "cctp-limit-changed");
    }

    /// @dev Emergency actions #1 (spell path): zeroing the Base domain key stops CCTP outflows from Ethereum.
    function test_ETHEREUM_subProxyCanStopCctpOutflowsAsEmergencyAction() public {
        _executeSpellViaStarGuard(payload);
        deal(USDC, OSERO_ALM_PROXY, ROUND_TRIP_USDC_AMOUNT);

        vm.prank(OSERO_PROXY);
        IRateLimitsAdminLike(OSERO_RATE_LIMITS).setRateLimitData(CCTP_TO_BASE_RATE_LIMIT_KEY, 0, 0);

        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(ICCTPControllerLike.cctp_transfer, (ROUND_TRIP_USDC_AMOUNT, 6, 0))
        );
    }

    /**********************************************************************************************/
    /*** Base                                                                                   ***/
    /**********************************************************************************************/

    function test_BASE_pauPreconfiguration() public onBase {
        _assertBaseOnboardingContracts();

        IEnumerableAccessControlsLike accessControls = IEnumerableAccessControlsLike(BASE_OSERO_ACCESS_CONTROLS);
        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1, "base-access-admin-count");
        assertEq(accessControls.getRoleMember(DEFAULT_ADMIN_ROLE, 0), BASE_OSERO_EXECUTOR, "base-access-admin");
        assertEq(accessControls.getRoleMemberCount(ALLOCATOR_ROLE), 0, "base-allocator-count");
        assertTrue(
            IALMProxyLike(BASE_OSERO_ALM_PROXY).hasRole(DEFAULT_ADMIN_ROLE, BASE_OSERO_EXECUTOR),
            "base-executor-not-almproxy-admin"
        );
        assertTrue(
            baseRateLimits.hasRole(DEFAULT_ADMIN_ROLE, BASE_OSERO_EXECUTOR), "base-executor-not-ratelimits-admin"
        );
        assertFalse(
            IALMProxyLike(BASE_OSERO_ALM_PROXY).hasRole(CONTROLLER, BASE_OSERO_CONTROLLER),
            "base-controller-already-almproxy-controller"
        );
        assertFalse(
            baseRateLimits.hasRole(CONTROLLER, BASE_OSERO_CONTROLLER), "base-controller-already-ratelimits-controller"
        );
        assertFalse(accessControls.hasRole(DEFAULT_ADMIN_ROLE, BASE_PAS_CONFIGURATOR), "base-pas-already-access-admin");
        assertFalse(
            baseRateLimits.hasRole(DEFAULT_ADMIN_ROLE, BASE_PAS_CONFIGURATOR), "base-pas-already-ratelimits-admin"
        );
        assertEq(IPASConfiguratorLike(BASE_PAS_CONFIGURATOR).beamState(), BASE_PAS_BEAM_STATE, "base-pas-beam-state");

        assertEq(baseController.accessControls(), BASE_OSERO_ACCESS_CONTROLS, "base-controller-access-controls");
        assertEq(baseController.proxy(), BASE_OSERO_ALM_PROXY, "base-controller-proxy");
        assertEq(baseController.rateLimits(), BASE_OSERO_RATE_LIMITS, "base-controller-rate-limits");
        assertEq(baseController.beacon(), BASE_SKY_PAU_BEACON, "base-controller-beacon");
        assertEq(baseController.integrations().length, 0, "base-controller-has-integrations");

        IAdministeredAgentLike agent = IAdministeredAgentLike(BASE_OSERO_ADMINISTERED_AGENT);
        assertEq(agent.adminCount(), 1, "base-agent-admin-count");
        assertEq(agent.getAdmin(0), BASE_OSERO_EXECUTOR, "base-agent-admin");
        assertEq(agent.actorCount(), 0, "base-agent-actor-count");
        assertEq(agent.grantorCount(), 0, "base-agent-grantor-count");
        assertEq(agent.revokerCount(), 0, "base-agent-revoker-count");

        _assertConfigWires(
            IBeaconLike(BASE_SKY_PAU_BEACON).getConfig(CCTP_FACET_INTEGRATION_ID),
            BASE_SKY_PAU_CCTP_FACET,
            _expectedCctpWires(),
            "base-beacon-cctp"
        );
        // The ERC-4626 facet registration on the Beacon (Pre-requirements #1) is checked by
        // test_BASE_skyCoreRegisteredErc4626FacetForBasePayload.

        ICCTPFacetLike cctpFacet = ICCTPFacetLike(BASE_SKY_PAU_CCTP_FACET);
        assertEq(cctpFacet.VERSION(), "1.0.0", "base-cctp-version");
        assertEq(cctpFacet.cctp(), CCTP_TOKEN_MESSENGER_V2, "base-cctp-token-messenger");
        assertEq(cctpFacet.usdc(), BASE_USDC, "base-cctp-usdc");
        assertEq(cctpFacet.MIN_FINALITY_THRESHOLD(), CCTP_MIN_FINALITY_THRESHOLD, "base-cctp-min-finality-threshold");
        assertEq(cctpFacet.DESTINATION_CALLER(), bytes32(0), "base-cctp-destination-caller");
        IERC4626FacetLike erc4626Facet = IERC4626FacetLike(BASE_SKY_PAU_ERC4626_FACET);
        assertEq(erc4626Facet.VERSION(), "1.0.0", "base-erc4626-version");
        assertEq(erc4626Facet.EXCHANGE_RATE_PRECISION(), EXCHANGE_RATE_PRECISION, "base-erc4626-precision");

        _assertBaseVaultPreconfiguration();
        _assertBaseMultisigs();
        _assertBaseNewRateLimitsUnset();
    }

    function test_BASE_spellExecutionInitializesPauAndAdministeredAgent() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        IEnumerableAccessControlsLike accessControls = IEnumerableAccessControlsLike(BASE_OSERO_ACCESS_CONTROLS);
        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 2, "base-access-admin-count");
        assertTrue(accessControls.hasRole(DEFAULT_ADMIN_ROLE, BASE_OSERO_EXECUTOR), "base-executor-not-access-admin");
        assertTrue(accessControls.hasRole(DEFAULT_ADMIN_ROLE, BASE_PAS_CONFIGURATOR), "base-pas-not-access-admin");
        assertEq(accessControls.getRoleMemberCount(ALLOCATOR_ROLE), 1, "base-allocator-count");
        assertEq(accessControls.getRoleMember(ALLOCATOR_ROLE, 0), BASE_OSERO_ADMINISTERED_AGENT, "base-allocator");

        IALMProxyLike almProxy = IALMProxyLike(BASE_OSERO_ALM_PROXY);
        assertTrue(almProxy.hasRole(CONTROLLER, BASE_OSERO_CONTROLLER), "base-controller-not-almproxy-controller");
        assertTrue(almProxy.hasRole(DEFAULT_ADMIN_ROLE, BASE_OSERO_EXECUTOR), "base-executor-not-almproxy-admin");
        assertFalse(almProxy.hasRole(DEFAULT_ADMIN_ROLE, BASE_PAS_CONFIGURATOR), "base-pas-is-almproxy-admin");
        assertFalse(almProxy.hasRole(CONTROLLER, BASE_OSERO_EXECUTOR), "base-executor-is-almproxy-controller");

        assertTrue(
            baseRateLimits.hasRole(CONTROLLER, BASE_OSERO_CONTROLLER), "base-controller-not-ratelimits-controller"
        );
        assertTrue(
            baseRateLimits.hasRole(DEFAULT_ADMIN_ROLE, BASE_OSERO_EXECUTOR), "base-executor-not-ratelimits-admin"
        );
        assertTrue(baseRateLimits.hasRole(DEFAULT_ADMIN_ROLE, BASE_PAS_CONFIGURATOR), "base-pas-not-ratelimits-admin");

        IAdministeredAgentLike agent = IAdministeredAgentLike(BASE_OSERO_ADMINISTERED_AGENT);
        IAdministeredAgentRolesLike agentRoles = IAdministeredAgentRolesLike(BASE_OSERO_ADMINISTERED_AGENT);
        assertEq(agent.adminCount(), 1, "base-agent-admin-count");
        assertEq(agent.getAdmin(0), BASE_OSERO_EXECUTOR, "base-agent-admin");
        assertEq(agent.actorCount(), 2, "base-agent-actor-count");
        assertEq(agentRoles.getActor(0), BASE_OSERO_OPERATOR, "base-agent-osero-relayer-actor");
        assertEq(agentRoles.getActor(1), BASE_SOTER_OPERATOR, "base-agent-core-operator-relayer-actor");
        assertEq(agent.grantorCount(), 0, "base-agent-grantor-count");
        assertFalse(agentRoles.getIsGrantor(BASE_OSERO_OPERATOR), "base-osero-relayer-is-grantor");
        assertFalse(agentRoles.getIsGrantor(BASE_SOTER_OPERATOR), "base-core-operator-relayer-is-grantor");
        assertFalse(agentRoles.getIsGrantor(BASE_SOTER_FREEZER), "base-freezer-is-grantor");
        assertEq(agent.revokerCount(), 1, "base-agent-revoker-count");
        assertEq(agent.getRevoker(0), BASE_SOTER_FREEZER, "base-agent-revoker");
        assertFalse(agentRoles.getIsAdmin(BASE_PAS_CONFIGURATOR), "base-pas-is-agent-admin");
        assertFalse(agent.getIsActor(BASE_SOTER_FREEZER), "base-freezer-is-actor");
        assertFalse(agentRoles.getIsRevoker(BASE_OSERO_OPERATOR), "base-osero-relayer-is-revoker");
    }

    function test_BASE_spellExecutionEnablesIntegrations() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        PauIntegration[] memory integrations = baseController.integrations();
        assertEq(integrations.length, 2, "base-integration-count");
        _assertConfigEquals(
            baseController.getConfig(CCTP_FACET_INTEGRATION_ID),
            IBeaconLike(BASE_SKY_PAU_BEACON).getConfig(CCTP_FACET_INTEGRATION_ID),
            "base-cctp"
        );
        _assertConfigEquals(
            baseController.getConfig(ERC4626_FACET_INTEGRATION_ID),
            IBeaconLike(BASE_SKY_PAU_BEACON).getConfig(ERC4626_FACET_INTEGRATION_ID),
            "base-erc4626"
        );
        _assertConfigWires(
            baseController.getConfig(CCTP_FACET_INTEGRATION_ID),
            BASE_SKY_PAU_CCTP_FACET,
            _expectedCctpWires(),
            "base-controller-cctp"
        );
        _assertConfigWires(
            baseController.getConfig(ERC4626_FACET_INTEGRATION_ID),
            BASE_SKY_PAU_ERC4626_FACET,
            _expectedErc4626Wires(),
            "base-controller-erc4626"
        );
        _assertWiresDispatched(BASE_OSERO_CONTROLLER, _expectedCctpWires(), BASE_SKY_PAU_CCTP_FACET, "base-cctp");
        _assertWiresDispatched(
            BASE_OSERO_CONTROLLER, _expectedErc4626Wires(), BASE_SKY_PAU_ERC4626_FACET, "base-erc4626"
        );

        assertEq(baseCctpController.cctp_cctp(), CCTP_TOKEN_MESSENGER_V2, "base-controller-cctp-token-messenger");
        assertEq(baseCctpController.cctp_usdc(), BASE_USDC, "base-controller-cctp-usdc");
        assertEq(baseController.erc4626_VERSION(), "1.0.0", "base-controller-erc4626-version");
        assertEq(baseController.erc4626_EXCHANGE_RATE_PRECISION(), EXCHANGE_RATE_PRECISION, "base-controller-precision");
        assertEq(baseCctpController.cctp_toCCTPRateLimitKey(), CCTP_RATE_LIMIT_KEY, "base-controller-cctp-key");
        assertEq(
            baseCctpController.cctp_getToDomainRateLimitKey(0),
            CCTP_TO_ETHEREUM_RATE_LIMIT_KEY,
            "base-controller-cctp-to-ethereum-key"
        );
        assertEq(
            baseController.erc4626_getDepositRateLimitKey(OGUSDCB_VAULT, BASE_USDC),
            OGUSDCB_DEPOSIT_RATE_LIMIT_KEY,
            "base-controller-ogusdcb-deposit-key"
        );
        assertEq(
            baseController.erc4626_getWithdrawRateLimitKey(OGUSDCB_VAULT),
            OGUSDCB_WITHDRAW_RATE_LIMIT_KEY,
            "base-controller-ogusdcb-withdraw-key"
        );
    }

    function test_BASE_spellExecutionSetsDomainParametersExchangeRateAndRateLimits() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        (bytes32 recipient, uint32 minFeeCapRate, uint32 maxFeeCapRate) = baseCctpController.cctp_getDomainParameters(0);
        assertEq(recipient, ETHEREUM_ALM_PROXY_RECIPIENT, "ethereum-domain-recipient");
        assertEq(minFeeCapRate, 0, "ethereum-domain-min-fee-cap-rate");
        assertEq(maxFeeCapRate, 0, "ethereum-domain-max-fee-cap-rate");
        (recipient,,) = baseCctpController.cctp_getDomainParameters(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        assertEq(recipient, bytes32(0), "base-domain-configured");

        assertEq(
            baseController.erc4626_getMaxExchangeRate(OGUSDCB_VAULT), OGUSDCB_MAX_EXCHANGE_RATE, "ogusdcb-max-rate"
        );

        _assertUnlimitedRateLimitOn(BASE_OSERO_RATE_LIMITS, CCTP_RATE_LIMIT_KEY, "base-cctp");
        _assertRateLimitOn(
            BASE_OSERO_RATE_LIMITS,
            CCTP_TO_ETHEREUM_RATE_LIMIT_KEY,
            CCTP_TO_DOMAIN_MAX,
            CCTP_TO_DOMAIN_SLOPE,
            "base-cctp-to-ethereum"
        );
        _assertRateLimitOn(
            BASE_OSERO_RATE_LIMITS,
            OGUSDCB_DEPOSIT_RATE_LIMIT_KEY,
            OGUSDCB_DEPOSIT_MAX,
            OGUSDCB_DEPOSIT_SLOPE,
            "ogusdcb-deposit"
        );
        _assertUnlimitedRateLimitOn(BASE_OSERO_RATE_LIMITS, OGUSDCB_WITHDRAW_RATE_LIMIT_KEY, "ogusdcb-withdraw");
    }

    function test_BASE_spellEmitsOnlyExpectedEvents() public {
        _executeSpellViaStarGuard(payload);
        uint256 actionsSetId = _relayBasePayload();

        vm.recordLogs();
        _executeBaseActionsSet(actionsSetId);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256[2] memory integrationSets;
        uint256 domainParametersSets;
        uint256[4] memory rateLimitSets;
        uint256 maxExchangeRateSets;
        uint256 roleGrants;
        uint256 actorAdds;
        uint256 revokerAdds;
        uint256 actionsSetExecutions;
        uint256 unexpected;

        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic == INTEGRATION_SET_TOPIC) {
                assertEq(logs[i].emitter, BASE_OSERO_CONTROLLER, "integration-set-emitter");
                if (logs[i].topics[1] == CCTP_FACET_INTEGRATION_ID) integrationSets[0]++;
                else if (logs[i].topics[1] == ERC4626_FACET_INTEGRATION_ID) integrationSets[1]++;
                else fail("unexpected-integration-set-id");
            } else if (topic == CCTP_DOMAIN_PARAMETERS_SET_TOPIC) {
                assertEq(logs[i].emitter, BASE_OSERO_CONTROLLER, "domain-parameters-emitter");
                assertEq(uint256(logs[i].topics[1]), 0, "domain-parameters-domain");
                assertEq(logs[i].topics[2], ETHEREUM_ALM_PROXY_RECIPIENT, "domain-parameters-recipient");
                domainParametersSets++;
            } else if (topic == RATE_LIMIT_DATA_SET_TOPIC) {
                assertEq(logs[i].emitter, BASE_OSERO_RATE_LIMITS, "rate-limit-event-emitter");
                bytes32 key = logs[i].topics[1];
                if (key == CCTP_RATE_LIMIT_KEY) rateLimitSets[0]++;
                else if (key == CCTP_TO_ETHEREUM_RATE_LIMIT_KEY) rateLimitSets[1]++;
                else if (key == OGUSDCB_DEPOSIT_RATE_LIMIT_KEY) rateLimitSets[2]++;
                else if (key == OGUSDCB_WITHDRAW_RATE_LIMIT_KEY) rateLimitSets[3]++;
                else fail("unexpected-rate-limit-key");
            } else if (topic == ERC4626_MAX_EXCHANGE_RATE_SET_TOPIC) {
                assertEq(logs[i].emitter, BASE_OSERO_CONTROLLER, "max-exchange-rate-emitter");
                assertEq(address(uint160(uint256(logs[i].topics[1]))), OGUSDCB_VAULT, "max-exchange-rate-token");
                assertEq(abi.decode(logs[i].data, (uint256)), OGUSDCB_MAX_EXCHANGE_RATE, "max-exchange-rate-value");
                maxExchangeRateSets++;
            } else if (topic == ROLE_GRANTED_TOPIC) {
                _assertExpectedBaseRoleGrant(logs[i]);
                roleGrants++;
            } else if (topic == ACTOR_ADDED_TOPIC) {
                assertEq(logs[i].emitter, BASE_OSERO_ADMINISTERED_AGENT, "actor-added-emitter");
                address actor = address(uint160(uint256(logs[i].topics[1])));
                assertTrue(actor == BASE_OSERO_OPERATOR || actor == BASE_SOTER_OPERATOR, "unexpected-actor-added");
                actorAdds++;
            } else if (topic == REVOKER_ADDED_TOPIC) {
                assertEq(logs[i].emitter, BASE_OSERO_ADMINISTERED_AGENT, "revoker-added-emitter");
                assertEq(address(uint160(uint256(logs[i].topics[1]))), BASE_SOTER_FREEZER, "unexpected-revoker-added");
                revokerAdds++;
            } else if (topic == ACTIONS_SET_EXECUTED_TOPIC) {
                assertEq(logs[i].emitter, BASE_OSERO_EXECUTOR, "actions-set-executed-emitter");
                assertEq(uint256(logs[i].topics[1]), actionsSetId, "actions-set-executed-id");
                actionsSetExecutions++;
            } else if (
                topic == ROLE_REVOKED_TOPIC || topic == INTEGRATION_REMOVED_TOPIC || topic == ADMIN_ADDED_TOPIC
                    || topic == GRANTOR_ADDED_TOPIC
            ) {
                unexpected++;
            }
        }

        assertEq(integrationSets[0], 1, "cctp-integration-set-count");
        assertEq(integrationSets[1], 1, "erc4626-integration-set-count");
        assertEq(domainParametersSets, 1, "domain-parameters-set-count");
        assertEq(rateLimitSets[0], 1, "cctp-rate-limit-event-count");
        assertEq(rateLimitSets[1], 1, "cctp-to-ethereum-rate-limit-event-count");
        assertEq(rateLimitSets[2], 1, "ogusdcb-deposit-rate-limit-event-count");
        assertEq(rateLimitSets[3], 1, "ogusdcb-withdraw-rate-limit-event-count");
        assertEq(maxExchangeRateSets, 1, "max-exchange-rate-set-count");
        assertEq(roleGrants, 5, "role-granted-event-count");
        assertEq(actorAdds, 2, "actor-added-event-count");
        assertEq(revokerAdds, 1, "revoker-added-event-count");
        assertEq(actionsSetExecutions, 1, "actions-set-executed-event-count");
        assertEq(unexpected, 0, "unexpected-role-revoke-integration-removal-admin-or-grantor-event");
    }

    /// @dev Pre-requirements #1, end to end: once Sky Core has registered `ERC4626_FACET` on the Sky PAU Beacon on
    ///      Base with the Ethereum wires, the relayed Base payload executes and wires the facet from the Beacon.
    ///      Runs against the registration `setUp` simulates until BASE_FORK_BLOCK is moved past the November 19,
    ///      2026 Sky Core spell, then against the real one.
    function test_BASE_skyCoreRegisteredErc4626FacetForBasePayload() public {
        _selectBase();
        _assertSkyCoreRegisteredErc4626Facet();

        _selectEthereum();
        _executeSpellViaStarGuard(payload);
        uint256 actionsSetId = _relayBasePayload();

        vm.prank(PERMISSIONLESS_EXECUTOR);
        baseExecutor.execute(actionsSetId);

        assertEq(
            uint256(baseExecutor.getCurrentState(actionsSetId)),
            uint256(IExecutor.ActionsSetState.Executed),
            "base-actions-set-not-executed"
        );
        _assertConfigEquals(
            baseController.getConfig(ERC4626_FACET_INTEGRATION_ID),
            IBeaconLike(BASE_SKY_PAU_BEACON).getConfig(ERC4626_FACET_INTEGRATION_ID),
            "base-erc4626-wired-from-beacon"
        );
    }

    /// @dev Pre-requirements #1: without the registration, `updateIntegrations` reverts, so the whole Base payload
    ///      reverts and the actions set stays queued. Removes the registration `setUp` guarantees (simulated or real).
    function test_BASE_payloadRevertsUntilSkyCoreRegistersErc4626Facet() public {
        _selectBase();
        vm.prank(_baseBeaconAdmin());
        IBeaconAdminLike(BASE_SKY_PAU_BEACON).removeIntegration(ERC4626_FACET_INTEGRATION_ID);

        _selectEthereum();
        _executeSpellViaStarGuard(payload);
        uint256 actionsSetId = _relayBasePayload();

        vm.expectRevert(abi.encodeWithSignature("IntegrationNotFound(bytes32)", ERC4626_FACET_INTEGRATION_ID));
        baseExecutor.execute(actionsSetId);

        assertEq(
            uint256(baseExecutor.getCurrentState(actionsSetId)),
            uint256(IExecutor.ActionsSetState.Queued),
            "base-actions-set-not-queued-after-revert"
        );
    }

    function test_BASE_directPayloadExecutionRevertsWithoutExecutorAuthority() public onBase {
        // The first action is PAUInit.init, which requires the executing context to be the AccessControls admin.
        vm.expectRevert(bytes("PAUInit/not-access-controls-admin"));
        ISpellLike(basePayload).execute();
    }

    function test_BASE_actorCannotChangeAdminConfiguration() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        bytes memory unauthorized = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)", BASE_OSERO_ADMINISTERED_AGENT, DEFAULT_ADMIN_ROLE
        );
        _expectCallAsBaseOseroActorRevert(
            unauthorized, abi.encodeCall(IOseroPauControllerLike.erc4626_setMaxExchangeRate, (OGUSDCB_VAULT, 1e18, 1e6))
        );
        _expectCallAsBaseOseroActorRevert(
            unauthorized,
            abi.encodeCall(ICCTPControllerLike.cctp_setDomainParameters, (0, bytes32(uint256(0xBAD)), 0, 0))
        );
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = ERC4626_FACET_INTEGRATION_ID;
        _expectCallAsBaseOseroActorRevert(
            abi.encodeWithSignature("NotAdmin(address)", BASE_OSERO_ADMINISTERED_AGENT),
            abi.encodeCall(IOseroPauControllerLike.removeIntegrations, (ids))
        );

        assertEq(
            baseController.erc4626_getMaxExchangeRate(OGUSDCB_VAULT), OGUSDCB_MAX_EXCHANGE_RATE, "max-rate-changed"
        );
        assertEq(baseController.integrations().length, 2, "base-integration-count-changed");
    }

    /// @dev Emergency actions #3: the Freezer Multisig on Base removes a compromised Actor.
    function test_BASE_freezerCanRemoveActor() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        vm.prank(BASE_SOTER_FREEZER);
        IAdministeredAgentLike(BASE_OSERO_ADMINISTERED_AGENT).removeActor(BASE_OSERO_OPERATOR);

        assertFalse(
            IAdministeredAgentLike(BASE_OSERO_ADMINISTERED_AGENT).getIsActor(BASE_OSERO_OPERATOR), "actor-not-removed"
        );
        vm.prank(BASE_OSERO_OPERATOR);
        vm.expectRevert(abi.encodeWithSignature("NotActor()"));
        // forge-lint: disable-next-line(unchecked-call)
        IAdministeredAgentLike(BASE_OSERO_ADMINISTERED_AGENT)
            .call(BASE_OSERO_CONTROLLER, abi.encodeCall(ICCTPControllerLike.cctp_transfer, (1e6, 0, 0)));
    }

    function test_BASE_ogusdcbDepositAndRedeemThroughAdministeredAgent() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        deal(BASE_USDC, BASE_OSERO_ALM_PROXY, ROUND_TRIP_USDC_AMOUNT);
        IVaultV2Like vault = IVaultV2Like(OGUSDCB_VAULT);

        uint256 minSharesOut = vault.previewDeposit(ROUND_TRIP_USDC_AMOUNT) * 999 / 1000;
        uint256 shares = abi.decode(
            _callAsBaseOseroActor(
                abi.encodeCall(
                    IOseroPauControllerLike.erc4626_deposit, (OGUSDCB_VAULT, ROUND_TRIP_USDC_AMOUNT, minSharesOut)
                )
            ),
            (uint256)
        );
        assertGe(shares, minSharesOut, "ogusdcb-shares-below-minimum");
        assertEq(ogusdcb.balanceOf(BASE_OSERO_ALM_PROXY), shares, "proxy-shares-not-received");
        assertEq(baseUsdc.balanceOf(BASE_OSERO_ALM_PROXY), 0, "proxy-usdc-not-deposited");
        assertEq(baseUsdc.allowance(BASE_OSERO_ALM_PROXY, OGUSDCB_VAULT), 0, "ogusdcb-usdc-approval-not-cleared");
        assertEq(
            baseRateLimits.getCurrentRateLimit(OGUSDCB_DEPOSIT_RATE_LIMIT_KEY),
            OGUSDCB_DEPOSIT_MAX - ROUND_TRIP_USDC_AMOUNT,
            "ogusdcb-deposit-limit-not-decreased"
        );

        uint256 assets = abi.decode(
            _callAsBaseOseroActor(
                abi.encodeCall(IOseroPauControllerLike.erc4626_redeem, (OGUSDCB_VAULT, shares, 999e6))
            ),
            (uint256)
        );
        assertGe(assets, 999e6, "ogusdcb-assets-below-minimum");
        assertLe(assets, ROUND_TRIP_USDC_AMOUNT, "ogusdcb-assets-above-deposit");
        assertEq(ogusdcb.balanceOf(BASE_OSERO_ALM_PROXY), 0, "proxy-shares-not-redeemed");
        assertEq(baseUsdc.balanceOf(BASE_OSERO_ALM_PROXY), assets, "proxy-usdc-not-redeemed");
        assertEq(
            baseRateLimits.getCurrentRateLimit(OGUSDCB_DEPOSIT_RATE_LIMIT_KEY),
            OGUSDCB_DEPOSIT_MAX - ROUND_TRIP_USDC_AMOUNT + assets,
            "ogusdcb-deposit-limit-not-refilled"
        );
        assertEq(
            baseRateLimits.getCurrentRateLimit(OGUSDCB_WITHDRAW_RATE_LIMIT_KEY),
            type(uint256).max,
            "ogusdcb-withdraw-limit-not-unlimited"
        );
    }

    function test_BASE_ogusdcbWithdrawThroughAdministeredAgent() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        deal(BASE_USDC, BASE_OSERO_ALM_PROXY, ROUND_TRIP_USDC_AMOUNT);
        IVaultV2Like vault = IVaultV2Like(OGUSDCB_VAULT);
        uint256 shares = abi.decode(
            _callAsBaseOseroActor(
                abi.encodeCall(IOseroPauControllerLike.erc4626_deposit, (OGUSDCB_VAULT, ROUND_TRIP_USDC_AMOUNT, 0))
            ),
            (uint256)
        );

        uint256 withdrawAmount = vault.previewRedeem(shares);
        assertGe(withdrawAmount, 999e6, "ogusdcb-withdrawable-below-minimum");
        uint256 expectedSharesBurned = vault.previewWithdraw(withdrawAmount);
        assertLe(expectedSharesBurned, shares, "ogusdcb-withdraw-burns-more-than-deposited");

        uint256 sharesBurned = abi.decode(
            _callAsBaseOseroActor(
                abi.encodeCall(IOseroPauControllerLike.erc4626_withdraw, (OGUSDCB_VAULT, withdrawAmount, shares))
            ),
            (uint256)
        );
        assertEq(sharesBurned, expectedSharesBurned, "ogusdcb-shares-burned");
        assertEq(ogusdcb.balanceOf(BASE_OSERO_ALM_PROXY), shares - sharesBurned, "proxy-shares-not-burned");
        assertEq(baseUsdc.balanceOf(BASE_OSERO_ALM_PROXY), withdrawAmount, "proxy-usdc-not-withdrawn");
        assertEq(
            baseRateLimits.getCurrentRateLimit(OGUSDCB_DEPOSIT_RATE_LIMIT_KEY),
            OGUSDCB_DEPOSIT_MAX - ROUND_TRIP_USDC_AMOUNT + withdrawAmount,
            "ogusdcb-deposit-limit-not-refilled-by-withdraw"
        );
    }

    function test_BASE_ogusdcbDepositRateLimitRejectsOversizedDepositAndRecoversOverTime() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        deal(BASE_USDC, BASE_OSERO_ALM_PROXY, OGUSDCB_DEPOSIT_MAX + 1);
        _expectCallAsBaseOseroActorRevert(
            bytes("RateLimits/rate-limit-exceeded"),
            abi.encodeCall(IOseroPauControllerLike.erc4626_deposit, (OGUSDCB_VAULT, OGUSDCB_DEPOSIT_MAX + 1, 0))
        );

        _callAsBaseOseroActor(
            abi.encodeCall(IOseroPauControllerLike.erc4626_deposit, (OGUSDCB_VAULT, OPERATIONAL_TEST_USDC_AMOUNT, 0))
        );
        assertEq(
            baseRateLimits.getCurrentRateLimit(OGUSDCB_DEPOSIT_RATE_LIMIT_KEY),
            OGUSDCB_DEPOSIT_MAX - OPERATIONAL_TEST_USDC_AMOUNT,
            "ogusdcb-deposit-limit-not-decreased"
        );

        vm.warp(block.timestamp + PARTIAL_RECOVERY_TIME);
        assertEq(
            baseRateLimits.getCurrentRateLimit(OGUSDCB_DEPOSIT_RATE_LIMIT_KEY),
            OGUSDCB_DEPOSIT_MAX - OPERATIONAL_TEST_USDC_AMOUNT + OGUSDCB_DEPOSIT_SLOPE * PARTIAL_RECOVERY_TIME,
            "ogusdcb-deposit-limit-not-recovering"
        );

        vm.warp(block.timestamp + 1 days);
        assertEq(
            baseRateLimits.getCurrentRateLimit(OGUSDCB_DEPOSIT_RATE_LIMIT_KEY),
            OGUSDCB_DEPOSIT_MAX,
            "ogusdcb-deposit-limit-not-capped"
        );
    }

    function test_BASE_ogusdcbDepositRejectsUnconfiguredVault() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        deal(BASE_USDC, BASE_OSERO_ALM_PROXY, ROUND_TRIP_USDC_AMOUNT);
        // Only the Osero x Gauntlet vault deposit key exists on Base.
        _expectCallAsBaseOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(
                IOseroPauControllerLike.erc4626_deposit, (UNCONFIGURED_BASE_USDC_VAULT, ROUND_TRIP_USDC_AMOUNT, 0)
            )
        );
    }

    function test_BASE_ogusdcbDepositRejectsExchangeRateAboveCeiling() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        // Donate twice the vault's assets so the donation alone would more than double the share price.
        // VaultV2 caps accrual at maxRate (about 100%/year linear), so the share price exceeds the 2 USDC
        // ceiling only after about one year.
        IVaultV2Like vault = IVaultV2Like(OGUSDCB_VAULT);
        deal(BASE_USDC, OGUSDCB_VAULT, baseUsdc.balanceOf(OGUSDCB_VAULT) + 2 * vault.totalAssets());
        vm.warp(block.timestamp + 366 days);
        assertGt(vault.convertToAssets(1e18), 2e6, "ogusdcb-exchange-rate-not-above-ceiling");

        deal(BASE_USDC, BASE_OSERO_ALM_PROXY, ROUND_TRIP_USDC_AMOUNT);
        _expectCallAsBaseOseroActorRevert(
            bytes("ERC4626Facet/exchange-rate-too-high"),
            abi.encodeCall(IOseroPauControllerLike.erc4626_deposit, (OGUSDCB_VAULT, ROUND_TRIP_USDC_AMOUNT, 0))
        );
    }

    function test_BASE_cctpTransferToEthereumThroughAdministeredAgent() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        deal(BASE_USDC, BASE_OSERO_ALM_PROXY, CCTP_TO_DOMAIN_MAX + 1);
        _expectCallAsBaseOseroActorRevert(
            bytes("RateLimits/rate-limit-exceeded"),
            abi.encodeCall(ICCTPControllerLike.cctp_transfer, (CCTP_TO_DOMAIN_MAX + 1, 0, 0))
        );
        _expectCallAsBaseOseroActorRevert(
            bytes("CCTPFacet/fee-cap-rate-too-high"),
            abi.encodeCall(ICCTPControllerLike.cctp_transfer, (ROUND_TRIP_USDC_AMOUNT, 0, 1))
        );
        _expectCallAsBaseOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(
                ICCTPControllerLike.cctp_transfer,
                (ROUND_TRIP_USDC_AMOUNT, CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE, 0)
            )
        );

        vm.expectEmit(BASE_OSERO_CONTROLLER);
        emit CCTPTransferInitiated(0, ETHEREUM_ALM_PROXY_RECIPIENT, ROUND_TRIP_USDC_AMOUNT, 0);
        _callAsBaseOseroActor(abi.encodeCall(ICCTPControllerLike.cctp_transfer, (ROUND_TRIP_USDC_AMOUNT, 0, 0)));

        assertEq(
            baseUsdc.balanceOf(BASE_OSERO_ALM_PROXY),
            CCTP_TO_DOMAIN_MAX + 1 - ROUND_TRIP_USDC_AMOUNT,
            "base-proxy-usdc-not-burned"
        );
        assertEq(baseUsdc.allowance(BASE_OSERO_ALM_PROXY, CCTP_TOKEN_MESSENGER_V2), 0, "base-cctp-approval-not-cleared");
        assertEq(
            baseRateLimits.getCurrentRateLimit(CCTP_TO_ETHEREUM_RATE_LIMIT_KEY),
            CCTP_TO_DOMAIN_MAX - ROUND_TRIP_USDC_AMOUNT,
            "base-cctp-to-ethereum-limit-not-decreased"
        );
        assertEq(baseRateLimits.getCurrentRateLimit(CCTP_RATE_LIMIT_KEY), type(uint256).max, "base-cctp-limit-changed");
    }

    /// @dev Emergency actions #4: the Osero Executor on Base (through a relayed Osero spell) removes an integration.
    function test_BASE_executorCanRemoveIntegrationsAsEmergencyAction() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = ERC4626_FACET_INTEGRATION_ID;
        vm.expectEmit(BASE_OSERO_CONTROLLER);
        emit IntegrationRemoved(ERC4626_FACET_INTEGRATION_ID);
        vm.prank(BASE_OSERO_EXECUTOR);
        baseController.removeIntegrations(ids);

        assertEq(baseController.integrations().length, 1, "base-integration-count-after-removal");
        assertEq(
            baseController.getDispatch(IOseroPauControllerLike.erc4626_deposit.selector).facet,
            address(0),
            "erc4626-deposit-still-wired"
        );
        _assertRateLimitOn(
            BASE_OSERO_RATE_LIMITS,
            OGUSDCB_DEPOSIT_RATE_LIMIT_KEY,
            OGUSDCB_DEPOSIT_MAX,
            OGUSDCB_DEPOSIT_SLOPE,
            "ogusdcb-deposit"
        );
    }

    /**********************************************************************************************/
    /*** Cross-chain                                                                            ***/
    /**********************************************************************************************/

    /// @dev Post-checks #6: a small round trip from Ethereum to the vault on Base and back through CCTP,
    ///      run by the Osero Relayer Multisig as Actor on both chains.
    function test_BASE_cctpToEthereumRateLimitRecoversOverTime() public {
        _executeAllPayloadsAndBridges();
        _selectBase();
        deal(BASE_USDC, BASE_OSERO_ALM_PROXY, OPERATIONAL_TEST_USDC_AMOUNT);

        _callAsBaseOseroActor(abi.encodeCall(ICCTPControllerLike.cctp_transfer, (OPERATIONAL_TEST_USDC_AMOUNT, 0, 0)));
        assertEq(
            baseRateLimits.getCurrentRateLimit(CCTP_TO_ETHEREUM_RATE_LIMIT_KEY),
            CCTP_TO_DOMAIN_MAX - OPERATIONAL_TEST_USDC_AMOUNT,
            "base-cctp-to-ethereum-limit-not-decreased"
        );

        vm.warp(block.timestamp + PARTIAL_RECOVERY_TIME);
        assertEq(
            baseRateLimits.getCurrentRateLimit(CCTP_TO_ETHEREUM_RATE_LIMIT_KEY),
            CCTP_TO_DOMAIN_MAX - OPERATIONAL_TEST_USDC_AMOUNT + CCTP_TO_DOMAIN_SLOPE * PARTIAL_RECOVERY_TIME,
            "base-cctp-to-ethereum-limit-not-recovering"
        );

        vm.warp(block.timestamp + 1 days);
        assertEq(
            baseRateLimits.getCurrentRateLimit(CCTP_TO_ETHEREUM_RATE_LIMIT_KEY),
            CCTP_TO_DOMAIN_MAX,
            "base-cctp-to-ethereum-limit-not-capped"
        );
        assertEq(baseRateLimits.getCurrentRateLimit(CCTP_RATE_LIMIT_KEY), type(uint256).max, "base-cctp-limit-changed");
    }

    /// @dev Proposed action #8: the second Actor, the Core Operator Relayer Multisig on Base, operates the Osero
    ///      controller on Base through the AdministeredAgent.
    function test_BASE_coreOperatorRelayerOperatesThroughAdministeredAgent() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        IAdministeredAgentLike agent = IAdministeredAgentLike(BASE_OSERO_ADMINISTERED_AGENT);
        assertTrue(agent.getIsActor(BASE_SOTER_OPERATOR), "base-core-operator-relayer-not-agent-actor");

        deal(BASE_USDC, BASE_OSERO_ALM_PROXY, ROUND_TRIP_USDC_AMOUNT);
        uint256 expectedShares = IVaultV2Like(OGUSDCB_VAULT).previewDeposit(ROUND_TRIP_USDC_AMOUNT);
        assertGt(expectedShares, 0, "ogusdcb-preview-deposit-zero");

        vm.prank(BASE_SOTER_OPERATOR);
        // Lint false positive: the agent's `call(address,bytes)` interface function reverts on failure.
        // forge-lint: disable-next-line(unchecked-call)
        agent.call(
            BASE_OSERO_CONTROLLER,
            abi.encodeCall(IOseroPauControllerLike.erc4626_deposit, (OGUSDCB_VAULT, ROUND_TRIP_USDC_AMOUNT, 0))
        );

        assertEq(ogusdcb.balanceOf(BASE_OSERO_ALM_PROXY), expectedShares, "proxy-ogusdcb-shares");
        assertEq(baseUsdc.balanceOf(BASE_OSERO_ALM_PROXY), 0, "proxy-usdc-not-deposited");
        assertEq(
            baseRateLimits.getCurrentRateLimit(OGUSDCB_DEPOSIT_RATE_LIMIT_KEY),
            OGUSDCB_DEPOSIT_MAX - ROUND_TRIP_USDC_AMOUNT,
            "ogusdcb-deposit-limit-not-decreased"
        );
    }

    /// @dev Pre-requirements #2 and Pre-deployed contracts #11-14: each Safe on Base has the same owners (in any
    ///      order: a Safe lists owners by insertion) and threshold as the Safe at the same address on Ethereum, with
    ///      no module and no guard.
    function test_BASE_multisigsMatchEthereumCounterparts() public {
        address[4] memory safes = [BASE_OSERO_OPERATOR, BASE_SOTER_OPERATOR, BASE_SOTER_FREEZER, BASE_OSERO_CBEAM];
        string[4] memory labels =
            ["osero-relayer-multisig", "core-operator-relayer-multisig", "freezer-multisig", "osero-operator-multisig"];

        for (uint256 i = 0; i < safes.length; ++i) {
            _selectEthereum();
            address[] memory ethereumOwners = _sortedAddresses(ISafeLike(safes[i]).getOwners());
            uint256 ethereumThreshold = ISafeLike(safes[i]).getThreshold();

            _selectBase();
            assertEq(
                _sortedAddresses(ISafeLike(safes[i]).getOwners()), ethereumOwners, string.concat(labels[i], "-owners")
            );
            assertEq(ISafeLike(safes[i]).getThreshold(), ethereumThreshold, string.concat(labels[i], "-threshold"));
            (address[] memory modules,) = ISafeLike(safes[i]).getModulesPaginated(SAFE_SENTINEL_MODULES, 10);
            assertEq(modules.length, 0, string.concat(labels[i], "-modules"));
            assertEq(vm.load(safes[i], SAFE_GUARD_STORAGE_SLOT), bytes32(0), string.concat(labels[i], "-guard"));
        }
    }

    /**********************************************************************************************/
    /*** Base PAS (Proposed actions #16-17)                                                     ***/
    /**********************************************************************************************/

    function test_BASE_pasRejectsUnpairedCallerAfterAuthorization() public {
        _executeAllPayloadsAndBridges();
        _selectBase();

        IPASConfiguratorLike configurator = IPASConfiguratorLike(BASE_PAS_CONFIGURATOR);

        vm.prank(BASE_OSERO_CBEAM);
        vm.expectRevert(bytes("Configurator/not-authorized-ratelimits-cBeam"));
        configurator.setRateLimit(
            BASE_OSERO_RATE_LIMITS,
            CCTP_TO_ETHEREUM_RATE_LIMIT_KEY,
            PAS_FIXTURE_LOWERED_CCTP_MAX,
            PAS_FIXTURE_LOWERED_CCTP_SLOPE
        );

        vm.prank(BASE_OSERO_CBEAM);
        vm.expectRevert(bytes("Configurator/not-authorized-controller-cBeam"));
        configurator.callControllerAction(BASE_OSERO_CONTROLLER, _pasFixtureBaseControllerAction());
    }

    /// @dev High-level goal of Proposed action #17: once paired, the Osero Operator Multisig on Base adjusts
    ///      Osero's Base rate limits through the Configurator on Base, within the BeamState bounds.
    function test_BASE_pasConfiguratorSetsRateLimitAfterSkyCorePairing() public {
        _executeAllPayloadsAndBridges();
        _selectBase();
        _pairOseroCBeamOnBaseAsSkyCore();

        IPASConfiguratorLike configurator = IPASConfiguratorLike(BASE_PAS_CONFIGURATOR);
        IPASBeamStateLike beamState = IPASBeamStateLike(BASE_PAS_BEAM_STATE);

        // A decrease applies at once.
        vm.expectEmit(BASE_PAS_CONFIGURATOR);
        emit SetRateLimit(
            BASE_OSERO_RATE_LIMITS,
            CCTP_TO_ETHEREUM_RATE_LIMIT_KEY,
            PAS_FIXTURE_LOWERED_CCTP_MAX,
            PAS_FIXTURE_LOWERED_CCTP_SLOPE
        );
        vm.prank(BASE_OSERO_CBEAM);
        configurator.setRateLimit(
            BASE_OSERO_RATE_LIMITS,
            CCTP_TO_ETHEREUM_RATE_LIMIT_KEY,
            PAS_FIXTURE_LOWERED_CCTP_MAX,
            PAS_FIXTURE_LOWERED_CCTP_SLOPE
        );
        _assertRateLimitOn(
            BASE_OSERO_RATE_LIMITS,
            CCTP_TO_ETHEREUM_RATE_LIMIT_KEY,
            PAS_FIXTURE_LOWERED_CCTP_MAX,
            PAS_FIXTURE_LOWERED_CCTP_SLOPE,
            "base-cctp-to-ethereum-lowered"
        );

        // An increase back to the spell's values (the BeamState default) consumes the hop and keeps the current
        // capacity.
        vm.prank(BASE_OSERO_CBEAM);
        configurator.setRateLimit(
            BASE_OSERO_RATE_LIMITS, CCTP_TO_ETHEREUM_RATE_LIMIT_KEY, CCTP_TO_DOMAIN_MAX, CCTP_TO_DOMAIN_SLOPE
        );
        IRateLimitsLike.RateLimitData memory raised = baseRateLimits.getRateLimitData(CCTP_TO_ETHEREUM_RATE_LIMIT_KEY);
        assertEq(raised.maxAmount, CCTP_TO_DOMAIN_MAX, "base-cctp-to-ethereum-raised-max-amount");
        assertEq(raised.slope, CCTP_TO_DOMAIN_SLOPE, "base-cctp-to-ethereum-raised-slope");
        assertEq(raised.lastAmount, PAS_FIXTURE_LOWERED_CCTP_MAX, "base-cctp-to-ethereum-raised-last-amount");
        assertEq(raised.lastUpdated, block.timestamp, "base-cctp-to-ethereum-raised-last-updated");

        // A further increase inside the hop is rejected.
        uint256 maxChangeAmount = CCTP_TO_DOMAIN_MAX * beamState.getMaxChange(BASE_OSERO_RATE_LIMITS) / 1e18;
        vm.prank(BASE_OSERO_CBEAM);
        vm.expectRevert(bytes("Configurator/increment-too-soon"));
        configurator.setRateLimit(
            BASE_OSERO_RATE_LIMITS, CCTP_TO_ETHEREUM_RATE_LIMIT_KEY, maxChangeAmount, CCTP_TO_DOMAIN_SLOPE
        );

        // After the hop, an increase is bounded by maxChange.
        vm.warp(block.timestamp + beamState.getHop(BASE_OSERO_RATE_LIMITS));
        vm.prank(BASE_OSERO_CBEAM);
        vm.expectRevert(bytes("Configurator/exceeds-max-amount"));
        configurator.setRateLimit(
            BASE_OSERO_RATE_LIMITS, CCTP_TO_ETHEREUM_RATE_LIMIT_KEY, maxChangeAmount + 1, CCTP_TO_DOMAIN_SLOPE
        );

        vm.prank(BASE_OSERO_CBEAM);
        configurator.setRateLimit(
            BASE_OSERO_RATE_LIMITS, CCTP_TO_ETHEREUM_RATE_LIMIT_KEY, maxChangeAmount, CCTP_TO_DOMAIN_SLOPE
        );
        assertEq(
            baseRateLimits.getRateLimitData(CCTP_TO_ETHEREUM_RATE_LIMIT_KEY).maxAmount,
            maxChangeAmount,
            "base-cctp-to-ethereum-raised-above-default"
        );
    }

    /// @dev The aggregate CCTP and vault withdrawal keys have no BeamState default, so the Configurator can only
    ///      keep them unlimited, even though it holds DEFAULT_ADMIN_ROLE on the rate limits.
    function test_BASE_pasConfiguratorCannotChangeUnlimitedRateLimitsAfterSkyCorePairing() public {
        _executeAllPayloadsAndBridges();
        _selectBase();
        _pairOseroCBeamOnBaseAsSkyCore();

        IPASConfiguratorLike configurator = IPASConfiguratorLike(BASE_PAS_CONFIGURATOR);

        vm.prank(BASE_OSERO_CBEAM);
        vm.expectRevert(bytes("Configurator/unlimited-incorrect-params"));
        configurator.setRateLimit(BASE_OSERO_RATE_LIMITS, CCTP_RATE_LIMIT_KEY, CCTP_TO_DOMAIN_MAX, CCTP_TO_DOMAIN_SLOPE);

        vm.prank(BASE_OSERO_CBEAM);
        vm.expectRevert(bytes("Configurator/unlimited-incorrect-params"));
        configurator.setRateLimit(
            BASE_OSERO_RATE_LIMITS, OGUSDCB_WITHDRAW_RATE_LIMIT_KEY, OGUSDCB_DEPOSIT_MAX, OGUSDCB_DEPOSIT_SLOPE
        );

        _assertUnlimitedRateLimitOn(BASE_OSERO_RATE_LIMITS, CCTP_RATE_LIMIT_KEY, "base-cctp");
        _assertUnlimitedRateLimitOn(BASE_OSERO_RATE_LIMITS, OGUSDCB_WITHDRAW_RATE_LIMIT_KEY, "ogusdcb-withdraw");
    }

    /// @dev High-level goal of Proposed action #16: once paired, the Osero Operator Multisig on Base runs the
    ///      controller actions Sky Core enables, such as `removeIntegrations`, through the Configurator on Base.
    function test_BASE_pasConfiguratorCallsControllerActionAfterSkyCorePairing() public {
        _executeAllPayloadsAndBridges();
        _selectBase();
        _pairOseroCBeamOnBaseAsSkyCore();

        IPASConfiguratorLike configurator = IPASConfiguratorLike(BASE_PAS_CONFIGURATOR);

        // Only the actions Sky Core registered in BeamState can be dispatched.
        vm.prank(BASE_OSERO_CBEAM);
        vm.expectRevert(bytes("Configurator/not-valid-data"));
        configurator.callControllerAction(
            BASE_OSERO_CONTROLLER,
            abi.encodeCall(IOseroPauControllerLike.erc4626_setMaxExchangeRate, (OGUSDCB_VAULT, 1e18, 3e6))
        );

        bytes memory data = _pasFixtureBaseControllerAction();
        vm.expectEmit(BASE_OSERO_CONTROLLER);
        emit IntegrationRemoved(ERC4626_FACET_INTEGRATION_ID);
        vm.expectEmit(BASE_PAS_CONFIGURATOR);
        emit CallControllerAction(BASE_OSERO_CONTROLLER, data);
        vm.prank(BASE_OSERO_CBEAM);
        configurator.callControllerAction(BASE_OSERO_CONTROLLER, data);

        assertEq(baseController.integrations().length, 1, "base-integration-count-after-pas-removal");
        assertEq(
            baseController.getDispatch(IOseroPauControllerLike.erc4626_deposit.selector).facet,
            address(0),
            "erc4626-deposit-still-wired"
        );
    }

    /// @dev Pairing alone is not enough: without the Base payload's two grants, the Configurator passes every
    ///      PAS-side check and then fails on the Osero AccessControls and RateLimits role checks on Base.
    function test_BASE_pasOperationsRevertWithoutSpellGrantsEvenWhenPaired() public {
        _selectBase();
        _pairOseroCBeamOnBaseAsSkyCore();

        IPASConfiguratorLike configurator = IPASConfiguratorLike(BASE_PAS_CONFIGURATOR);

        vm.prank(BASE_OSERO_CBEAM);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", BASE_PAS_CONFIGURATOR, DEFAULT_ADMIN_ROLE
            )
        );
        configurator.setRateLimit(
            BASE_OSERO_RATE_LIMITS,
            CCTP_TO_ETHEREUM_RATE_LIMIT_KEY,
            PAS_FIXTURE_LOWERED_CCTP_MAX,
            PAS_FIXTURE_LOWERED_CCTP_SLOPE
        );

        vm.prank(BASE_OSERO_CBEAM);
        vm.expectRevert(bytes("Configurator/call-failed"));
        configurator.callControllerAction(BASE_OSERO_CONTROLLER, _pasFixtureBaseControllerAction());

        // The controller call fails on its admin check.
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = ERC4626_FACET_INTEGRATION_ID;
        vm.prank(BASE_PAS_CONFIGURATOR);
        vm.expectRevert(abi.encodeWithSignature("NotAdmin(address)", BASE_PAS_CONFIGURATOR));
        baseController.removeIntegrations(ids);

        _assertUnsetRateLimitOn(BASE_OSERO_RATE_LIMITS, CCTP_TO_ETHEREUM_RATE_LIMIT_KEY, "base-cctp-to-ethereum");
    }

    function test_ETHEREUM_cctpRoundTripThroughBaseVault() public {
        _executeAllPayloadsAndBridges();
        cctpBridge = CCTPV2BridgeTesting.createCircleBridge(ethereumDomain, baseDomain);

        // Ethereum: mint USDS, swap it to USDC and send it to the Osero ALM Proxy on Base.
        _selectEthereum();
        uint256 proxyUsdsStart = usds.balanceOf(OSERO_ALM_PROXY);
        uint256 proxyUsdcStart = usdc.balanceOf(OSERO_ALM_PROXY);
        uint256 debtStart = _allocatorDebt();

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_mint, (ROUND_TRIP_USDS_AMOUNT)));
        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.psm_swapUSDSToUSDC, (ROUND_TRIP_USDC_AMOUNT)));
        vm.expectEmit(OSERO_CONTROLLER);
        emit CCTPTransferInitiated(6, BASE_ALM_PROXY_RECIPIENT, ROUND_TRIP_USDC_AMOUNT, 0);
        _callAsOseroActor(abi.encodeCall(ICCTPControllerLike.cctp_transfer, (ROUND_TRIP_USDC_AMOUNT, 6, 0)));
        assertEq(usdc.balanceOf(OSERO_ALM_PROXY), proxyUsdcStart, "ethereum-proxy-usdc-not-sent");

        // Base: receive the USDC, deposit it in the vault, redeem the shares and send the USDC back.
        _selectBase();
        uint256 baseProxyUsdcStart = baseUsdc.balanceOf(BASE_OSERO_ALM_PROXY);
        uint256 baseProxySharesStart = ogusdcb.balanceOf(BASE_OSERO_ALM_PROXY);
        CCTPV2BridgeTesting.relayMessagesToDestination(cctpBridge, true);
        assertEq(
            baseUsdc.balanceOf(BASE_OSERO_ALM_PROXY),
            baseProxyUsdcStart + ROUND_TRIP_USDC_AMOUNT,
            "base-proxy-usdc-not-minted"
        );

        uint256 minSharesOut = IVaultV2Like(OGUSDCB_VAULT).previewDeposit(ROUND_TRIP_USDC_AMOUNT) * 999 / 1000;
        uint256 shares = abi.decode(
            _callAsBaseOseroActor(
                abi.encodeCall(
                    IOseroPauControllerLike.erc4626_deposit, (OGUSDCB_VAULT, ROUND_TRIP_USDC_AMOUNT, minSharesOut)
                )
            ),
            (uint256)
        );
        uint256 assets = abi.decode(
            _callAsBaseOseroActor(
                abi.encodeCall(IOseroPauControllerLike.erc4626_redeem, (OGUSDCB_VAULT, shares, 999e6))
            ),
            (uint256)
        );
        assertEq(ogusdcb.balanceOf(BASE_OSERO_ALM_PROXY), baseProxySharesStart, "base-proxy-shares-not-redeemed");

        vm.expectEmit(BASE_OSERO_CONTROLLER);
        emit CCTPTransferInitiated(0, ETHEREUM_ALM_PROXY_RECIPIENT, assets, 0);
        _callAsBaseOseroActor(abi.encodeCall(ICCTPControllerLike.cctp_transfer, (assets, 0, 0)));
        assertEq(baseUsdc.balanceOf(BASE_OSERO_ALM_PROXY), baseProxyUsdcStart, "base-proxy-usdc-not-sent");

        // Ethereum: receive the USDC, swap it back to USDS and burn it.
        CCTPV2BridgeTesting.relayMessagesToSource(cctpBridge, true);
        assertEq(usdc.balanceOf(OSERO_ALM_PROXY), proxyUsdcStart + assets, "ethereum-proxy-usdc-not-minted");
        assertGe(assets, 999e6, "round-trip-recovered-below-minimum");

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.psm_swapUSDCToUSDS, (assets)));
        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_burn, (assets * 1e12)));

        assertEq(usdc.balanceOf(OSERO_ALM_PROXY), proxyUsdcStart, "ethereum-proxy-usdc-not-swapped-back");
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart, "ethereum-proxy-usds-not-burned");
        // Any residual allocator debt is exactly the round-trip shortfall.
        assertEq(_allocatorDebt() - debtStart, ROUND_TRIP_USDS_AMOUNT - assets * 1e12, "allocator-debt-not-reconciled");
    }

    /**********************************************************************************************/
    /*** Helpers                                                                                ***/
    /**********************************************************************************************/

    /// @dev Base prerequisites checked before every execution of the Base payload (see `CrossChainSpellRunner`).
    function _assertBasePrerequisites() internal view override {
        _assertSkyCoreRegisteredErc4626Facet();
    }

    /// @dev Pre-requirements #1: the November 19, 2026 Sky Core spell registers the ERC-4626 facet on Base on the
    ///      Sky PAU Beacon on Base with the wires registered on Ethereum. Must be called with Base selected.
    function _assertSkyCoreRegisteredErc4626Facet() internal view {
        PauConfig memory config = IBeaconLike(BASE_SKY_PAU_BEACON).getConfig(ERC4626_FACET_INTEGRATION_ID);
        assertEq(
            config.facet,
            BASE_SKY_PAU_ERC4626_FACET,
            "sky-core-prerequisite-missing-erc4626-facet-not-registered-on-base-beacon"
        );
        _assertConfigWires(config, BASE_SKY_PAU_ERC4626_FACET, _expectedErc4626Wires(), "base-beacon-erc4626");
    }

    /// @dev Base Beacon fixture, NOT part of this spell. Models the November 19, 2026 Sky Core spell
    ///      (Pre-requirements #1): the Beacon admin registers `ERC4626_FACET` on the Sky PAU Beacon on Base with the
    ///      deployed Base ERC-4626 facet and the canonical diamond-pau wires (`BeaconConfig`, as registered on
    ///      Ethereum). The wires come from diamond-pau, not `_expectedErc4626Wires`, so `_assertBasePrerequisites`
    ///      still checks them independently. A no-op once BASE_FORK_BLOCK is past the real registration, so the
    ///      tests then run against the Beacon state on Base.
    function _registerErc4626FacetOnBaseBeaconAsSkyCore() internal onBase {
        if (IBeaconLike(BASE_SKY_PAU_BEACON).getConfig(ERC4626_FACET_INTEGRATION_ID).facet != address(0)) return;

        vm.prank(_baseBeaconAdmin());
        BeaconConfig.setERC4626Integration(BASE_SKY_PAU_BEACON, BASE_SKY_PAU_ERC4626_FACET);
    }

    /// @dev Base PAS fixture, NOT part of this spell. Models the November 19, 2026 Sky Core spell
    ///      (Pre-requirements #5): it registers the Osero RateLimits and Controller on Base in BeamState on Base,
    ///      registers and pairs the Osero Operator Multisig on Base as cBEAM, and registers a rate-limit default and
    ///      a controller action. On Base these go through the Sky Governance Relay, the BeamState ward.
    function _pairOseroCBeamOnBaseAsSkyCore() internal onBase {
        IPASBeamStateLike beamState = IPASBeamStateLike(BASE_PAS_BEAM_STATE);

        // Pre-state at the fork block: PAS is live on Base, Osero is not registered or paired.
        assertEq(beamState.wards(BASE_SKY_GOV_RELAY), 1, "base-gov-relay-not-beamstate-ward");
        assertFalse(beamState.stopped(), "base-beamstate-stopped");
        assertEq(beamState.rateLimits(BASE_OSERO_RATE_LIMITS), 0, "base-osero-ratelimits-already-registered");
        assertEq(beamState.controllers(BASE_OSERO_CONTROLLER), 0, "base-osero-controller-already-registered");
        assertEq(beamState.cBeams(BASE_OSERO_CBEAM), 0, "base-osero-cbeam-already-registered");
        assertGt(beamState.getHop(BASE_OSERO_RATE_LIMITS), 0, "base-beamstate-hop-not-set");
        assertGt(beamState.getMaxChange(BASE_OSERO_RATE_LIMITS), 1e18, "base-beamstate-max-change-not-set");

        vm.startPrank(BASE_SKY_GOV_RELAY);
        beamState.addRateLimits(BASE_OSERO_RATE_LIMITS);
        beamState.addController(BASE_OSERO_CONTROLLER);
        beamState.addCBeam(BASE_OSERO_CBEAM);
        beamState.setCBeamForRateLimits(BASE_OSERO_RATE_LIMITS, BASE_OSERO_CBEAM);
        beamState.setCBeamForController(BASE_OSERO_CONTROLLER, BASE_OSERO_CBEAM);
        beamState.addInitRateLimits(
            CCTP_TO_ETHEREUM_RATE_LIMIT_KEY, BASE_OSERO_RATE_LIMITS, CCTP_TO_DOMAIN_MAX, CCTP_TO_DOMAIN_SLOPE
        );
        beamState.addInitControllerActions(_pasFixtureBaseControllerAction(), BASE_OSERO_CONTROLLER);
        vm.stopPrank();

        assertEq(
            beamState.rateLimitsCBeams(BASE_OSERO_RATE_LIMITS, BASE_OSERO_CBEAM), 1, "base-cbeam-not-paired-ratelimits"
        );
        assertEq(
            beamState.controllersCBeams(BASE_OSERO_CONTROLLER, BASE_OSERO_CBEAM), 1, "base-cbeam-not-paired-controller"
        );
    }

    function _sortedAddresses(address[] memory addresses) internal pure returns (address[] memory) {
        for (uint256 i = 1; i < addresses.length; ++i) {
            address current = addresses[i];
            uint256 j = i;
            while (j > 0 && addresses[j - 1] > current) {
                addresses[j] = addresses[j - 1];
                --j;
            }
            addresses[j] = current;
        }
        return addresses;
    }

    /// @dev The controller action the Base PAS fixture registers for the Osero cBEAM on Base.
    function _pasFixtureBaseControllerAction() internal pure returns (bytes memory) {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = ERC4626_FACET_INTEGRATION_ID;
        return abi.encodeCall(IOseroPauControllerLike.removeIntegrations, (ids));
    }

    /// @dev The Spark Executor on Base until the November 5, 2026 Spark spell hands Beacon admin to the
    ///      Governance Relay on Base.
    function _baseBeaconAdmin() internal view returns (address admin) {
        IBeaconAdminLike beacon = IBeaconAdminLike(BASE_SKY_PAU_BEACON);
        admin = beacon.hasRole(DEFAULT_ADMIN_ROLE, BASE_SKY_GOV_RELAY) ? BASE_SKY_GOV_RELAY : BASE_SPARK_EXECUTOR;
        assertTrue(beacon.hasRole(DEFAULT_ADMIN_ROLE, admin), "base-beacon-admin-unknown");
    }

    function _assertExpectedBaseRoleGrant(Vm.Log memory log) internal pure {
        bytes32 role = log.topics[1];
        address account = address(uint160(uint256(log.topics[2])));
        assertEq(address(uint160(uint256(log.topics[3]))), BASE_OSERO_EXECUTOR, "role-granted-sender");

        bool expected = (log.emitter == BASE_OSERO_ALM_PROXY && role == CONTROLLER && account == BASE_OSERO_CONTROLLER)
            || (log.emitter == BASE_OSERO_RATE_LIMITS && role == CONTROLLER && account == BASE_OSERO_CONTROLLER)
            || (log.emitter == BASE_OSERO_ACCESS_CONTROLS
                && role == ALLOCATOR_ROLE
                && account == BASE_OSERO_ADMINISTERED_AGENT)
            || (log.emitter == BASE_OSERO_ACCESS_CONTROLS
                && role == DEFAULT_ADMIN_ROLE
                && account == BASE_PAS_CONFIGURATOR)
            || (log.emitter == BASE_OSERO_RATE_LIMITS && role == DEFAULT_ADMIN_ROLE && account == BASE_PAS_CONFIGURATOR);
        assertTrue(expected, "unexpected-role-granted");
    }

    function _assertBaseOnboardingContracts() internal view {
        _assertContract(BASE_OSERO_ACCESS_CONTROLS, "base-access-controls");
        _assertContract(BASE_OSERO_ALM_PROXY, "base-alm-proxy");
        _assertContract(BASE_OSERO_RATE_LIMITS, "base-rate-limits");
        _assertContract(BASE_OSERO_CONTROLLER, "base-controller");
        _assertContract(BASE_OSERO_ADMINISTERED_AGENT, "base-administered-agent");
        _assertContract(BASE_SKY_PAU_BEACON, "base-beacon");
        _assertContract(BASE_SKY_PAU_CCTP_FACET, "base-cctp-facet");
        _assertContract(BASE_SKY_PAU_ERC4626_FACET, "base-erc4626-facet");
        _assertContract(BASE_PAS_CONFIGURATOR, "base-pas-configurator");
        _assertContract(BASE_USDC, "base-usdc");
        _assertContract(CCTP_TOKEN_MESSENGER_V2, "base-cctp-token-messenger-v2");
        _assertContract(OGUSDCB_VAULT, "ogusdcb-vault");
        _assertContract(BASE_MORPHO_ADAPTER, "base-morpho-adapter");
    }

    function _assertBaseVaultPreconfiguration() internal view {
        IVaultV2Like vault = IVaultV2Like(OGUSDCB_VAULT);
        assertEq(vault.asset(), BASE_USDC, "ogusdcb-asset");
        assertEq(vault.decimals(), 18, "ogusdcb-decimals");
        assertEq(vault.name(), "Osero x Gauntlet USDC Prime", "ogusdcb-name");
        assertEq(vault.symbol(), "ogUSDCb", "ogusdcb-symbol");
        assertGt(vault.totalSupply(), 0, "ogusdcb-not-seeded");
        assertGe(vault.convertToAssets(1e18), 1e6, "ogusdcb-share-price-below-one");
        assertLt(vault.convertToAssets(1e18), 2e6, "ogusdcb-share-price-above-max-exchange-rate");
        assertEq(vault.owner(), BASE_OSERO_EXECUTOR, "ogusdcb-owner");
        assertEq(vault.curator(), OGUSDCB_CURATOR_MULTISIG, "ogusdcb-curator");
        assertTrue(vault.isAllocator(OGUSDCB_ALLOCATOR), "ogusdcb-allocator-not-authorized");
        assertFalse(vault.isAllocator(OGUSDCB_CURATOR_MULTISIG), "ogusdcb-curator-is-allocator");
        assertFalse(vault.isAllocator(BASE_OSERO_EXECUTOR), "ogusdcb-executor-is-allocator");
        assertTrue(vault.isSentinel(OGUSDCB_SENTINEL), "ogusdcb-sentinel-not-authorized");
        assertTrue(vault.isSentinel(SOTER_LABS_SENTINEL_MULTISIG), "ogusdcb-soter-labs-sentinel-not-authorized");
        assertEq(vault.liquidityAdapter(), BASE_MORPHO_ADAPTER, "ogusdcb-liquidity-adapter");
        assertEq(vault.adaptersLength(), 1, "ogusdcb-adapter-count");
        assertEq(vault.adapters(0), BASE_MORPHO_ADAPTER, "ogusdcb-adapter-zero");
        assertEq(IMorphoAdapterLike(BASE_MORPHO_ADAPTER).parentVault(), OGUSDCB_VAULT, "morpho-adapter-parent-vault");
        assertTrue(
            IVaultV2FactoryLike(BASE_MORPHO_VAULT_V2_FACTORY).isVaultV2(OGUSDCB_VAULT), "ogusdcb-not-factory-vault"
        );
        assertTrue(
            IMorphoAdapterFactoryLike(BASE_MORPHO_ADAPTER_FACTORY).isMorphoMarketV1AdapterV2(BASE_MORPHO_ADAPTER),
            "morpho-adapter-not-factory-adapter"
        );
        assertEq(vault.receiveSharesGate(), address(0), "ogusdcb-receive-shares-gate");
        assertEq(vault.sendAssetsGate(), address(0), "ogusdcb-send-assets-gate");
        assertEq(vault.sendSharesGate(), address(0), "ogusdcb-send-shares-gate");
        assertEq(vault.receiveAssetsGate(), address(0), "ogusdcb-receive-assets-gate");
        assertTrue(vault.canReceiveShares(BASE_OSERO_ALM_PROXY), "base-almproxy-cannot-receive-shares");
        assertTrue(vault.canSendShares(BASE_OSERO_ALM_PROXY), "base-almproxy-cannot-send-shares");
        assertTrue(vault.canReceiveAssets(BASE_OSERO_ALM_PROXY), "base-almproxy-cannot-receive-assets");
        assertTrue(vault.canSendAssets(BASE_OSERO_ALM_PROXY), "base-almproxy-cannot-send-assets");
        assertEq(vault.maxRate(), 31_709_791_983, "ogusdcb-max-rate");
        assertEq(vault.virtualShares(), 1e12, "ogusdcb-virtual-shares");
        assertEq(vault.performanceFee(), 0, "ogusdcb-performance-fee");
        assertEq(vault.managementFee(), 0, "ogusdcb-management-fee");
    }

    function _assertBaseMultisigs() internal view {
        _assertSafe(BASE_OSERO_OPERATOR, 2, 3, "base-osero-relayer-multisig");
        _assertSafe(BASE_SOTER_OPERATOR, 2, 3, "base-core-operator-relayer-multisig");
        _assertSafe(BASE_SOTER_FREEZER, 2, 5, "base-freezer-multisig");
        _assertSafe(OGUSDCB_CURATOR_MULTISIG, 2, 2, "ogusdcb-curator-multisig");
        address[] memory curatorSigners = ISafeLike(OGUSDCB_CURATOR_MULTISIG).getOwners();
        assertEq(curatorSigners[0], GAUNTLET_CO_CURATOR_MULTISIG, "ogusdcb-curator-gauntlet-signer");
        assertEq(curatorSigners[1], SOTER_LABS_CO_CURATOR_MULTISIG, "ogusdcb-curator-soter-labs-signer");
    }

    function _assertSafe(address safe, uint256 threshold, uint256 ownerCount, string memory label) internal view {
        _assertContract(safe, label);
        assertEq(ISafeLike(safe).getThreshold(), threshold, string.concat(label, "-threshold"));
        assertEq(ISafeLike(safe).getOwners().length, ownerCount, string.concat(label, "-owner-count"));
    }

    function _assertBaseNewRateLimitsUnset() internal view {
        _assertUnsetRateLimitOn(BASE_OSERO_RATE_LIMITS, CCTP_RATE_LIMIT_KEY, "base-cctp");
        _assertUnsetRateLimitOn(BASE_OSERO_RATE_LIMITS, CCTP_TO_ETHEREUM_RATE_LIMIT_KEY, "base-cctp-to-ethereum");
        _assertUnsetRateLimitOn(BASE_OSERO_RATE_LIMITS, OGUSDCB_DEPOSIT_RATE_LIMIT_KEY, "ogusdcb-deposit");
        _assertUnsetRateLimitOn(BASE_OSERO_RATE_LIMITS, OGUSDCB_WITHDRAW_RATE_LIMIT_KEY, "ogusdcb-withdraw");
    }

    /// @dev Asserts `config` has `facet` and exactly the `expected` wires, in any order (the Beacons on
    ///      Ethereum and Base register the same CCTP wires in different orders).
    function _assertConfigWires(PauConfig memory config, address facet, PauWire[] memory expected, string memory label)
        internal
        pure
    {
        assertEq(config.facet, facet, string.concat(label, "-facet"));
        assertEq(config.wires.length, expected.length, string.concat(label, "-wire-count"));
        for (uint256 i = 0; i < expected.length; ++i) {
            uint256 matches;
            for (uint256 j = 0; j < config.wires.length; ++j) {
                if (config.wires[j].callSelector != expected[i].callSelector) continue;
                assertEq(
                    config.wires[j].delegateSelector,
                    expected[i].delegateSelector,
                    string.concat(label, "-delegate-selector")
                );
                matches++;
            }
            assertEq(matches, 1, string.concat(label, "-call-selector-not-exactly-once"));
        }
    }

    function _assertConfigEquals(PauConfig memory actual, PauConfig memory expected, string memory label)
        internal
        pure
    {
        assertEq(actual.facet, expected.facet, string.concat(label, "-config-facet"));
        assertEq(actual.wires.length, expected.wires.length, string.concat(label, "-config-wire-count"));
        for (uint256 i = 0; i < expected.wires.length; ++i) {
            assertEq(
                actual.wires[i].callSelector,
                expected.wires[i].callSelector,
                string.concat(label, "-config-call-selector")
            );
            assertEq(
                actual.wires[i].delegateSelector,
                expected.wires[i].delegateSelector,
                string.concat(label, "-config-delegate-selector")
            );
        }
    }

    function _assertWiresDispatched(address controller_, PauWire[] memory wires, address facet, string memory label)
        internal
        view
    {
        for (uint256 i = 0; i < wires.length; ++i) {
            (address dispatchFacet, bytes4 delegateSelector) = _dispatch(controller_, wires[i].callSelector);
            assertEq(dispatchFacet, facet, string.concat(label, "-dispatch-facet"));
            assertEq(delegateSelector, wires[i].delegateSelector, string.concat(label, "-dispatch-delegate-selector"));
        }
    }

    function _dispatch(address controller_, bytes4 callSelector)
        internal
        view
        returns (address facet, bytes4 delegateSelector)
    {
        IOseroPauControllerLike pauController = IOseroPauControllerLike(controller_);
        facet = pauController.getDispatch(callSelector).facet;
        delegateSelector = pauController.getDispatch(callSelector).delegateSelector;
    }

    function _expectedCctpWires() internal pure returns (PauWire[] memory wires) {
        wires = new PauWire[](CCTP_FACET_WIRE_COUNT);
        wires[0] = PauWire(ICCTPControllerLike.cctp_VERSION.selector, ICCTPFacetLike.VERSION.selector);
        wires[1] =
            PauWire(ICCTPControllerLike.cctp_DESTINATION_CALLER.selector, ICCTPFacetLike.DESTINATION_CALLER.selector);
        wires[2] = PauWire(
            ICCTPControllerLike.cctp_MIN_FINALITY_THRESHOLD.selector, ICCTPFacetLike.MIN_FINALITY_THRESHOLD.selector
        );
        wires[3] = PauWire(ICCTPControllerLike.cctp_cctp.selector, ICCTPFacetLike.cctp.selector);
        wires[4] = PauWire(ICCTPControllerLike.cctp_usdc.selector, ICCTPFacetLike.usdc.selector);
        wires[5] = PauWire(
            ICCTPControllerLike.cctp_setDomainParameters.selector,
            bytes4(keccak256("setDomainParameters(uint32,bytes32,uint32,uint32)"))
        );
        wires[6] =
            PauWire(ICCTPControllerLike.cctp_transfer.selector, bytes4(keccak256("transfer(uint256,uint32,uint64)")));
        wires[7] =
            PauWire(ICCTPControllerLike.cctp_toCCTPRateLimitKey.selector, ICCTPFacetLike.toCCTPRateLimitKey.selector);
        wires[8] = PauWire(
            ICCTPControllerLike.cctp_getDomainParameters.selector, bytes4(keccak256("getDomainParameters(uint32)"))
        );
        wires[9] = PauWire(
            ICCTPControllerLike.cctp_getToDomainRateLimitKey.selector, ICCTPFacetLike.getToDomainRateLimitKey.selector
        );
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

    /// @dev ALLOCATOR-PRYSM-A debt (18 decimals) drawn by the Osero allocator vault urn.
    function _allocatorDebt() internal view returns (uint256) {
        (, uint256 art) = IVatLike(MCD_VAT).urns(OSERO_ILK, OSERO_ALLOCATOR_VAULT);
        (, uint256 rate,,,) = IVatLike(MCD_VAT).ilks(OSERO_ILK);
        return art * rate / RAY;
    }

    function _snapshotExistingRateLimits() internal view returns (ExistingRateLimitsSnapshot memory snapshot) {
        bytes32[8] memory keys = [
            USDS_MINT_RATE_LIMIT_KEY,
            USDS_BURN_RATE_LIMIT_KEY,
            PSM_USDS_TO_USDC_RATE_LIMIT_KEY,
            PSM_USDC_TO_USDS_RATE_LIMIT_KEY,
            SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY,
            SPARKLEND_USDS_WITHDRAW_RATE_LIMIT_KEY,
            OGUSDCP_DEPOSIT_RATE_LIMIT_KEY,
            OGUSDCP_WITHDRAW_RATE_LIMIT_KEY
        ];
        for (uint256 i = 0; i < keys.length; ++i) {
            snapshot.data[i] = rateLimits.getRateLimitData(keys[i]);
            assertGt(snapshot.data[i].maxAmount, 0, string.concat("existing-rate-limit-unset-", vm.toString(i)));
        }
    }

    function _snapshotExistingIntegrationConfigs() internal view returns (PauConfig[4] memory configs) {
        configs[0] = controller.getConfig(USDS_FACET_INTEGRATION_ID);
        configs[1] = controller.getConfig(AAVE_FACET_INTEGRATION_ID);
        configs[2] = controller.getConfig(ERC4626_FACET_INTEGRATION_ID);
        configs[3] = controller.getConfig(PSM_FACET_INTEGRATION_ID);
    }

    function _snapshotLaunchConfiguration() internal view returns (LaunchConfigurationSnapshot memory snapshot) {
        IAccessControlsLike accessControls = IAccessControlsLike(OSERO_ACCESS_CONTROLS);
        IALMProxyLike almProxy = IALMProxyLike(OSERO_ALM_PROXY);
        IAdministeredAgentLike agent = IAdministeredAgentLike(OSERO_ADMINISTERED_AGENT);
        snapshot.subProxyAccessAdmin = accessControls.hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY);
        snapshot.subProxyRateLimitsAdmin = rateLimits.hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY);
        snapshot.subProxyAlmProxyAdmin = almProxy.hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY);
        snapshot.pasAccessAdmin = accessControls.hasRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR);
        snapshot.pasRateLimitsAdmin = rateLimits.hasRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR);
        snapshot.agentAllocator = accessControls.hasRole(ALLOCATOR_ROLE, OSERO_ADMINISTERED_AGENT);
        snapshot.controllerRateLimits = rateLimits.hasRole(CONTROLLER, OSERO_CONTROLLER);
        snapshot.controllerAlmProxy = almProxy.hasRole(CONTROLLER, OSERO_CONTROLLER);
        snapshot.accessAdminCount = accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE);
        snapshot.allocatorCount = accessControls.getRoleMemberCount(ALLOCATOR_ROLE);
        snapshot.agentAdminCount = agent.adminCount();
        snapshot.agentActorCount = agent.actorCount();
        snapshot.agentRevokerCount = agent.revokerCount();
        snapshot.agentGrantorCount = agent.grantorCount();
        snapshot.starGuardWard = ISubProxyLike(OSERO_PROXY).wards(OSERO_STAR_GUARD);
    }

    function _assertLaunchConfigurationUnchanged(LaunchConfigurationSnapshot memory before_) internal view {
        LaunchConfigurationSnapshot memory after_ = _snapshotLaunchConfiguration();
        assertTrue(before_.subProxyAccessAdmin && after_.subProxyAccessAdmin, "subproxy-access-admin-changed");
        assertTrue(
            before_.subProxyRateLimitsAdmin && after_.subProxyRateLimitsAdmin, "subproxy-ratelimits-admin-changed"
        );
        assertTrue(before_.subProxyAlmProxyAdmin && after_.subProxyAlmProxyAdmin, "subproxy-almproxy-admin-changed");
        assertTrue(before_.pasAccessAdmin && after_.pasAccessAdmin, "pas-access-admin-changed");
        assertTrue(before_.pasRateLimitsAdmin && after_.pasRateLimitsAdmin, "pas-ratelimits-admin-changed");
        assertTrue(before_.agentAllocator && after_.agentAllocator, "agent-allocator-role-changed");
        assertTrue(before_.controllerRateLimits && after_.controllerRateLimits, "controller-ratelimits-role-changed");
        assertTrue(before_.controllerAlmProxy && after_.controllerAlmProxy, "controller-almproxy-role-changed");
        assertEq(after_.accessAdminCount, before_.accessAdminCount, "access-admin-count-changed");
        assertEq(after_.allocatorCount, before_.allocatorCount, "allocator-count-changed");
        assertEq(after_.agentAdminCount, before_.agentAdminCount, "agent-admin-count-changed");
        assertEq(after_.agentActorCount, before_.agentActorCount, "agent-actor-count-changed");
        assertEq(after_.agentRevokerCount, before_.agentRevokerCount, "agent-revoker-count-changed");
        assertEq(after_.agentGrantorCount, before_.agentGrantorCount, "agent-grantor-count-changed");
        assertEq(after_.starGuardWard, before_.starGuardWard, "star-guard-ward-changed");
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

    /// @dev Config for the inherited pre-spell integration test: the four integrations wired by earlier spells.
    function _expectedControllerIntegrations() internal pure override returns (ExpectedIntegration[] memory expected) {
        expected = new ExpectedIntegration[](4);
        expected[0] = ExpectedIntegration(USDS_FACET_INTEGRATION_ID, SKY_PAU_USDS_FACET, 8, "usds");
        expected[1] = ExpectedIntegration(AAVE_FACET_INTEGRATION_ID, SKY_PAU_AAVE_FACET, 7, "aave");
        expected[2] = ExpectedIntegration(ERC4626_FACET_INTEGRATION_ID, SKY_PAU_ERC4626_FACET, 9, "erc4626");
        expected[3] = ExpectedIntegration(PSM_FACET_INTEGRATION_ID, SKY_PAU_PSM_FACET, 11, "psm");
    }
}
