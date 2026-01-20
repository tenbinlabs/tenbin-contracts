// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {Initializable} from "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {IRestrictedRegistry} from "src/interface/IRestrictedRegistry.sol";
import {IStakedAsset} from "src/interface/IStakedAsset.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {StakedAsset} from "src/StakedAsset.sol";
import {StakedAssetPause} from "test/mocks/StakedAssetPause.sol";

contract StakedAssetTest is BaseTest {
    function test_StakedAsset_Initialize() public view {
        assertEq(staking.name(), "Staked Asset");
        assertEq(staking.symbol(), "stAST");
        assertEq(staking.asset(), address(asset));
        assertEq(manager.hasRole(DEFAULT_ADMIN_ROLE, owner), true);
    }

    function test_Revert_StakedAsset_Initialize() public {
        StakedAsset stakingImplementation = new StakedAsset();

        // cannot initialize again
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        manager.initialize(address(controller), address(this));

        // cannot initialize implementation
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        stakingImplementation.initialize("Staked Asset", "stAST", address(asset), owner);

        // test failed initialization cases
        bytes memory data = abi.encodeWithSelector(StakedAsset.initialize.selector, "", "", address(0), address(this));
        vm.expectRevert(IStakedAsset.NonZeroAddress.selector);
        StakedAsset(address(new ERC1967Proxy(address(stakingImplementation), data)));

        data = abi.encodeWithSelector(StakedAsset.initialize.selector, "", "", address(asset), address(0));
        vm.expectRevert(IStakedAsset.NonZeroAddress.selector);
        StakedAsset(address(new ERC1967Proxy(address(stakingImplementation), data)));
    }

    function test_Revert_StakedAsset_UpgradeToAndCall() public {
        address newImplementation = address(new StakedAssetPause());
        address badImplementation = address(new MockERC20("mock", "mock", 18));

        // revert if not default admin role
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        manager.upgradeToAndCall(newImplementation, new bytes(0));

        // revert if implementation is not UUPS
        vm.expectPartialRevert(ERC1967Utils.ERC1967InvalidImplementation.selector);
        vm.prank(owner);
        manager.upgradeToAndCall(badImplementation, new bytes(0));
    }

    function test_StakedAsset_UpgradeToAndCall() public {
        address newImplementation = address(new StakedAssetPause());
        vm.prank(owner);
        staking.upgradeToAndCall(newImplementation, new bytes(0));

        // check implementation slot to ensure new implementation is correct
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assertEq(abi.encode(vm.load(address(staking), slot)), abi.encode(newImplementation));

        // ensure roles are still valid after upgrade
        assertEq(staking.hasRole(DEFAULT_ADMIN_ROLE, owner), true);
        assertEq(staking.hasRole(ADMIN_ROLE, admin), true);
        assertEq(staking.hasRole(REWARDER_ROLE, rewarder), true);
        assertEq(staking.hasRole(RESTRICTER_ROLE, restricter), true);

        // expect all interface functions to revert based on the new implementation
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.decimals();
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.name();
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.symbol();
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.totalSupply();
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.balanceOf(address(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        staking.transfer(address(0), uint256(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        staking.transferFrom(address(0), address(0), uint256(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.approve(address(0), uint256(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.allowance(address(0), address(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.asset();
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.totalAssets();
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.convertToAssets(uint256(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.convertToShares(uint256(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.deposit(uint256(0), address(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.mint(uint256(0), address(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.withdraw(uint256(0), address(0), address(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.redeem(uint256(0), address(0), address(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.previewDeposit(uint256(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.previewMint(uint256(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.previewWithdraw(uint256(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.previewRedeem(uint256(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.maxDeposit(address(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.maxMint(address(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.maxWithdraw(address(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.maxRedeem(address(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.pendingRewards();
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.reward(uint256(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.cooldownShares(address(0), uint256(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.cooldownAssets(address(0), uint256(0));
        vm.expectRevert(StakedAssetPause.ContractPaused.selector);
        staking.unstake(address(0));

        // upgrade back to original implementation
        newImplementation = address(new StakedAsset());
        vm.prank(owner);
        staking.upgradeToAndCall(newImplementation, new bytes(0));

        // check implementation slot to ensure new implementation is correct
        slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assertEq(abi.encode(vm.load(address(staking), slot)), abi.encode(newImplementation));

        // check some functions return correct values
        assertEq(staking.asset(), address(asset));
    }

    function test_Decimals() public view {
        assertEq(staking.decimals(), 18);
    }

    function test_Revert_Deposit() public {
        mintAsset(user, 1000e18);
        address restrictedAddress = address(1);
        vm.prank(restricter);
        staking.setIsRestricted(restrictedAddress, true);

        // restricted receiver
        vm.prank(user);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        staking.deposit(1000e18, restrictedAddress);

        assertEq(staking.balanceOf(restrictedAddress), 0);

        // restricted sender
        vm.prank(restrictedAddress);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        staking.deposit(1000e18, user);

        assertEq(staking.balanceOf(user), 0);
    }

    function test_Deposit() public {
        mintAsset(user, 1000e18);

        vm.prank(user);
        uint256 shares = staking.deposit(1000e18, user);

        assertEq(shares, 1000e18);
    }

    function test_Revert_Mint() public {
        address restrictedAddress = address(1);
        vm.prank(restricter);
        staking.setIsRestricted(restrictedAddress, true);

        // restricted receiver
        vm.prank(user);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        staking.mint(1000e18, restrictedAddress);

        assertEq(staking.balanceOf(restrictedAddress), 0);

        // restricted sender
        vm.prank(restrictedAddress);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        staking.mint(1000e18, user);

        assertEq(staking.balanceOf(user), 0);
    }

    function test_Mint() public {
        mintAsset(user, 1000e18);
        vm.prank(user);
        uint256 assets = staking.mint(1000e18, user);

        assertEq(assets, 1000e18);
    }

    function test_Revert_Unstake_Access() public {
        // setup
        mintAsset(user, 1000e18);
        vm.prank(admin);
        staking.setCooldownPeriod(7 days);

        // deposit
        vm.prank(user);
        staking.deposit(1000e18, user);

        // initiate cooldown
        vm.prank(user);
        staking.cooldownShares(user, 1000e18); // Avoid falling below 0
        (uint256 assets, uint256 end) = staking.cooldowns(user);
        assertEq(end, block.timestamp + 7 days);
        assertEq(assets, 1000e18);

        // fast forward to end of cooldown
        vm.warp(block.timestamp + 7 days);

        // unstake
        vm.prank(restricter);
        staking.setIsRestricted(user, true);

        vm.prank(user);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector); // restricted sender
        staking.unstake(user);

        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector); // restricted to
        staking.unstake(user);

        assertEq(staking.balanceOf(user), 0);
        assertEq(asset.balanceOf(address(silo)), 1000e18);

        // Removing restriction allows interaction
        vm.prank(restricter);
        staking.setIsRestricted(user, false);

        vm.prank(user);
        staking.unstake(user);

        assertEq(staking.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), 1000e18);
    }

    function test_Revert_RestrictedRegistry_Transfer() public {
        // forge-lint: disable-start(erc20-unchecked-transfer)
        address user2 = vm.addr(0xC001);
        // setup
        mintAsset(user, 1000e18);
        mintAsset(user2, 1000e18);

        // deposit
        vm.startPrank(user);
        staking.deposit(1000e18, user);
        vm.startPrank(user2);
        asset.approve(address(staking), type(uint256).max);
        staking.deposit(1000e18, user2);
        vm.stopPrank();

        // restrict user
        vm.prank(restricter);
        staking.setIsRestricted(user, true);

        // can't transfer assets from a non-restricted account
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        vm.prank(user);
        staking.transfer(address(this), 1000e18);

        // can't transfer assets to a non-restricted account
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        vm.prank(user2);
        staking.transfer(user, 1000e18);

        // can't call transfer assets from a restricted account
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        vm.prank(user);
        staking.transferFrom(user2, user2, 1000e18);

        // can't transfer assets to a non-restricted account
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        vm.prank(user2);
        staking.transferFrom(user, user2, 1000e18);

        // can't transfer assets to a non-restricted account
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        vm.prank(user2);
        staking.transferFrom(user2, user, 1000e18);

        // forge-lint: disable-end(erc20-unchecked-transfer)
    }

    function test_transfers() public {
        address user2 = vm.addr(0xC001);
        // setup
        mintAsset(user, 2000e18);

        // deposit
        vm.prank(user);
        staking.deposit(2000e18, user);

        // transfers
        vm.startPrank(user);
        staking.approve(user, 1000e18);
        bool success = staking.transferFrom(user, user2, 1000e18);

        bool success2 = staking.transfer(user2, 1000e18);
        vm.stopPrank();

        assertTrue(success);
        assertTrue(success2);
        assertEq(staking.balanceOf(user), 0);
        assertEq(staking.balanceOf(user2), 2000e18);
    }

    function test_Revert_TransferRestrictedAssets() public {
        // setup
        mintAsset(user, 1000e18);
        vm.prank(admin);
        staking.setCooldownPeriod(7 days);

        // deposit
        vm.prank(user);
        staking.deposit(1000e18, user);

        // only default admin can transfer restricted assets
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        staking.transferRestrictedAssets(user, address(this));

        vm.startPrank(owner);
        // can't transfer assets for a non-restricted account
        vm.expectRevert(IStakedAsset.NonRestrictedAccount.selector);
        staking.transferRestrictedAssets(user, address(this));

        // cannot specify address(0) when transferring restricted assets
        vm.expectRevert(IStakedAsset.NonZeroAddress.selector);
        staking.transferRestrictedAssets(user, address(0));
    }

    function test_TransferRestrictedAssets() public {
        // First deposit that happens at deployment
        test_Deposit();
        // setup
        address restricted = address(2);

        mintAsset(restricted, 1000e18);
        vm.prank(restricted);
        asset.approve(address(staking), 1000e18);
        vm.prank(admin);
        staking.setCooldownPeriod(7 days);

        // deposit
        vm.prank(restricted);
        staking.deposit(1000e18, restricted);

        // restrict user
        vm.prank(restricter);
        staking.setIsRestricted(restricted, true);

        // successful transfer
        vm.prank(owner);
        staking.transferRestrictedAssets(restricted, address(this));
        assertEq(staking.balanceOf(restricted), 0);
        assertEq(asset.balanceOf(address(staking)), 1000e18);
        assertEq(asset.balanceOf(address(this)), 1000e18);
    }

    function test_Cooldown_TransferRestrictedAssets() public {
        // First deposit that happens at deployment
        test_Deposit();
        // setup
        address restricted = address(2);
        mintAsset(restricted, 1000e18);
        vm.prank(restricted);
        asset.approve(address(staking), 1000e18);
        vm.prank(admin);
        staking.setCooldownPeriod(7 days);

        // deposit
        vm.prank(restricted);
        staking.deposit(1000e18, restricted);

        // cooldowns asset
        vm.prank(restricted);
        staking.cooldownAssets(restricted, 1000e18);

        // restrict user
        vm.prank(restricter);
        staking.setIsRestricted(restricted, true);

        //execute transfer
        vm.prank(owner);
        staking.transferRestrictedAssets(restricted, address(this));

        // successful transfer
        assertEq(staking.balanceOf(restricted), 0);
        assertEq(asset.balanceOf(address(staking)), 1000e18);
        assertEq(asset.balanceOf(address(this)), 1000e18);
    }

    function test_Revert_Withdraw() public {
        // setup
        address restrictedAddress = address(1);
        vm.prank(restricter);
        staking.setIsRestricted(restrictedAddress, true);

        // ensure withdrawal reverts for receiver
        vm.startPrank(user);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        staking.withdraw(1000e18, restrictedAddress, user);

        // ensure withdrawal reverts for owner
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        staking.withdraw(1000e18, user, restrictedAddress);
        vm.stopPrank();

        // ensure withdrawal reverts for caller
        vm.prank(restrictedAddress);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        staking.withdraw(1000e18, user, user);
    }

    function test_Revert_Redeem() public {
        // setup
        address restrictedAddress = address(1);
        vm.prank(restricter);
        staking.setIsRestricted(restrictedAddress, true);

        // ensure redeem reverts for receiver
        vm.startPrank(user);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        staking.redeem(1000e18, restrictedAddress, user);

        // ensure redeem reverts for owner
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        staking.redeem(1000e18, user, restrictedAddress);
        vm.stopPrank();

        // ensure redeem reverts for caller
        vm.prank(restrictedAddress);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        staking.redeem(1000e18, user, user);
    }

    function test_Revert_Reward() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        staking.reward(1000e18);
    }

    function test_Reward() public {
        // setup
        mintAsset(user, 1000e18);
        mintAsset(rewarder, 1000e18);

        // deposit
        vm.prank(user);
        staking.deposit(1000e18, user);

        // reward with no vesting period
        vm.prank(rewarder);
        staking.reward(1000e18);
        (,, uint256 amountVesting) = staking.vesting();
        assertEq(amountVesting, 0);
        assertEq(asset.balanceOf(address(staking)), 2000e18);
        assertEq(staking.balanceOf(user), 1000e18);
        assertApproxEqAbs(staking.convertToAssets(1000e18), 2000e18, VAULT_TOLERANCE);

        // ensure withdrawal grants correct amount
        vm.prank(user);
        staking.withdraw(1000e18, user, user);
        assertApproxEqAbs(staking.balanceOf(address(user)), 500e18, VAULT_TOLERANCE);
        assertEq(asset.balanceOf(address(user)), 1000e18);
        assertApproxEqAbs(asset.balanceOf(address(staking)), 1000e18, VAULT_TOLERANCE);

        // redeem
        vm.prank(user);
        staking.redeem(250e18, user, user);

        assertApproxEqAbs(staking.balanceOf(address(user)), 250e18, VAULT_TOLERANCE);
        assertApproxEqAbs(asset.balanceOf(address(user)), 1500e18, VAULT_TOLERANCE);
    }

    function test_Reward_Update() public {
        // mint some asset tokens
        mintAsset(rewarder, 2000e18);
        mintAsset(user, 1000e18);

        // set vesting period
        vm.prank(admin);
        staking.setVestingPeriod(7 days);

        // mint some staking tokens
        vm.prank(user);
        staking.deposit(1000e18, user);

        // start vesting
        vm.prank(rewarder);
        staking.reward(1000e18);
        assertEq(staking.totalAssets(), 1000e18);
        assertEq(staking.pendingRewards(), 1000e18);

        // fast forward 25% through reward period
        vm.warp(block.timestamp + 7 days / 4);

        // reward the contract again
        vm.prank(rewarder);
        staking.reward(1000e18);
        (uint256 period, uint256 time, uint256 amountVesting) = staking.vesting();
        assertEq(period, 7 days);
        assertEq(time, block.timestamp + 7 days);
        assertEq(amountVesting, 1750e18);
        assertEq(staking.totalAssets(), 1250e18);
        assertEq(staking.pendingRewards(), 1750e18);

        // fast forward through reward period
        vm.warp(block.timestamp + 7 days);
        assertEq(amountVesting, 1750e18);
        assertEq(staking.totalAssets(), 3000e18);
        assertEq(staking.pendingRewards(), 0);

        // make a withdrawal
        vm.prank(user);
        staking.redeem(1000e18, user, user);
        assertApproxEqAbs(staking.totalAssets(), 0, VAULT_TOLERANCE);
        assertApproxEqAbs(asset.balanceOf(user), 3000e18, VAULT_TOLERANCE);
    }

    function test_SetVestingPeriod() public {
        // setup
        mintAsset(user, 1000e18);
        mintAsset(rewarder, 2000e18);

        // deposit
        vm.prank(user);
        staking.deposit(1000e18, user);

        // set vesting
        vm.expectEmit();
        emit IStakedAsset.VestingPeriodUpdated(2 days);
        vm.prank(admin);
        staking.setVestingPeriod(2 days);

        // reward contract (starts vesting period)
        vm.prank(rewarder);
        staking.reward(1000e18);

        // allow one day to pass
        vm.warp(block.timestamp + 1 days);

        // set new vesting period
        vm.expectEmit();
        emit IStakedAsset.VestingStarted(500e18, block.timestamp + 4 days);
        vm.expectEmit();
        emit IStakedAsset.VestingPeriodUpdated(4 days);
        vm.prank(admin);
        staking.setVestingPeriod(4 days);

        // ensure correct state
        (uint256 period, uint256 time, uint256 amountVesting) = staking.vesting();
        assertEq(staking.pendingRewards(), 500e18);
        assertEq(period, 4 days);
        assertEq(time, block.timestamp + 4 days);
        assertEq(amountVesting, 500e18);

        // rewards are correctly vested after period ends
        vm.warp(block.timestamp + 4 days);
        (period, time, amountVesting) = staking.vesting();
        assertEq(staking.pendingRewards(), 0);
        assertEq(time, block.timestamp);
    }

    function test_Revert_SetVestingPeriod() public {
        // only admin can set vesting period
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        staking.setVestingPeriod(7 days);

        // cannot exceed max vesting period
        vm.prank(admin);
        vm.expectRevert(IStakedAsset.ExceedsMaxVestingPeriod.selector);
        staking.setVestingPeriod(91 days);

        vm.prank(admin);
        vm.expectRevert(IStakedAsset.SubceedsMinVestingPeriod.selector);
        staking.setVestingPeriod(800 seconds);

        // set vesting
        vm.prank(admin);
        staking.setVestingPeriod(7 days);
    }

    function test_Vesting() public {
        // setup
        mintAsset(user, 1000e18);
        mintAsset(rewarder, 1000e18);

        // deposit
        vm.prank(user);
        staking.deposit(1000e18, user);

        // set vesting
        vm.prank(admin);
        staking.setVestingPeriod(7 days);

        // reward contract
        vm.prank(rewarder);
        vm.expectEmit();
        emit IStakedAsset.VestingStarted(1000e18, block.timestamp + 7 days);
        emit IStakedAsset.RewardsReceived(1000e18);
        staking.reward(1000e18);
        (uint256 period, uint256 time, uint256 amountVesting) = staking.vesting();
        assertEq(period, 7 days);
        assertEq(time, block.timestamp + 7 days);
        assertEq(amountVesting, 1000e18);
        assertEq(staking.pendingRewards(), 1000e18);
        assertEq(staking.totalAssets(), 1000e18);
        assertEq(asset.balanceOf(address(staking)), 2000e18);
        assertEq(staking.balanceOf(user), 1000e18);
        assertApproxEqAbs(staking.convertToAssets(1000e18), 1000e18, VAULT_TOLERANCE);

        // simulate 50% of vesting time
        vm.warp(block.timestamp + 7 days / 2);

        // ensure 50% of reward is vested
        assertEq(staking.pendingRewards(), 500e18);
        assertEq(staking.totalAssets(), 1500e18);
        assertApproxEqAbs(staking.convertToAssets(1000e18), 1500e18, VAULT_TOLERANCE);

        // redeem 50% of shares 50% through vesting
        vm.prank(user);
        staking.redeem(500e18, user, user);
        assertEq(staking.balanceOf(address(user)), 500e18);
        assertApproxEqAbs(asset.balanceOf(address(user)), 750e18, VAULT_TOLERANCE);
        assertApproxEqAbs(staking.totalAssets(), 750e18, VAULT_TOLERANCE);

        // simulate 50% of vesting time
        vm.warp(block.timestamp + 7 days);

        // ensure assets and reward calculated correctly
        assertEq(staking.pendingRewards(), 0);
        assertApproxEqAbs(staking.totalAssets(), 1250e18, VAULT_TOLERANCE);
        assertApproxEqAbs(staking.convertToAssets(500e18), 1250e18, VAULT_TOLERANCE);

        // redeem 50% after vesting
        vm.startPrank(user);
        staking.redeem(500e18, user, user);
        assertEq(staking.balanceOf(address(user)), 0);
        assertApproxEqAbs(asset.balanceOf(address(user)), 2000e18, VAULT_TOLERANCE);
    }

    function test_fuzz_Vesting(uint256 depositAmount, uint256 rewardAmount, uint32 vestingPeriod) public {
        depositAmount = bound(depositAmount, 4e18, 1e30);
        rewardAmount = bound(rewardAmount, 4e18, 1e30);
        uint256 vestingTime = bound(uint256(vestingPeriod), 1200 seconds, staking.MAX_VESTING_PERIOD());
        uint256 startTimestamp = block.timestamp;
        uint256 redeemCounter;
        // setup
        mintAsset(user, depositAmount);
        mintAsset(rewarder, rewardAmount);

        // deposit
        vm.prank(user);
        staking.deposit(depositAmount, user);

        // set vesting
        vm.prank(admin);
        // forge-lint: disable-next-line(unsafe-typecast)
        staking.setVestingPeriod(uint128(vestingTime));

        // reward contract
        vm.prank(rewarder);
        staking.reward(rewardAmount);
        (uint256 period, uint256 time, uint256 amountVesting) = staking.vesting();
        assertEq(period, vestingTime);
        assertEq(time, block.timestamp + vestingTime);
        assertEq(amountVesting, rewardAmount);
        assertEq(staking.pendingRewards(), rewardAmount);
        assertEq(staking.totalAssets(), depositAmount);
        assertEq(asset.balanceOf(address(staking)), depositAmount + rewardAmount);
        assertEq(staking.balanceOf(user), depositAmount);
        assertApproxEqAbs(staking.convertToAssets(depositAmount), depositAmount, VAULT_TOLERANCE);

        // simulate 50% of vesting time
        vm.warp(startTimestamp + vestingTime / 2);

        // ensure 50% of reward is vested
        assertApproxEqRel(staking.pendingRewards(), rewardAmount / 2, FUZZ_TOLERANCE_REL);
        assertApproxEqRel(staking.totalAssets(), depositAmount + rewardAmount / 2, FUZZ_TOLERANCE_REL);
        assertApproxEqRel(staking.convertToAssets(depositAmount), depositAmount + rewardAmount / 2, FUZZ_TOLERANCE_REL);

        // redeem 50% of shares 50% through vesting
        uint256 expectedWithdraw = depositAmount / 2 + rewardAmount / 4;
        vm.startPrank(user);
        redeemCounter += staking.redeem(depositAmount / 2, user, user);
        assertApproxEqRel(staking.balanceOf(address(user)), depositAmount / 2, FUZZ_TOLERANCE_REL);
        assertApproxEqRel(asset.balanceOf(address(user)), expectedWithdraw, FUZZ_TOLERANCE_REL);
        assertApproxEqRel(
            staking.totalAssets(), depositAmount + rewardAmount / 2 - expectedWithdraw, FUZZ_TOLERANCE_REL
        );

        // simulate 50% of vesting time
        vm.warp(startTimestamp + vestingTime);

        // ensure assets and reward calculated correctly
        assertEq(staking.pendingRewards(), 0);
        assertApproxEqRel(staking.totalAssets(), depositAmount + rewardAmount - expectedWithdraw, FUZZ_TOLERANCE_REL);
        assertApproxEqRel(
            staking.convertToAssets(depositAmount / 2),
            depositAmount + rewardAmount - expectedWithdraw,
            FUZZ_TOLERANCE_REL
        );

        // redeem 50% after vesting
        redeemCounter += staking.redeem(staking.balanceOf(address(user)), user, user);
        assertEq(staking.balanceOf(address(user)), 0);
        assertApproxEqRel(asset.balanceOf(address(user)), redeemCounter, FUZZ_TOLERANCE_REL);
        vm.stopPrank();
    }

    function test_Revert_SetCooldownPeriod() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        staking.setCooldownPeriod(91 days);

        vm.prank(admin);
        vm.expectRevert(IStakedAsset.ExceedsMaxCooldownPeriod.selector);
        staking.setCooldownPeriod(91 days);
    }

    function test_SetCooldownPeriod() public {
        vm.prank(admin);
        staking.setCooldownPeriod(7 days);
        assertEq(staking.cooldownPeriod(), 7 days);
    }

    function test_Revert_CooldownShares() public {
        // setup
        address restrictedAddress = address(1);
        vm.prank(restricter);
        staking.setIsRestricted(restrictedAddress, true);
        mintAsset(user, 1000e18);
        vm.prank(admin);
        staking.setCooldownPeriod(7 days);

        // ensure cooldown reverts for restricted caller
        vm.prank(restrictedAddress);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        staking.cooldownShares(user, 500e18);

        vm.startPrank(user);

        // cannot cooldown zero shares
        vm.expectRevert(IStakedAsset.InvalidCooldownAmount.selector);
        staking.cooldownShares(user, 0);

        // deposit and initiate cooldown
        staking.deposit(1000e18, user);
        staking.cooldownShares(user, 500e18);

        // revert if trying to unstake before cooldown
        vm.expectRevert(IStakedAsset.CooldownInProgress.selector);
        staking.unstake(user);

        // cannot cooldown more shares than user has
        vm.expectRevert(IStakedAsset.CooldownExceededMaxRedeem.selector);
        staking.cooldownShares(user, 1100e18);

        // cannot use withdraw function when cooldown enabled
        vm.expectRevert(IStakedAsset.RequiresCooldown.selector);
        staking.withdraw(500e18, user, user);

        // cannot use redeem function when cooldown enabled
        vm.expectRevert(IStakedAsset.RequiresCooldown.selector);
        staking.redeem(500e18, user, user);
        vm.stopPrank();

        // cannot be called by a spender with no allowance
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        staking.cooldownShares(user, 500e18);
    }

    function test_CooldownShares() public {
        // setup
        mintAsset(user, 1000e18);
        vm.prank(admin);
        staking.setCooldownPeriod(7 days);

        // deposit
        vm.prank(user);
        staking.deposit(1000e18, user);

        // initiate cooldown for 1/2 shares
        vm.prank(user);
        staking.cooldownShares(user, 500e18);
        (uint256 assets, uint256 end) = staking.cooldowns(user);
        assertEq(end, block.timestamp + 7 days);
        assertEq(assets, 500e18);

        // fast forward to end of cooldown
        vm.warp(block.timestamp + 7 days);

        // unstake
        vm.prank(user);
        staking.unstake(user);
        (assets, end) = staking.cooldowns(user);
        assertEq(end, 0);
        assertEq(assets, 0);
        assertApproxEqAbs(asset.balanceOf(user), 500e18, VAULT_TOLERANCE);
        assertEq(staking.balanceOf(user), 500e18);

        // initiate cooldown for more shares by approved account. should reset cooldown
        vm.prank(user);
        staking.approve(address(this), 400e18);

        staking.cooldownShares(user, 400e18);
        (assets, end) = staking.cooldowns(user);
        assertEq(end, block.timestamp + 7 days);
        assertEq(assets, 400e18);
        assertEq(staking.allowance(user, address(this)), 0);

        // fast forward past end of cooldown
        vm.warp(block.timestamp + 10 days);

        // unstake
        vm.prank(user);
        staking.unstake(user);
        (assets, end) = staking.cooldowns(user);
        assertEq(end, 0);
        assertEq(assets, 0);

        assertApproxEqAbs(asset.balanceOf(user), 900e18, VAULT_TOLERANCE);
        assertEq(staking.balanceOf(user), 100e18);
    }

    function test_Revert_CooldownAssets() public {
        uint256 max = staking.maxWithdraw(user) + 1;
        address restrictedAddress = address(1);
        vm.prank(restricter);
        staking.setIsRestricted(restrictedAddress, true);

        // cannot cooldown zero assets
        vm.expectRevert(IStakedAsset.InvalidCooldownAmount.selector);
        staking.cooldownAssets(user, 0);

        vm.expectRevert(IStakedAsset.CooldownExceededMaxWithdraw.selector);
        vm.prank(user);
        staking.cooldownAssets(user, max);

        // ensure cooldown reverts for restricted caller
        vm.prank(restrictedAddress);
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        staking.cooldownAssets(user, max);
    }

    function test_CooldownAssets() public {
        // setup
        mintAsset(user, 1000e18);
        vm.prank(admin);
        staking.setCooldownPeriod(7 days);

        // deposit
        vm.prank(user);
        staking.deposit(1000e18, user);

        // initiate cooldown for 1/2 shares
        vm.prank(user);
        staking.cooldownAssets(user, 500e18);
        (uint256 assets, uint256 end) = staking.cooldowns(user);
        assertEq(end, block.timestamp + 7 days);
        assertEq(assets, 500e18);

        // fast forward to end of cooldown
        vm.warp(block.timestamp + 7 days);

        // unstake
        vm.prank(user);
        staking.unstake(user);
        (assets, end) = staking.cooldowns(user);
        assertEq(end, 0);
        assertEq(assets, 0);
        assertApproxEqAbs(asset.balanceOf(user), 500e18, VAULT_TOLERANCE);
        assertEq(staking.balanceOf(user), 500e18);

        // initiate cooldown for more shares by approved account. should reset cooldown
        vm.prank(user);
        staking.approve(address(this), 400e18);

        staking.cooldownAssets(user, 400e18);
        (assets, end) = staking.cooldowns(user);
        assertEq(end, block.timestamp + 7 days);
        assertEq(assets, 400e18);
        assertEq(staking.allowance(user, address(this)), 0);

        // fast forward past end of cooldown
        vm.warp(block.timestamp + 10 days);

        // unstake
        vm.prank(user);
        staking.unstake(user);
        (assets, end) = staking.cooldowns(user);
        assertEq(end, 0);
        assertEq(assets, 0);
        assertApproxEqAbs(asset.balanceOf(user), 900e18, VAULT_TOLERANCE);
        assertEq(staking.balanceOf(user), 100e18);
    }

    function test_fuzz_CooldownShares(uint256 amount, uint32 cooldownPeriod) public {
        uint256 cooldownTime = bound(uint256(cooldownPeriod), 20 seconds, staking.MAX_COOLDOWN_PERIOD());
        amount = bound(amount, 4e18, 1e40);
        uint256 startTime = block.timestamp;

        // setup
        mintAsset(user, amount);
        vm.prank(admin);
        staking.setCooldownPeriod(cooldownTime);

        // deposit
        vm.prank(user);
        staking.deposit(amount, user);

        // initiate cooldown for half of shares
        vm.prank(user);
        staking.cooldownShares(user, amount / 2);
        uint256 coolDownCounter = amount / 2;
        (uint256 assets, uint256 end) = staking.cooldowns(user);
        assertEq(end, startTime + cooldownTime);
        assertEq(assets, amount / 2);

        // fast forward to end of cooldown
        vm.warp(block.timestamp + cooldownTime);

        // unstake
        vm.prank(user);
        staking.unstake(user);
        (assets, end) = staking.cooldowns(user);
        assertEq(end, 0);
        assertEq(assets, 0);
        assertApproxEqAbs(asset.balanceOf(user), amount / 2, VAULT_TOLERANCE);
        assertApproxEqAbs(staking.balanceOf(user), amount / 2, VAULT_TOLERANCE);

        // initiate cooldown again
        startTime = block.timestamp;
        vm.prank(user);
        staking.cooldownShares(user, amount / 4);
        coolDownCounter += amount / 4;
        (assets, end) = staking.cooldowns(user);
        assertEq(end, startTime + cooldownTime);
        assertEq(assets, amount / 4);

        // fast forward past end of cooldown
        vm.warp(startTime + cooldownTime + 60 seconds);

        // unstake
        vm.prank(user);
        staking.unstake(user);
        (assets, end) = staking.cooldowns(user);
        assertEq(end, 0);
        assertEq(assets, 0);
        assertApproxEqAbs(asset.balanceOf(user), coolDownCounter, VAULT_TOLERANCE);
        assertApproxEqAbs(staking.balanceOf(user), amount - coolDownCounter, VAULT_TOLERANCE);
    }

    function test_fuzz_CooldownAssets(uint256 amount, uint32 cooldownPeriod) public {
        uint256 cooldownTime = bound(uint256(cooldownPeriod), 20 seconds, staking.MAX_COOLDOWN_PERIOD());
        amount = bound(amount, 4e18, 1e40);
        uint256 startTime = block.timestamp;

        // setup
        mintAsset(user, amount);
        vm.prank(admin);
        staking.setCooldownPeriod(cooldownTime);

        // deposit
        vm.prank(user);
        staking.deposit(amount, user);

        // initiate cooldown for half of shares
        uint256 totalCooldownAmount = amount / 2;
        vm.prank(user);
        staking.cooldownAssets(user, amount / 2);
        (uint256 assets, uint256 end) = staking.cooldowns(user);
        assertEq(end, startTime + cooldownTime);
        assertEq(assets, amount / 2);

        // fast forward to end of cooldown
        vm.warp(block.timestamp + cooldownTime);

        // unstake
        vm.prank(user);
        staking.unstake(user);
        (assets, end) = staking.cooldowns(user);
        assertEq(end, 0);
        assertEq(assets, 0);
        assertApproxEqAbs(asset.balanceOf(user), amount / 2, VAULT_TOLERANCE);
        assertApproxEqAbs(staking.balanceOf(user), amount / 2, VAULT_TOLERANCE);

        // initiate cooldown again
        startTime = block.timestamp;
        uint256 cooldownAmount = (amount / 4) > 1e18 ? amount / 4 : 1e18; //Avoid falling below minimum shares
        totalCooldownAmount += cooldownAmount;
        vm.prank(user);
        staking.cooldownAssets(user, cooldownAmount);
        (assets, end) = staking.cooldowns(user);
        assertEq(end, startTime + cooldownTime);
        assertEq(assets, cooldownAmount);

        // fast forward before end of cooldown
        vm.warp(startTime + cooldownTime - 1);
        startTime = block.timestamp;

        // fast forward past end of cooldown
        vm.warp(startTime + cooldownTime + 60 seconds);

        // unstake
        vm.prank(user);
        staking.unstake(user);
        (assets, end) = staking.cooldowns(user);
        assertEq(end, 0);
        assertEq(assets, 0);
        assertApproxEqAbs(asset.balanceOf(user), totalCooldownAmount, VAULT_TOLERANCE);
        assertApproxEqAbs(staking.balanceOf(user), amount - totalCooldownAmount, VAULT_TOLERANCE);
    }

    function test_Revert_CancelCooldown() public {
        mintAsset(user, 1e18);

        vm.prank(user);
        staking.deposit(1e18, user);

        // set vesting
        vm.prank(admin);
        staking.setVestingPeriod(7 days);

        // set cooldown
        vm.prank(admin);
        staking.setCooldownPeriod(3 days);

        // can't cancel if no cooldown exists
        vm.expectRevert(IStakedAsset.RequiresCooldown.selector);
        vm.prank(user);
        staking.cancelCooldown();

        // start cooldown
        vm.prank(user);
        staking.cooldownAssets(user, 1e18);

        // set restricted
        vm.prank(restricter);
        staking.setIsRestricted(user, true);

        // restricted user can't cancel cooldown
        vm.expectRevert(IRestrictedRegistry.AccountRestricted.selector);
        vm.prank(user);
        staking.cancelCooldown();
    }

    function test_fuzz_CancelCooldown(uint256 amount) public {
        // setup
        amount = bound(amount, 100, 10e18);
        mintAsset(user, amount);
        mintAsset(rewarder, amount);

        vm.prank(user);
        staking.deposit(amount, user);

        // set vesting
        vm.prank(admin);
        staking.setVestingPeriod(7 days);

        // set cooldown
        vm.prank(admin);
        staking.setCooldownPeriod(3 days);

        // start cooldown
        vm.prank(user);
        staking.cooldownAssets(user, amount);

        // cancel cooldown
        vm.expectEmit();
        emit IStakedAsset.CooldownCancelled(user, amount);
        vm.prank(user);
        staking.cancelCooldown();

        // ensure balances are correct
        assertEq(staking.balanceOf(user), amount);
        assertEq(asset.balanceOf(user), 0);
        assertEq(asset.balanceOf(address(silo)), 0);

        // ensure cooldown is cancelled
        (uint256 assets, uint256 end) = staking.cooldowns(user);
        assertEq(assets, 0);
        assertEq(end, 0);
    }

    function test_Donation() public {
        // forge-lint: disable-start(erc20-unchecked-transfer)
        address attacker = address(1);
        test_Deposit(); // Initial deposit

        // Pretend contract had many deposits
        for (uint256 i = 0; i < 100; i++) {
            test_Deposit();
        }

        mintAsset(attacker, 1000e18);

        vm.startPrank(attacker);

        asset.transfer(address(staking), 1000e18);
        vm.stopPrank();

        // Post donation deposit
        mintAsset(user, 1000e18);

        vm.prank(user);
        uint256 shares = staking.deposit(1000e18, user);

        assertApproxEqAbs(shares, 1000e18, 9.901e20); // tolerable 0.99 difference
        // forge-lint: disable-end(erc20-unchecked-transfer)
    }

    function test_Revert_RescueToken() public {
        vm.prank(admin);
        vm.expectRevert(IStakedAsset.NonZeroAddress.selector);
        staking.rescueToken(address(collateral), address(0));

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        controller.rescueToken(address(collateral2), address(1));
        address asset = staking.asset();

        vm.prank(admin);
        vm.expectRevert(IStakedAsset.InvalidRescueToken.selector);
        staking.rescueToken(asset, address(1));
    }

    function test_RescueToken() public {
        address to = address(1);

        // Send non asset token
        collateral2.mint(address(staking), 1e18);
        assertEq(collateral2.balanceOf(to), 0);
        assertEq(collateral2.balanceOf(address(staking)), 1e18);

        // Rescue tokens
        vm.prank(admin);
        staking.rescueToken(address(collateral2), to);
        assertEq(collateral2.balanceOf(to), 1e18);
        assertEq(collateral2.balanceOf(address(staking)), 0);
    }

    function test_ExposedPendingRewards() public {
        // mint some asset tokens
        mintAsset(rewarder, 2000e18);
        mintAsset(user, 1000e18);

        // set vesting period
        vm.prank(admin);
        staking.setVestingPeriod(7 days);

        // mint some staking tokens
        vm.prank(user);
        staking.deposit(1000e18, user);

        // start vesting
        vm.prank(rewarder);
        staking.reward(1000e18);
        assertEq(staking.exposedPendingRewards(), 1000e18);
    }
}
