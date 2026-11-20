// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";

import {SparkLend} from "spark-address-registry/SparkLend.sol";

import {Ethereum as SkyPau} from "sky-pau-registry/Ethereum.sol";

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

interface IAccessControlEnumerableLike {
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function hasRole(bytes32 role, address account) external view returns (bool);
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
    // Forks at the technical scope readback block for the Test Halo side (November 19, 2026 01:07:11 UTC, Pre-requirements
    // #3-4). The NFAT Prime Facet, the Test NFAT Facility and the Test NFAT Facility Diamond PAU are deployed at that
    // block. Two things the December 3, 2026 Executive Vote does, and one pre-state the tests assume, are not on-chain
    // yet. `setUp` simulates each until MAINNET_FORK_BLOCK is moved past it:
    // - the Sky Core spell registers the NFAT Prime Facet on the Sky PAU Beacon (Pre-requirements #1,
    //   `_registerNfatPrimeFacetAsSkyCore`);
    // - the Executive Vote initializes the Test NFAT Facility (Pre-requirements #3, #7,
    //   `_initializeTestNfatFacilityAsTestHalo`);
    // - the November 19, 2026 Osero spell has not executed (`_executeNovember19SpellIfPending`). This spell does not
    //   depend on it, but the tests expect its `CCTP_FACET` integration and CCTP keys to be in place.
    uint256 internal constant MAINNET_FORK_BLOCK = 26_445_734;

    // The on-chain payload; address(0) until it is deployed.
    address internal constant DEPLOYED_PAYLOAD = address(0);

    // `OseroEthereum_20261119`, deployed and plotted for the November 19, 2026 Sky Core spell.
    address internal constant NOVEMBER_19_PAYLOAD = 0xC1989b5c81eA2bC4A6Abda0e73e3E3C48D500d05;

    // Addresses from the technical scope (Trusted addresses, Pre-deployed contracts, Pre-requirements #3-4).
    // The Test NFAT Facility ALM Proxy is the USDS transfer destination, and, once the facility is initialized, its
    // `recipient` and only `bud`.
    address internal constant TEST_NFAT_FACILITY_ALM_PROXY = 0xBEE5C2E8436e9834e6890A528E5B294D93b2Eec7;
    address internal constant TEST_NFAT_FACILITY = 0x02Cb9629B0806b11202C59433eCe4e664C521128;
    address internal constant NFAT_PRIME_FACET = 0x74d139d6e730F29D62F2Acc6A3b59dF2f2d6D9A8;
    // The `Controller` of the Test NFAT Facility Diamond PAU; its `proxy()` is the Test NFAT Facility ALM Proxy.
    address internal constant TEST_NFAT_FACILITY_CONTROLLER = 0x37F628D95ceC5aDA038A1cca734573dbcb79d1cB;
    // Test Halo SubProxy, the facility's only ward and the ALM Proxy's only `DEFAULT_ADMIN_ROLE` holder.
    address internal constant TEST_HALO_SUBPROXY = 0xF12Be1673758f8fBC275755401774Ec45C80c0F0;

    // The Test NFAT Facility as deployed on-chain (Pre-requirements #3): the deployer relied the Test Halo SubProxy and
    // denied itself. Its role history is read from TEST_NFAT_FACILITY_DEPLOYMENT_BLOCK to MAINNET_FORK_BLOCK.
    address internal constant TEST_NFAT_FACILITY_DEPLOYER = 0x548DAc55f260AA4631F589Cb2fe72b5E9E4C93Dc;
    uint256 internal constant TEST_NFAT_FACILITY_DEPLOYMENT_BLOCK = 26_443_860;
    string internal constant TEST_NFAT_FACILITY_NAME = "Pilot Test Allocation";
    string internal constant TEST_NFAT_FACILITY_SYMBOL = "$PTA";
    // TODO: the facility's freezers are set at initialization in the December 3, 2026 Executive Vote and are not yet
    //       documented (Pre-requirements #3). Until then this synthetic freezer configures the simulated initialization.
    address internal constant TEST_NFAT_FACILITY_FREEZER = address(0xFAC2);

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
        keccak256(abi.encode(LIMIT_ASSET_TRANSFER, USDS, TEST_NFAT_FACILITY_ALM_PROXY));
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

