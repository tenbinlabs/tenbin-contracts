// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PyriteFixtures} from "../helpers/PyriteFixtures.sol";
import {NewAssetDeployer} from "../helpers/NewAssetDeployer.sol";
import {LibVariable} from "forge-std/LibVariable.sol";
import {StdConfig} from "forge-std/StdConfig.sol";

/// forge-config: default.isolate = false
contract DeployNewAssetGuardsTest is PyriteFixtures {
    struct Inputs {
        NewAssetDeployer deployer;
        string asset;
        string vault;
        string market;
    }

    function freshInputs() internal returns (Inputs memory inputs) {
        vm.chainId(31337);
        string memory directory = string.concat("cache/test/pyrite-guards/", vm.toString(bytes32(msg.sig)), "/");
        (inputs.asset, inputs.vault) = writePyriteFixtures("sepolia", directory, "31337");
        inputs.market = string.concat(directory, "markets/tpyr_sepolia_stpyr_usdc_market.toml");
        inputs.deployer = new NewAssetDeployer(vm.addr(0x3456), string.concat(directory, "output"));
    }

    function test_RejectsRecordedMarketAddressesAndMockFeeds() public {
        Inputs memory inputs = freshInputs();
        string[4] memory fields = [string("collateral_token"), "oracle", "base_feed", "quote_feed"];
        string[4] memory errors = [
            string("market collateral already set"),
            "market oracle already set",
            "mock feeds must be fresh",
            "mock feeds must be fresh"
        ];
        for (uint256 i; i < fields.length; i++) {
            vm.writeToml(
                '"0x0000000000000000000000000000000000000001"',
                inputs.market,
                string.concat(".31337.address.", fields[i])
            );
            vm.expectRevert(bytes(errors[i]));
            inputs.deployer.run(inputs.asset, inputs.vault, true);
            resetPyriteAddress(inputs.market, "31337", fields[i]);
        }
    }

    function test_RequiresOneMarketAndItsAdapter() public {
        Inputs memory inputs = freshInputs();
        string memory original = vm.readFile(inputs.vault);
        vm.writeToml('["tpyr_sepolia_usdc_steakhousev2_adapter"]', inputs.vault, ".31337.string.adapters");
        vm.expectRevert("market adapter required");
        inputs.deployer.run(inputs.asset, inputs.vault, true);
        vm.writeFile(inputs.vault, original);
        vm.writeToml("[]", inputs.vault, ".31337.string.markets");
        vm.expectRevert("exactly one new market required");
        inputs.deployer.run(inputs.asset, inputs.vault, true);
        vm.writeToml('["first", "second"]', inputs.vault, ".31337.string.markets");
        vm.expectRevert("exactly one new market required");
        inputs.deployer.run(inputs.asset, inputs.vault, true);
    }

    function test_RejectsPartialDeploymentEntrypoints() public {
        Inputs memory inputs = freshInputs();
        vm.expectRevert("use Deploy for partial deployment");
        inputs.deployer.runCoreOnly(inputs.asset, true);
        vm.expectRevert("use Deploy for partial deployment");
        inputs.deployer.runVaultOnly(inputs.asset, inputs.vault);
    }

    function test_RejectsInvalidOrMissingStakingSeed() public {
        Inputs memory inputs = freshInputs();
        vm.writeToml("0", inputs.asset, ".31337.uint.staking_dead_deposit");
        vm.expectRevert("invalid staking dead deposit");
        inputs.deployer.run(inputs.asset, inputs.vault, true);
        vm.writeToml("1000000000000000", inputs.asset, ".31337.uint.staking_dead_deposit");
        vm.writeToml('"999999999999999"', inputs.asset, ".31337.string.mint_limit");
        vm.expectRevert("invalid staking dead deposit");
        inputs.deployer.run(inputs.asset, inputs.vault, true);
        vm.writeFile(inputs.asset, vm.replace(vm.readFile(inputs.asset), "staking_dead_deposit", "unused_seed"));
        vm.expectRevert(LibVariable.NotInitialized.selector);
        inputs.deployer.run(inputs.asset, inputs.vault, true);
    }

    function test_RejectsInvalidOrMissingMockPrice() public {
        Inputs memory inputs = freshInputs();
        vm.writeToml("0", inputs.asset, ".31337.uint.mock_oracle_price");
        vm.expectRevert("invalid mock price");
        inputs.deployer.run(inputs.asset, inputs.vault, true);
        vm.writeToml("9999999999", inputs.asset, ".31337.uint.mock_oracle_price");
        vm.expectRevert("invalid mock price");
        inputs.deployer.run(inputs.asset, inputs.vault, true);
        vm.writeToml(
            string.concat('"', vm.toString(uint256(type(int256).max) + 1), '"'),
            inputs.asset,
            ".31337.uint.mock_oracle_price"
        );
        vm.expectRevert("invalid mock price");
        inputs.deployer.run(inputs.asset, inputs.vault, true);
        vm.writeToml(vm.toString(type(uint256).max), inputs.asset, ".31337.uint.mock_oracle_price");
        vm.expectRevert(abi.encodeWithSelector(StdConfig.UnableToParseVariable.selector, "mock_oracle_price"));
        inputs.deployer.run(inputs.asset, inputs.vault, true);
        vm.writeToml("3500000000000000000000", inputs.asset, ".31337.uint.mock_oracle_price");
        vm.writeFile(inputs.asset, vm.replace(vm.readFile(inputs.asset), "mock_oracle_price", "unused_price"));
        vm.expectRevert(LibVariable.NotInitialized.selector);
        inputs.deployer.run(inputs.asset, inputs.vault, true);
    }
}
