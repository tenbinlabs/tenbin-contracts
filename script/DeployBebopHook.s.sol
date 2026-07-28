// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseScript} from "./Base.s.sol";
import {BebopHook} from "../src/external/bebop/BebopHook.sol";
import {console2} from "forge-std/console2.sol";
import {Config} from "forge-std/Config.sol";

/// @notice Deploy BebopHook
/// @dev Before running verify the controllers, OWNER, ROUTER and MAKER addresses.
/// Deploys a hook for every controller
/// FOUNDRY_PROFILE=production forge script script/DeployBebopHook.s.sol --rpc-url $MAINNET_RPC_URLL --private-key $BROADCASTER_KEY --slow --verify --verifier etherscan --verifier-api-key $ETHERSCAN_API_KEY
// Add --broadcast to broadcast
contract DeployBebopHook is BaseScript, Config {
    // controllers
    address constant TBRL_CONTROLLER = 0x0EF47CC8E244dBc8628FdEfFD4EE4DD747d14081;
    address constant TGLD_CONTROLLER = 0x5e631388b24ec493619DAEEAef6fc34B33d97Dcd;
    address constant TMXN_CONTROLLER = 0xB5EBDeC6DA02119DD7BEB4782C181261f8BfEcC2;

    // owner multisig
    address constant OWNER = 0x698c6d3726846C4AD4Dc9331862b92Cd80D2fb99;

    // General parameters
    address constant ROUTER = 0xBeb0009ACa35087ce7cCF11637E24dd1Aad3bf2A; // bebop mainnet router
    address constant MAKER = 0x143eC4305186064c77a4682Dc982b49692ba305c; // tenbin market maker

    function run() public returns (address[] memory controllers, address[] memory hooks) {
        (controllers, hooks) = deployHooks();
    }

    // deploy bebop hooks for all controllers
    function deployHooks() internal broadcast returns (address[] memory controllers, address[] memory hooks) {
        controllers = new address[](3);
        hooks = new address[](3);
        controllers[0] = TBRL_CONTROLLER;
        controllers[1] = TGLD_CONTROLLER;
        controllers[2] = TMXN_CONTROLLER;
        hooks[0] = address(new BebopHook(ROUTER, MAKER, controllers[0], OWNER));
        hooks[1] = address(new BebopHook(ROUTER, MAKER, controllers[1], OWNER));
        hooks[2] = address(new BebopHook(ROUTER, MAKER, controllers[2], OWNER));
        printLogo();
        console2.log("\n========================= HOOK ADDRESSES =========================\n\n");
        console2.log("TBRL Hook: ", hooks[0]);
        console2.log("TGLD Hook: ", hooks[1]);
        console2.log("TMXN Hook: ", hooks[2]);
        console2.log("\n==================================================================\n");
    }
}