    // Rate limits, as in the spell (Proposed actions #2, #4-6). The withdraw and collect keys are unlimited.
    uint256 internal constant USDS_TRANSFER_MAX = 1_000_000e18;
    uint256 internal constant USDS_TRANSFER_SLOPE = uint256(1_000_000e18) / 1 days;
    uint256 internal constant NFAT_SUBSCRIBE_MAX = 5_000_000e18;
    uint256 internal constant NFAT_SUBSCRIBE_SLOPE = uint256(1_000_000e18) / 1 days;
    // The time the subscribe key takes to refill from 0 to its maximum: just over 5 days, as the slope is rounded down.
    uint256 internal constant NFAT_SUBSCRIBE_REFILL_TIME = NFAT_SUBSCRIBE_MAX / NFAT_SUBSCRIBE_SLOPE + 1;

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

    // The role events of the simulated initialization; they follow the facility's on-chain role history.
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
        _initializeTestNfatFacilityAsTestHalo();
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

        // The new keys as written in the technical scope (Proposed actions #2, #4-6, Emergency actions #1-2).
        assertEq(
            USDS_TRANSFER_RATE_LIMIT_KEY,
            0xdc1d794c3b887903c7ddbbd9993389bb07143e4becb9aa609297dc205c77505d,
            "usds-transfer-key-literal"
        );
        assertEq(
            NFAT_SUBSCRIBE_RATE_LIMIT_KEY,
            0x4f1900e2604bdf2ad80de16402ae5bb5ae9196fe59d4377629cc546cd78d6d98,
            "nfat-subscribe-key-literal"
        );
        assertEq(
            NFAT_WITHDRAW_RATE_LIMIT_KEY,
            0x3ec73e26bc851816b1ea627ba14b63765e90b7885b507ed7757fa47bb23774eb,
            "nfat-withdraw-key-literal"
        );
        assertEq(
            NFAT_COLLECT_RATE_LIMIT_KEY,
            0x33d797249dda8ed1272964e57b594ab4b6b20d8a66cdfaa248fdbb9d32458c75,
            "nfat-collect-key-literal"
        );

        ITransferAssetFacetLike transferAssetFacet = ITransferAssetFacetLike(SkyPau.TRANSFER_ASSET_FACET);
        assertEq(
            transferAssetFacet.getTransferRateLimitKey(USDS, TEST_NFAT_FACILITY_ALM_PROXY),
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

        // Rate limit values (Proposed actions #2 and #4); Proposed actions #5-6 are unlimited.
        assertEq(USDS_TRANSFER_MAX, 1_000_000_000_000_000_000_000_000, "usds-transfer-max-literal");
        assertEq(USDS_TRANSFER_SLOPE, 11_574_074_074_074_074_074, "usds-transfer-slope-literal");
        assertEq(NFAT_SUBSCRIBE_MAX, 5_000_000_000_000_000_000_000_000, "nfat-subscribe-max-literal");
        assertEq(NFAT_SUBSCRIBE_SLOPE, 11_574_074_074_074_074_074, "nfat-subscribe-slope-literal");
        assertEq(NFAT_SUBSCRIBE_REFILL_TIME, 432_001, "nfat-subscribe-refill-time");
    }

