// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Config} from "forge-std/Config.sol";
import {DeploySwapModule} from "../../script/DeploySwapModule.s.sol";
import {SwapModule} from "tenbin-contracts/src/SwapModule.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {stdToml} from "forge-std/StdToml.sol";

// test deployment script
// this requires .env is set up correctly
contract DeploySwapModuleForkTest is ForkBaseTest, Config {
    using stdToml for string;

    string constant TARGET_VERSION = "1.4.3";
    address constant ASSET_TOKEN_ADDRESS = 0x067f03Be93c7Dcd21C3eB700f58203F514c2Be1A;
    address constant MANAGER_ADDRESS = 0x7d673FC54632a4cb8B31e6AD5678aA1Fd834A528;

    DeploySwapModule.CoreParameters params;
    DeploySwapModule.RolesParameters roles;
    DeploySwapModule.DeploymentResult deployment;
    string constant CONFIG_DIR = "./config/mainnet/tgld/tgld.toml";

    function setUp() public override {
        super.setUp();
        DeploySwapModule deployer = new DeploySwapModule();
        deployment = deployer.run(CONFIG_DIR);
    }

    function test_fork_DeploySwapModule() public {
        _loadConfig(CONFIG_DIR, false);
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory toml = vm.readFile(CONFIG_DIR);

        // addresses
        roles.admin_role = vm.parseTomlAddress(toml, ".mainnet.address.admin_role");
        params.one_inch_router = vm.parseTomlAddress(toml, ".mainnet.address.one_inch_router");

        // check swapModule is correctly configured
        // Manager must match correct one
        assertEq(SwapModule(deployment.swap_module).manager(), MANAGER_ADDRESS);

        // Admin must match correct one
        assertTrue(SwapModule(deployment.swap_module).admin() == roles.admin_role);

        // Router must match correct one
        assertEq(SwapModule(deployment.swap_module).router(), params.one_inch_router);
    }
}
