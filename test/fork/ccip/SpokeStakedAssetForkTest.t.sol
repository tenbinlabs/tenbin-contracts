// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "../../../src/AssetToken.sol";
import {CCIPForkBase} from "./CCIPForkBase.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SpokeERC20} from "../../../src/external/chainlink/SpokeERC20.sol";
import {SpokeERC20Restricted} from "../../../src/external/chainlink/SpokeERC20Restricted.sol";
import {StakedAsset} from "tenbin-contracts/src/StakedAsset.sol";

contract SpokeStakedAssetForkTest is CCIPForkBase {
    StakedAsset stkAsset;
    SpokeERC20Restricted spokeAsset;

    function deployContracts() internal override {
        createForks();
        vm.selectFork(destinationFork);
        spokeAsset = new SpokeERC20Restricted("StakingToken2", "STK", owner);
        destinationCCIPBnMToken = SpokeERC20(address(spokeAsset));

        vm.selectFork(sourceFork);
        asset = AssetToken(ASSET_ADDRESS);
        sourceCCIPBnMToken = IERC20(STAKED_ASSET_ADDRESS);
        stkAsset = StakedAsset(STAKED_ASSET_ADDRESS);

        vm.startPrank(alice);
        asset.approve(STAKED_ASSET_ADDRESS, type(uint256).max);
        stkAsset.approve(STAKED_ASSET_ADDRESS, type(uint256).max);
        vm.stopPrank();
    }

    function mintTokens(uint256 amount) internal override {
        vm.selectFork(sourceFork);
        vm.prank(asset.minter());
        asset.mint(alice, amount);

        vm.prank(alice);
        stkAsset.mint(amount, alice);
    }
}
