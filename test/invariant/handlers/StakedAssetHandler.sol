// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "src/AssetToken.sol";
import {StakedAsset} from "src/StakedAsset.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Handler to interact with the staking contract and save snapshots for invariant testing
contract StakedAssetHandler is Test {
    address admin;
    address rewarder;
    address user;
    uint256 public blockAtCooldown;
    StakedAsset staking;
    AssetToken asset;

    constructor(address _admin, address _rewarder, address _user, StakedAsset _staking, AssetToken _asset) {
        admin = _admin;
        rewarder = _rewarder;
        user = _user;
        staking = _staking;
        asset = _asset;

        vm.startPrank(user);
        asset.approve(address(this), type(uint256).max);
        staking.approve(address(this), type(uint256).max);
        vm.stopPrank();

        vm.prank(rewarder);
        asset.approve(address(this), type(uint256).max);
    }

    function reward(uint256 rewardAmount) public {
        rewardAmount = bound(rewardAmount, 0, 1e40);
        mintAsset(user, rewardAmount);
        mintAsset(rewarder, rewardAmount);

        // deposit
        vm.prank(user);
        staking.deposit(rewardAmount, user);

        vm.prank(rewarder);
        staking.reward(rewardAmount);
    }

    function cooldownShares(uint256 shares) public {
        shares = bound(shares, 0, 1e40);
        mintAsset(user, shares);
        vm.prank(admin);
        staking.setCooldownPeriod(7 days);

        // deposit
        vm.prank(user);
        shares = staking.deposit(shares, user);

        blockAtCooldown = block.timestamp;

        vm.prank(user);
        staking.cooldownShares(shares);
    }

    function unstake(uint256 shares) public {
        shares = bound(shares, 0, 1e40);
        cooldownShares(shares);

        // fast forward to end of cooldown
        vm.warp(block.timestamp + 7 days);

        // unstake
        vm.prank(user);
        staking.unstake(user);
    }

    function withdraw(uint256 assets) public {
        assets = bound(assets, 0, 1e40);
        reward(assets);

        vm.prank(admin);
        staking.setCooldownPeriod(0);

        uint256 amount = staking.maxWithdraw(user); // some times the rounding causes 1 wei difference so we need the actual max amount

        vm.prank(user);
        staking.withdraw(amount, user, user);
    }

    function redeem(uint256 shares) public {
        shares = bound(shares, 0, 1e40);

        withdraw(shares);

        vm.prank(user);
        asset.approve(address(this), staking.balanceOf(user));

        vm.prank(user);
        staking.redeem(staking.balanceOf(user), user, user);
    }

    // helper to mint assets
    function mintAsset(address account, uint256 amount) internal {
        vm.prank(asset.minter());
        asset.mint(account, amount);
    }
}
