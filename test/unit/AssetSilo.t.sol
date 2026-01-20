// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetSilo} from "src/AssetSilo.sol";
import {BaseTest} from "test/BaseTest.sol";

contract AssetSiloTest is BaseTest {
    function test_constructor() public view {
        assertEq(silo.staking(), address(staking));
    }

    function test_Revert_Withdraw() public {
        vm.expectRevert(AssetSilo.OnlyStaking.selector);
        silo.withdraw(address(1), 1e18);
    }

    function test_Withdraw() public {
        vm.prank(minter);
        mintAsset(address(silo), 1e18);

        vm.prank(address(staking));
        silo.withdraw(address(this), 1e18);

        assertEq(asset.balanceOf(address(silo)), 0);
        assertEq(asset.balanceOf(address(this)), 1e18);
    }

    function test_Cancel() public {
        mintAsset(address(silo), 1e18);
        vm.prank(address(staking));
        silo.cancel(user, 1e18);
        assertEq(staking.balanceOf(user), 1e18);
    }

    function test_Revert_Cancel() public {
        vm.prank(address(user));
        vm.expectRevert(AssetSilo.OnlyStaking.selector);
        silo.cancel(user, 1e18);
    }
}
