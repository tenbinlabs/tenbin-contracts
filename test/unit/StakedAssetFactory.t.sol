// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "src/AssetToken.sol";
import {StakedAsset} from "src/StakedAsset.sol";
import {StakedAssetFactory} from "script/StakedAssetFactory.s.sol";
import {Test} from "forge-std/Test.sol";

contract StakedAssetFactoryTest is Test {
    address owner = vm.addr(0xB00D);
    address preComputedAddress = 0xAc9041542324Fb96D7c51DdC7e508A859436e291;

    AssetToken internal asset;
    StakedAsset internal staking;
    StakedAssetFactory internal factory;

    function test_CreateStakedAsset() public virtual {
        address payer = address(1);
        bytes32 salt = bytes32(abi.encodePacked("salt"));
        factory = new StakedAssetFactory(owner);
        asset = new AssetToken("AssetToken", "SYN", owner);
        vm.prank(owner);
        asset.setMinter(address(this));
        // simulates a mint order going thought the controller with the payer as receiver.
        asset.mint(payer, 1e18);

        vm.prank(payer);
        asset.approve(address(factory), 1e18);

        vm.startPrank(owner);
        vm.expectEmit(false, false, false, false);
        emit StakedAssetFactory.StakingCreated(preComputedAddress);
        staking = factory.createStakedAsset(payer, salt, "test", "TST", address(asset), owner);
        vm.stopPrank();

        assertEq(staking.totalAssets(), 1e18);
        assertEq(staking.totalSupply(), 1e18);
        assertEq(staking.name(), "test");
        assertEq(staking.symbol(), "TST");
        assertEq(staking.asset(), address(asset));
    }
}
