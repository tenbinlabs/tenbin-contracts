// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetToken} from "src/AssetToken.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Client} from "lib/chainlink-local/lib/ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ForkBaseTest} from "test/fork/ForkBaseTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IRouterClient} from "lib/chainlink-local/src/ccip/CCIPLocalSimulator.sol";
import {ITokenAdminRegistry} from "test/external/chainlink/ITokenAdminRegistry.sol";
import {MockBurnMintMultiTokenPool} from "test/mocks/MockBurnMintMultiTokenPool.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {RateLimiter} from "lib/chainlink-ccip/chains/evm/contracts/libraries/RateLimiter.sol";
import {SpokeERC20} from "src/external/chainlink/SpokeERC20.sol";
import {StakedAssetHarness} from "test/harness/StakedAssetHarness.sol";
import {StakedAsset} from "src/StakedAsset.sol";

contract CCIPForkTest is ForkBaseTest {
    // contracts deployed in testnet chains
    address ethTokenAdmin; // Token Admin Registry Eth Sepolia
    address arbTokenAdmin; // Token Admin Registry Arbitrum Sepolia
    // pools
    MockBurnMintMultiTokenPool ethPool; // eth sepolia pool
    MockBurnMintMultiTokenPool arbPool; // arbitrum sepolia pool
    // simulation
    CCIPLocalSimulatorFork internal ccipLocalSimulatorFork;
    IRouterClient internal sourceRouter;
    uint256 internal destinationFork;
    uint64 internal destinationChainSelector;
    // tokens
    AssetToken internal dstAsset;
    SpokeERC20 internal dstStaking;

    function setUp() public override {
        // forks
        address[] memory empty = new address[](0);
        IERC20[] memory tokens = new IERC20[](2);
        bytes32 salt = bytes32(abi.encodePacked("salt"));
        super.setUp();
        string memory rpc = vm.rpcUrl("sepolia"); // eth sepolia
        sourceFork = vm.createFork(rpc);

        string memory destRpc = vm.rpcUrl("dstSepolia"); // arbitrum sepolia
        destinationFork = vm.createSelectFork(destRpc);

        // Deploy contracts on each chain
        // DESTINATION CHAIN
        vm.selectFork(destinationFork);
        uint256 dstChainId = block.chainid;
        dstAsset = new AssetToken("AssetToken2", "SYN", owner);
        dstStaking = new SpokeERC20("SpokeToken", "STK", owner);
        tokens[0] = IERC20(dstAsset);
        tokens[1] = IERC20(dstStaking);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        Register.NetworkDetails memory destinationNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(dstChainId);
        arbTokenAdmin = destinationNetworkDetails.tokenAdminRegistryAddress;
        require(destinationNetworkDetails.tokenAdminRegistryAddress.code.length > 0, "dst TAR has no code");
        destinationNetworkDetails.ccipBnMAddress = address(dstAsset);
        destinationChainSelector = destinationNetworkDetails.chainSelector;
        ccipLocalSimulatorFork.setNetworkDetails(dstChainId, destinationNetworkDetails);
        arbPool = new MockBurnMintMultiTokenPool(tokens, empty, address(0), destinationNetworkDetails.routerAddress);
        vm.startPrank(owner);
        dstStaking.grantRole(dstStaking.MINTER_BURNER_ROLE(), address(arbPool));
        dstStaking.grantRole(dstStaking.MINTER_BURNER_ROLE(), address(this));
        dstAsset.setMinter(address(arbPool));
        vm.stopPrank();

        // SOURCE CHAIN
        vm.selectFork(sourceFork);
        uint256 chainId = block.chainid;
        asset = new AssetToken("AssetToken1", "SYN", owner);
        address stakingImplementation = address(new StakedAsset{salt: salt}());
        bytes memory data =
            abi.encodeWithSelector(StakedAsset.initialize.selector, "WAGMI", "STK", address(asset), owner);
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(stakingImplementation, data);
        staking = StakedAssetHarness(address(proxy));
        tokens[0] = IERC20(asset);
        tokens[1] = IERC20(staking);

        Register.NetworkDetails memory sourceNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(chainId);
        ethTokenAdmin = sourceNetworkDetails.tokenAdminRegistryAddress;
        sourceNetworkDetails.ccipBnMAddress = address(asset);
        sourceRouter = IRouterClient(sourceNetworkDetails.routerAddress);
        ccipLocalSimulatorFork.setNetworkDetails(chainId, sourceNetworkDetails);
        ethPool = new MockBurnMintMultiTokenPool(tokens, empty, address(0), sourceNetworkDetails.routerAddress);

        setUpNewLabels();
        // Configure pools
        // souce chain
        // asset
        configPool(
            sourceFork,
            ethTokenAdmin,
            address(asset),
            address(dstAsset),
            destinationChainSelector,
            ethPool,
            address(arbPool)
        );
        // staking
        configPool(
            sourceFork,
            ethTokenAdmin,
            address(staking),
            address(dstStaking),
            destinationChainSelector,
            ethPool,
            address(arbPool)
        );

        // destination chain
        // staking
        configPool(
            destinationFork,
            arbTokenAdmin,
            address(dstStaking),
            address(staking),
            destinationChainSelector,
            arbPool,
            address(ethPool)
        );
        // asset
        configPool(
            destinationFork,
            arbTokenAdmin,
            address(dstAsset),
            address(asset),
            destinationChainSelector,
            arbPool,
            address(ethPool)
        );
    }

    function test_transferAssetTokensFromEoaToEoaPayFeesInNative() external {
        (Client.EVMTokenAmount[] memory tokensToSendDetails, uint256 amountToSend) = prepareScenario(true);
        uint256 totalSupply = asset.totalSupply();
        uint256 balanceOfUserBefore = asset.balanceOf(user);
        vm.startPrank(user);
        deal(user, 5 ether);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(recipient),
            data: abi.encode(""),
            tokenAmounts: tokensToSendDetails,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})),
            feeToken: address(0)
        });

        uint256 fees = sourceRouter.getFee(destinationChainSelector, message);
        // cross chain transfer
        sourceRouter.ccipSend{value: fees}(destinationChainSelector, message);
        vm.stopPrank();

        assertEq(asset.balanceOf(user), balanceOfUserBefore - amountToSend);
        assertEq(totalSupply - amountToSend, asset.totalSupply());

        ccipLocalSimulatorFork.switchChainAndRouteMessage(destinationFork);

        assertEq(dstAsset.balanceOf(recipient), amountToSend);
        assertEq(dstAsset.totalSupply(), amountToSend);
    }

    function test_transferStakingTokensFromEoaToEoaPayFeesInNative() external {
        (Client.EVMTokenAmount[] memory tokensToSendDetails, uint256 amountToSend) = prepareScenario(false);
        ethPool.setIsLock(true);
        uint256 totalSupply = staking.totalSupply();

        vm.startPrank(user);
        deal(user, 5 ether);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(recipient),
            data: abi.encode(""),
            tokenAmounts: tokensToSendDetails,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})),
            feeToken: address(0)
        });

        uint256 fees = sourceRouter.getFee(destinationChainSelector, message);
        // cross chain transfer
        sourceRouter.ccipSend{value: fees}(destinationChainSelector, message);
        vm.stopPrank();

        assertEq(staking.balanceOf(user), 0);
        // supply must not change, only be locked
        assertEq(totalSupply, staking.totalSupply());
        assertEq(totalSupply, staking.balanceOf(address(ethPool)));

        ccipLocalSimulatorFork.switchChainAndRouteMessage(destinationFork);

        assertEq(dstStaking.balanceOf(recipient), amountToSend);
        assertEq(dstStaking.totalSupply(), amountToSend);
    }

    // helpers
    function prepareScenario(bool isAssetToken)
        public
        returns (Client.EVMTokenAmount[] memory tokensToSendDetails, uint256 amountToSend)
    {
        amountToSend = 1e18;
        vm.selectFork(sourceFork);
        mintAsset(user, amountToSend * 10);

        vm.startPrank(user);

        asset.approve(address(staking), type(uint256).max);
        staking.mint(amountToSend, user);

        asset.approve(address(sourceRouter), amountToSend);
        staking.approve(address(sourceRouter), amountToSend);

        tokensToSendDetails = new Client.EVMTokenAmount[](1);
        tokensToSendDetails[0] = isAssetToken
            ? Client.EVMTokenAmount({token: address(asset), amount: amountToSend})
            : Client.EVMTokenAmount({token: address(staking), amount: amountToSend});

        vm.stopPrank();

        ITokenAdminRegistry.TokenConfig memory cfg = isAssetToken
            ? ITokenAdminRegistry(ethTokenAdmin).getTokenConfig(address(asset))
            : ITokenAdminRegistry(ethTokenAdmin).getTokenConfig(address(staking));

        address admin = cfg.administrator;
        require(admin != address(0), "Token not configured / no admin");
    }

    function configPool(
        uint256 fork,
        address tokenRegistry,
        address localToken,
        address remoteToken,
        uint64 chainSelector,
        MockBurnMintMultiTokenPool localPool,
        address remotePool
    ) internal {
        vm.selectFork(fork);
        address tarOwner = Ownable(tokenRegistry).owner();

        vm.prank(tarOwner);
        ITokenAdminRegistry(tokenRegistry).proposeAdministrator(localToken, owner);

        vm.startPrank(owner);
        ITokenAdminRegistry(tokenRegistry).acceptAdminRole(localToken);
        ITokenAdminRegistry(tokenRegistry).setPool(localToken, address(localPool));
        vm.stopPrank();

        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);

        MockBurnMintMultiTokenPool.ChainUpdate[] memory chainUpdates = new MockBurnMintMultiTokenPool.ChainUpdate[](1);
        chainUpdates[0] = MockBurnMintMultiTokenPool.ChainUpdate({
            remoteChainSelector: chainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePool),
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100e28, rate: 1e15}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 222e30, rate: 1e18})
        });

        localPool.applyChainUpdates(address(localToken), chainUpdates);

        assertTrue(localPool.isSupportedChain(chainSelector));
    }

    function setUpNewLabels() internal {
        label(address(dstAsset), "dstAsset");
        label(address(dstStaking), "dstStaking");
        label(ethTokenAdmin, "TokenRegistryEthSepolia");
        label(arbTokenAdmin, "TokenRegistryArbSepolia");
        label(address(ethPool), "ethPool");
        label(address(arbPool), "arbPool");
    }
}
