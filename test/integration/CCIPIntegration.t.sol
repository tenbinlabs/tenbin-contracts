// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CCIPLocalSimulator, IRouterClient} from "lib/chainlink-local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "lib/chainlink-local/lib/chainlink-ccip/chains/evm/contracts/libraries/Client.sol";

contract CCIPIntegrationTest is BaseTest {
    CCIPLocalSimulator public ccipLocalSimulator;

    address user1 = vm.addr(0xA001);
    address user2 = vm.addr(0xA002);
    IRouterClient ccipRouter;
    uint64 destinationChainSelector;

    function setUp() public override {
        super.setUp();
        ccipLocalSimulator = new CCIPLocalSimulator();
        vm.startPrank(owner);
        ccipLocalSimulator.supportNewTokenViaOwner(address(asset));
        vm.stopPrank();

        (uint64 chainSelector, IRouterClient sourceRouter,,,,,) = ccipLocalSimulator.configuration();

        ccipRouter = sourceRouter;
        destinationChainSelector = chainSelector;
    }

    function test_TransferAssetTokens() external {
        mintAsset(user1, 1e18);
        (Client.EVMTokenAmount[] memory tokensToSendDetails) = prepareScenario(asset);

        vm.startPrank(user1);
        deal(user1, 5 ether);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user2),
            data: abi.encode(""),
            tokenAmounts: tokensToSendDetails,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})),
            feeToken: address(0)
        });

        uint256 fees = ccipRouter.getFee(destinationChainSelector, message);
        ccipRouter.ccipSend{value: fees}(destinationChainSelector, message);
        vm.stopPrank();

        assertEq(asset.balanceOf(user1), 0);
        assertEq(asset.balanceOf(user2), 1e18);
    }

    function test_TransferStakingTokens() external {
        mintAsset(user, 1000e18);

        vm.startPrank(user);
        staking.deposit(1000e18, user);
        staking.approve(address(ccipRouter), type(uint256).max);
        vm.stopPrank();
        (Client.EVMTokenAmount[] memory tokensToSendDetails) = prepareScenario(staking);

        vm.startPrank(user);
        deal(user, 5 ether);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user2),
            data: abi.encode(""),
            tokenAmounts: tokensToSendDetails,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})),
            feeToken: address(0)
        });

        uint256 fees = ccipRouter.getFee(destinationChainSelector, message);
        uint256 prevBalance = staking.balanceOf(user);
        ccipRouter.ccipSend{value: fees}(destinationChainSelector, message);
        vm.stopPrank();

        assertEq(staking.balanceOf(user), prevBalance - 1e18);
        assertEq(staking.balanceOf(user2), 1e18);
    }

    // helper
    function prepareScenario(IERC20 token) public returns (Client.EVMTokenAmount[] memory tokensToSendDetails) {
        vm.startPrank(user1);

        token.approve(address(ccipRouter), 1e18);

        tokensToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenToSendDetails = Client.EVMTokenAmount({token: address(token), amount: 1e18});
        tokensToSendDetails[0] = tokenToSendDetails;

        vm.stopPrank();
    }
}