    /// @dev Once DEPLOYED_PAYLOAD is set (it cannot run earlier), the deployed payload is tested on a fork past the
    ///      November 19, 2026 spell. Only the December 3, 2026 Executive Vote's registration of the facet and
    ///      initialization of the facility may still be simulated, since they happen in the Sky Core spell that plots
    ///      this payload.
    function test_ETHEREUM_deployedPayloadTestedPastNovember19Spell() public {
        vm.skip(deployedPayload == address(0));

        assertFalse(november19SpellExecutedByFixture, "november-19-spell-not-executed");
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
        assertEq(facility.recipient(), TEST_NFAT_FACILITY_ALM_PROXY, "facility-recipient");

        // The Test Halo SubProxy is the only ward, the Test NFAT Facility ALM Proxy the only operator, and the deployer
        // kept no ward.
        FacilityRoleEvent[] memory roleEvents = _facilityRoleEvents();
        _assertRoleSet(_replayRoles(roleEvents, RELY_TOPIC, DENY_TOPIC), TEST_HALO_SUBPROXY, "facility-wards");
        _assertRoleSet(_replayRoles(roleEvents, KISS_TOPIC, DISS_TOPIC), TEST_NFAT_FACILITY_ALM_PROXY, "facility-buds");
        _assertRoleSet(
            _replayRoles(roleEvents, ADD_FREEZER_TOPIC, REMOVE_FREEZER_TOPIC),
            TEST_NFAT_FACILITY_FREEZER,
            "facility-cops"
        );
        assertEq(facility.wards(TEST_HALO_SUBPROXY), 1, "facility-owner-not-ward");
        assertEq(facility.wards(TEST_NFAT_FACILITY_DEPLOYER), 0, "facility-deployer-still-ward");
        assertEq(facility.buds(TEST_NFAT_FACILITY_ALM_PROXY), 1, "facility-operator-not-bud");
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

    /// @dev Pre-requirements #4: the USDS transfer destination is the ALM Proxy of the Test NFAT Facility Diamond PAU,
    ///      and the Test Halo SubProxy is its only `DEFAULT_ADMIN_ROLE` holder.
    function test_ETHEREUM_testNfatFacilityAlmProxyPreconfiguration() public view {
        _assertContract(TEST_NFAT_FACILITY_CONTROLLER, "test-nfat-facility-controller");
        _assertContract(TEST_NFAT_FACILITY_ALM_PROXY, "test-nfat-facility-alm-proxy");
        assertEq(
            IOseroPauControllerLike(TEST_NFAT_FACILITY_CONTROLLER).proxy(),
            TEST_NFAT_FACILITY_ALM_PROXY,
            "test-nfat-facility-controller-proxy"
        );

        IAccessControlEnumerableLike almProxy = IAccessControlEnumerableLike(TEST_NFAT_FACILITY_ALM_PROXY);
        assertEq(almProxy.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1, "test-nfat-facility-alm-proxy-admin-count");
        assertEq(
            almProxy.getRoleMember(DEFAULT_ADMIN_ROLE, 0), TEST_HALO_SUBPROXY, "test-nfat-facility-alm-proxy-admin"
        );
        assertFalse(
            almProxy.hasRole(DEFAULT_ADMIN_ROLE, OSERO_PROXY), "test-nfat-facility-alm-proxy-admin-is-osero-subproxy"
        );
    }

    /// @dev The role check above replays the facility's role events: an extra ward or operator is counted, and a
    ///      `Deny` removes one, so the check fails for any role set other than the approved one.
    function test_ETHEREUM_facilityRoleReplayCountsExtraAndRemovedRoles() public pure {
        address unapproved = address(0xBAD);
        FacilityRoleEvent[] memory roleEvents = new FacilityRoleEvent[](6);
        roleEvents[0] = FacilityRoleEvent(RELY_TOPIC, TEST_NFAT_FACILITY_DEPLOYER);
        roleEvents[1] = FacilityRoleEvent(RELY_TOPIC, TEST_HALO_SUBPROXY);
        roleEvents[2] = FacilityRoleEvent(DENY_TOPIC, TEST_NFAT_FACILITY_DEPLOYER);
        roleEvents[3] = FacilityRoleEvent(RELY_TOPIC, unapproved);
        roleEvents[4] = FacilityRoleEvent(KISS_TOPIC, TEST_NFAT_FACILITY_ALM_PROXY);
        roleEvents[5] = FacilityRoleEvent(KISS_TOPIC, unapproved);

        address[] memory wards = _replayRoles(roleEvents, RELY_TOPIC, DENY_TOPIC);
        assertEq(wards.length, 2, "ward-count");
        assertEq(wards[0], TEST_HALO_SUBPROXY, "ward-owner");
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
        _assertUnlimitedRateLimit(NFAT_COLLECT_RATE_LIMIT_KEY, "nfat-collect-after-retry");
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
            transferAssetController.transferAsset_getTransferRateLimitKey(USDS, TEST_NFAT_FACILITY_ALM_PROXY),
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
        _assertUnlimitedRateLimit(NFAT_WITHDRAW_RATE_LIMIT_KEY, "nfat-withdraw");
        _assertUnlimitedRateLimit(NFAT_COLLECT_RATE_LIMIT_KEY, "nfat-collect");
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
        uint256 destinationUsdsStart = usds.balanceOf(TEST_NFAT_FACILITY_ALM_PROXY);

        vm.expectEmit(OSERO_CONTROLLER);
        emit TransferAssetTransfer(USDS, TEST_NFAT_FACILITY_ALM_PROXY, ROUND_TRIP_USDS_AMOUNT);
        _callAsOseroActor(
            abi.encodeCall(
                ITransferAssetControllerLike.transferAsset_transfer,
                (USDS, TEST_NFAT_FACILITY_ALM_PROXY, ROUND_TRIP_USDS_AMOUNT)
            )
        );

        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart - ROUND_TRIP_USDS_AMOUNT, "proxy-usds-not-sent");
        assertEq(
            usds.balanceOf(TEST_NFAT_FACILITY_ALM_PROXY),
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
                (USDS, TEST_NFAT_FACILITY_ALM_PROXY, USDS_TRANSFER_MAX + 1)
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
            abi.encodeCall(ITransferAssetControllerLike.transferAsset_transfer, (USDC, TEST_NFAT_FACILITY_ALM_PROXY, 1))
        );
    }

