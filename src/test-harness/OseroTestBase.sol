// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {Ethereum as OseroEthereum} from "osero-address-registry/Ethereum.sol";
import {Ethereum as SkyPau} from "sky-pau-registry/Ethereum.sol";

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

interface ISpellLike {
    function execute() external;
    function isExecutable() external view returns (bool);
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
    function usds_usds() external view returns (address);
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

interface IALMProxyLike {
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
    function removeActor(address account) external;
    function revokerCount() external view returns (uint256);
}

interface IAllocatorVaultLike {
    function buffer() external view returns (address);
    function ilk() external view returns (bytes32);
    function jug() external view returns (address);
    function wards(address usr) external view returns (uint256);
}

interface IAllocatorBufferLike {
    function wards(address usr) external view returns (uint256);
}

interface IJugLike {
    function ilks(bytes32 ilk) external view returns (uint256 duty, uint256 rho);
}

interface IATokenLike {
    function POOL() external view returns (address);
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

interface ILitePsmLike {
    function bud(address usr) external view returns (uint256);
    function kiss(address usr) external;
}

interface IAutoLineLike {
    function exec(bytes32 ilk) external returns (uint256 line);
    function ilks(bytes32 ilk)
        external
        view
        returns (uint256 line, uint256 gap, uint48 ttl, uint48 last, uint48 lastInc);
    function setIlk(bytes32 ilk, uint256 line, uint256 gap, uint256 ttl) external;
}

interface IVatLike {
    function ilks(bytes32 ilk)
        external
        view
        returns (uint256 Art, uint256 rate, uint256 spot, uint256 line, uint256 dust);
}

/// @dev Shared helpers and system addresses for Osero spell tests. Spell-specific test
///      contracts inherit `CommonPauSpellTests` (which extends this) and configure the
///      payload under test via `spellId` and `_setupPayload`.
abstract contract OseroTestBase is Test {
    // Sky Core addresses. Source: https://chainlog.skyeco.com/ (keys match the constant names)
    address internal constant MCD_PAUSE_PROXY = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;
    address internal constant MCD_LITE_PSM_USDC_A = 0xf6e72Db5454dd049d0788e411b06CfAF16853042;
    address internal constant MCD_IAM_AUTO_LINE = 0xC7Bdd1F2B16447dcf3dE045C4a039A60EC2f0ba3;
    address internal constant MCD_VAT = 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B;
    address internal constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    // Osero PAU addresses from the osero-address-registry. Independent verification sources:
    // https://chainlog.skyeco.com/ where a key exists (noted per address), otherwise the approved
    // technical-scope forum post:
    // https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-osero-for-upcoming-spell/28023
    address internal constant OSERO_PROXY = OseroEthereum.OSERO_PROXY; // chainlog: PRYSM_SUBPROXY
    address internal constant OSERO_STAR_GUARD = OseroEthereum.OSERO_STAR_GUARD; // chainlog: PRYSM_STARGUARD
    address internal constant OSERO_ALLOCATOR_VAULT = OseroEthereum.OSERO_ALLOCATOR_VAULT; // chainlog: ALLOCATOR_PRYSM_A_VAULT
    address internal constant OSERO_ALLOCATOR_BUFFER = OseroEthereum.OSERO_ALLOCATOR_BUFFER; // chainlog: ALLOCATOR_PRYSM_A_BUFFER
    bytes32 internal constant OSERO_ILK = OseroEthereum.OSERO_ILK;
    address internal constant OSERO_OPERATOR = OseroEthereum.OSERO_OPERATOR;
    address internal constant OSERO_ACCESS_CONTROLS = OseroEthereum.OSERO_ACCESS_CONTROLS;
    address internal constant OSERO_ALM_PROXY = OseroEthereum.OSERO_ALM_PROXY;
    address internal constant OSERO_RATE_LIMITS = OseroEthereum.OSERO_RATE_LIMITS;
    address internal constant OSERO_CONTROLLER = OseroEthereum.OSERO_CONTROLLER;
    address internal constant OSERO_ADMINISTERED_AGENT = OseroEthereum.OSERO_ADMINISTERED_AGENT;
    address internal constant SOTER_OPERATOR = OseroEthereum.SOTER_OPERATOR;
    address internal constant SOTER_FREEZER = OseroEthereum.SOTER_FREEZER;

    // Sky PAU addresses from the sky-pau-registry. Independent verification sources:
    // https://chainlog.skyeco.com/ for the Beacon (key: PAU_BEACON), the technical-scope forum
    // post above for the facets and the assembler.
    address internal constant SKY_PAU_BEACON = SkyPau.BEACON;
    address internal constant SKY_PAU_DEFAULT_PAU_ASSEMBLER = SkyPau.DEFAULT_PAU_ASSEMBLER;
    address internal constant SKY_PAU_USDS_FACET = SkyPau.USDS_FACET;
    address internal constant SKY_PAU_AAVE_FACET = SkyPau.AAVE_FACET;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant CONTROLLER = keccak256("CONTROLLER");

    // Synthetic test actor proving StarGuard.exec() is permissionless.
    address internal constant PERMISSIONLESS_EXECUTOR = address(0xE2E);

    uint256 internal constant MAX_EXECUTION_GAS = 30_000_000;

    IOseroPauControllerLike internal constant controller = IOseroPauControllerLike(OSERO_CONTROLLER);
    IRateLimitsLike internal constant rateLimits = IRateLimitsLike(OSERO_RATE_LIMITS);
    IStarGuardLike internal constant starGuard = IStarGuardLike(OSERO_STAR_GUARD);
    IERC20 internal constant usds = IERC20(USDS);

    // Spell date suffix (e.g. "20260716") driving artifact lookup for fresh payload deployments.
    string internal spellId;
    // The on-chain payload once deployed; address(0) while the spell is still in development.
    address internal deployedPayload;
    // Payload under test: the deployed payload when given, otherwise a freshly deployed one.
    address internal payload;

    function _setupPayload(address deployedPayload_) internal {
        deployedPayload = deployedPayload_;
        payload = deployedPayload_ == address(0) ? _deployPayload() : deployedPayload_;
    }

    function _deployPayload() internal returns (address) {
        string memory slug = string.concat("OseroEthereum_", spellId);
        return deployCode(string.concat(slug, ".sol:", slug));
    }

    function _executeSpellViaStarGuard(address payload_) internal returns (uint256) {
        assertTrue(ISpellLike(payload_).isExecutable(), "payload-not-executable-before-plot");

        bytes32 codehash = payload_.codehash;

        vm.prank(MCD_PAUSE_PROXY);
        starGuard.plot(payload_, codehash);

        (address plottedPayload, bytes32 plottedCodehash, uint256 deadline) = starGuard.spellData();
        assertEq(plottedPayload, payload_, "starguard-plotted-payload-mismatch");
        assertEq(plottedCodehash, codehash, "starguard-plotted-codehash-mismatch");
        assertEq(deadline, block.timestamp + starGuard.maxDelay(), "starguard-deadline-mismatch");
        assertTrue(starGuard.prob(), "starguard-prob-false");

        vm.startPrank(PERMISSIONLESS_EXECUTOR);

        uint256 gasStart = gasleft();
        address returnedPayload = starGuard.exec();
        uint256 gasUsed = gasStart - gasleft();

        vm.stopPrank();

        assertEq(returnedPayload, payload_, "starguard-returned-payload-mismatch");
        (plottedPayload,,) = starGuard.spellData();
        assertEq(plottedPayload, address(0), "starguard-spell-data-not-cleared");
        assertEq(ISubProxyLike(OSERO_PROXY).wards(OSERO_STAR_GUARD), 1, "starguard-removed-from-subproxy");

        return gasUsed;
    }

    function _callAsOseroActor(bytes memory data) internal returns (bytes memory result) {
        IAdministeredAgentLike agent = IAdministeredAgentLike(OSERO_ADMINISTERED_AGENT);
        assertTrue(agent.getIsActor(OSERO_OPERATOR), "osero-operator-not-agent-actor");

        vm.prank(OSERO_OPERATOR);
        result = agent.call(OSERO_CONTROLLER, data);
    }

    function _expectCallAsOseroActorRevert(bytes memory revertData, bytes memory data) internal {
        IAdministeredAgentLike agent = IAdministeredAgentLike(OSERO_ADMINISTERED_AGENT);
        assertTrue(agent.getIsActor(OSERO_OPERATOR), "osero-operator-not-agent-actor");

        vm.prank(OSERO_OPERATOR);
        vm.expectRevert(revertData);
        // Lint false positive: this is the agent's `call(address,bytes)` interface function, not
        // `address.call`, so there is no success flag to check — it reverts on failure instead.
        // forge-lint: disable-next-line(unchecked-call)
        agent.call(OSERO_CONTROLLER, data);
    }

    function _assertContract(address target, string memory label) internal view {
        assertGt(target.code.length, 0, string.concat(label, "-not-deployed"));
    }

    function _assertDispatch(bytes4 callSelector, address expectedFacet, string memory label) internal view {
        PauDispatch memory dispatch = controller.getDispatch(callSelector);
        assertEq(dispatch.facet, expectedFacet, string.concat(label, "-facet-mismatch"));
        assertNotEq(dispatch.delegateSelector, bytes4(0), string.concat(label, "-delegate-selector-not-set"));
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

    /// @dev Asserts the rate limit was never onboarded
    function _assertUnsetRateLimit(bytes32 key, string memory label) internal view {
        IRateLimitsLike.RateLimitData memory data = rateLimits.getRateLimitData(key);
        assertEq(data.maxAmount, 0, string.concat(label, "-unset-max-amount"));
        assertEq(data.slope, 0, string.concat(label, "-unset-slope"));
        assertEq(data.lastAmount, 0, string.concat(label, "-unset-last-amount"));
        assertEq(data.lastUpdated, 0, string.concat(label, "-unset-last-updated"));
    }

    function _getBytecodeMetadataLength(address target) internal view returns (uint256 length) {
        // The Solidity compiler encodes the metadata length in the last two bytes of the contract bytecode.
        assembly {
            let ptr := mload(0x40)
            let size := extcodesize(target)
            if iszero(lt(size, 2)) {
                extcodecopy(target, ptr, sub(size, 2), 2)
                length := mload(ptr)
                length := shr(240, length)
                // The two bytes used to specify the length are not counted in the length.
                length := add(length, 2)
            }
            // Return zero if the bytecode is shorter than two bytes.
        }
    }
}
