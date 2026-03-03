// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "../../../src/AssetToken.sol";
import {StakedAsset} from "../../../src/StakedAsset.sol";
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
        asset.approve(address(staking), type(uint256).max);
        staking.approve(address(this), type(uint256).max);
        vm.stopPrank();

        vm.prank(rewarder);
        asset.approve(address(this), type(uint256).max);
        asset.approve(address(staking), type(uint256).max);
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
        shares = bound(shares, 1e18, 1e40);
        stake(shares);

        // initiate cooldown
        vm.prank(user);
        staking.cooldownShares(user, shares);

        // fast forward to end of cooldown
        vm.warp(block.timestamp + 7 days);
    }

    function unstake(uint256 shares) public {
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
        stake(shares);
        withdraw(shares);
        uint256 maxShares = staking.balanceOf(user);
        uint256 amount = shares > maxShares ? maxShares : shares;
        vm.prank(user);
        staking.redeem(amount, user, user);
    }

    // helper to mint assets
    function mintAsset(address account, uint256 amount) internal {
        vm.prank(asset.minter());
        asset.mint(account, amount);
    }

    // helper to ensure stake balance
    function stake(uint256 amount) internal {
        // setup
        mintAsset(user, amount);
        vm.prank(admin);
        staking.setCooldownPeriod(7 days);

        // deposit
        vm.prank(user);
        staking.deposit(amount, user);
    }
}
