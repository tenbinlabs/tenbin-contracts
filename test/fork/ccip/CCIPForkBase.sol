// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CCIPLocalSimulatorFork, Register} from "chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Client} from "chainlink-local/lib/chainlink-ccip/chains/evm/contracts/libraries/Client.sol";
import {IRouterClient} from "chainlink-local/src/ccip/CCIPLocalSimulator.sol";
import {ForkBaseTest} from "../ForkBaseTest.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ITokenAdminRegistry} from "../../external/chainlink/ITokenAdminRegistry.sol";
import {MockBurnMintMultiTokenPool} from "../../mocks/MockBurnMintMultiTokenPool.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {RateLimiter} from "chainlink-ccip/chains/evm/contracts/libraries/RateLimiter.sol";
import {SpokeERC20} from "../../../src/external/chainlink/SpokeERC20.sol";

abstract contract CCIPForkBase is ForkBaseTest {
    // Deployed contracts
    address constant ASSET_ADDRESS = 0xbE8EeAfbeaF84ae375f2e99047C68E9f7D746532;
    address constant STAKED_ASSET_ADDRESS = 0xd71723E1CBeC4aa75443E6c285dB61cbFdE72799;
    address ethTokenAdmin; // Token Admin Registry Eth Sepolia
    address arbTokenAdmin; // Token Admin Registry Arbitrum Sepolia

    // Networks set up
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    uint256 public destinationFork;
    IRouterClient public destinationRouter;
    IRouterClient public sourceRouter;
    uint64 public sourceChainSelector;
    uint64 public destinationChainSelector;

    // tokens
    IERC20 public sourceCCIPBnMToken;
    SpokeERC20 public destinationCCIPBnMToken;

    // pools
    MockBurnMintMultiTokenPool ethPool; // eth sepolia pool
    MockBurnMintMultiTokenPool arbPool; // arbitrum sepolia pool

    address public alice = makeAddr("alice");

    function setUp() public virtual override {
        super.setUp();
        deployContracts();

        (arbTokenAdmin, destinationChainSelector, destinationRouter, arbPool) =
            _setupChain(destinationFork, IERC20(destinationCCIPBnMToken));

        vm.startPrank(owner);
        destinationCCIPBnMToken.grantRole(destinationCCIPBnMToken.MINTER_BURNER_ROLE(), address(arbPool));
        vm.stopPrank();

        (ethTokenAdmin, sourceChainSelector, sourceRouter, ethPool) = _setupChain(sourceFork, sourceCCIPBnMToken);

        // source chain
        configPool(
            sourceFork,
            ethTokenAdmin,
            address(sourceCCIPBnMToken),
            address(destinationCCIPBnMToken),
            destinationChainSelector,
            ethPool,
            address(arbPool),
            true
        );

        // destination chain
        configPool(
            destinationFork,
            arbTokenAdmin,
            address(destinationCCIPBnMToken),
            address(sourceCCIPBnMToken),
            sourceChainSelector,
            arbPool,
            address(ethPool),
            false
        );

        setUpNewLabels();
    }

    function test_CCIP_SetUp() public {
        assertNotEq(ethTokenAdmin, address(0), "eth token admin zero");
        assertNotEq(arbTokenAdmin, address(0), "arb token admin zero");

        assertNotEq(sourceChainSelector, 0, "source selector zero");
        assertNotEq(destinationChainSelector, 0, "destination selector zero");
        assertNotEq(sourceChainSelector, destinationChainSelector, "selectors equal");

        vm.selectFork(sourceFork);

        assertEq(block.chainid, 11155111, "wrong source fork");
        assertNotEq(address(sourceRouter), address(0), "source router zero");
        assertNotEq(address(sourceCCIPBnMToken), address(0), "source token zero");
        assertNotEq(address(ethPool), address(0), "eth pool zero");

        Register.NetworkDetails memory sourceDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        assertEq(sourceDetails.ccipBnMAddress, address(sourceCCIPBnMToken), "wrong source ccipBnM");
        assertEq(sourceDetails.routerAddress, address(sourceRouter), "wrong source router");
        assertEq(sourceDetails.tokenAdminRegistryAddress, ethTokenAdmin, "wrong eth token admin");

        assertTrue(ethPool.isSupportedChain(destinationChainSelector), "eth pool does not support destination");

        assertEq(
            ITokenAdminRegistry(ethTokenAdmin).getPool(address(sourceCCIPBnMToken)), address(ethPool), "wrong eth pool"
        );

        vm.selectFork(destinationFork);

        assertEq(block.chainid, 421614, "wrong destination fork");
        assertNotEq(address(destinationRouter), address(0), "destination router zero");
        assertNotEq(address(destinationCCIPBnMToken), address(0), "destination token zero");
        assertNotEq(address(arbPool), address(0), "arb pool zero");

        Register.NetworkDetails memory destinationDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        assertEq(destinationDetails.ccipBnMAddress, address(destinationCCIPBnMToken), "wrong destination ccipBnM");
        assertEq(destinationDetails.routerAddress, address(destinationRouter), "wrong destination router");
        assertEq(destinationDetails.tokenAdminRegistryAddress, arbTokenAdmin, "wrong arb token admin");

        assertTrue(arbPool.isSupportedChain(sourceChainSelector), "arb pool does not support source");

        assertEq(
            ITokenAdminRegistry(arbTokenAdmin).getPool(address(destinationCCIPBnMToken)),
            address(arbPool),
            "wrong arb pool"
        );

        assertTrue(
            destinationCCIPBnMToken.hasRole(destinationCCIPBnMToken.MINTER_BURNER_ROLE(), address(arbPool)),
            "arb pool is not spoke token minter"
        );
    }

    function test_CCIP_SourceSide_LocksAndEmitsMessage() external {
        (Client.EVMTokenAmount[] memory tokensToSendDetails, uint256 amountToSend) = buildSendTokenData();

        vm.selectFork(sourceFork);

        uint256 aliceBalanceBefore = sourceCCIPBnMToken.balanceOf(alice);
        uint256 supplyBefore = sourceCCIPBnMToken.totalSupply();

        assertEq(aliceBalanceBefore, amountToSend, "alice missing source tokens");

        ccipLocalSimulatorFork.requestLinkFromFaucet(alice, 10 ether);

        vm.startPrank(alice);
        deal(alice, 5 ether);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(recipient),
            data: abi.encode(""),
            tokenAmounts: tokensToSendDetails,
            extraArgs: "",
            feeToken: address(0)
        });

        uint256 fees = sourceRouter.getFee(destinationChainSelector, message);

        vm.recordLogs();

        bytes32 messageId = sourceRouter.ccipSend{value: fees}(destinationChainSelector, message);

        vm.stopPrank();

        assertNotEq(messageId, bytes32(0), "empty message id");

        assertEq(sourceCCIPBnMToken.balanceOf(alice), 0, "sender source balance not spent");
        assertEq(sourceCCIPBnMToken.totalSupply(), supplyBefore, "source token was burned");
        assertEq(sourceCCIPBnMToken.balanceOf(address(ethPool)), amountToSend, "sender source balance not spent");
    }

    function test_CCIP_DestinationCanMint() public {
        vm.selectFork(destinationFork);

        vm.prank(address(arbPool));
        destinationCCIPBnMToken.mint(recipient, 100);

        assertEq(destinationCCIPBnMToken.balanceOf(recipient), 100);
    }

    function test_transferAssetTokensFromEoaToEoaPayFeesInNative() external {
        (Client.EVMTokenAmount[] memory tokensToSendDetails, uint256 amountToSend) = buildSendTokenData();
        uint256 totalSupply = sourceCCIPBnMToken.totalSupply();
        uint256 balanceOfUserBefore = sourceCCIPBnMToken.balanceOf(alice);
        vm.startPrank(alice);
        deal(alice, 5 ether);
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

        assertEq(sourceCCIPBnMToken.balanceOf(alice), balanceOfUserBefore - amountToSend);
        assertEq(sourceCCIPBnMToken.totalSupply(), totalSupply);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(destinationFork);

        assertEq(destinationCCIPBnMToken.balanceOf(recipient), amountToSend);
        assertEq(destinationCCIPBnMToken.totalSupply(), amountToSend);
    }

    function setUpNewLabels() internal {
        label(address(ccipLocalSimulatorFork), "ccipLocalSimulatorFork");
        label(address(sourceRouter), "sourceRouter");
        label(address(destinationRouter), "destinationRouter");
        label(address(destinationCCIPBnMToken), "destinationCCIPBnMToken");
        label(address(sourceCCIPBnMToken), "sourceCCIPBnMToken");
        label(address(arbPool), "arbPool");
        label(address(ethPool), "ethPool");
    }

    function buildSendTokenData()
        public
        virtual
        returns (Client.EVMTokenAmount[] memory tokensToSendDetails, uint256 amountToSend)
    {
        amountToSend = 100;
        mintTokens(amountToSend);

        ethPool.setIsLock(true);
        vm.startPrank(alice);
        sourceCCIPBnMToken.approve(address(sourceRouter), amountToSend);

        tokensToSendDetails = new Client.EVMTokenAmount[](1);
        tokensToSendDetails[0] = Client.EVMTokenAmount({token: address(sourceCCIPBnMToken), amount: amountToSend});

        vm.stopPrank();
    }

    function configPool(
        uint256 fork,
        address tokenRegistry,
        address localToken,
        address remoteToken,
        uint64 chainSelector,
        MockBurnMintMultiTokenPool localPool,
        address remotePool,
        bool isSource
    ) internal {
        vm.selectFork(fork);
        address tarOwner = Ownable(tokenRegistry).owner();

        vm.prank(tarOwner);
        ITokenAdminRegistry(tokenRegistry).proposeAdministrator(localToken, owner);

        vm.startPrank(owner);
        ITokenAdminRegistry(tokenRegistry).acceptAdminRole(localToken);
        ITokenAdminRegistry(tokenRegistry).setPool(localToken, address(localPool));
        vm.stopPrank();

        MockBurnMintMultiTokenPool.ChainUpdate[] memory chainUpdates = new MockBurnMintMultiTokenPool.ChainUpdate[](1);
        chainUpdates[0] = MockBurnMintMultiTokenPool.ChainUpdate({
            remoteChainSelector: chainSelector,
            allowed: true,
            remotePoolAddress: isSource ? abi.encode(remotePool) : abi.encodePacked(remotePool),
            remoteTokenAddress: isSource ? abi.encode(remoteToken) : abi.encodePacked(remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100e28, rate: 1e15}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 222e30, rate: 1e18})
        });

        localPool.applyChainUpdates(address(localToken), chainUpdates);

        assertTrue(localPool.isSupportedChain(chainSelector));
    }

    function createForks() internal {
        string memory SOURCE_RPC_URL = vm.rpcUrl("sepolia");
        string memory DESTINATION_RPC_URL = vm.rpcUrl("dstSepolia");

        sourceFork = vm.createFork(SOURCE_RPC_URL);
        destinationFork = vm.createFork(DESTINATION_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));
    }

    function _setupChain(uint256 fork, IERC20 token)
        internal
        returns (address tokenAdmin, uint64 chainSelector, IRouterClient router, MockBurnMintMultiTokenPool pool)
    {
        vm.selectFork(fork);

        Register.NetworkDetails memory details = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        tokenAdmin = details.tokenAdminRegistryAddress;
        chainSelector = details.chainSelector;
        router = IRouterClient(details.routerAddress);

        details.ccipBnMAddress = address(token);
        ccipLocalSimulatorFork.setNetworkDetails(block.chainid, details);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = token;

        address[] memory empty = new address[](0);

        pool = new MockBurnMintMultiTokenPool(tokens, empty, address(0), details.routerAddress);
    }

    function deployContracts() internal virtual;
    function mintTokens(uint256 amount) internal virtual;
}
