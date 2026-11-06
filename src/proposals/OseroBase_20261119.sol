// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

import {Base} from "osero-address-registry/Base.sol";
import {Ethereum as OseroEthereum} from "osero-address-registry/Ethereum.sol";

import {PAUInit, PAUInstance} from "diamond-pau/deploy/PAUInit.sol";
import {ICCTPController} from "diamond-pau/src/facets/cctp/ICCTPController.sol";
import {IERC4626Controller} from "diamond-pau/src/facets/erc4626/IERC4626Controller.sol";
import {IController} from "diamond-pau/src/interfaces/IController.sol";
import {IRateLimits} from "diamond-pau/src/interfaces/IRateLimits.sol";

import {
    AdministeredAgentInit,
    AdministeredAgentInitParams
} from "pau-administered-agent/deploy/AdministeredAgentInit.sol";

import {PASAuthorizeInPAU} from "pas/deploy/PASAuthorizeInPAU.sol";

import {CCTPForwarder} from "xchain-helpers/forwarders/CCTPForwarder.sol";

import {OseroPayloadBase} from "../OseroPayloadBase.sol";

/// @title  November 19, 2026 Osero Base Proposal
/// @notice Sets up the Osero Diamond PAU on Base: initializes the PAU and its AdministeredAgent, enables the
///         CCTP facet toward the Osero ALM Proxy on Ethereum and the ERC-4626 facet, onboards the Osero x
///         Gauntlet USDC Prime Vault on Base (Morpho Vault V2), and authorizes the Sky PAS Configurator on Base.
///         Executed by the Osero Executor on Base, which delegatecalls it once the Ethereum spell's relayed
///         actions set is executed.
/// @custom:forum https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
contract OseroBase_20261119 is OseroPayloadBase {
    // Contract: USDC on Base / Source: https://developers.circle.com/stablecoins/usdc-contract-addresses
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // Contract: Sky PAU Beacon on Base / Source: https://sky-atlas.io/#eb4e8e2e-2a55-4c67-aa11-d26b07a481d9 (A.2.2.10.1.1.1.2.3.3.1 - Beacon)
    address internal constant SKY_PAU_BEACON = 0x7ac96180C4d6b2A328D3a19ac059D0E7Fc3C6d41;

    // Contract: Sky PAS Configurator on Base / Source: https://sky-atlas.io/#e5cf7362-7ea2-4a33-8373-565d56c7da67 (A.2.2.10.1.1.1.2.3.3.5 - Configurator)
    address internal constant PAS_CONFIGURATOR = 0x458Acd38fD749F6325039e63e8Bc496dBc286D11;

    // Contract: Core Operator Relayer Multisig on Base, the same address as on Ethereum (Ethereum.SOTER_OPERATOR) / Source: https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388 (Pre-deployed contracts #12)
    address internal constant SOTER_OPERATOR = 0x3dE688267Cf099307aBdd85F64D8efe03D0b2b26;

    // Contract: Freezer Multisig on Base, the same address as on Ethereum (Ethereum.SOTER_FREEZER) / Source: https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388 (Pre-deployed contracts #13)
    address internal constant SOTER_FREEZER = 0xF61F90907551a8A23f0f8EEE9658Fa53326de603;

    // Contract: Osero x Gauntlet USDC Prime Vault on Base (Morpho Vault V2, ogUSDCb) / Source: https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388 (Pre-deployed contracts #9)
    address internal constant OGUSDCB_VAULT = 0x8c1e205C408b90A0dDDbD53594049a379557c651;

    bytes32 internal constant CCTP_FACET_INTEGRATION_ID = "CCTP_FACET";
    bytes32 internal constant ERC4626_FACET_INTEGRATION_ID = "ERC4626_FACET";

    // Fee caps in basis points: CCTP standard transfers are fee-free, so every transfer must pass a 0 fee cap.
    uint32 internal constant CCTP_MIN_FEE_CAP_RATE = 0;
    uint32 internal constant CCTP_MAX_FEE_CAP_RATE = 0;

    // Max exchange rate: at most 2 USDC (6 decimals) per 1e18 vault shares; stored as 1e36 * 2e6 / 1e18 = 2e24.
    uint256 internal constant OGUSDCB_MAX_EXCHANGE_RATE_SHARES = 1e18;
    uint256 internal constant OGUSDCB_MAX_EXCHANGE_RATE_ASSETS = 2e6;

    // USDC-denominated (6 decimals) limits.
    uint256 internal constant CCTP_TO_ETHEREUM_MAX = 10_000_000e6;
    uint256 internal constant CCTP_TO_ETHEREUM_SLOPE = uint256(50_000_000e6) / 1 days;

    uint256 internal constant OGUSDCB_DEPOSIT_MAX = 15_000_000e6;
    uint256 internal constant OGUSDCB_DEPOSIT_SLOPE = uint256(10_000_000e6) / 1 days;

    function execute() external override {
        // Note: every rate limit key below is read from the Osero controller on Base once the facet is wired, as
        //       `RateLimitsHelper` reads the Sky PAU facets on Ethereum and cannot be used on Base.

        // [Base] Proposed action #6: Initialize the Osero Diamond PAU on Base
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        _initializePau();

        // [Base] Proposed action #7: Grant `ALLOCATOR_ROLE` on the Osero `AccessControls` on Base to the Osero
        //   `AdministeredAgent` on Base
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        _addAllocator();

        // [Base] Proposed action #8: Register the Actors and the Revoker on the Osero `AdministeredAgent` on Base
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        _initializeAdministeredAgent();

        // [Base] Proposed action #9: Enable the CCTP and ERC-4626 integrations on the Osero `Controller` on Base
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        //   Note: Sky Core must first register `ERC4626_FACET` on the Sky PAU Beacon on Base (Pre-requirements #1).
        //         Until then `updateIntegrations` reverts with `IntegrationNotFound`, so the whole payload reverts
        //         and the actions set stays queued on the Osero Executor on Base, executable until its 7-day grace
        //         period ends.
        _enableIntegrations();

        // [Base] Proposed action #10: Set the CCTP domain parameters for Ethereum Mainnet
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        _setEthereumDomainParameters();

        // [Base] Proposed action #11: Set the `LIMIT_USDC_TO_CCTP` rate limit on Base to unlimited
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        _setUnlimitedCctpRateLimit();

        // [Base] Proposed action #12: Set the `LIMIT_USDC_TO_DOMAIN` rate limit for Ethereum Mainnet on Base to
        //   `maxAmount` `10,000,000 USDC` and `slope` `50,000,000 USDC/day`
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        _setCctpToEthereumRateLimit();

        // [Base] Proposed action #13: Set the maximum exchange rate for the Osero x Gauntlet USDC Prime Vault on Base
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        _setOgusdcbMaxExchangeRate();

        // [Base] Proposed action #14: Set the vault deposit rate limit to `maxAmount` `15,000,000 USDC` and `slope`
        //   `10,000,000 USDC/day`
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        _setOgusdcbDepositRateLimit();

        // [Base] Proposed action #15: Set the vault withdrawal rate limit to unlimited
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        _setUnlimitedOgusdcbWithdrawRateLimit();

        // [Base] Proposed action #16: Grant `DEFAULT_ADMIN_ROLE` on the Osero `AccessControls` on Base to the
        //   Configurator on Base
        // [Base] Proposed action #17: Grant `DEFAULT_ADMIN_ROLE` on the Osero ALM Rate Limits contract on Base to the
        //   Configurator on Base
        //   Forum : https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-osero-for-upcoming-spell/28388
        //   Note: `PASAuthorizeInPAU.authorize` makes both grants in one call, as in the September 24, 2026 spell. It
        //         runs after Proposed action #6, because `PAUInit.init` requires the Executor to be the only
        //         `AccessControls` admin.
        _authorizePasConfigurator();
    }

    function _pauInstance() private pure returns (PAUInstance memory) {
        return PAUInstance({
            accessControls: Base.OSERO_ACCESS_CONTROLS,
            almProxy: Base.OSERO_ALM_PROXY,
            beacon: SKY_PAU_BEACON,
            controller: Base.OSERO_CONTROLLER,
            rateLimits: Base.OSERO_RATE_LIMITS
        });
    }

    function _initializePau() private {
        // Integrations are imported in Proposed action #9.
        // BEFORE: the controller holds CONTROLLER on neither the ALM proxy nor the rate limits.
        // AFTER:  the controller holds CONTROLLER on both.
        PAUInit.init(_pauInstance(), new bytes32[](0));
    }

    function _addAllocator() private {
        PAUInit.addAllocator(_pauInstance(), Base.OSERO_ADMINISTERED_AGENT); // BEFORE: no ALLOCATOR_ROLE holder, AFTER: AdministeredAgent
    }

    function _initializeAdministeredAgent() private {
        address[] memory actors = new address[](2);
        actors[0] = Base.OSERO_OPERATOR; // Osero Relayer Multisig on Base (Pre-deployed contracts #11)
        actors[1] = SOTER_OPERATOR; // Core Operator Relayer Multisig on Base (Pre-deployed contracts #12)

        address[] memory revokers = new address[](1);
        revokers[0] = SOTER_FREEZER; // Freezer Multisig on Base (Pre-deployed contracts #13)

        // BEFORE: Executor is the only Admin; no Actor, Grantor or Revoker.
        // AFTER:  Executor is the only Admin; Actors: Osero and Core Operator Relayer Multisigs; Revoker: Freezer Multisig; no Grantor.
        AdministeredAgentInit.init(
            Base.OSERO_ADMINISTERED_AGENT,
            AdministeredAgentInitParams({
                admins: new address[](0), actors: actors, grantors: new address[](0), revokers: revokers
            })
        );
    }

    function _enableIntegrations() private {
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = CCTP_FACET_INTEGRATION_ID; // BEFORE: not wired on the controller, AFTER: wired from the beacon config
        ids[1] = ERC4626_FACET_INTEGRATION_ID; // BEFORE: not wired on the controller, AFTER: wired from the beacon config
        IController(Base.OSERO_CONTROLLER).updateIntegrations(ids);
    }

    function _setEthereumDomainParameters() private {
        ICCTPController(Base.OSERO_CONTROLLER).cctp_setDomainParameters({
            destinationDomain: CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            recipient: bytes32(uint256(uint160(OseroEthereum.OSERO_ALM_PROXY))), // BEFORE: bytes32(0), AFTER: Osero ALM Proxy on Ethereum
            minFeeCapRate: CCTP_MIN_FEE_CAP_RATE, // BEFORE: 0, AFTER: 0
            maxFeeCapRate: CCTP_MAX_FEE_CAP_RATE // BEFORE: 0, AFTER: 0
        });
    }

    function _setUnlimitedCctpRateLimit() private {
        IRateLimits(Base.OSERO_RATE_LIMITS)
            .setUnlimitedRateLimitData(ICCTPController(Base.OSERO_CONTROLLER).cctp_toCCTPRateLimitKey()); // BEFORE: unset, AFTER: unlimited
    }

    function _setCctpToEthereumRateLimit() private {
        IRateLimits(Base.OSERO_RATE_LIMITS).setRateLimitData({
            key: ICCTPController(Base.OSERO_CONTROLLER)
                .cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            maxAmount: CCTP_TO_ETHEREUM_MAX, // BEFORE: unset, AFTER: 10_000_000e6
            slope: CCTP_TO_ETHEREUM_SLOPE // BEFORE: unset, AFTER: uint256(50_000_000e6) / 1 days
        });
    }

    function _setOgusdcbMaxExchangeRate() private {
        IERC4626Controller(Base.OSERO_CONTROLLER).erc4626_setMaxExchangeRate({
            token: OGUSDCB_VAULT,
            shares: OGUSDCB_MAX_EXCHANGE_RATE_SHARES,
            maxExpectedAssets: OGUSDCB_MAX_EXCHANGE_RATE_ASSETS // BEFORE: 0 (unset), AFTER: 2e6 (stored as 2e24)
        });
    }

    function _setOgusdcbDepositRateLimit() private {
        IRateLimits(Base.OSERO_RATE_LIMITS).setRateLimitData({
            key: IERC4626Controller(Base.OSERO_CONTROLLER).erc4626_getDepositRateLimitKey(OGUSDCB_VAULT, USDC),
            maxAmount: OGUSDCB_DEPOSIT_MAX, // BEFORE: unset, AFTER: 15_000_000e6
            slope: OGUSDCB_DEPOSIT_SLOPE // BEFORE: unset, AFTER: uint256(10_000_000e6) / 1 days
        });
    }

    function _setUnlimitedOgusdcbWithdrawRateLimit() private {
        IRateLimits(Base.OSERO_RATE_LIMITS)
            .setUnlimitedRateLimitData(
                IERC4626Controller(Base.OSERO_CONTROLLER).erc4626_getWithdrawRateLimitKey(OGUSDCB_VAULT)
            ); // BEFORE: unset, AFTER: unlimited
    }

    function _authorizePasConfigurator() private {
        // BEFORE: Configurator holds neither admin role; the Executor is the only AccessControls admin.
        // AFTER:  Configurator holds both; the Executor keeps both.
        PASAuthorizeInPAU.authorize({
            configurator: PAS_CONFIGURATOR,
            accessControls: Base.OSERO_ACCESS_CONTROLS,
            rateLimits: Base.OSERO_RATE_LIMITS
        });
    }
}
