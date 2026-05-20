// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkBaseTest} from "./ForkBaseTest.sol";
import {CollateralManagerHarness} from "../harness/CollateralManagerHarness.sol";
import {ICollateralManager} from "../../src/interface/ICollateralManager.sol";
import {IDistributor} from "../../src/external/merkl/IDistributor.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MerklForkTest is ForkBaseTest {
    address constant DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address constant RECIPIENT_MULTISIG = 0x76D1415AB9d2CB6A790499a36313F5B700CF035d;
    address constant MORPHO = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2;
    address constant MANAGER = 0x42F3F01D45E67294e20cE98AcFDC24dD7EA75dEa;
    address constant OWNER = 0x698c6d3726846C4AD4Dc9331862b92Cd80D2fb99;
    IERC20 morpho = IERC20(MORPHO);

    function setUp() public override {
        // Must fork a specific block where the test proofs are correct
        forkBlock = 25086076;
        super.setUp();
        manager = CollateralManagerHarness(0x42F3F01D45E67294e20cE98AcFDC24dD7EA75dEa);
        // Must upgrade existing contract to new version
        // TODO once new version is deployed we can avoid the next step
        address newImplementation = address(new CollateralManagerHarness());
        vm.prank(OWNER);
        manager.upgradeToAndCall(newImplementation, new bytes(0));

        vm.prank(OWNER);
        manager.setDistributor(DISTRIBUTOR);

        vm.prank(OWNER);
        manager.setClaimRecipient(RECIPIENT_MULTISIG, address(0));
    }

    function test_claimMerklRewardsFromContract() external {
        address[] memory users = new address[](1);
        users[0] = MANAGER;

        address[] memory tokens = new address[](1);
        tokens[0] = MORPHO;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5123959145828625979;

        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](19);

        proofs[0][0] = 0xd6e21a927ad516c53885f7ce67755622c77cb6c4e592a2025ea867f9468f267f;
        proofs[0][1] = 0x0871db542ed43ff1c5aba41e8503b9e345fc02d9e8253ce094c7e3fcc3fd0efc;
        proofs[0][2] = 0xf3d399d58f082b8d0f1709aaaa8583014e4e8f672e83591c5165d4e98e20a758;
        proofs[0][3] = 0x0c25c489e7d6c34f962f5a642a859283b68dc8517b22bfe5a5b48a8e7e72aba1;
        proofs[0][4] = 0xfaacf2f72d7f2118ee16bf34f6084dfe1801ca8572566d6eb32b89340a5ff44e;
        proofs[0][5] = 0xb44bc19ecccc814ad80d9841ac8a9413528e8815f94eaf9fb786e6a4ced1266b;
        proofs[0][6] = 0xb4c425011506660f2b7281935e6d8ed9e9c003c56608e43c4b952d4f3a36990c;
        proofs[0][7] = 0x731d70a97a7e86673105e8958ace413149483d6396bd12b3c1886c7e8b9b766f;
        proofs[0][8] = 0xcbb5870f0c0eb2dce0aa9218034007632c65bd2f0a528320e59e8714923e7edc;
        proofs[0][9] = 0x54abaefcd32cc57c78accef332c69f29989ddfb0259adc002073cb2d174e17d6;
        proofs[0][10] = 0xd68fb3542544c09c633c6cf806ee68308b4d669731bbc1b2db7ac254015a6d1d;
        proofs[0][11] = 0xeda2ab60c2ca43e2ce0d7e4478da86b52115739484a3bd228e59c5ddbd04fa5b;
        proofs[0][12] = 0x485aec5d54edc7ec976bc07e86ede11f57ceb3816484282afbaf9aa4753e2179;
        proofs[0][13] = 0xa8e75c393444457bee422f6352e14faa27b21139bc353765107e4407ecd4841a;
        proofs[0][14] = 0x7c71fcc3835fd96ac61bb01a714a257820a0e9a34645add8a873efd0f3dff9c6;
        proofs[0][15] = 0x258585866db5b1c696529df1044e7ac1ee25e6be021a373d7394013a1fec08ec;
        proofs[0][16] = 0x6e86f9675146f7148321d4c123120b97edf385c9a53beab39766e495390a8e8c;
        proofs[0][17] = 0x61cc3cd53617698b73e01428fb5583181e4b3593914bbc67aadd04c7b1990784;
        proofs[0][18] = 0x40c7e004c5c663c410abba17942ee6f9866a7009251821f32c9289d758586914;

        uint256 recipientBalanceBefore = morpho.balanceOf(RECIPIENT_MULTISIG);
        uint256 managerBalanceBefore = morpho.balanceOf(address(manager));

        vm.prank(RECIPIENT_MULTISIG);
        IDistributor(DISTRIBUTOR).claim(users, tokens, amounts, proofs);

        uint256 recipientBalanceAfter = morpho.balanceOf(RECIPIENT_MULTISIG);
        uint256 managerBalanceAfter = morpho.balanceOf(address(manager));

        assertEq(recipientBalanceAfter - recipientBalanceBefore, amounts[0]);
        assertEq(managerBalanceAfter, managerBalanceBefore);
    }
}