    function test_ETHEREUM_usdsTransferRateLimitRecoversOverTime() public {
        _executeSpellViaStarGuard(payload);
        deal(USDS, OSERO_ALM_PROXY, USDS_TRANSFER_MAX);

        _callAsOseroActor(
            abi.encodeCall(
                ITransferAssetControllerLike.transferAsset_transfer,
                (USDS, TEST_NFAT_FACILITY_ALM_PROXY, USDS_TRANSFER_MAX)
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
                (USDS, TEST_NFAT_FACILITY_ALM_PROXY, ROUND_TRIP_USDS_AMOUNT)
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
        IRateLimitsLike.RateLimitData memory withdrawLimitBefore =
            rateLimits.getRateLimitData(NFAT_WITHDRAW_RATE_LIMIT_KEY);

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
        // The withdraw key is unlimited, so a withdrawal leaves it untouched.
        _assertRateLimitDataUnchanged(
            withdrawLimitBefore, rateLimits.getRateLimitData(NFAT_WITHDRAW_RATE_LIMIT_KEY), "nfat-withdraw"
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
        uint256 recipientUsdsStart = usds.balanceOf(TEST_NFAT_FACILITY_ALM_PROXY);

        vm.prank(TEST_NFAT_FACILITY_ALM_PROXY);
        facility.issue(OSERO_ALM_PROXY, NFAT_TOKEN_ID, ROUND_TRIP_USDS_AMOUNT);
        assertEq(facility.ownerOf(NFAT_TOKEN_ID), OSERO_ALM_PROXY, "nfat-not-issued-to-osero-almproxy");
        assertEq(facility.deposits(OSERO_ALM_PROXY), 0, "deposit-not-drawn");
        assertEq(
            usds.balanceOf(TEST_NFAT_FACILITY_ALM_PROXY),
            recipientUsdsStart + ROUND_TRIP_USDS_AMOUNT,
            "principal-not-sent-to-recipient"
        );

        _repayAsBorrower(NFAT_TOKEN_ID, REPAID_USDS_AMOUNT);
        assertEq(facility.collectable(NFAT_TOKEN_ID), REPAID_USDS_AMOUNT, "repayment-not-collectable");

        uint256 proxyUsdsStart = usds.balanceOf(OSERO_ALM_PROXY);
        IRateLimitsLike.RateLimitData memory collectLimitBefore =
            rateLimits.getRateLimitData(NFAT_COLLECT_RATE_LIMIT_KEY);
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
        // The collect key is unlimited, so a collection leaves it untouched.
        _assertRateLimitDataUnchanged(
            collectLimitBefore, rateLimits.getRateLimitData(NFAT_COLLECT_RATE_LIMIT_KEY), "nfat-collect"
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

        vm.warp(start + NFAT_SUBSCRIBE_REFILL_TIME - 1);
        assertLt(
            rateLimits.getCurrentRateLimit(NFAT_SUBSCRIBE_RATE_LIMIT_KEY),
            NFAT_SUBSCRIBE_MAX,
            "nfat-subscribe-limit-refilled-early"
        );

        vm.warp(start + NFAT_SUBSCRIBE_REFILL_TIME);
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

    /// @dev Proposed actions #5: the withdraw key is unlimited, so a deposit larger than the subscribe key allows at
    ///      once is withdrawn in one call, and the key is left untouched. The deposit is built in two subscriptions,
    ///      since each is capped by the subscribe key.
    function test_ETHEREUM_nfatWithdrawIsUnlimited() public {
        _executeSpellViaStarGuard(payload);
        _subscribeAsOseroActor(NFAT_SUBSCRIBE_MAX);
        vm.warp(vm.getBlockTimestamp() + NFAT_SUBSCRIBE_REFILL_TIME);
        _subscribeAsOseroActor(NFAT_SUBSCRIBE_MAX);
        uint256 deposit = facility.deposits(OSERO_ALM_PROXY);
        assertEq(deposit, 2 * NFAT_SUBSCRIBE_MAX, "deposit-not-built");
        uint256 proxyUsdsStart = usds.balanceOf(OSERO_ALM_PROXY);
        IRateLimitsLike.RateLimitData memory withdrawLimitBefore =
            rateLimits.getRateLimitData(NFAT_WITHDRAW_RATE_LIMIT_KEY);

        _callAsOseroActor(abi.encodeCall(INFATPrimeControllerLike.nfatPrime_withdraw, (TEST_NFAT_FACILITY, deposit)));

        assertEq(facility.deposits(OSERO_ALM_PROXY), 0, "deposit-not-withdrawn");
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart + deposit, "proxy-usds-not-returned");
        _assertRateLimitDataUnchanged(
            withdrawLimitBefore, rateLimits.getRateLimitData(NFAT_WITHDRAW_RATE_LIMIT_KEY), "nfat-withdraw"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(NFAT_WITHDRAW_RATE_LIMIT_KEY),
            type(uint256).max,
            "nfat-withdraw-not-unlimited"
        );
    }

    /// @dev Proposed actions #6: the collect key is unlimited, so a repayment larger than the subscribe key's maximum
    ///      is collected in one call, and the key is left untouched.
    function test_ETHEREUM_nfatCollectIsUnlimited() public {
        _executeSpellViaStarGuard(payload);
        _subscribeAsOseroActor(ROUND_TRIP_USDS_AMOUNT);
        vm.prank(TEST_NFAT_FACILITY_ALM_PROXY);
        facility.issue(OSERO_ALM_PROXY, NFAT_TOKEN_ID, ROUND_TRIP_USDS_AMOUNT);
        uint256 repayment = 2 * NFAT_SUBSCRIBE_MAX;
        _repayAsBorrower(NFAT_TOKEN_ID, repayment);
        uint256 proxyUsdsStart = usds.balanceOf(OSERO_ALM_PROXY);
        IRateLimitsLike.RateLimitData memory collectLimitBefore =
            rateLimits.getRateLimitData(NFAT_COLLECT_RATE_LIMIT_KEY);

        _callAsOseroActor(
            abi.encodeCall(INFATPrimeControllerLike.nfatPrime_collect, (TEST_NFAT_FACILITY, NFAT_TOKEN_ID, repayment))
        );

        assertEq(facility.collectable(NFAT_TOKEN_ID), 0, "repayment-not-collected");
        assertEq(usds.balanceOf(OSERO_ALM_PROXY), proxyUsdsStart + repayment, "proxy-usds-not-collected");
        _assertRateLimitDataUnchanged(
            collectLimitBefore, rateLimits.getRateLimitData(NFAT_COLLECT_RATE_LIMIT_KEY), "nfat-collect"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(NFAT_COLLECT_RATE_LIMIT_KEY), type(uint256).max, "nfat-collect-not-unlimited"
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
        vm.prank(TEST_HALO_SUBPROXY);
        facility.file("identityNetwork", address(identityNetwork));

        vm.prank(TEST_NFAT_FACILITY_ALM_PROXY);
        vm.expectRevert(bytes("NFATFacility/not-member"));
        facility.issue(OSERO_ALM_PROXY, NFAT_TOKEN_ID, ROUND_TRIP_USDS_AMOUNT);

        identityNetwork.setMember(OSERO_ALM_PROXY, true);
        vm.prank(TEST_NFAT_FACILITY_ALM_PROXY);
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
        vm.prank(TEST_NFAT_FACILITY_ALM_PROXY);
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
            abi.encodeCall(ITransferAssetControllerLike.transferAsset_transfer, (USDS, TEST_NFAT_FACILITY_ALM_PROXY, 1))
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
            abi.encodeCall(ITransferAssetControllerLike.transferAsset_transfer, (USDS, TEST_NFAT_FACILITY_ALM_PROXY, 1))
        );
        _expectCallAsOseroActorRevert(
            bytes("RateLimits/zero-maxAmount"),
            abi.encodeCall(
                INFATPrimeControllerLike.nfatPrime_subscribe, (TEST_NFAT_FACILITY, ROUND_TRIP_USDS_AMOUNT, "")
            )
        );
    }

    /// @dev Emergency actions #3: unissued USDS can be withdrawn while the facility is stopped, with
    ///      `amount = min(deposits, current withdraw limit)`. The withdraw key is unlimited, so the whole deposit is
    ///      recovered in one call. Subscriptions and collections revert while the facility is stopped.
    function test_ETHEREUM_withdrawRecoversUnissuedUsdsWhileFacilityStopped() public {
        _executeSpellViaStarGuard(payload);
        _subscribeAsOseroActor(NFAT_SUBSCRIBE_MAX);
        uint256 deposit = facility.deposits(OSERO_ALM_PROXY);
        assertEq(deposit, NFAT_SUBSCRIBE_MAX, "deposit-not-built");
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
            abi.encodeCall(ITransferAssetControllerLike.transferAsset_transfer, (USDS, TEST_NFAT_FACILITY_ALM_PROXY, 1))
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
            abi.encodeCall(ITransferAssetControllerLike.transferAsset_transfer, (USDS, TEST_NFAT_FACILITY_ALM_PROXY, 1))
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
    ///      #1): the Sky Pause Proxy registers the deployed NFAT_PRIME_FACET with
    ///      `BeaconConfig.setNFATPrimeIntegration`. The wires come from diamond-pau, not `_expectedNfatPrimeWires`, so
    ///      the tests still check them independently. A no-op once the fork block is past the real registration.
    function _registerNfatPrimeFacetAsSkyCore() internal {
        if (IBeaconLike(SKY_PAU_BEACON).getConfig(NFAT_PRIME_FACET_INTEGRATION_ID).facet != address(0)) return;

        vm.startPrank(MCD_PAUSE_PROXY);
        BeaconConfig.setNFATPrimeIntegration(SKY_PAU_BEACON, NFAT_PRIME_FACET);
        vm.stopPrank();
    }

    /// @dev Test NFAT Facility fixture, NOT part of this spell. Models the facility's initialization in the December 3,
    ///      2026 Executive Vote (Pre-requirements #3, #7), following `NFATInit.init` at the audited `fa089fe0`: the Test
    ///      Halo SubProxy, the facility's ward, sets the Test NFAT Facility ALM Proxy as `recipient` and only operator,
    ///      and adds the freezer. `identityNetwork` stays `address(0)`. The script is not called: at diamond-pau's
    ///      pinned `nfat` (`530a5e32`) it requires sUSDS as `gem`. The role events are recorded for
    ///      `_facilityRoleEvents`. A no-op once the fork block is past the real initialization.
    function _initializeTestNfatFacilityAsTestHalo() internal {
        if (facility.recipient() != address(0)) return;

        vm.recordLogs();

        vm.startPrank(TEST_HALO_SUBPROXY);
        facility.file("recipient", TEST_NFAT_FACILITY_ALM_PROXY);
        facility.kiss(TEST_NFAT_FACILITY_ALM_PROXY);
        facility.addFreezer(TEST_NFAT_FACILITY_FREEZER);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != TEST_NFAT_FACILITY || !_isFacilityRoleTopic(logs[i].topics[0])) continue;
            fixtureFacilityRoleEvents.push(
                FacilityRoleEvent(logs[i].topics[0], address(uint160(uint256(logs[i].topics[1]))))
            );
        }
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

    /// @dev The facility's role events in order: those on chain from TEST_NFAT_FACILITY_DEPLOYMENT_BLOCK to
    ///      MAINNET_FORK_BLOCK, then those of the simulated initialization, if any. Needs an RPC that serves
    ///      `eth_getLogs` over that range.
    function _facilityRoleEvents() internal view returns (FacilityRoleEvent[] memory roleEvents) {
        Vm.EthGetLogs[] memory logs = vm.eth_getLogs(
            TEST_NFAT_FACILITY_DEPLOYMENT_BLOCK, MAINNET_FORK_BLOCK, TEST_NFAT_FACILITY, new bytes32[](0)
        );
        roleEvents = new FacilityRoleEvent[](logs.length + fixtureFacilityRoleEvents.length);
        uint256 count;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || !_isFacilityRoleTopic(logs[i].topics[0])) continue;
            roleEvents[count++] = FacilityRoleEvent(logs[i].topics[0], address(uint160(uint256(logs[i].topics[1]))));
        }
        for (uint256 i = 0; i < fixtureFacilityRoleEvents.length; ++i) {
            roleEvents[count++] = fixtureFacilityRoleEvents[i];
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
