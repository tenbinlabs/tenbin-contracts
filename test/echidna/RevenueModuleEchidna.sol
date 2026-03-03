// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CollateralManager} from "../../src/CollateralManager.sol";
import {CollateralManagerHarness} from "../harness/CollateralManagerHarness.sol";
import {Controller} from "../../src/Controller.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EchidnaBase} from "./EchidnaBase.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {RevenueModule} from "../../src/RevenueModule.sol";

// echidna test/echidna/RevenueModuleEchidna.sol --contract RevenueModuleEchidna --config echidna.yaml
contract RevenueModuleEchidna is EchidnaBase {
    RevenueModule revenueModule;
    MockERC4626 staking;
    CollateralManagerHarness manager;
    address multisig;

    constructor() {
        multisig = address(1);
        staking = new MockERC4626("Staking vault", "STK", asset);
        address managerImplementation = address(new CollateralManagerHarness());
        bytes memory data =
            abi.encodeWithSelector(CollateralManager.initialize.selector, address(controller), address(this));
        ERC1967Proxy proxy = new ERC1967Proxy(managerImplementation, data);
        manager = CollateralManagerHarness(address(proxy));

        revenueModule = new RevenueModule(
            address(manager), address(staking), address(this), address(controller), address(asset), multisig
        );

        revenueModule.grantRole(revenueModule.REVENUE_KEEPER_ROLE(), address(this));
        revenueModule.grantRole(ADMIN_ROLE, address(this));
        grantRole(ADMIN_ROLE, address(revenueModule));
    }

    // Manager is never the zero address
    function echidna_manager_never_zero_address() public view returns (bool) {
        return revenueModule.manager() != address(0);
    }

    // Staking is never the zero address
    function echidna_staking_never_zero_address() public view returns (bool) {
        return revenueModule.staking() != address(0);
    }

    // Controller is never the zero address
    function echidna_controller_never_zero_address() public view returns (bool) {
        return revenueModule.controller() != address(0);
    }

    // Asset is never the zero address
    function echidna_asset_never_zero_address() public view returns (bool) {
        return revenueModule.asset() != address(0);
    }

    // Multisig is never the zero address
    function echidna_multisig_never_zero_address() public view returns (bool) {
        return revenueModule.multisig() != address(0);
    }
}
