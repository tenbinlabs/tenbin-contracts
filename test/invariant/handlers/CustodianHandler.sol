// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CustodianModule} from "../../../src/CustodianModule.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Handler to interact with the asset token and save snapshots for invariant testing
contract CustodianHandler is Test {
    CustodianModule custodianModule;
    address owner;
    address custodianKeeper;
    MockERC20 token;

    constructor(CustodianModule _custodianModule, address _owner, address _custodianKeeper) {
        custodianModule = _custodianModule;
        owner = _owner;
        custodianKeeper = _custodianKeeper;
        token = new MockERC20("Mock ERC20", "MERC20", 18);
        token.mint(address(custodianModule), type(uint256).max);
    }

    function setCustodianStatus(address account, bool status) public {
        vm.prank(owner);
        custodianModule.setCustodianStatus(account, status);
    }

    function offramp(address account, uint256 amount) external {
        if (!custodianModule.custodians(account)) setCustodianStatus(account, true);
        vm.prank(custodianKeeper);
        custodianModule.offramp(account, address(token), amount);
    }
}
