// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";

import {SparkLend} from "spark-address-registry/SparkLend.sol";

import {Ethereum as SkyPau} from "sky-pau-registry/Ethereum.sol";

import {NFATPrimeFacet} from "diamond-pau/src/facets/nfat-prime/NFATPrimeFacet.sol";
import {BeaconConfig} from "diamond-pau/src/libraries/BeaconConfig.sol";

import {NFATFacility} from "nfat/src/NFATFacility.sol";

import {
    IAccessControlsLike,
    IAdministeredAgentLike,
    IALMProxyLike,
    IAutoLineLike,
    IBeaconLike,
    IOseroPauControllerLike,
    IRateLimitsLike,
    ISpellLike,
    ISubProxyLike,
    IVatLike,
    PauConfig,
    PauWire
} from "../test-harness/OseroTestBase.sol";
import {CommonPauSpellTests, ExpectedIntegration} from "../test-harness/CommonPauSpellTests.sol";

interface ITransferAssetControllerLike {
    function transferAsset_VERSION() external view returns (string memory);
    function transferAsset_transfer(address asset, address destination, uint256 amount) external;
    function transferAsset_getTransferRateLimitKey(address asset, address destination) external view returns (bytes32);
}

interface ITransferAssetFacetLike {
    function VERSION() external view returns (string memory);
    function transfer(address asset, address destination, uint256 amount) external;
    function getTransferRateLimitKey(address asset, address destination) external view returns (bytes32);
}

interface INFATPrimeControllerLike {
    function nfatPrime_VERSION() external view returns (string memory);
    function nfatPrime_subscribe(address facility, uint256 amount, bytes calldata data) external;
    function nfatPrime_withdraw(address facility, uint256 amount) external;
    function nfatPrime_collect(address facility, uint256 tokenId, uint256 amount) external;
    function nfatPrime_getSubscribeRateLimitKey(address facility, address gem) external view returns (bytes32);
    function nfatPrime_getCollectRateLimitKey(address facility) external view returns (bytes32);
    function nfatPrime_getWithdrawRateLimitKey(address facility) external view returns (bytes32);
}

interface INFATPrimeFacetLike {
    function VERSION() external view returns (string memory);
    function subscribe(address facility, uint256 amount, bytes calldata data) external;
    function withdraw(address facility, uint256 amount) external;
    function collect(address facility, uint256 tokenId, uint256 amount) external;
    function getSubscribeRateLimitKey(address facility, address gem) external view returns (bytes32);
    function getCollectRateLimitKey(address facility) external view returns (bytes32);
    function getWithdrawRateLimitKey(address facility) external view returns (bytes32);
}

