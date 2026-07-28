// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Config} from "forge-std/Config.sol";

import {DeployBebopHook} from "../../script/DeployBebopHook.s.sol";
import {BebopHook} from "../../src/external/bebop/BebopHook.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";

/// @notice Fork test for the BebopHook deployment script.
/// @dev Requires the RPC URL and deployment environment to be configured.
contract DeployBebopHookForkTest is ForkBaseTest, Config {
    address constant TBRL_CONTROLLER = 0x0EF47CC8E244dBc8628FdEfFD4EE4DD747d14081;
    address constant TGLD_CONTROLLER = 0x5e631388b24ec493619DAEEAef6fc34B33d97Dcd;
    address constant TMXN_CONTROLLER = 0xB5EBDeC6DA02119DD7BEB4782C181261f8BfEcC2;
    address constant OWNER = 0x698c6d3726846C4AD4Dc9331862b92Cd80D2fb99;
    address constant ROUTER = 0xBeb0009ACa35087ce7cCF11637E24dd1Aad3bf2A;

    // Must match the MAKER constant in DeployBebopHook.s.sol.
    address constant MAKER = 0x143eC4305186064c77a4682Dc982b49692ba305c;

    address[] internal controllers;
    address[] internal hooks;

    function setUp() public override {
        forkBlock = 25603766;
        super.setUp();

        DeployBebopHook deployer = new DeployBebopHook();
        (controllers, hooks) = deployer.run();
    }

    function test_fork_DeployBebopHook() public view {
        assertEq(controllers.length, 3);
        assertEq(hooks.length, 3);
        assertEq(controllers[0], TBRL_CONTROLLER);
        assertEq(controllers[1], TGLD_CONTROLLER);
        assertEq(controllers[2], TMXN_CONTROLLER);

        _assertHook(hooks[0], TBRL_CONTROLLER);
        _assertHook(hooks[1], TGLD_CONTROLLER);
        _assertHook(hooks[2], TMXN_CONTROLLER);
    }

    function _assertHook(address hookAddress, address controller) internal view {
        BebopHook hook = BebopHook(hookAddress);

        // Contract was deployed.
        assertTrue(hookAddress != address(0));
        assertTrue(hookAddress.code.length > 0);

        // Constructor parameters were configured correctly.
        assertEq(hook.router(), ROUTER);
        assertEq(hook.marketMaker(), MAKER);
        assertEq(address(hook.controller()), controller);

        // Ownership was assigned directly to the final owner.
        assertEq(hook.owner(), OWNER);

        // No pending two-step ownership transfer should exist.
        assertEq(hook.pendingOwner(), address(0));
    }
}
