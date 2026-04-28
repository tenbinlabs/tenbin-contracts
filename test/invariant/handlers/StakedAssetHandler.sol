// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "../../../src/AssetToken.sol";
import {StakedAssetHarness} from "../../harness/StakedAssetHarness.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Handler to interact with the staking contract and save snapshots for invariant testing
contract StakedAssetHandler is Test {
    address admin;
    address rewarder;
    address user;
    mapping(uint256 => uint256) public blockAtCooldown;
    StakedAssetHarness staking;
    AssetToken asset;
    bool public idDecreased;
    uint256 public totalIntantUnStaked;

    constructor(address _admin, address _rewarder, address _user, StakedAssetHarness _staking, AssetToken _asset) {
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
        rewardAmount = bound(rewardAmount, 0, 1e18); //Avoid rewarding giant amounts
        mintAsset(rewarder, rewardAmount);

        vm.prank(rewarder);
        staking.reward(rewardAmount);
    }

    function cooldownShares(uint256 assets) public returns (uint256 id) {
        uint256 shares = stake(assets);
        assets = staking.convertToAssets(shares);
        uint256 prev = staking.cooldownIds(user);

        // initiate cooldown
        vm.prank(user);
        (, id) = staking.cooldownShares(shares);
        if (!idDecreased && staking.cooldownIds(user) < prev) idDecreased = true;
        blockAtCooldown[id] = block.number;

        // fast forward to end of cooldown
        vm.warp(block.timestamp + 7 days);
    }

    function cooldownAssets(uint256 assets) public returns (uint256 id) {
        uint256 shares = stake(assets);
        assets = staking.convertToAssets(shares);
        uint256 prev = staking.cooldownIds(user);

        // initiate cooldown
        vm.prank(user);
        (, id) = staking.cooldownAssets(assets);
        if (!idDecreased && staking.cooldownIds(user) < prev) idDecreased = true;
        blockAtCooldown[id] = block.number;

        // fast forward to end of cooldown
        vm.warp(block.timestamp + 7 days);
    }

    function unstake(uint256 shares) public {
        uint256 id = block.number % 2 == 0 ? cooldownAssets(staking.previewWithdraw(shares)) : cooldownShares(shares); //randomly call cooldownAssets or cooldownShares

        // fast forward to end of cooldown
        vm.warp(block.timestamp + 7 days);

        // unstake
        vm.prank(user);
        staking.unstake(user, id);
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
    function stake(uint256 amount) internal returns (uint256 shares) {
        // setup
        // Makes sure is enough to at least mint one share
        if (asset.balanceOf(address(staking)) > 0) {
            uint256 sharePrice = staking.convertToAssets(1);
            amount = bound(amount, sharePrice, asset.totalSupply());
        } else {
            // if no shares it would return the share price as 0
            amount = bound(amount, 1e18, 1e40);
        }
        mintAsset(user, amount);
        vm.prank(admin);
        staking.setCooldownPeriod(7 days);

        // deposit
        vm.prank(user);
        shares = staking.deposit(amount, user);
    }

    function instantUnstake(uint256 assets) external {
        // setup
        uint256 shares = stake(assets);
        assets = staking.convertToAssets(shares);
        vm.prank(user);
        staking.approve(address(this), assets);

        shares = staking.instantUnstake(assets, user, user);
        totalIntantUnStaked += assets;
    }
}