interface INFATFacilityLike {
    function addFreezer(address usr) external;
    function buds(address usr) external view returns (uint256);
    function collectable(uint256 tokenId) external view returns (uint256);
    function cops(address usr) external view returns (uint256);
    function deny(address usr) external;
    function deposits(address depositor) external view returns (uint256);
    function file(bytes32 what, address data) external;
    function gem() external view returns (address);
    function identityNetwork() external view returns (address);
    function issue(address to, uint256 tokenId, uint256 amount) external;
    function kiss(address usr) external;
    function name() external view returns (string memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function recipient() external view returns (address);
    function rely(address usr) external;
    function repay(uint256 tokenId, uint256 amount) external;
    function stop() external;
    function stopped() external view returns (bool);
    function symbol() external view returns (string memory);
    function wards(address usr) external view returns (uint256);
}

interface IIdentityNetworkLike {
    function isMember(address usr) external view returns (bool);
}

interface IBeaconAdminLike {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function removeIntegration(bytes32 id) external;
}

interface IRateLimitsAdminLike {
    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;
}

interface IPASConfiguratorLike {
    function setRateLimit(address rateLimits, bytes32 key, uint256 maxAmount, uint256 slope) external;
}

interface IPASBeamStateLike {
    function getHop(address rateLimits_) external view returns (uint256);
    function getInitRateLimits(bytes32 key, address rateLimits_)
        external
        view
        returns (uint256 maxAmount, uint256 slope);
    function getMaxChange(address rateLimits_) external view returns (uint256);
    function rateLimitsCBeams(address rateLimits_, address cBeam) external view returns (uint256);
    function stopped() external view returns (bool);
}

interface IVatLineLike {
    function Line() external view returns (uint256);
}

/// @dev Test-only identity network for the `identityNetwork` checks of the Test NFAT Facility.
contract IdentityNetworkMock {
    mapping(address => bool) public isMember;

    function setMember(address usr, bool member) external {
        isMember[usr] = member;
    }
}

contract OseroEthereum_20261203_Test is CommonPauSpellTests {
    // Forks at the technical scope readback block (November 16, 2026 14:06:23 UTC). Two things the spell depends on, and
    // one pre-state the tests assume, are not on-chain at that block. `setUp` simulates each until MAINNET_FORK_BLOCK is
    // moved past it:
    // - the NFAT Prime Facet is not deployed, and the December 3, 2026 Sky Core spell registers it on the Sky PAU
    //   Beacon (Pre-requirements #1, `_registerNfatPrimeFacetAsSkyCore`);
    // - the Test NFAT Facility is not deployed (Pre-requirements #3, `_deployTestNfatFacilityAsFacilityOwner`);
    // - the November 19, 2026 Osero spell has not executed (`_executeNovember19SpellIfPending`). This spell does not
    //   depend on it, but the tests expect its `CCTP_FACET` integration and CCTP keys to be in place.
    uint256 internal constant MAINNET_FORK_BLOCK = 26_428_080;

    // The on-chain payload; address(0) until it is deployed.
    address internal constant DEPLOYED_PAYLOAD = address(0);

    // `OseroEthereum_20261119`, deployed and plotted for the November 19, 2026 Sky Core spell.
    address internal constant NOVEMBER_19_PAYLOAD = 0xC1989b5c81eA2bC4A6Abda0e73e3E3C48D500d05;

    // TODO: placeholders for the technical scope's `<DESTINATION_ADDRESS>`, `<FACILITY_ADDRESS>` and
    //       `<NFAT_PRIME_FACET_ADDRESS>`. `test_ETHEREUM_deployedPayloadHasNoPlaceholders` fails once DEPLOYED_PAYLOAD
    //       is set while any of them is still in use.
    address internal constant PLACEHOLDER_USDS_TRANSFER_DESTINATION = 0x1111111111111111111111111111111111111111;
    address internal constant PLACEHOLDER_TEST_NFAT_FACILITY = 0x2222222222222222222222222222222222222222;
    address internal constant PLACEHOLDER_NFAT_PRIME_FACET = 0x3333333333333333333333333333333333333333;

    // Addresses from the technical scope (Trusted addresses, Pre-deployed contracts, Pre-requirements #4).
    address internal constant USDS_TRANSFER_DESTINATION = PLACEHOLDER_USDS_TRANSFER_DESTINATION;
    address internal constant TEST_NFAT_FACILITY = PLACEHOLDER_TEST_NFAT_FACILITY;
    address internal constant NFAT_PRIME_FACET = PLACEHOLDER_NFAT_PRIME_FACET;

    // TODO: the Test NFAT Facility configuration (Pre-deployed contracts #2) is `TBD` in the technical scope. Until then
    //       these synthetic values configure the simulated facility.
    address internal constant TEST_NFAT_FACILITY_OWNER = address(0xFAC0);
    address internal constant TEST_HALO_ALM_PROXY = address(0xFAC1); // `recipient` and the only `bud`
    address internal constant TEST_NFAT_FACILITY_FREEZER = address(0xFAC2);
    address internal constant TEST_NFAT_FACILITY_DEPLOYER = address(0xFAC3);
    // The block the facility is deployed in; its role history is read from there to MAINNET_FORK_BLOCK.
    uint256 internal constant TEST_NFAT_FACILITY_DEPLOYMENT_BLOCK = 0;
    string internal constant TEST_NFAT_FACILITY_NAME = "Test NFAT Facility";
    string internal constant TEST_NFAT_FACILITY_SYMBOL = "TNFAT";

    // Sky PAS on Ethereum. Source: https://chainlog.skyeco.com/ (keys: PAS_CONFIGURATOR, PAS_STATE)
    address internal constant PAS_CONFIGURATOR = 0xb7E61Df6CAb0A51E9A5dab1A7DD3f942dDe5b929;
    address internal constant PAS_BEAM_STATE = 0x1A1879E66547F90bfF87D45A5b0335950E019E02;
    // Osero Operator Multisig, the cBEAM paired to the Osero ALM Rate Limits contract. Source: the technical scope
    // (Trusted addresses).
    address internal constant OSERO_CBEAM = 0x42D1038017E466b413aa44Ae798E30FB80b2E180;
    // Osero x Gauntlet USDC Prime Vault on Ethereum, onboarded in the October 8, 2026 spell.
    address internal constant OGUSDCP_VAULT = 0x802148D518A6De2aF866f9A61ffB5e5C39156dB2;

    bytes32 internal constant USDS_FACET_INTEGRATION_ID = "USDS_FACET";
    bytes32 internal constant AAVE_FACET_INTEGRATION_ID = "AAVE_FACET";
    bytes32 internal constant ERC4626_FACET_INTEGRATION_ID = "ERC4626_FACET";
    bytes32 internal constant PSM_FACET_INTEGRATION_ID = "PSM_FACET";
    bytes32 internal constant CCTP_FACET_INTEGRATION_ID = "CCTP_FACET";
    bytes32 internal constant TRANSFER_ASSET_FACET_INTEGRATION_ID = "TRANSFER_ASSET_FACET";
    bytes32 internal constant NFAT_PRIME_FACET_INTEGRATION_ID = "NFAT_PRIME_FACET";

    // Encoded values as written in the technical scope (Proposed actions).
    bytes32 internal constant TRANSFER_ASSET_FACET_ID_LITERAL =
        0x5452414e534645525f41535345545f4641434554000000000000000000000000;
    bytes32 internal constant NFAT_PRIME_FACET_ID_LITERAL =
        0x4e4641545f5052494d455f464143455400000000000000000000000000000000;
    bytes32 internal constant LIMIT_ASSET_TRANSFER = 0x48f98264e3feb9c04c94251c86b84a95f369fb2973906e457f22ec9080cb6755;
    bytes32 internal constant LIMIT_NFAT_PRIME_SUBSCRIBE =
        0x8473567056328c618c1cfd978a104f32b493b61c46768ffcd0896dfed52d717e;
    bytes32 internal constant LIMIT_NFAT_PRIME_WITHDRAW =
        0x9d78029a08327b4fd0dfa4d5e6a140d71936e947294b39736e46b8ba46ffb1ad;
    bytes32 internal constant LIMIT_NFAT_PRIME_COLLECT =
        0x594d768565fc53d4f10aa71734dc71a1e302040a35980646fda5494b86748c8a;

    // New keys, from the formulas in the technical scope (Proposed actions #2, #4-6).
    bytes32 internal constant USDS_TRANSFER_RATE_LIMIT_KEY =
        keccak256(abi.encode(LIMIT_ASSET_TRANSFER, USDS, USDS_TRANSFER_DESTINATION));
    bytes32 internal constant NFAT_SUBSCRIBE_RATE_LIMIT_KEY =
        keccak256(abi.encode(LIMIT_NFAT_PRIME_SUBSCRIBE, USDS, TEST_NFAT_FACILITY));
    bytes32 internal constant NFAT_WITHDRAW_RATE_LIMIT_KEY =
        keccak256(abi.encode(LIMIT_NFAT_PRIME_WITHDRAW, TEST_NFAT_FACILITY));
    bytes32 internal constant NFAT_COLLECT_RATE_LIMIT_KEY =
        keccak256(abi.encode(LIMIT_NFAT_PRIME_COLLECT, TEST_NFAT_FACILITY));

    // Existing keys (technical scope, Post-checks #2).
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
    bytes32 internal constant CCTP_RATE_LIMIT_KEY = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 internal constant CCTP_TO_BASE_RATE_LIMIT_KEY =
        keccak256(abi.encode(keccak256("LIMIT_USDC_TO_DOMAIN"), uint32(6)));

    // TODO: placeholders, as in the spell, for the values the Core Council Risk Advisor confirms (Pre-requirements #5).
    uint256 internal constant USDS_TRANSFER_MAX = 1_000_000e18;
    uint256 internal constant USDS_TRANSFER_SLOPE = uint256(1_000_000e18) / 1 days;
    uint256 internal constant NFAT_SUBSCRIBE_MAX = 2_000_000e18;
    uint256 internal constant NFAT_SUBSCRIBE_SLOPE = uint256(1_000_000e18) / 1 days;
    uint256 internal constant NFAT_WITHDRAW_MAX = 3_000_000e18;
    uint256 internal constant NFAT_WITHDRAW_SLOPE = uint256(3_000_000e18) / 1 days;
    uint256 internal constant NFAT_COLLECT_MAX = 4_000_000e18;
    uint256 internal constant NFAT_COLLECT_SLOPE = uint256(4_000_000e18) / 1 days;

    // ALLOCATOR-PRYSM-A DC-IAM parameters (technical scope, Pre-requirements #2), in rad.
    uint256 internal constant RAD = 1e45;
    uint256 internal constant DC_IAM_LINE_BEFORE = 100_000_000 * RAD;
    uint256 internal constant DC_IAM_GAP_BEFORE = 15_000_000 * RAD;
    uint256 internal constant DC_IAM_LINE_AFTER = 500_000_000 * RAD;
    uint256 internal constant DC_IAM_GAP_AFTER = 150_000_000 * RAD;
    uint256 internal constant DC_IAM_TTL = 86_400;

    uint256 internal constant USDS_FACET_WIRE_COUNT = 8;
    uint256 internal constant AAVE_FACET_WIRE_COUNT = 7;
    uint256 internal constant ERC4626_FACET_WIRE_COUNT = 9;
    uint256 internal constant PSM_FACET_WIRE_COUNT = 11;
    uint256 internal constant CCTP_FACET_WIRE_COUNT = 10;
    uint256 internal constant TRANSFER_ASSET_FACET_WIRE_COUNT = 3;
    uint256 internal constant NFAT_PRIME_FACET_WIRE_COUNT = 7;

    // Post-checks #5 amount, and a repayment with interest on top for the collect test.
    uint256 internal constant ROUND_TRIP_USDS_AMOUNT = 1_000e18;
    uint256 internal constant REPAID_USDS_AMOUNT = 1_050e18;
    uint256 internal constant NFAT_TOKEN_ID = 1;
    uint256 internal constant PARTIAL_RECOVERY_TIME = 20 minutes;
    bytes internal constant SUBSCRIPTION_DATA = "test-subscription";

    bytes32 internal constant INTEGRATION_SET_TOPIC = keccak256("IntegrationSet(bytes32,(address,(bytes4,bytes4)[]))");
    bytes32 internal constant INTEGRATION_REMOVED_TOPIC = keccak256("IntegrationRemoved(bytes32)");
    bytes32 internal constant RATE_LIMIT_DATA_SET_TOPIC =
        keccak256("RateLimitDataSet(bytes32,uint256,uint256,uint256,uint256)");
    bytes32 internal constant ROLE_GRANTED_TOPIC = keccak256("RoleGranted(bytes32,address,address)");
    bytes32 internal constant ROLE_REVOKED_TOPIC = keccak256("RoleRevoked(bytes32,address,address)");
    bytes32 internal constant RELY_TOPIC = keccak256("Rely(address)");
    bytes32 internal constant DENY_TOPIC = keccak256("Deny(address)");
    bytes32 internal constant KISS_TOPIC = keccak256("Kiss(address)");
    bytes32 internal constant DISS_TOPIC = keccak256("Diss(address)");
    bytes32 internal constant ADD_FREEZER_TOPIC = keccak256("AddFreezer(address)");
    bytes32 internal constant REMOVE_FREEZER_TOPIC = keccak256("RemoveFreezer(address)");

    ITransferAssetControllerLike internal constant transferAssetController =
        ITransferAssetControllerLike(OSERO_CONTROLLER);
    INFATPrimeControllerLike internal constant nfatPrimeController = INFATPrimeControllerLike(OSERO_CONTROLLER);
    INFATFacilityLike internal constant facility = INFATFacilityLike(TEST_NFAT_FACILITY);

    // Set by `setUp` when a fixture stands in for something the technical scope expects on-chain.
    bool internal november19SpellExecutedByFixture;
    bool internal nfatPrimeFacetDeployedByFixture;
    bool internal testNfatFacilityDeployedByFixture;

    // The role history of the facility the fixture deploys; a deployed facility's history is read from the chain.
    FacilityRoleEvent[] internal fixtureFacilityRoleEvents;

    event TransferAssetTransfer(address indexed asset, address indexed destination, uint256 amount);
    event NFATPrimeSubscribe(address indexed facility, uint256 amount, bytes data);
    event NFATPrimeWithdraw(address indexed facility, uint256 amount);
    event NFATPrimeCollect(address indexed facility, uint256 indexed tokenId, uint256 amount);
    event Subscribe(address indexed depositor, uint256 amount, bytes data);
    event Withdraw(address indexed depositor, uint256 amount);
    event Collect(uint256 indexed tokenId, uint256 amount);
    event SetRateLimit(address indexed rateLimits, bytes32 indexed key, uint256 maxAmount, uint256 slope);

    // A `Rely`/`Deny`, `Kiss`/`Diss` or `AddFreezer`/`RemoveFreezer` event of the Test NFAT Facility.
    struct FacilityRoleEvent {
        bytes32 topic;
        address usr;
    }

    struct ExistingRateLimitsSnapshot {
        IRateLimitsLike.RateLimitData[10] data;
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
        spellId = "20261203";
    }

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), MAINNET_FORK_BLOCK);
        _executeNovember19SpellIfPending();
        _registerNfatPrimeFacetAsSkyCore();
        _deployTestNfatFacilityAsFacilityOwner();
        _setupPayload(DEPLOYED_PAYLOAD);
    }

    /**********************************************************************************************/
    /*** Technical scope                                                                        ***/
    /**********************************************************************************************/

    function test_ETHEREUM_scopeKeysAndEncodedParametersMatchTechnicalScope() public view {
        assertEq(TRANSFER_ASSET_FACET_INTEGRATION_ID, TRANSFER_ASSET_FACET_ID_LITERAL, "transfer-asset-id-literal");
        assertEq(NFAT_PRIME_FACET_INTEGRATION_ID, NFAT_PRIME_FACET_ID_LITERAL, "nfat-prime-id-literal");
        assertEq(keccak256("LIMIT_ASSET_TRANSFER"), LIMIT_ASSET_TRANSFER, "limit-asset-transfer-literal");
        assertEq(keccak256("LIMIT_NFAT_PRIME_SUBSCRIBE"), LIMIT_NFAT_PRIME_SUBSCRIBE, "limit-nfat-subscribe-literal");
        assertEq(keccak256("LIMIT_NFAT_PRIME_WITHDRAW"), LIMIT_NFAT_PRIME_WITHDRAW, "limit-nfat-withdraw-literal");
        assertEq(keccak256("LIMIT_NFAT_PRIME_COLLECT"), LIMIT_NFAT_PRIME_COLLECT, "limit-nfat-collect-literal");

        ITransferAssetFacetLike transferAssetFacet = ITransferAssetFacetLike(SkyPau.TRANSFER_ASSET_FACET);
        assertEq(
            transferAssetFacet.getTransferRateLimitKey(USDS, USDS_TRANSFER_DESTINATION),
            USDS_TRANSFER_RATE_LIMIT_KEY,
            "transfer-asset-facet-key"
        );

        INFATPrimeFacetLike nfatPrimeFacet = INFATPrimeFacetLike(NFAT_PRIME_FACET);
        assertEq(
            nfatPrimeFacet.getSubscribeRateLimitKey(TEST_NFAT_FACILITY, USDS),
            NFAT_SUBSCRIBE_RATE_LIMIT_KEY,
            "nfat-prime-facet-subscribe-key"
        );
        // The getter takes `(facility, gem)`, but the key encodes `gem` first.
        assertNotEq(
            NFAT_SUBSCRIBE_RATE_LIMIT_KEY,
            keccak256(abi.encode(LIMIT_NFAT_PRIME_SUBSCRIBE, TEST_NFAT_FACILITY, USDS)),
            "nfat-subscribe-key-argument-order"
        );
        assertEq(
            nfatPrimeFacet.getWithdrawRateLimitKey(TEST_NFAT_FACILITY),
            NFAT_WITHDRAW_RATE_LIMIT_KEY,
            "nfat-prime-facet-withdraw-key"
        );
        assertEq(
            nfatPrimeFacet.getCollectRateLimitKey(TEST_NFAT_FACILITY),
            NFAT_COLLECT_RATE_LIMIT_KEY,
            "nfat-prime-facet-collect-key"
        );

        // Call and facet selectors (Proposed actions #1, Pre-requirements #1).
        assertEq(ITransferAssetControllerLike.transferAsset_VERSION.selector, bytes4(0xc58a1a66), "sel-ta-version");
        assertEq(ITransferAssetControllerLike.transferAsset_transfer.selector, bytes4(0x56ebb17a), "sel-ta-transfer");
        assertEq(
            ITransferAssetControllerLike.transferAsset_getTransferRateLimitKey.selector,
            bytes4(0x18cb1daf),
            "sel-ta-key"
        );
        assertEq(ITransferAssetFacetLike.transfer.selector, bytes4(0xbeabacc8), "sel-ta-facet-transfer");
        assertEq(ITransferAssetFacetLike.getTransferRateLimitKey.selector, bytes4(0xa7811f56), "sel-ta-facet-key");
        assertEq(INFATPrimeControllerLike.nfatPrime_subscribe.selector, bytes4(0xe2f5e974), "sel-np-subscribe");
        assertEq(INFATPrimeControllerLike.nfatPrime_withdraw.selector, bytes4(0xba6cfa89), "sel-np-withdraw");
        assertEq(INFATPrimeControllerLike.nfatPrime_collect.selector, bytes4(0x440a8b3b), "sel-np-collect");
        assertEq(
            INFATPrimeControllerLike.nfatPrime_getSubscribeRateLimitKey.selector,
            bytes4(0xe952141a),
            "sel-np-subscribe-key"
        );
        assertEq(
            INFATPrimeControllerLike.nfatPrime_getCollectRateLimitKey.selector, bytes4(0xf348434d), "sel-np-collect-key"
        );
        assertEq(
            INFATPrimeControllerLike.nfatPrime_getWithdrawRateLimitKey.selector,
            bytes4(0x43f7b5f5),
            "sel-np-withdraw-key"
        );
        assertEq(INFATPrimeControllerLike.nfatPrime_VERSION.selector, bytes4(0x9027aa28), "sel-np-version");
        assertEq(INFATPrimeFacetLike.subscribe.selector, bytes4(0xd0804281), "sel-np-facet-subscribe");
        assertEq(INFATPrimeFacetLike.withdraw.selector, bytes4(0xf3fef3a3), "sel-np-facet-withdraw");
        assertEq(INFATPrimeFacetLike.collect.selector, bytes4(0xacc10f11), "sel-np-facet-collect");
        assertEq(INFATPrimeFacetLike.getSubscribeRateLimitKey.selector, bytes4(0xdf897ee4), "sel-np-facet-sub-key");
        assertEq(INFATPrimeFacetLike.getCollectRateLimitKey.selector, bytes4(0x5285d449), "sel-np-facet-col-key");
        assertEq(INFATPrimeFacetLike.getWithdrawRateLimitKey.selector, bytes4(0x180c92e7), "sel-np-facet-wd-key");
        assertEq(INFATPrimeFacetLike.VERSION.selector, bytes4(0xffa1ad74), "sel-facet-version");

        // Event topics (Monitoring).
        assertEq(
            INTEGRATION_SET_TOPIC, 0x5d055c4f05bd18deea319d5a3203b45d847aedd23073a618067b95ddd537c946, "topic-int-set"
        );
        assertEq(
            RATE_LIMIT_DATA_SET_TOPIC,
            0x356822943b80f809508a684c67d901d5c13b6a22161bf07d510e50a6cb727028,
            "topic-rate-limit-set"
        );
        assertEq(
            TransferAssetTransfer.selector,
            0xff364e1ef6190841ba9dfd518157372a542d1a297893d3d0a7e9beda04cb0cd0,
            "topic-transfer-asset"
        );
        assertEq(
            NFATPrimeSubscribe.selector,
            0x4107fe54af094322a23ddae3e87bb59132232334bf1e4447de16f07bfc4ba0e8,
            "topic-nfat-subscribe"
        );
        assertEq(
            NFATPrimeWithdraw.selector,
            0xc2b0ddd08a2de5bf3f6a133b70189e2327b1730dffd8a47dfa9813dd1e47c319,
            "topic-nfat-withdraw"
        );
        assertEq(
            NFATPrimeCollect.selector,
            0x4c91b7ea811d3a13d0f61635d6cb9f1182efe762903c945967ccb7b3d95f2e41,
            "topic-nfat-collect"
        );

        // TODO: placeholder values, as above.
        assertEq(USDS_TRANSFER_MAX, 1_000_000_000_000_000_000_000_000, "usds-transfer-max-literal");
        assertEq(USDS_TRANSFER_SLOPE, 11_574_074_074_074_074_074, "usds-transfer-slope-literal");
        assertEq(NFAT_SUBSCRIBE_MAX, 2_000_000_000_000_000_000_000_000, "nfat-subscribe-max-literal");
        assertEq(NFAT_SUBSCRIBE_SLOPE, 11_574_074_074_074_074_074, "nfat-subscribe-slope-literal");
        assertEq(NFAT_WITHDRAW_MAX, 3_000_000_000_000_000_000_000_000, "nfat-withdraw-max-literal");
        assertEq(NFAT_WITHDRAW_SLOPE, 34_722_222_222_222_222_222, "nfat-withdraw-slope-literal");
        assertEq(NFAT_COLLECT_MAX, 4_000_000_000_000_000_000_000_000, "nfat-collect-max-literal");
        assertEq(NFAT_COLLECT_SLOPE, 46_296_296_296_296_296_296, "nfat-collect-slope-literal");
    }

    /// @dev Detects a payload deployed with a placeholder, once DEPLOYED_PAYLOAD is set (it cannot run earlier): the
    ///      tests must use the real destination and facility, the NFAT Prime Facet and the Test NFAT Facility must
    ///      exist on-chain at the fork block, and the November 19, 2026 spell must have executed. Only Sky Core's
    ///      registration of the facet may still be simulated, since it happens in the Sky Core spell that plots this
    ///      payload. The keys the tests derive from the real addresses then fail against a payload built with a
    ///      placeholder. Before deploying, also check that the placeholder addresses are not in
    ///      `forge inspect OseroEthereum_20261203 deployedBytecode`.
    function test_ETHEREUM_deployedPayloadHasNoPlaceholders() public {
        vm.skip(deployedPayload == address(0));

        assertNotEq(USDS_TRANSFER_DESTINATION, PLACEHOLDER_USDS_TRANSFER_DESTINATION, "destination-placeholder");
        assertNotEq(TEST_NFAT_FACILITY, PLACEHOLDER_TEST_NFAT_FACILITY, "facility-placeholder");
        assertNotEq(NFAT_PRIME_FACET, PLACEHOLDER_NFAT_PRIME_FACET, "nfat-prime-facet-placeholder");
        assertGt(TEST_NFAT_FACILITY_DEPLOYMENT_BLOCK, 0, "facility-deployment-block-placeholder");
        assertFalse(november19SpellExecutedByFixture, "november-19-spell-not-executed");
        assertFalse(nfatPrimeFacetDeployedByFixture, "nfat-prime-facet-not-deployed");
        assertFalse(testNfatFacilityDeployedByFixture, "test-nfat-facility-not-deployed");
    }

    /**********************************************************************************************/
    /*** Pre-state and Sky Core prerequisites                                                   ***/
    /**********************************************************************************************/

    function test_ETHEREUM_transferAssetPreconfiguration() public view {
        _assertContract(SkyPau.TRANSFER_ASSET_FACET, "sky-pau-transfer-asset-facet");
        _assertConfigWires(
            IBeaconLike(SKY_PAU_BEACON).getConfig(TRANSFER_ASSET_FACET_INTEGRATION_ID),
            SkyPau.TRANSFER_ASSET_FACET,
            _expectedTransferAssetWires(),
            "beacon-transfer-asset"
        );
        assertEq(ITransferAssetFacetLike(SkyPau.TRANSFER_ASSET_FACET).VERSION(), "1.0.0", "transfer-asset-version");

        _assertWiresNotDispatched(_expectedTransferAssetWires(), "transfer-asset");
        _assertUnsetRateLimit(USDS_TRANSFER_RATE_LIMIT_KEY, "usds-transfer");
    }

    function test_ETHEREUM_nfatPrimePreconfiguration() public view {
        _assertSkyCoreRegisteredNfatPrimeFacet();
        assertEq(INFATPrimeFacetLike(NFAT_PRIME_FACET).VERSION(), "1.0.0", "nfat-prime-version");

        _assertWiresNotDispatched(_expectedNfatPrimeWires(), "nfat-prime");
        _assertUnsetRateLimit(NFAT_SUBSCRIBE_RATE_LIMIT_KEY, "nfat-subscribe");
        _assertUnsetRateLimit(NFAT_WITHDRAW_RATE_LIMIT_KEY, "nfat-withdraw");
        _assertUnsetRateLimit(NFAT_COLLECT_RATE_LIMIT_KEY, "nfat-collect");
    }

    /// @dev Pre-deployed contracts #2 and Pre-requirements #3. The role sets are rebuilt from the facility's role
    ///      events, so an extra ward, operator or freezer fails the test, not just a missing one.
    function test_ETHEREUM_testNfatFacilityPreconfiguration() public view {
        _assertContract(TEST_NFAT_FACILITY, "test-nfat-facility");

        assertEq(facility.gem(), USDS, "facility-gem");
        assertEq(facility.name(), TEST_NFAT_FACILITY_NAME, "facility-name");
        assertEq(facility.symbol(), TEST_NFAT_FACILITY_SYMBOL, "facility-symbol");
        assertFalse(facility.stopped(), "facility-stopped");
        assertEq(facility.recipient(), TEST_HALO_ALM_PROXY, "facility-recipient");

        // The owner is the only ward, the Halo-side ALM Proxy the only operator, and the deployer kept no ward.
        FacilityRoleEvent[] memory roleEvents = _facilityRoleEvents();
        _assertRoleSet(_replayRoles(roleEvents, RELY_TOPIC, DENY_TOPIC), TEST_NFAT_FACILITY_OWNER, "facility-wards");
        _assertRoleSet(_replayRoles(roleEvents, KISS_TOPIC, DISS_TOPIC), TEST_HALO_ALM_PROXY, "facility-buds");
        _assertRoleSet(
            _replayRoles(roleEvents, ADD_FREEZER_TOPIC, REMOVE_FREEZER_TOPIC),
            TEST_NFAT_FACILITY_FREEZER,
            "facility-cops"
        );
        assertEq(facility.wards(TEST_NFAT_FACILITY_OWNER), 1, "facility-owner-not-ward");
        assertEq(facility.wards(TEST_NFAT_FACILITY_DEPLOYER), 0, "facility-deployer-still-ward");
        assertEq(facility.buds(TEST_HALO_ALM_PROXY), 1, "facility-operator-not-bud");
        assertEq(facility.cops(TEST_NFAT_FACILITY_FREEZER), 1, "facility-freezer-not-cop");

        // No identity network, or one the Osero ALM Proxy is a member of.
        address identityNetwork = facility.identityNetwork();
        if (identityNetwork != address(0)) {
            assertTrue(
                IIdentityNetworkLike(identityNetwork).isMember(OSERO_ALM_PROXY),
                "facility-identity-network-excludes-osero"
            );
        }

        // The Osero ALM Proxy only subscribes: it holds no facility role and no deposit yet.
        assertNotEq(facility.recipient(), OSERO_ALM_PROXY, "osero-almproxy-is-recipient");
        assertEq(facility.buds(OSERO_ALM_PROXY), 0, "osero-almproxy-is-bud");
        assertEq(facility.wards(OSERO_ALM_PROXY), 0, "osero-almproxy-is-ward");
        assertEq(facility.wards(OSERO_PROXY), 0, "osero-subproxy-is-ward");
        assertEq(facility.deposits(OSERO_ALM_PROXY), 0, "osero-almproxy-deposit");
    }

    /// @dev The role check above replays the facility's role events: an extra ward or operator is counted, and a
    ///      `Deny` removes one, so the check fails for any role set other than the approved one.
    function test_ETHEREUM_facilityRoleReplayCountsExtraAndRemovedRoles() public pure {
        address unapproved = address(0xBAD);
        FacilityRoleEvent[] memory roleEvents = new FacilityRoleEvent[](6);
        roleEvents[0] = FacilityRoleEvent(RELY_TOPIC, TEST_NFAT_FACILITY_DEPLOYER);
        roleEvents[1] = FacilityRoleEvent(RELY_TOPIC, TEST_NFAT_FACILITY_OWNER);
        roleEvents[2] = FacilityRoleEvent(DENY_TOPIC, TEST_NFAT_FACILITY_DEPLOYER);
        roleEvents[3] = FacilityRoleEvent(RELY_TOPIC, unapproved);
        roleEvents[4] = FacilityRoleEvent(KISS_TOPIC, TEST_HALO_ALM_PROXY);
        roleEvents[5] = FacilityRoleEvent(KISS_TOPIC, unapproved);

        address[] memory wards = _replayRoles(roleEvents, RELY_TOPIC, DENY_TOPIC);
        assertEq(wards.length, 2, "ward-count");
        assertEq(wards[0], TEST_NFAT_FACILITY_OWNER, "ward-owner");
        assertEq(wards[1], unapproved, "ward-unapproved");

        address[] memory buds = _replayRoles(roleEvents, KISS_TOPIC, DISS_TOPIC);
        assertEq(buds.length, 2, "bud-count");
        assertEq(buds[1], unapproved, "bud-unapproved");

        assertEq(_replayRoles(roleEvents, ADD_FREEZER_TOPIC, REMOVE_FREEZER_TOPIC).length, 0, "cop-count");
    }

    /// @dev Pre-requirements #1: without the registration, `updateIntegrations` reverts with `IntegrationNotFound`,
    ///      so the whole payload reverts, including Proposed actions #1-2 (Technical risk #7). The plot survives the
    ///      revert, so the payload executes once Sky Core registers the facet. Removes the registration `setUp`
    ///      guarantees (simulated or real).
    function test_ETHEREUM_payloadRevertsUntilSkyCoreRegistersNfatPrimeFacet() public {
        vm.prank(MCD_PAUSE_PROXY);
        IBeaconAdminLike(SKY_PAU_BEACON).removeIntegration(NFAT_PRIME_FACET_INTEGRATION_ID);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = NFAT_PRIME_FACET_INTEGRATION_ID;
        vm.prank(OSERO_PROXY);
        vm.expectRevert(abi.encodeWithSignature("IntegrationNotFound(bytes32)", NFAT_PRIME_FACET_INTEGRATION_ID));
        controller.updateIntegrations(ids);

        vm.prank(MCD_PAUSE_PROXY);
        starGuard.plot(payload, payload.codehash);
        // The SubProxy replaces the payload's revert data with its own error.
        vm.prank(PERMISSIONLESS_EXECUTOR);
        vm.expectRevert(bytes("SubProxy/delegatecall-error"));
        starGuard.exec();

        (address plotted,,) = starGuard.spellData();
        assertEq(plotted, payload, "plot-cleared-by-revert");
        assertTrue(starGuard.prob(), "starguard-not-probable-after-revert");

        _registerNfatPrimeFacetAsSkyCore();
        vm.prank(PERMISSIONLESS_EXECUTOR);
        starGuard.exec();
        _assertRateLimit(
            USDS_TRANSFER_RATE_LIMIT_KEY, USDS_TRANSFER_MAX, USDS_TRANSFER_SLOPE, "usds-transfer-after-retry"
        );
        _assertRateLimit(NFAT_COLLECT_RATE_LIMIT_KEY, NFAT_COLLECT_MAX, NFAT_COLLECT_SLOPE, "nfat-collect-after-retry");
    }

    /**********************************************************************************************/
    /*** Spell execution                                                                        ***/
    /**********************************************************************************************/

    function test_ETHEREUM_spellExecutionEnablesTransferAssetAndNfatPrimeIntegrations() public {
        _executeSpellViaStarGuard(payload);

        ExpectedIntegration[] memory expected = new ExpectedIntegration[](7);
        expected[0] = ExpectedIntegration(USDS_FACET_INTEGRATION_ID, SKY_PAU_USDS_FACET, USDS_FACET_WIRE_COUNT, "usds");
        expected[1] = ExpectedIntegration(AAVE_FACET_INTEGRATION_ID, SKY_PAU_AAVE_FACET, AAVE_FACET_WIRE_COUNT, "aave");
        expected[2] = ExpectedIntegration(
            ERC4626_FACET_INTEGRATION_ID, SKY_PAU_ERC4626_FACET, ERC4626_FACET_WIRE_COUNT, "erc4626"
        );
        expected[3] = ExpectedIntegration(PSM_FACET_INTEGRATION_ID, SKY_PAU_PSM_FACET, PSM_FACET_WIRE_COUNT, "psm");
        expected[4] = ExpectedIntegration(CCTP_FACET_INTEGRATION_ID, SkyPau.CCTP_FACET, CCTP_FACET_WIRE_COUNT, "cctp");
        expected[5] = ExpectedIntegration(
            TRANSFER_ASSET_FACET_INTEGRATION_ID,
            SkyPau.TRANSFER_ASSET_FACET,
            TRANSFER_ASSET_FACET_WIRE_COUNT,
            "transfer-asset"
        );
        expected[6] = ExpectedIntegration(
            NFAT_PRIME_FACET_INTEGRATION_ID, NFAT_PRIME_FACET, NFAT_PRIME_FACET_WIRE_COUNT, "nfat-prime"
        );
        _assertControllerIntegrations(expected);

        _assertConfigEquals(
            controller.getConfig(TRANSFER_ASSET_FACET_INTEGRATION_ID),
            IBeaconLike(SKY_PAU_BEACON).getConfig(TRANSFER_ASSET_FACET_INTEGRATION_ID),
            "transfer-asset"
        );
        _assertConfigEquals(
            controller.getConfig(NFAT_PRIME_FACET_INTEGRATION_ID),
            IBeaconLike(SKY_PAU_BEACON).getConfig(NFAT_PRIME_FACET_INTEGRATION_ID),
            "nfat-prime"
        );
        _assertWiresDispatched(_expectedTransferAssetWires(), SkyPau.TRANSFER_ASSET_FACET, "transfer-asset");
        _assertWiresDispatched(_expectedNfatPrimeWires(), NFAT_PRIME_FACET, "nfat-prime");

        assertEq(transferAssetController.transferAsset_VERSION(), "1.0.0", "controller-transfer-asset-version");
        assertEq(nfatPrimeController.nfatPrime_VERSION(), "1.0.0", "controller-nfat-prime-version");
        assertEq(
            transferAssetController.transferAsset_getTransferRateLimitKey(USDS, USDS_TRANSFER_DESTINATION),
            USDS_TRANSFER_RATE_LIMIT_KEY,
            "controller-usds-transfer-key"
        );
        assertEq(
            nfatPrimeController.nfatPrime_getSubscribeRateLimitKey(TEST_NFAT_FACILITY, USDS),
            NFAT_SUBSCRIBE_RATE_LIMIT_KEY,
            "controller-nfat-subscribe-key"
        );
        assertEq(
            nfatPrimeController.nfatPrime_getWithdrawRateLimitKey(TEST_NFAT_FACILITY),
            NFAT_WITHDRAW_RATE_LIMIT_KEY,
            "controller-nfat-withdraw-key"
        );
        assertEq(
            nfatPrimeController.nfatPrime_getCollectRateLimitKey(TEST_NFAT_FACILITY),
            NFAT_COLLECT_RATE_LIMIT_KEY,
            "controller-nfat-collect-key"
        );
    }

    function test_ETHEREUM_spellExecutionSetsRateLimits() public {
        _executeSpellViaStarGuard(payload);

        _assertRateLimit(USDS_TRANSFER_RATE_LIMIT_KEY, USDS_TRANSFER_MAX, USDS_TRANSFER_SLOPE, "usds-transfer");
        _assertRateLimit(NFAT_SUBSCRIBE_RATE_LIMIT_KEY, NFAT_SUBSCRIBE_MAX, NFAT_SUBSCRIBE_SLOPE, "nfat-subscribe");
        _assertRateLimit(NFAT_WITHDRAW_RATE_LIMIT_KEY, NFAT_WITHDRAW_MAX, NFAT_WITHDRAW_SLOPE, "nfat-withdraw");
        _assertRateLimit(NFAT_COLLECT_RATE_LIMIT_KEY, NFAT_COLLECT_MAX, NFAT_COLLECT_SLOPE, "nfat-collect");
    }

    function test_ETHEREUM_existingRateLimitsPermissionsAndIntegrationsUnchanged() public {
        ExistingRateLimitsSnapshot memory limitsBefore = _snapshotExistingRateLimits();
        LaunchConfigurationSnapshot memory launchBefore = _snapshotLaunchConfiguration();
        PauConfig[5] memory configsBefore = _snapshotExistingIntegrationConfigs();

        _executeSpellViaStarGuard(payload);

        ExistingRateLimitsSnapshot memory limitsAfter = _snapshotExistingRateLimits();
        for (uint256 i = 0; i < 10; ++i) {
            _assertRateLimitDataUnchanged(limitsBefore.data[i], limitsAfter.data[i], vm.toString(i));
        }
        _assertLaunchConfigurationUnchanged(launchBefore);

        PauConfig[5] memory configsAfter = _snapshotExistingIntegrationConfigs();
        for (uint256 i = 0; i < 5; ++i) {
            _assertConfigEquals(
                configsAfter[i], configsBefore[i], string.concat("existing-integration-", vm.toString(i))
            );
        }
    }

    /// @dev Post-checks #1: two `IntegrationSet` and four `RateLimitDataSet` events, in the order of Proposed actions
    ///      #1-6, and no `IntegrationRemoved`, `RoleGranted` or `RoleRevoked`.
    function test_ETHEREUM_spellEmitsOnlyExpectedEvents() public {
        vm.recordLogs();
        _executeSpellViaStarGuard(payload);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Proposed actions #1-6 in order: each entry is the event topic and its first indexed topic.
        bytes32[2][6] memory expected = [
            [INTEGRATION_SET_TOPIC, TRANSFER_ASSET_FACET_INTEGRATION_ID],
            [RATE_LIMIT_DATA_SET_TOPIC, USDS_TRANSFER_RATE_LIMIT_KEY],
            [INTEGRATION_SET_TOPIC, NFAT_PRIME_FACET_INTEGRATION_ID],
            [RATE_LIMIT_DATA_SET_TOPIC, NFAT_SUBSCRIBE_RATE_LIMIT_KEY],
            [RATE_LIMIT_DATA_SET_TOPIC, NFAT_WITHDRAW_RATE_LIMIT_KEY],
            [RATE_LIMIT_DATA_SET_TOPIC, NFAT_COLLECT_RATE_LIMIT_KEY]
        ];
        uint256 actionEvents;
        uint256 integrationRemovals;
        uint256 roleChanges;

        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic == INTEGRATION_SET_TOPIC || topic == RATE_LIMIT_DATA_SET_TOPIC) {
                assertEq(
                    logs[i].emitter,
                    topic == INTEGRATION_SET_TOPIC ? OSERO_CONTROLLER : OSERO_RATE_LIMITS,
                    "action-event-emitter"
                );
                assertLt(actionEvents, expected.length, "unexpected-action-event");
                assertEq(topic, expected[actionEvents][0], "action-event-topic-or-order");
                assertEq(logs[i].topics[1], expected[actionEvents][1], "action-event-id-or-order");
                actionEvents++;
            } else if (topic == INTEGRATION_REMOVED_TOPIC) {
                integrationRemovals++;
            } else if (topic == ROLE_GRANTED_TOPIC || topic == ROLE_REVOKED_TOPIC) {
                roleChanges++;
            }
        }

        assertEq(actionEvents, expected.length, "action-event-count");
        assertEq(integrationRemovals, 0, "integration-removed-event-count");
        assertEq(roleChanges, 0, "role-change-event-count");
    }

    function test_ETHEREUM_directPayloadExecutionRevertsWithoutSubProxyAuthority() public {
        // The first action is updateIntegrations, whose onlyAdmin check requires SubProxy authority.
        vm.expectRevert(abi.encodeWithSignature("NotAdmin(address)", payload));
        ISpellLike(payload).execute();
    }

    function test_ETHEREUM_actorCannotChangeIntegrations() public {
        _executeSpellViaStarGuard(payload);

        bytes32[] memory ids = new bytes32[](2);
        ids[0] = TRANSFER_ASSET_FACET_INTEGRATION_ID;
        ids[1] = NFAT_PRIME_FACET_INTEGRATION_ID;
        _expectCallAsOseroActorRevert(
            abi.encodeWithSignature("NotAdmin(address)", OSERO_ADMINISTERED_AGENT),
            abi.encodeCall(IOseroPauControllerLike.removeIntegrations, (ids))
        );
        _expectCallAsOseroActorRevert(
            abi.encodeWithSignature("NotAdmin(address)", OSERO_ADMINISTERED_AGENT),
            abi.encodeCall(IOseroPauControllerLike.updateIntegrations, (ids))
        );

        assertEq(controller.integrations().length, 7, "integration-count-changed");
    }

    /// @dev Changes 3-4 are Sky Core spell actions: the Osero spell does not touch the DC-IAM or the Vat.
    function test_ETHEREUM_spellDoesNotChangeAllocatorDebtCeiling() public {
        IAutoLineLike autoLine = IAutoLineLike(MCD_IAM_AUTO_LINE);
        (uint256 lineBefore, uint256 gapBefore, uint48 ttlBefore, uint48 lastBefore, uint48 lastIncBefore) =
            autoLine.ilks(OSERO_ILK);
        (,,, uint256 vatLineBefore,) = IVatLike(MCD_VAT).ilks(OSERO_ILK);

        _executeSpellViaStarGuard(payload);

        (uint256 line, uint256 gap, uint48 ttl, uint48 last, uint48 lastInc) = autoLine.ilks(OSERO_ILK);
        (,,, uint256 vatLine,) = IVatLike(MCD_VAT).ilks(OSERO_ILK);
        assertEq(line, lineBefore, "dc-iam-line-changed");
        assertEq(gap, gapBefore, "dc-iam-gap-changed");
        assertEq(ttl, ttlBefore, "dc-iam-ttl-changed");
        assertEq(last, lastBefore, "dc-iam-last-changed");
        assertEq(lastInc, lastIncBefore, "dc-iam-last-inc-changed");
        assertEq(vatLine, vatLineBefore, "vat-line-changed");
    }

    /**********************************************************************************************/
    /*** Transfer Asset (Proposed actions #1-2)                                                 ***/
    /**********************************************************************************************/

    /// @dev Post-checks #2: an Actor sends USDS to the destination through the AdministeredAgent.
    function test_ETHEREUM_usdsTransferToDestinationThroughAdministeredAgent() public {
        _executeSpellViaStarGuard(payload);

        deal(USDS, OSERO_ALM_PROXY, usds.balanceOf(OSERO_ALM_PROXY) + ROUND_TRIP_USDS_AMOUNT);
        uint256 proxyUsdsStart = usds.balanceOf(OSERO_ALM_PROXY);
        uint256 destinationUsdsStart = usds.balanceOf(USDS_TRANSFER_DESTINATION);

        vm.expectEmit(OSERO_CONTROLLER);
        emit TransferAssetTransfer(USDS, USDS_TRANSFER_DESTINATION, ROUND_TRIP_USDS_AMOUNT);
        _callAsOseroActor(
            abi.encodeCall(
                ITransferAssetControllerLike.transferAsset_transfer,
                (USDS, USDS_TRANSFER_DESTINATION, ROUND_TRIP_USDS_AMOUNT)
            )
        );

        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart - ROUND_TRIP_USDS_AMOUNT, "proxy-usds-not-sent");
        assertEq(
            usds.balanceOf(USDS_TRANSFER_DESTINATION),
            destinationUsdsStart + ROUND_TRIP_USDS_AMOUNT,
            "destination-usds-not-received"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_TRANSFER_RATE_LIMIT_KEY),
            USDS_TRANSFER_MAX - ROUND_TRIP_USDS_AMOUNT,
            "usds-transfer-limit-not-decreased"
        );
    }

    /// @dev Post-checks #2: any other destination, or USDC, stays blocked.
    function test_ETHEREUM_usdsTransferRejectsOversizedAmountOtherDestinationAndOtherAsset() public {
        _executeSpellViaStarGuard(payload);
        deal(USDS, OSERO_ALM_PROXY, USDS_TRANSFER_MAX + 1);
        deal(USDC, OSERO_ALM_PROXY, 1_000e6);

        _expectCallAsOseroActorRevert(
            bytes("RateLimits/rate-limit-exceeded"),
            abi.encodeCall(
                ITransferAssetControllerLike.transferAsset_transfer,
                (USDS, USDS_TRANSFER_DESTINATION, USDS_TRANSFER_MAX + 1)
            )
        );
        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(ITransferAssetControllerLike.transferAsset_transfer, (USDS, OSERO_OPERATOR, 1))
        );
        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(ITransferAssetControllerLike.transferAsset_transfer, (USDS, TEST_NFAT_FACILITY, 1))
        );
        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(ITransferAssetControllerLike.transferAsset_transfer, (USDC, USDS_TRANSFER_DESTINATION, 1))
        );
    }

    function test_ETHEREUM_usdsTransferRateLimitRecoversOverTime() public {
        _executeSpellViaStarGuard(payload);
        deal(USDS, OSERO_ALM_PROXY, USDS_TRANSFER_MAX);

        _callAsOseroActor(
            abi.encodeCall(
                ITransferAssetControllerLike.transferAsset_transfer,
                (USDS, USDS_TRANSFER_DESTINATION, USDS_TRANSFER_MAX)
            )
        );
        assertEq(rateLimits.getCurrentRateLimit(USDS_TRANSFER_RATE_LIMIT_KEY), 0, "usds-transfer-limit-not-used");

        uint256 start = vm.getBlockTimestamp();
        vm.warp(start + PARTIAL_RECOVERY_TIME);
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_TRANSFER_RATE_LIMIT_KEY),
            USDS_TRANSFER_SLOPE * PARTIAL_RECOVERY_TIME,
            "usds-transfer-limit-not-recovering"
        );

        vm.warp(start + PARTIAL_RECOVERY_TIME + 1 days);
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_TRANSFER_RATE_LIMIT_KEY),
            USDS_TRANSFER_MAX,
            "usds-transfer-limit-not-capped"
        );
    }

    /// @dev Technical risk #6: both Actors can use the new integrations.
    function test_ETHEREUM_coreOperatorRelayerOperatesThroughAdministeredAgent() public {
        _executeSpellViaStarGuard(payload);
        deal(USDS, OSERO_ALM_PROXY, usds.balanceOf(OSERO_ALM_PROXY) + 2 * ROUND_TRIP_USDS_AMOUNT);

        IAdministeredAgentLike agent = IAdministeredAgentLike(OSERO_ADMINISTERED_AGENT);
        assertTrue(agent.getIsActor(SOTER_OPERATOR), "core-operator-relayer-not-actor");

        vm.startPrank(SOTER_OPERATOR);
        // forge-lint: disable-next-item(unchecked-call)
        agent.call(
            OSERO_CONTROLLER,
            abi.encodeCall(
                ITransferAssetControllerLike.transferAsset_transfer,
                (USDS, USDS_TRANSFER_DESTINATION, ROUND_TRIP_USDS_AMOUNT)
            )
        );
        // forge-lint: disable-next-item(unchecked-call)
        agent.call(
            OSERO_CONTROLLER,
            abi.encodeCall(
                INFATPrimeControllerLike.nfatPrime_subscribe, (TEST_NFAT_FACILITY, ROUND_TRIP_USDS_AMOUNT, "")
            )
        );
        vm.stopPrank();

        assertEq(facility.deposits(OSERO_ALM_PROXY), ROUND_TRIP_USDS_AMOUNT, "core-operator-subscription-missing");
        assertEq(
            rateLimits.getCurrentRateLimit(USDS_TRANSFER_RATE_LIMIT_KEY),
            USDS_TRANSFER_MAX - ROUND_TRIP_USDS_AMOUNT,
            "core-operator-transfer-not-limited"
        );
    }

    /**********************************************************************************************/
    /*** NFAT Prime and the Test NFAT Facility (Proposed actions #3-6)                          ***/
    /**********************************************************************************************/

    /// @dev Post-checks #5: a small subscribe and withdraw round trip, funded by a USDS mint and burnt afterwards.
    function test_ETHEREUM_nfatSubscribeAndWithdrawRoundTripThroughAdministeredAgent() public {
        _executeSpellViaStarGuard(payload);

        uint256 proxyUsdsStart = usds.balanceOf(OSERO_ALM_PROXY);
        uint256 debtStart = _allocatorDebt();
        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_mint, (ROUND_TRIP_USDS_AMOUNT)));
        uint256 proxyUsdsBeforeSubscribe = usds.balanceOf(OSERO_ALM_PROXY);

        vm.expectEmit(TEST_NFAT_FACILITY);
        emit Subscribe(OSERO_ALM_PROXY, ROUND_TRIP_USDS_AMOUNT, "");
        vm.expectEmit(OSERO_CONTROLLER);
        emit NFATPrimeSubscribe(TEST_NFAT_FACILITY, ROUND_TRIP_USDS_AMOUNT, "");
        _callAsOseroActor(
            abi.encodeCall(
                INFATPrimeControllerLike.nfatPrime_subscribe, (TEST_NFAT_FACILITY, ROUND_TRIP_USDS_AMOUNT, "")
            )
        );
        assertEq(facility.deposits(OSERO_ALM_PROXY), ROUND_TRIP_USDS_AMOUNT, "facility-deposit-not-recorded");
        assertEq(usds.allowance(OSERO_ALM_PROXY, TEST_NFAT_FACILITY), 0, "facility-usds-approval-not-cleared");
        assertEq(
            rateLimits.getCurrentRateLimit(NFAT_SUBSCRIBE_RATE_LIMIT_KEY),
            NFAT_SUBSCRIBE_MAX - ROUND_TRIP_USDS_AMOUNT,
            "nfat-subscribe-limit-not-decreased"
        );

        vm.expectEmit(TEST_NFAT_FACILITY);
        emit Withdraw(OSERO_ALM_PROXY, ROUND_TRIP_USDS_AMOUNT);
        vm.expectEmit(OSERO_CONTROLLER);
        emit NFATPrimeWithdraw(TEST_NFAT_FACILITY, ROUND_TRIP_USDS_AMOUNT);
        _callAsOseroActor(
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_withdraw, (TEST_NFAT_FACILITY, ROUND_TRIP_USDS_AMOUNT))
        );
        assertEq(facility.deposits(OSERO_ALM_PROXY), 0, "facility-deposit-not-withdrawn");
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsBeforeSubscribe, "proxy-usds-not-returned");
        assertEq(
            rateLimits.getCurrentRateLimit(NFAT_WITHDRAW_RATE_LIMIT_KEY),
            NFAT_WITHDRAW_MAX - ROUND_TRIP_USDS_AMOUNT,
            "nfat-withdraw-limit-not-decreased"
        );
        // Withdrawals do not restore subscribe capacity (Cantina 3.2.3 item 6).
        assertEq(
            rateLimits.getCurrentRateLimit(NFAT_SUBSCRIBE_RATE_LIMIT_KEY),
            NFAT_SUBSCRIBE_MAX - ROUND_TRIP_USDS_AMOUNT,
            "nfat-subscribe-limit-restored-by-withdraw"
        );

        _callAsOseroActor(abi.encodeCall(IOseroPauControllerLike.usds_burn, (ROUND_TRIP_USDS_AMOUNT)));
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart, "proxy-usds-not-burned");
        assertEq(_allocatorDebt(), debtStart, "allocator-debt-not-reconciled");
    }

    /// @dev The operator issues an NFAT to the Osero ALM Proxy, the borrower repays, and an Actor collects.
    function test_ETHEREUM_nfatIssueRepayAndCollectThroughAdministeredAgent() public {
        _executeSpellViaStarGuard(payload);
        _subscribeAsOseroActor(ROUND_TRIP_USDS_AMOUNT);
        uint256 recipientUsdsStart = usds.balanceOf(TEST_HALO_ALM_PROXY);

        vm.prank(TEST_HALO_ALM_PROXY);
        facility.issue(OSERO_ALM_PROXY, NFAT_TOKEN_ID, ROUND_TRIP_USDS_AMOUNT);
        assertEq(facility.ownerOf(NFAT_TOKEN_ID), OSERO_ALM_PROXY, "nfat-not-issued-to-osero-almproxy");
        assertEq(facility.deposits(OSERO_ALM_PROXY), 0, "deposit-not-drawn");
        assertEq(
            usds.balanceOf(TEST_HALO_ALM_PROXY),
            recipientUsdsStart + ROUND_TRIP_USDS_AMOUNT,
            "principal-not-sent-to-recipient"
        );

        _repayAsBorrower(NFAT_TOKEN_ID, REPAID_USDS_AMOUNT);
        assertEq(facility.collectable(NFAT_TOKEN_ID), REPAID_USDS_AMOUNT, "repayment-not-collectable");

        uint256 proxyUsdsStart = usds.balanceOf(OSERO_ALM_PROXY);
        vm.expectEmit(TEST_NFAT_FACILITY);
        emit Collect(NFAT_TOKEN_ID, REPAID_USDS_AMOUNT);
        vm.expectEmit(OSERO_CONTROLLER);
        emit NFATPrimeCollect(TEST_NFAT_FACILITY, NFAT_TOKEN_ID, REPAID_USDS_AMOUNT);
        _callAsOseroActor(
            abi.encodeCall(
                INFATPrimeControllerLike.nfatPrime_collect, (TEST_NFAT_FACILITY, NFAT_TOKEN_ID, REPAID_USDS_AMOUNT)
            )
        );

        assertEq(facility.collectable(NFAT_TOKEN_ID), 0, "repayment-not-collected");
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart + REPAID_USDS_AMOUNT, "proxy-usds-not-collected");
        assertEq(
            rateLimits.getCurrentRateLimit(NFAT_COLLECT_RATE_LIMIT_KEY),
            NFAT_COLLECT_MAX - REPAID_USDS_AMOUNT,
            "nfat-collect-limit-not-decreased"
        );
    }

    function test_ETHEREUM_nfatSubscribeRateLimitRejectsOversizedSubscriptionAndRecoversOverTime() public {
        _executeSpellViaStarGuard(payload);
        deal(USDS, OSERO_ALM_PROXY, NFAT_SUBSCRIBE_MAX + 1);

        _expectCallAsOseroActorRevert(
            bytes("RateLimits/rate-limit-exceeded"),
            abi.encodeCall(
                INFATPrimeControllerLike.nfatPrime_subscribe, (TEST_NFAT_FACILITY, NFAT_SUBSCRIBE_MAX + 1, "")
            )
        );

        _subscribeAsOseroActor(NFAT_SUBSCRIBE_MAX);
        assertEq(rateLimits.getCurrentRateLimit(NFAT_SUBSCRIBE_RATE_LIMIT_KEY), 0, "nfat-subscribe-limit-not-used");

        uint256 start = vm.getBlockTimestamp();
        vm.warp(start + PARTIAL_RECOVERY_TIME);
        assertEq(
            rateLimits.getCurrentRateLimit(NFAT_SUBSCRIBE_RATE_LIMIT_KEY),
            NFAT_SUBSCRIBE_SLOPE * PARTIAL_RECOVERY_TIME,
            "nfat-subscribe-limit-not-recovering"
        );

        vm.warp(start + PARTIAL_RECOVERY_TIME + 2 days);
        assertEq(
            rateLimits.getCurrentRateLimit(NFAT_SUBSCRIBE_RATE_LIMIT_KEY),
            NFAT_SUBSCRIBE_MAX,
            "nfat-subscribe-limit-not-capped"
        );
    }

    /// @dev ChainSecurity SC1 (Technical risk #3): while the subscribe key is set, a data-only subscription consumes
    ///      no rate limit.
    function test_ETHEREUM_nfatDataOnlySubscriptionConsumesNoRateLimit() public {
        _executeSpellViaStarGuard(payload);

        vm.expectEmit(TEST_NFAT_FACILITY);
        emit Subscribe(OSERO_ALM_PROXY, 0, SUBSCRIPTION_DATA);
        vm.expectEmit(OSERO_CONTROLLER);
        emit NFATPrimeSubscribe(TEST_NFAT_FACILITY, 0, SUBSCRIPTION_DATA);
        _callAsOseroActor(
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_subscribe, (TEST_NFAT_FACILITY, 0, SUBSCRIPTION_DATA))
        );

        assertEq(facility.deposits(OSERO_ALM_PROXY), 0, "data-only-subscription-deposited");
        assertEq(
            rateLimits.getCurrentRateLimit(NFAT_SUBSCRIBE_RATE_LIMIT_KEY),
            NFAT_SUBSCRIBE_MAX,
            "data-only-subscription-consumed-rate-limit"
        );
    }

    /// @dev Proposed actions #5: a withdrawal above the limit reverts and leaves the deposit in place, and the key
    ///      refills at its slope. The deposit is built in two subscriptions, since each is capped by the subscribe key.
    function test_ETHEREUM_nfatWithdrawRateLimitRejectsOversizedWithdrawalAndRecoversOverTime() public {
        _executeSpellViaStarGuard(payload);
        _subscribeAsOseroActor(NFAT_SUBSCRIBE_MAX);
        // Three days, not two: the slope is rounded down, so two days refill slightly less than NFAT_SUBSCRIBE_MAX.
        vm.warp(vm.getBlockTimestamp() + 3 days);
        _subscribeAsOseroActor(NFAT_SUBSCRIBE_MAX);
        uint256 deposit = facility.deposits(OSERO_ALM_PROXY);
        assertGt(deposit, NFAT_WITHDRAW_MAX, "deposit-not-above-withdraw-max");
        uint256 proxyUsdsStart = usds.balanceOf(OSERO_ALM_PROXY);

        _expectCallAsOseroActorRevert(
            bytes("RateLimits/rate-limit-exceeded"),
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_withdraw, (TEST_NFAT_FACILITY, NFAT_WITHDRAW_MAX + 1))
        );
        assertEq(facility.deposits(OSERO_ALM_PROXY), deposit, "oversized-withdrawal-moved-deposit");
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart, "oversized-withdrawal-moved-usds");

        _callAsOseroActor(
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_withdraw, (TEST_NFAT_FACILITY, NFAT_WITHDRAW_MAX))
        );
        assertEq(rateLimits.getCurrentRateLimit(NFAT_WITHDRAW_RATE_LIMIT_KEY), 0, "nfat-withdraw-limit-not-used");

        uint256 start = vm.getBlockTimestamp();
        vm.warp(start + PARTIAL_RECOVERY_TIME);
        assertEq(
            rateLimits.getCurrentRateLimit(NFAT_WITHDRAW_RATE_LIMIT_KEY),
            NFAT_WITHDRAW_SLOPE * PARTIAL_RECOVERY_TIME,
            "nfat-withdraw-limit-not-recovering"
        );

        vm.warp(start + PARTIAL_RECOVERY_TIME + 2 days);
        assertEq(
            rateLimits.getCurrentRateLimit(NFAT_WITHDRAW_RATE_LIMIT_KEY),
            NFAT_WITHDRAW_MAX,
            "nfat-withdraw-limit-not-capped"
        );
    }

    /// @dev Proposed actions #6: a collection above the limit reverts and leaves the repayment in place, and the key
    ///      refills at its slope.
    function test_ETHEREUM_nfatCollectRateLimitRejectsOversizedCollectionAndRecoversOverTime() public {
        _executeSpellViaStarGuard(payload);
        _subscribeAsOseroActor(ROUND_TRIP_USDS_AMOUNT);
        vm.prank(TEST_HALO_ALM_PROXY);
        facility.issue(OSERO_ALM_PROXY, NFAT_TOKEN_ID, ROUND_TRIP_USDS_AMOUNT);
        _repayAsBorrower(NFAT_TOKEN_ID, NFAT_COLLECT_MAX + 1);
        uint256 proxyUsdsStart = usds.balanceOf(OSERO_ALM_PROXY);

        _expectCallAsOseroActorRevert(
            bytes("RateLimits/rate-limit-exceeded"),
            abi.encodeCall(
                INFATPrimeControllerLike.nfatPrime_collect, (TEST_NFAT_FACILITY, NFAT_TOKEN_ID, NFAT_COLLECT_MAX + 1)
            )
        );
        assertEq(facility.collectable(NFAT_TOKEN_ID), NFAT_COLLECT_MAX + 1, "oversized-collection-moved-repayment");
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart, "oversized-collection-moved-usds");

        _callAsOseroActor(
            abi.encodeCall(
                INFATPrimeControllerLike.nfatPrime_collect, (TEST_NFAT_FACILITY, NFAT_TOKEN_ID, NFAT_COLLECT_MAX)
            )
        );
        assertEq(rateLimits.getCurrentRateLimit(NFAT_COLLECT_RATE_LIMIT_KEY), 0, "nfat-collect-limit-not-used");

        uint256 start = vm.getBlockTimestamp();
        vm.warp(start + PARTIAL_RECOVERY_TIME);
        assertEq(
            rateLimits.getCurrentRateLimit(NFAT_COLLECT_RATE_LIMIT_KEY),
            NFAT_COLLECT_SLOPE * PARTIAL_RECOVERY_TIME,
            "nfat-collect-limit-not-recovering"
        );
        _callAsOseroActor(
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_collect, (TEST_NFAT_FACILITY, NFAT_TOKEN_ID, 1))
        );
        assertEq(facility.collectable(NFAT_TOKEN_ID), 0, "repayment-not-collected");

        vm.warp(start + PARTIAL_RECOVERY_TIME + 2 days);
        assertEq(
            rateLimits.getCurrentRateLimit(NFAT_COLLECT_RATE_LIMIT_KEY),
            NFAT_COLLECT_MAX,
            "nfat-collect-limit-not-capped"
        );
    }

    /// @dev Every other NFAT Facility stays blocked, including for data-only subscriptions.
    function test_ETHEREUM_nfatRejectsUnconfiguredFacility() public {
        _executeSpellViaStarGuard(payload);
        deal(USDS, OSERO_ALM_PROXY, usds.balanceOf(OSERO_ALM_PROXY) + ROUND_TRIP_USDS_AMOUNT);
        address otherFacility = address(new NFATFacility(USDS, "Other NFAT Facility", "ONFAT"));

        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_subscribe, (otherFacility, ROUND_TRIP_USDS_AMOUNT, ""))
        );
        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_subscribe, (otherFacility, 0, SUBSCRIPTION_DATA))
        );
    }

    /// @dev Cantina 3.2.3 item 3 (Technical risk #3): with an `identityNetwork` set, the Osero ALM Proxy must be a
    ///      member to receive an NFAT and to collect.
    function test_ETHEREUM_nfatIdentityNetworkGatesIssuanceAndCollection() public {
        _executeSpellViaStarGuard(payload);
        _subscribeAsOseroActor(ROUND_TRIP_USDS_AMOUNT);

        IdentityNetworkMock identityNetwork = new IdentityNetworkMock();
        vm.prank(TEST_NFAT_FACILITY_OWNER);
        facility.file("identityNetwork", address(identityNetwork));

        vm.prank(TEST_HALO_ALM_PROXY);
        vm.expectRevert(bytes("NFATFacility/not-member"));
        facility.issue(OSERO_ALM_PROXY, NFAT_TOKEN_ID, ROUND_TRIP_USDS_AMOUNT);

        identityNetwork.setMember(OSERO_ALM_PROXY, true);
        vm.prank(TEST_HALO_ALM_PROXY);
        facility.issue(OSERO_ALM_PROXY, NFAT_TOKEN_ID, ROUND_TRIP_USDS_AMOUNT);

        _repayAsBorrower(NFAT_TOKEN_ID, REPAID_USDS_AMOUNT);

        identityNetwork.setMember(OSERO_ALM_PROXY, false);
        _expectCallAsOseroActorRevert(
            bytes("NFATFacility/not-member"),
            abi.encodeCall(
                INFATPrimeControllerLike.nfatPrime_collect, (TEST_NFAT_FACILITY, NFAT_TOKEN_ID, REPAID_USDS_AMOUNT)
            )
        );
    }

    /**********************************************************************************************/
    /*** Emergency actions                                                                      ***/
    /**********************************************************************************************/

    /// @dev Emergency actions #1-2: the Osero Operator Multisig zeroes the transfer and subscribe keys through the
    ///      Configurator. Data-only subscriptions revert too, withdrawals and collections keep working, and the
    ///      Configurator cannot raise a key again from `0`.
    function test_ETHEREUM_operatorMultisigCanStopTransfersAndSubscriptionsThroughConfigurator() public {
        _executeSpellViaStarGuard(payload);
        _subscribeAsOseroActor(2 * ROUND_TRIP_USDS_AMOUNT);
        vm.prank(TEST_HALO_ALM_PROXY);
        facility.issue(OSERO_ALM_PROXY, NFAT_TOKEN_ID, ROUND_TRIP_USDS_AMOUNT);
        _repayAsBorrower(NFAT_TOKEN_ID, REPAID_USDS_AMOUNT);
        deal(USDS, OSERO_ALM_PROXY, usds.balanceOf(OSERO_ALM_PROXY) + ROUND_TRIP_USDS_AMOUNT);

        IPASBeamStateLike beamState = IPASBeamStateLike(PAS_BEAM_STATE);
        assertFalse(beamState.stopped(), "beamstate-stopped");
        assertEq(beamState.rateLimitsCBeams(OSERO_RATE_LIMITS, OSERO_CBEAM), 1, "osero-cbeam-not-paired");

        IPASConfiguratorLike configurator = IPASConfiguratorLike(PAS_CONFIGURATOR);
        vm.startPrank(OSERO_CBEAM);
        vm.expectEmit(PAS_CONFIGURATOR);
        emit SetRateLimit(OSERO_RATE_LIMITS, USDS_TRANSFER_RATE_LIMIT_KEY, 0, 0);
        configurator.setRateLimit(OSERO_RATE_LIMITS, USDS_TRANSFER_RATE_LIMIT_KEY, 0, 0);
        vm.expectEmit(PAS_CONFIGURATOR);
        emit SetRateLimit(OSERO_RATE_LIMITS, NFAT_SUBSCRIBE_RATE_LIMIT_KEY, 0, 0);
        configurator.setRateLimit(OSERO_RATE_LIMITS, NFAT_SUBSCRIBE_RATE_LIMIT_KEY, 0, 0);
        vm.stopPrank();

        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(ITransferAssetControllerLike.transferAsset_transfer, (USDS, USDS_TRANSFER_DESTINATION, 1))
        );
        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(
                INFATPrimeControllerLike.nfatPrime_subscribe, (TEST_NFAT_FACILITY, ROUND_TRIP_USDS_AMOUNT, "")
            )
        );
        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_subscribe, (TEST_NFAT_FACILITY, 0, SUBSCRIPTION_DATA))
        );

        _callAsOseroActor(
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_withdraw, (TEST_NFAT_FACILITY, ROUND_TRIP_USDS_AMOUNT))
        );
        assertEq(facility.deposits(OSERO_ALM_PROXY), 0, "withdraw-blocked-after-subscribe-stop");
        _callAsOseroActor(
            abi.encodeCall(
                INFATPrimeControllerLike.nfatPrime_collect, (TEST_NFAT_FACILITY, NFAT_TOKEN_ID, REPAID_USDS_AMOUNT)
            )
        );
        assertEq(facility.collectable(NFAT_TOKEN_ID), 0, "collect-blocked-after-subscribe-stop");

        vm.prank(OSERO_CBEAM);
        vm.expectRevert(bytes("Configurator/exceeds-max-amount"));
        configurator.setRateLimit(OSERO_RATE_LIMITS, USDS_TRANSFER_RATE_LIMIT_KEY, 1, 0);
    }

    /// @dev Technical risk #5: BeamState has no default for the new keys, so the Osero Operator Multisig can raise each
    ///      by at most `maxChange` (20%) per `hop` (16 hours). The first raise needs no wait, because the Configurator
    ///      has recorded no earlier raise for a new key. A raise does not add capacity.
    function test_ETHEREUM_operatorMultisigRaisesNewKeysWithinMaxChangeAndHop() public {
        _executeSpellViaStarGuard(payload);

        IPASBeamStateLike beamState = IPASBeamStateLike(PAS_BEAM_STATE);
        assertEq(beamState.getMaxChange(OSERO_RATE_LIMITS), 1.2e18, "beamstate-max-change");
        assertEq(beamState.getHop(OSERO_RATE_LIMITS), 57_600, "beamstate-hop");
        bytes32[4] memory keys = [
            USDS_TRANSFER_RATE_LIMIT_KEY,
            NFAT_SUBSCRIBE_RATE_LIMIT_KEY,
            NFAT_WITHDRAW_RATE_LIMIT_KEY,
            NFAT_COLLECT_RATE_LIMIT_KEY
        ];
        for (uint256 i = 0; i < keys.length; ++i) {
            (uint256 defaultMax, uint256 defaultSlope) = beamState.getInitRateLimits(keys[i], OSERO_RATE_LIMITS);
            assertEq(defaultMax, 0, string.concat("beamstate-default-max-", vm.toString(i)));
            assertEq(defaultSlope, 0, string.concat("beamstate-default-slope-", vm.toString(i)));
        }

        IPASConfiguratorLike configurator = IPASConfiguratorLike(PAS_CONFIGURATOR);
        uint256 raisedMax = USDS_TRANSFER_MAX * 12 / 10;
        uint256 raisedSlope = USDS_TRANSFER_SLOPE * 12 / 10;
        vm.startPrank(OSERO_CBEAM);
        vm.expectRevert(bytes("Configurator/exceeds-max-amount"));
        configurator.setRateLimit(OSERO_RATE_LIMITS, USDS_TRANSFER_RATE_LIMIT_KEY, raisedMax + 1, USDS_TRANSFER_SLOPE);
        vm.expectRevert(bytes("Configurator/exceeds-max-slope"));
        configurator.setRateLimit(OSERO_RATE_LIMITS, USDS_TRANSFER_RATE_LIMIT_KEY, raisedMax, raisedSlope + 1);
        configurator.setRateLimit(OSERO_RATE_LIMITS, USDS_TRANSFER_RATE_LIMIT_KEY, raisedMax, raisedSlope);
        vm.expectRevert(bytes("Configurator/increment-too-soon"));
        configurator.setRateLimit(OSERO_RATE_LIMITS, USDS_TRANSFER_RATE_LIMIT_KEY, raisedMax + 1, raisedSlope);
        vm.stopPrank();

        IRateLimitsLike.RateLimitData memory data = rateLimits.getRateLimitData(USDS_TRANSFER_RATE_LIMIT_KEY);
        assertEq(data.maxAmount, raisedMax, "usds-transfer-max-not-raised");
        assertEq(data.slope, raisedSlope, "usds-transfer-slope-not-raised");
        assertEq(data.lastAmount, USDS_TRANSFER_MAX, "usds-transfer-capacity-changed-by-raise");
    }

    /// @dev Emergency actions #4: the Osero Operator Multisig stops new USDS minting through the Configurator.
    function test_ETHEREUM_operatorMultisigCanStopUsdsMintingThroughConfigurator() public {
        _executeSpellViaStarGuard(payload);

        vm.prank(OSERO_CBEAM);
        IPASConfiguratorLike(PAS_CONFIGURATOR).setRateLimit(OSERO_RATE_LIMITS, USDS_MINT_RATE_LIMIT_KEY, 0, 0);

        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(IOseroPauControllerLike.usds_mint, (ROUND_TRIP_USDS_AMOUNT))
        );
    }

    /// @dev Emergency actions #1-2 (spell path): an Osero spell zeroes the transfer and subscribe keys.
    function test_ETHEREUM_subProxyCanZeroTransferAndSubscribeKeysAsEmergencyAction() public {
        _executeSpellViaStarGuard(payload);
        deal(USDS, OSERO_ALM_PROXY, usds.balanceOf(OSERO_ALM_PROXY) + ROUND_TRIP_USDS_AMOUNT);

        vm.startPrank(OSERO_PROXY);
        IRateLimitsAdminLike(OSERO_RATE_LIMITS).setRateLimitData(USDS_TRANSFER_RATE_LIMIT_KEY, 0, 0);
        IRateLimitsAdminLike(OSERO_RATE_LIMITS).setRateLimitData(NFAT_SUBSCRIBE_RATE_LIMIT_KEY, 0, 0);
        vm.stopPrank();

        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(ITransferAssetControllerLike.transferAsset_transfer, (USDS, USDS_TRANSFER_DESTINATION, 1))
        );
        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(
                INFATPrimeControllerLike.nfatPrime_subscribe, (TEST_NFAT_FACILITY, ROUND_TRIP_USDS_AMOUNT, "")
            )
        );
    }

    /// @dev Emergency actions #3: unissued USDS can be withdrawn while the facility is stopped, with
    ///      `amount = min(deposits, current withdraw limit)`; a deposit above the limit is recovered in parts as the key
    ///      refills. Subscriptions and collections revert while the facility is stopped.
    function test_ETHEREUM_withdrawRecoversUnissuedUsdsInPartsWhileFacilityStopped() public {
        _executeSpellViaStarGuard(payload);
        _subscribeAsOseroActor(NFAT_SUBSCRIBE_MAX);
        // Three days, not two: the slope is rounded down, so two days refill slightly less than NFAT_SUBSCRIBE_MAX.
        vm.warp(vm.getBlockTimestamp() + 3 days);
        _subscribeAsOseroActor(NFAT_SUBSCRIBE_MAX);
        uint256 deposit = facility.deposits(OSERO_ALM_PROXY);
        assertGt(deposit, NFAT_WITHDRAW_MAX, "deposit-not-above-withdraw-max");
        deal(USDS, OSERO_ALM_PROXY, usds.balanceOf(OSERO_ALM_PROXY) + ROUND_TRIP_USDS_AMOUNT);

        vm.prank(TEST_NFAT_FACILITY_FREEZER);
        facility.stop();
        assertTrue(facility.stopped(), "facility-not-stopped");

        _expectCallAsOseroActorRevert(
            bytes("NFATFacility/stopped"),
            abi.encodeCall(
                INFATPrimeControllerLike.nfatPrime_subscribe, (TEST_NFAT_FACILITY, ROUND_TRIP_USDS_AMOUNT, "")
            )
        );
        _expectCallAsOseroActorRevert(
            bytes("NFATFacility/stopped"),
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_collect, (TEST_NFAT_FACILITY, NFAT_TOKEN_ID, 1))
        );

        uint256 proxyUsdsStart = usds.balanceOf(OSERO_ALM_PROXY);
        _withdrawRecoverableAsOseroActor();
        assertEq(facility.deposits(OSERO_ALM_PROXY), deposit - NFAT_WITHDRAW_MAX, "first-part-not-recovered");
        _expectCallAsOseroActorRevert(
            bytes("RateLimits/rate-limit-exceeded"),
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_withdraw, (TEST_NFAT_FACILITY, 1))
        );

        vm.warp(vm.getBlockTimestamp() + 1 days);
        _withdrawRecoverableAsOseroActor();
        assertEq(facility.deposits(OSERO_ALM_PROXY), 0, "deposit-not-recovered");
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart + deposit, "proxy-usds-not-recovered");
    }

    /// @dev Emergency actions #5: the Freezer Multisig removes a compromised Actor.
    function test_ETHEREUM_freezerCanRemoveActor() public {
        _executeSpellViaStarGuard(payload);

        IAdministeredAgentLike agent = IAdministeredAgentLike(OSERO_ADMINISTERED_AGENT);
        vm.prank(SOTER_FREEZER);
        agent.removeActor(OSERO_OPERATOR);

        assertFalse(agent.getIsActor(OSERO_OPERATOR), "actor-not-removed");
        vm.prank(OSERO_OPERATOR);
        vm.expectRevert(abi.encodeWithSignature("NotActor()"));
        // forge-lint: disable-next-item(unchecked-call)
        agent.call(
            OSERO_CONTROLLER,
            abi.encodeCall(ITransferAssetControllerLike.transferAsset_transfer, (USDS, USDS_TRANSFER_DESTINATION, 1))
        );
    }

    /// @dev Emergency actions #8: an Osero spell removes the new integrations.
    function test_ETHEREUM_subProxyCanRemoveNewIntegrationsAsEmergencyAction() public {
        _executeSpellViaStarGuard(payload);

        bytes32[] memory ids = new bytes32[](2);
        ids[0] = TRANSFER_ASSET_FACET_INTEGRATION_ID;
        ids[1] = NFAT_PRIME_FACET_INTEGRATION_ID;
        vm.prank(OSERO_PROXY);
        controller.removeIntegrations(ids);

        _assertWiresNotDispatched(_expectedTransferAssetWires(), "transfer-asset-after-removal");
        _assertWiresNotDispatched(_expectedNfatPrimeWires(), "nfat-prime-after-removal");
        assertEq(controller.integrations().length, 5, "integration-count-after-removal");

        _expectCallAsOseroActorRevert(
            abi.encodeWithSignature(
                "CallSelectorNotWired(bytes4)", ITransferAssetControllerLike.transferAsset_transfer.selector
            ),
            abi.encodeCall(ITransferAssetControllerLike.transferAsset_transfer, (USDS, USDS_TRANSFER_DESTINATION, 1))
        );
        _expectCallAsOseroActorRevert(
            abi.encodeWithSignature(
                "CallSelectorNotWired(bytes4)", INFATPrimeControllerLike.nfatPrime_withdraw.selector
            ),
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_withdraw, (TEST_NFAT_FACILITY, 1))
        );
    }

    /**********************************************************************************************/
    /*** Sky Core DC-IAM change (Pre-requirements #2, NOT part of this spell)                    ***/
    /**********************************************************************************************/

    /// @dev Models change 4 in the December 3, 2026 Sky Core spell and checks Post-checks #4: the new `line` and
    ///      `gap` apply at once, and the Vat `Line` moves by the same amount as the ilk `line`.
    function test_ETHEREUM_skyCoreDcIamChangeRaisesAllocatorDebtCeiling() public {
        IAutoLineLike autoLine = IAutoLineLike(MCD_IAM_AUTO_LINE);
        (uint256 lineBefore, uint256 gapBefore, uint48 ttlBefore,,) = autoLine.ilks(OSERO_ILK);
        // Once MAINNET_FORK_BLOCK is past the December 3, 2026 Sky Core spell, there is nothing left to model.
        vm.skip(lineBefore == DC_IAM_LINE_AFTER && gapBefore == DC_IAM_GAP_AFTER);

        _executeSpellViaStarGuard(payload);
        assertEq(lineBefore, DC_IAM_LINE_BEFORE, "dc-iam-line-before");
        assertEq(gapBefore, DC_IAM_GAP_BEFORE, "dc-iam-gap-before");
        assertEq(ttlBefore, DC_IAM_TTL, "dc-iam-ttl-before");
        (,,, uint256 vatLineBefore,) = IVatLike(MCD_VAT).ilks(OSERO_ILK);
        uint256 globalLineBefore = IVatLineLike(MCD_VAT).Line();

        vm.prank(MCD_PAUSE_PROXY);
        autoLine.setIlk(OSERO_ILK, DC_IAM_LINE_AFTER, DC_IAM_GAP_AFTER, DC_IAM_TTL);
        autoLine.exec(OSERO_ILK);

        (uint256 line, uint256 gap, uint48 ttl, uint48 last,) = autoLine.ilks(OSERO_ILK);
        assertEq(line, DC_IAM_LINE_AFTER, "dc-iam-line-after");
        assertEq(gap, DC_IAM_GAP_AFTER, "dc-iam-gap-after");
        assertEq(ttl, DC_IAM_TTL, "dc-iam-ttl-after");
        assertEq(last, block.number, "dc-iam-last-after");

        (uint256 art, uint256 rate,, uint256 vatLine,) = IVatLike(MCD_VAT).ilks(OSERO_ILK);
        assertEq(vatLine, _min(art * rate + DC_IAM_GAP_AFTER, DC_IAM_LINE_AFTER), "vat-line-after");
        assertGt(vatLine, vatLineBefore, "vat-line-not-raised");
        assertEq(
            IVatLineLike(MCD_VAT).Line() - globalLineBefore, vatLine - vatLineBefore, "vat-global-line-not-matching"
        );
    }

    /**********************************************************************************************/
    /*** Helpers                                                                                ***/
    /**********************************************************************************************/

    /// @dev The November 19, 2026 Osero spell executes before this one. Until MAINNET_FORK_BLOCK is past its execution,
    ///      it is executed here through the StarGuard, so this spell is tested against the Osero `Controller` with
    ///      `CCTP_FACET` wired. A no-op once the fork block is past that execution.
    function _executeNovember19SpellIfPending() internal {
        if (controller.getConfig(CCTP_FACET_INTEGRATION_ID).facet != address(0)) return;

        _executeSpellViaStarGuard(NOVEMBER_19_PAYLOAD);
        november19SpellExecutedByFixture = true;
    }

    /// @dev Sky PAU Beacon fixture, NOT part of this spell. Models the December 3, 2026 Sky Core spell (Pre-requirements
    ///      #1): the Sky Pause Proxy registers `NFAT_PRIME_FACET` with `BeaconConfig.setNFATPrimeIntegration`. Until the
    ///      NFAT Prime Facet is deployed (Pre-deployed contracts #1), a facet built from diamond-pau (the facet files
    ///      are unchanged from the audited `v1.14.0` to the pinned `v1.15.0`) is placed at NFAT_PRIME_FACET. The wires
    ///      come from diamond-pau, not `_expectedNfatPrimeWires`, so the tests still check them independently. A no-op
    ///      once the fork block is past the real registration.
    function _registerNfatPrimeFacetAsSkyCore() internal {
        if (IBeaconLike(SKY_PAU_BEACON).getConfig(NFAT_PRIME_FACET_INTEGRATION_ID).facet != address(0)) return;

        if (NFAT_PRIME_FACET.code.length == 0) {
            // The facet has no constructor and no immutables, so its runtime code can be placed as is.
            vm.etch(NFAT_PRIME_FACET, address(new NFATPrimeFacet()).code);
            nfatPrimeFacetDeployedByFixture = true;
        }

        vm.startPrank(MCD_PAUSE_PROXY);
        BeaconConfig.setNFATPrimeIntegration(SKY_PAU_BEACON, NFAT_PRIME_FACET);
        vm.stopPrank();
    }

    /// @dev Test NFAT Facility fixture, NOT part of this spell. Models Pre-requirements #3 until the facility is
    ///      deployed, following `NFATDeploy.deploy` (with `gemKey` `"USDS"`) and `NFATInit.init` at the audited
    ///      `fa089fe0`: the deployer creates the facility and hands the ward to the owner (`switchOwner`), then the owner
    ///      sets the Halo-side ALM Proxy as `recipient` and only operator, and adds a freezer. The scripts are not called:
    ///      at diamond-pau's pinned `nfat` (`530a5e32`) they hard-code sUSDS as `gem`. Only `NFATFacility` is built from
    ///      that pin, where `src/NFATFacility.sol` and its OpenZeppelin pin are identical to `fa089fe0`. The role events
    ///      are recorded for `_facilityRoleEvents`. A no-op once the fork block is past the deployment.
    function _deployTestNfatFacilityAsFacilityOwner() internal {
        if (TEST_NFAT_FACILITY.code.length != 0) return;

        vm.recordLogs();

        vm.startPrank(TEST_NFAT_FACILITY_DEPLOYER);
        deployCodeTo(
            "NFATFacility.sol:NFATFacility",
            abi.encode(USDS, TEST_NFAT_FACILITY_NAME, TEST_NFAT_FACILITY_SYMBOL),
            TEST_NFAT_FACILITY
        );
        facility.rely(TEST_NFAT_FACILITY_OWNER);
        facility.deny(TEST_NFAT_FACILITY_DEPLOYER);
        vm.stopPrank();

        vm.startPrank(TEST_NFAT_FACILITY_OWNER);
        facility.file("recipient", TEST_HALO_ALM_PROXY);
        facility.kiss(TEST_HALO_ALM_PROXY);
        facility.addFreezer(TEST_NFAT_FACILITY_FREEZER);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != TEST_NFAT_FACILITY || !_isFacilityRoleTopic(logs[i].topics[0])) continue;
            fixtureFacilityRoleEvents.push(
                FacilityRoleEvent(logs[i].topics[0], address(uint160(uint256(logs[i].topics[1]))))
            );
        }

        testNfatFacilityDeployedByFixture = true;
    }

    /// @dev Pre-requirements #1: the Sky PAU Beacon registers the NFAT Prime Facet with exactly the seven wires, and
    ///      the Sky Pause Proxy is the Beacon admin.
    function _assertSkyCoreRegisteredNfatPrimeFacet() internal view {
        _assertContract(NFAT_PRIME_FACET, "nfat-prime-facet");
        assertTrue(
            IBeaconAdminLike(SKY_PAU_BEACON).hasRole(DEFAULT_ADMIN_ROLE, MCD_PAUSE_PROXY),
            "beacon-admin-not-pause-proxy"
        );
        PauConfig memory config = IBeaconLike(SKY_PAU_BEACON).getConfig(NFAT_PRIME_FACET_INTEGRATION_ID);
        assertEq(
            config.facet, NFAT_PRIME_FACET, "sky-core-prerequisite-missing-nfat-prime-facet-not-registered-on-beacon"
        );
        _assertConfigWires(config, NFAT_PRIME_FACET, _expectedNfatPrimeWires(), "beacon-nfat-prime");
    }

    /// @dev The facility's role events in order: those the fixture recorded, or, for a deployed facility, those on
    ///      chain from TEST_NFAT_FACILITY_DEPLOYMENT_BLOCK to MAINNET_FORK_BLOCK. The latter needs an RPC that serves
    ///      `eth_getLogs` over that range.
    function _facilityRoleEvents() internal view returns (FacilityRoleEvent[] memory roleEvents) {
        if (testNfatFacilityDeployedByFixture) return fixtureFacilityRoleEvents;

        Vm.EthGetLogs[] memory logs = vm.eth_getLogs(
            TEST_NFAT_FACILITY_DEPLOYMENT_BLOCK, MAINNET_FORK_BLOCK, TEST_NFAT_FACILITY, new bytes32[](0)
        );
        roleEvents = new FacilityRoleEvent[](logs.length);
        uint256 count;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || !_isFacilityRoleTopic(logs[i].topics[0])) continue;
            roleEvents[count++] = FacilityRoleEvent(logs[i].topics[0], address(uint160(uint256(logs[i].topics[1]))));
        }
        assembly {
            mstore(roleEvents, count)
        }
    }

    function _isFacilityRoleTopic(bytes32 topic) internal pure returns (bool) {
        return topic == RELY_TOPIC || topic == DENY_TOPIC || topic == KISS_TOPIC || topic == DISS_TOPIC
            || topic == ADD_FREEZER_TOPIC || topic == REMOVE_FREEZER_TOPIC;
    }

    /// @dev Replays the `addTopic` and `removeTopic` events in order and returns the accounts that end up holding the
    ///      role.
    function _replayRoles(FacilityRoleEvent[] memory roleEvents, bytes32 addTopic, bytes32 removeTopic)
        internal
        pure
        returns (address[] memory members)
    {
        members = new address[](roleEvents.length);
        uint256 count;
        for (uint256 i = 0; i < roleEvents.length; ++i) {
            bool isAdd = roleEvents[i].topic == addTopic;
            if (!isAdd && roleEvents[i].topic != removeTopic) continue;

            uint256 index = count;
            for (uint256 j = 0; j < count; ++j) {
                if (members[j] == roleEvents[i].usr) {
                    index = j;
                    break;
                }
            }
            if (isAdd && index == count) members[count++] = roleEvents[i].usr;
            else if (!isAdd && index < count) members[index] = members[--count];
        }
        assembly {
            mstore(members, count)
        }
    }

    function _assertRoleSet(address[] memory members, address expected, string memory label) internal pure {
        assertEq(members.length, 1, string.concat(label, "-count"));
        assertEq(members[0], expected, string.concat(label, "-member"));
    }

    function _repayAsBorrower(uint256 tokenId, uint256 amount) internal {
        address borrower = makeAddr("borrower");
        deal(USDS, borrower, amount);
        vm.startPrank(borrower);
        usds.approve(TEST_NFAT_FACILITY, amount);
        facility.repay(tokenId, amount);
        vm.stopPrank();
    }

    /// @dev Emergency actions #3: withdraws `min(deposits, current withdraw limit)`.
    function _withdrawRecoverableAsOseroActor() internal {
        uint256 amount =
            _min(facility.deposits(OSERO_ALM_PROXY), rateLimits.getCurrentRateLimit(NFAT_WITHDRAW_RATE_LIMIT_KEY));
        _callAsOseroActor(abi.encodeCall(INFATPrimeControllerLike.nfatPrime_withdraw, (TEST_NFAT_FACILITY, amount)));
    }

    function _subscribeAsOseroActor(uint256 amount) internal {
        deal(USDS, OSERO_ALM_PROXY, usds.balanceOf(OSERO_ALM_PROXY) + amount);
        _callAsOseroActor(
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_subscribe, (TEST_NFAT_FACILITY, amount, ""))
        );
    }

    /// @dev Asserts `config` has `facet` and exactly the `expected` wires, in any order.
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

    function _assertWiresDispatched(PauWire[] memory wires, address facet, string memory label) internal view {
        for (uint256 i = 0; i < wires.length; ++i) {
            _assertWire(wires[i].callSelector, facet, wires[i].delegateSelector, label);
        }
    }

    function _assertWiresNotDispatched(PauWire[] memory wires, string memory label) internal view {
        for (uint256 i = 0; i < wires.length; ++i) {
            _assertWire(wires[i].callSelector, address(0), bytes4(0), string.concat(label, "-already-wired"));
        }
    }

    function _expectedTransferAssetWires() internal pure returns (PauWire[] memory wires) {
        wires = new PauWire[](TRANSFER_ASSET_FACET_WIRE_COUNT);
        wires[0] = PauWire(
            ITransferAssetControllerLike.transferAsset_VERSION.selector, ITransferAssetFacetLike.VERSION.selector
        );
        wires[1] = PauWire(
            ITransferAssetControllerLike.transferAsset_transfer.selector, ITransferAssetFacetLike.transfer.selector
        );
        wires[2] = PauWire(
            ITransferAssetControllerLike.transferAsset_getTransferRateLimitKey.selector,
            ITransferAssetFacetLike.getTransferRateLimitKey.selector
        );
    }

    function _expectedNfatPrimeWires() internal pure returns (PauWire[] memory wires) {
        wires = new PauWire[](NFAT_PRIME_FACET_WIRE_COUNT);
        wires[0] =
            PauWire(INFATPrimeControllerLike.nfatPrime_subscribe.selector, INFATPrimeFacetLike.subscribe.selector);
        wires[1] = PauWire(INFATPrimeControllerLike.nfatPrime_withdraw.selector, INFATPrimeFacetLike.withdraw.selector);
        wires[2] = PauWire(INFATPrimeControllerLike.nfatPrime_collect.selector, INFATPrimeFacetLike.collect.selector);
        wires[3] = PauWire(
            INFATPrimeControllerLike.nfatPrime_getSubscribeRateLimitKey.selector,
            INFATPrimeFacetLike.getSubscribeRateLimitKey.selector
        );
        wires[4] = PauWire(
            INFATPrimeControllerLike.nfatPrime_getCollectRateLimitKey.selector,
            INFATPrimeFacetLike.getCollectRateLimitKey.selector
        );
        wires[5] = PauWire(
            INFATPrimeControllerLike.nfatPrime_getWithdrawRateLimitKey.selector,
            INFATPrimeFacetLike.getWithdrawRateLimitKey.selector
        );
        wires[6] = PauWire(INFATPrimeControllerLike.nfatPrime_VERSION.selector, INFATPrimeFacetLike.VERSION.selector);
    }

    /// @dev ALLOCATOR-PRYSM-A debt (18 decimals) drawn by the Osero allocator vault urn.
    function _allocatorDebt() internal view returns (uint256) {
        (, uint256 art) = IVatLike(MCD_VAT).urns(OSERO_ILK, OSERO_ALLOCATOR_VAULT);
        (, uint256 rate,,,) = IVatLike(MCD_VAT).ilks(OSERO_ILK);
        return art * rate / RAY;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _snapshotExistingRateLimits() internal view returns (ExistingRateLimitsSnapshot memory snapshot) {
        bytes32[10] memory keys = [
            USDS_MINT_RATE_LIMIT_KEY,
            USDS_BURN_RATE_LIMIT_KEY,
            PSM_USDS_TO_USDC_RATE_LIMIT_KEY,
            PSM_USDC_TO_USDS_RATE_LIMIT_KEY,
            SPARKLEND_USDS_DEPOSIT_RATE_LIMIT_KEY,
            SPARKLEND_USDS_WITHDRAW_RATE_LIMIT_KEY,
            OGUSDCP_DEPOSIT_RATE_LIMIT_KEY,
            OGUSDCP_WITHDRAW_RATE_LIMIT_KEY,
            CCTP_RATE_LIMIT_KEY,
            CCTP_TO_BASE_RATE_LIMIT_KEY
        ];
        for (uint256 i = 0; i < keys.length; ++i) {
            snapshot.data[i] = rateLimits.getRateLimitData(keys[i]);
            assertGt(snapshot.data[i].maxAmount, 0, string.concat("existing-rate-limit-unset-", vm.toString(i)));
        }
    }

    function _snapshotExistingIntegrationConfigs() internal view returns (PauConfig[5] memory configs) {
        configs[0] = controller.getConfig(USDS_FACET_INTEGRATION_ID);
        configs[1] = controller.getConfig(AAVE_FACET_INTEGRATION_ID);
        configs[2] = controller.getConfig(ERC4626_FACET_INTEGRATION_ID);
        configs[3] = controller.getConfig(PSM_FACET_INTEGRATION_ID);
        configs[4] = controller.getConfig(CCTP_FACET_INTEGRATION_ID);
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

    /// @dev Config for the inherited pre-spell integration test: the five integrations wired by earlier spells,
    ///      including `CCTP_FACET` from the November 19, 2026 spell.
    function _expectedControllerIntegrations() internal pure override returns (ExpectedIntegration[] memory expected) {
        expected = new ExpectedIntegration[](5);
        expected[0] = ExpectedIntegration(USDS_FACET_INTEGRATION_ID, SKY_PAU_USDS_FACET, USDS_FACET_WIRE_COUNT, "usds");
        expected[1] = ExpectedIntegration(AAVE_FACET_INTEGRATION_ID, SKY_PAU_AAVE_FACET, AAVE_FACET_WIRE_COUNT, "aave");
        expected[2] = ExpectedIntegration(
            ERC4626_FACET_INTEGRATION_ID, SKY_PAU_ERC4626_FACET, ERC4626_FACET_WIRE_COUNT, "erc4626"
        );
        expected[3] = ExpectedIntegration(PSM_FACET_INTEGRATION_ID, SKY_PAU_PSM_FACET, PSM_FACET_WIRE_COUNT, "psm");
        expected[4] = ExpectedIntegration(CCTP_FACET_INTEGRATION_ID, SkyPau.CCTP_FACET, CCTP_FACET_WIRE_COUNT, "cctp");
    }
}
