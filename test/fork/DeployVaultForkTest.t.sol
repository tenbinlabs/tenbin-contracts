// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Config} from "forge-std/Config.sol";
import {DeployVault} from "script/DeployVault.s.sol";
import {ForkBaseTest} from "test/fork/ForkBaseTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IVaultV2} from "lib/vault-v2/src/interfaces/IVaultV2.sol";
import {IVaultV2Gates} from "test/external/morpho/IVaultV2Gates.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

// test deployment script
// this requires .env is set up correctly
contract DeployVaultForkTest is ForkBaseTest, Config {
    using SafeERC20 for IERC20;

    DeployVault.DeploymentResult deployment;
    DeployVault.VaultParams params;

    function setUp() public override {
        super.setUp();
        dealTo(usdc, broadcaster, 1e6);
        DeployVault deployer = new DeployVault();
        deployment = deployer.run();
    }

    function test_fork_DeployVault() public {
        _loadConfig("./config/vault.toml", false);
        // hard coded for redundancy. could read from config/vault.toml instead
        params.name = "tGLD USDC Vault";
        params.symbol = "tGLDv-USDC";
        params.allocator = 0x48Fa008bD2660974d55Ee9b7A9ECA1cE61347614;
        params.asset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        params.curator = 0xE6Eb534f33A635e8d867414Af32F766D221F30d1;
        params.initial_vault = 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB;
        params.owner = 0x698c6d3726846C4AD4Dc9331862b92Cd80D2fb99;
        params.sentinel = 0x44C24D0937A829B3057be462b0e069516f1D9D45;
        params.dead_deposit = 1_000000;
        params.initial_absolute_cap = 100_000_000_000000;
        params.initial_relative_cap = 1_000000000000000000;
        params.max_rate = 63419583967;
        params.timelock_duration = 172800;
        bytes32 adapter_id = keccak256(abi.encode("this", address(deployment.adapter)));
        uint256 asset_decimals = 6;

        // test config
        assertEq(deployment.vault.asset(), params.asset);
        assertEq(deployment.vault.name(), params.name);
        assertEq(deployment.vault.symbol(), params.symbol);
        assertEq(deployment.vault.owner(), params.owner);
        assertEq(deployment.vault.curator(), params.curator);
        assertEq(deployment.vault.isAllocator(params.allocator), true);
        assertEq(deployment.vault.isSentinel(params.sentinel), true);
        assertEq(deployment.vault.liquidityAdapter(), address(deployment.adapter));
        assertEq(deployment.vault.absoluteCap(adapter_id), params.initial_absolute_cap);
        assertEq(deployment.vault.relativeCap(adapter_id), params.initial_relative_cap);
        assertEq(deployment.vault.maxRate(), params.max_rate);
        assertEq(deployment.gate.owner(), params.curator);
        assertEq(IVaultV2Gates(address(deployment.vault)).receiveSharesGate(), address(deployment.gate));
        assertEq(IVaultV2Gates(address(deployment.vault)).sendSharesGate(), address(deployment.gate));
        assertEq(IVaultV2Gates(address(deployment.vault)).receiveAssetsGate(), address(deployment.gate));
        assertEq(IVaultV2Gates(address(deployment.vault)).sendAssetsGate(), address(deployment.gate));

        // ensure 1 share = 1 asset and dead deposit
        assertApproxEqAbs(deployment.vault.convertToAssets(1e18), 10 ** asset_decimals, 1);
        assertApproxEqAbs(deployment.vault.totalAssets(), params.dead_deposit, 1);

        // test timelock
        bytes4[] memory timelockedSelectors = new bytes4[](10);
        timelockedSelectors[0] = IVaultV2.setReceiveSharesGate.selector;
        timelockedSelectors[1] = IVaultV2.setSendSharesGate.selector;
        timelockedSelectors[2] = IVaultV2.setReceiveAssetsGate.selector;
        timelockedSelectors[3] = IVaultV2.addAdapter.selector;
        timelockedSelectors[4] = IVaultV2.increaseAbsoluteCap.selector;
        timelockedSelectors[5] = IVaultV2.increaseRelativeCap.selector;
        timelockedSelectors[6] = IVaultV2.setForceDeallocatePenalty.selector;
        timelockedSelectors[7] = IVaultV2.abdicate.selector;
        timelockedSelectors[8] = IVaultV2.removeAdapter.selector;
        timelockedSelectors[9] = IVaultV2.increaseTimelock.selector;

        // Submit timelock increases for all selectors
        for (uint256 i = 0; i < timelockedSelectors.length; i++) {
            assertEq(deployment.vault.timelock(timelockedSelectors[i]), params.timelock_duration);
        }
    }
}
