// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/src/console2.sol";
import {AssetSilo} from "../src/AssetSilo.sol";
import {AssetToken} from "../src/AssetToken.sol";
import {CollateralManager} from "../src/CollateralManager.sol";
import {CollateralManagerHarness} from "./harness/CollateralManagerHarness.sol";
import {ControllerHarness} from "./harness/ControllerHarness.sol";
import {CustodianModule} from "../src/CustodianModule.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAggregationRouterV6} from "../src/external/1inch/IAggregationRouterV6.sol";
import {IController} from "../src/interface/IController.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {ISwapModule} from "../src/interface/ISwapModule.sol";
import {Mock1InchRouter} from "./mocks/Mock1InchRouter.sol";
import {MockAggregator} from "./mocks/MockAggregator.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";
import {MockERC1271Signer} from "./mocks/MockERC1271Signer.sol";
import {MockEtherReceiver} from "./mocks/MockEtherReceiver.sol";
import {MultiCall} from "../src/MultiCall.sol";
import {GoldOracleAdapter} from "../src/oracle/GoldOracleAdapter.sol";
import {RevenueModule} from "../src/RevenueModule.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {StakedAsset} from "../src/StakedAsset.sol";
import {StakedAssetHarness} from "./harness/StakedAssetHarness.sol";
import {SwapModuleHarness} from "./harness/SwapModuleHarness.sol";
import {Test} from "forge-std/src/Test.sol";
import {UniversalRewardsDistributor} from "./mocks/MockUniversalRewardsDistributor.sol";

contract BaseTest is Test {
    using SafeERC20 for IERC20;
    using SafeERC20 for AssetToken;

    // structs
    struct SwapContext {
        MockERC20 token1;
        MockERC20 token2;
        address srcToken;
        address dstToken;
        uint8 dec1;
        uint8 dec2;
        uint256 minPrice;
        uint256 amount; //In tokenIn precision
        uint256 minReturnAmount; //In tokenOut precision
        address executor;
    }

    // constants
    uint256 internal constant BASIS_PRECISION = 10_000;
    uint256 internal constant RATIO_PRECISION = 1e18;
    uint256 internal constant DEFAULT_RATIO = 1e17;
    uint256 internal constant ONE_YEAR_SECONDS = 365 * 24 * 60 * 60;
    uint256 internal constant ONE_YEAR_BLOCKS = ONE_YEAR_SECONDS / 20;
    uint256 internal constant VAULT_TOLERANCE = 2; // tolerance for vault calculations
    // percentage tolerance for rounding during fuzz testing
    uint256 internal constant FUZZ_TOLERANCE_REL = 0.001e18; // 0.1%
    // max price delta tolerance for controller
    uint96 internal constant MAX_ORACLE_TOLERANCE = 1e18;
    // chainlink price aggregator precision
    uint256 internal constant ADAPTER_PRECISION = 1e10;
    // dead deposit address
    address internal constant DEAD_DEPOSIT_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // keys
    uint256 internal payerKey = 0xB000;
    uint256 internal recipientKey = 0xB001;

    // accounts
    address internal payer;
    address internal recipient;
    address internal admin;
    address internal minter;
    address internal gatekeeper;
    address internal custodian;
    address internal curator;
    address internal rebalancer;
    address internal capAdjuster;
    address internal signerManager;
    address internal multicaller;
    address internal deployer;
    address internal owner;
    address internal revenueKeeper;
    address internal custodianKeeper;
    address internal multisig;
    address internal user;
    address internal rewarder;
    address internal restricter;
    address internal broadcaster;

    // contracts
    ControllerHarness internal controller;
    MockERC20 internal collateral;
    MockERC20 internal collateral2;
    AssetToken internal asset;
    MockERC1271Signer internal signerContract;
    CollateralManagerHarness internal manager;
    IERC4626 internal vault;
    IERC4626 internal vault2;
    MultiCall internal multicall;
    SwapModuleHarness internal swapModule;
    IAggregationRouterV6 router;
    RevenueModule internal revenueModule;
    StakedAssetHarness internal staking;
    CustodianModule internal custodianModule;
    MockAggregator internal aggregator;
    GoldOracleAdapter internal oracleAdapter;
    AssetSilo internal silo;
    UniversalRewardsDistributor internal distributor;
    MockEtherReceiver etherReceiver;

    // roles
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant CURATOR_ROLE = keccak256("CURATOR_ROLE");
    bytes32 internal constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    bytes32 internal constant MULTICALLER_ROLE = keccak256("MULTICALLER_ROLE");
    bytes32 internal constant CAP_ADJUSTER_ROLE = keccak256("CAP_ADJUSTER_ROLE");
    bytes32 internal constant SIGNER_MANAGER_ROLE = keccak256("SIGNER_MANAGER_ROLE");
    bytes32 internal constant REVENUE_KEEPER_ROLE = keccak256("REVENUE_KEEPER_ROLE");
    bytes32 internal constant CUSTODIAN_KEEPER_ROLE = keccak256("CUSTODIAN_KEEPER_ROLE");
    bytes32 internal constant REWARDER_ROLE = keccak256("REWARDER_ROLE");
    bytes32 internal constant RESTRICTER_ROLE = keccak256("RESTRICTER_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    // mark this as a test contract
    function test() public {}

    function setUp() public virtual {
        setUpAccounts();
        setUpDeployments();
        setUpLabels();
        setUpController();
        setUpStaking();
        setUpManager();
        setUpRevenueModule();
        setUpConfiguration();
        setUpCustodianModule();
        setUpDistributor();
    }

    function setUpAccounts() internal {
        deployer = address(this);
        payer = vm.addr(payerKey);
        recipient = vm.addr(recipientKey);
        admin = vm.addr(0xB003);
        minter = vm.addr(0xB004);
        gatekeeper = vm.addr(0xB005);
        custodian = vm.addr(0xB006);
        curator = vm.addr(0xB007);
        rebalancer = vm.addr(0xB009);
        capAdjuster = vm.addr(0xB00A);
        signerManager = vm.addr(0xB00B);
        multicaller = vm.addr(0xB00C);
        owner = vm.addr(0xB00D);
        revenueKeeper = vm.addr(0xB00E);
        custodianKeeper = vm.addr(0xB00F);
        multisig = vm.addr(0xB010);
        user = vm.addr(0xB011);
        rewarder = vm.addr(0xB012);
        restricter = vm.addr(0xB013);
        broadcaster = getTestBroadcaster();
    }

    function setUpDeployments() internal {
        collateral = new MockERC20("CollateralToken", "CLT", 6);
        collateral2 = new MockERC20("CollateralToken2", "CLT2", 18);
        asset = new AssetToken("AssetToken", "SYN", owner);
        vault = new MockERC4626("Collateral Vault", "vCLT", collateral);
        vault2 = new MockERC4626("Collateral Vault 2", "vCLT2", collateral2);
        controller = new ControllerHarness(address(asset), DEFAULT_RATIO, custodian, owner);
        address managerImplementation = address(new CollateralManagerHarness());
        bytes memory data = abi.encodeWithSelector(CollateralManager.initialize.selector, address(controller), owner);
        ERC1967Proxy proxy = new ERC1967Proxy(managerImplementation, data);
        manager = CollateralManagerHarness(address(proxy));
        router = new Mock1InchRouter();
        swapModule = new SwapModuleHarness(address(manager), address(router), owner);
        multicall = new MultiCall(owner);
        address stakingImplementation = address(new StakedAssetHarness());
        data = abi.encodeWithSelector(StakedAsset.initialize.selector, "Staked Asset", "stAST", address(asset), owner);
        proxy = new ERC1967Proxy(stakingImplementation, data);
        staking = StakedAssetHarness(address(proxy));
        revenueModule = new RevenueModule(
            address(manager), address(staking), owner, address(controller), address(asset), address(multisig)
        );
        signerContract = new MockERC1271Signer();
        custodianModule = new CustodianModule(owner);
        aggregator = new MockAggregator();
        oracleAdapter = new GoldOracleAdapter(address(aggregator));
        distributor = new UniversalRewardsDistributor();
        etherReceiver = new MockEtherReceiver();
    }

    function setUpLabels() internal {
        label(address(this), "this");
        label(payer, "payer");
        label(recipient, "recipient");
        label(admin, "admin");
        label(minter, "minter");
        label(gatekeeper, "gatekeeper");
        label(custodian, "custodian");
        label(curator, "curator");
        label(rebalancer, "rebalancer");
        label(capAdjuster, "capAdjuster");
        label(signerManager, "signerManager");
        label(multicaller, "multicaller");
        label(deployer, "deployer");
        label(owner, "owner");
        label(revenueKeeper, "revenueKeeper");
        label(custodianKeeper, "custodianKeeper");
        label(multisig, "multisig");
        label(user, "user");
        label(restricter, "restricter");

        // contracts
        label(address(collateral), "collateral");
        label(address(collateral2), "collateral2");
        label(address(asset), "asset");
        label(address(vault), "vault");
        label(address(controller), "controller");
        label(address(manager), "manager");
        label(address(multicall), "multicall");
        label(address(router), "router");
        label(address(swapModule), "swapModule");
        label(address(revenueModule), "revenueModule");
        label(address(staking), "staking");
        label(address(signerContract), "signerContract");
        label(address(custodianModule), "custodianModule");
        label(address(aggregator), "aggregator");
        label(address(oracleAdapter), "oracleAdapter");
        label(address(silo), "silo");
        label(address(distributor), "distributor");
    }

    // helper function to configure controller
    function setUpController() internal {
        vm.startPrank(owner);
        asset.setMinter(address(controller));
        controller.grantRole(ADMIN_ROLE, admin);
        controller.grantRole(MINTER_ROLE, minter);
        // multicall is minter and curator
        controller.grantRole(MINTER_ROLE, address(multicall));
        controller.grantRole(GATEKEEPER_ROLE, gatekeeper);
        controller.grantRole(SIGNER_MANAGER_ROLE, signerManager);
        controller.grantRole(RESTRICTER_ROLE, restricter);
    }

    // helper function to configure manager
    function setUpManager() internal {
        vm.startPrank(owner);
        manager.grantRole(ADMIN_ROLE, admin);
        manager.grantRole(CURATOR_ROLE, curator);
        manager.grantRole(REBALANCER_ROLE, rebalancer);
        // multicall is minter and curator
        manager.grantRole(CURATOR_ROLE, address(multicall));
        manager.grantRole(GATEKEEPER_ROLE, gatekeeper);
        manager.grantRole(CAP_ADJUSTER_ROLE, capAdjuster);
        manager.setSwapModule(address(swapModule));
        manager.setRevenueModule(address(revenueModule));

        vm.startPrank(capAdjuster);
        manager.setSwapCap(address(collateral), type(uint256).max);
        manager.setSwapCap(address(collateral2), type(uint256).max);
        vm.stopPrank();
    }

    // helper function to configure staking
    function setUpStaking() internal {
        // configuration
        vm.startPrank(owner);
        staking.grantRole(REWARDER_ROLE, rewarder);
        staking.grantRole(REWARDER_ROLE, address(revenueModule));
        staking.grantRole(ADMIN_ROLE, admin);
        staking.grantRole(RESTRICTER_ROLE, restricter);
        vm.stopPrank();

        // approvals
        vm.startPrank(user);
        asset.approve(address(staking), type(uint256).max);
        staking.approve(address(staking), type(uint256).max);
        vm.stopPrank();
        vm.prank(rewarder);
        asset.approve(address(staking), type(uint256).max);
        silo = AssetSilo(staking.silo());
    }

    // helper function to configure revenue module
    function setUpRevenueModule() internal {
        vm.startPrank(owner);
        revenueModule.grantRole(REVENUE_KEEPER_ROLE, revenueKeeper);
        revenueModule.grantRole(ADMIN_ROLE, admin);
        vm.stopPrank();
    }

    // helper function to configure collateral
    function setUpConfiguration() internal {
        vm.startPrank(owner);
        multicall.grantRole(MULTICALLER_ROLE, multicaller);
        controller.setManager(address(manager));
        manager.addCollateral(address(collateral), address(vault));
        controller.setIsCollateral(address(collateral), true);
        vm.stopPrank();
    }

    // helper function to configure custodian module
    function setUpCustodianModule() internal {
        vm.startPrank(owner);
        custodianModule.grantRole(ADMIN_ROLE, admin);
        custodianModule.grantRole(CUSTODIAN_KEEPER_ROLE, custodianKeeper);
        vm.stopPrank();
    }

    function setUpDistributor() internal {
        vm.prank(curator);
        collateral.mint(address(distributor), 1000e18);
    }

    // helper to label accounts for tracing
    function label(address account, string memory newLabel) internal {
        vm.label({account: account, newLabel: newLabel});
    }

    // helper to stop current prank and start a new prank
    function resetPrank(address account) internal {
        vm.stopPrank();
        vm.startPrank(account);
    }

    // helper to mock minting asset tokens
    function mintAsset(address account, uint256 amount) internal {
        vm.prank(asset.minter());
        asset.mint(account, amount);
    }

    // helper function to add collateral to the controller
    function addCollateral(IERC20 token) internal {
        vm.prank(owner);
        controller.setIsCollateral(address(token), true);
    }

    // helper function to whitelist a signer
    function allowSigner(address signer) internal {
        vm.prank(signerManager);
        controller.setSignerStatus(signer, true);
    }

    // helper to approve controller to spend tokens
    function approveController(IERC20 token, address account, uint256 amount) internal {
        vm.prank(account);
        token.approve(address(controller), amount);
    }

    // helper function to execute a mint
    function mint(IController.Order memory order, IController.Signature memory signature) internal {
        vm.prank(minter);
        controller.mint(order, signature);
    }

    // helper function to execute a redeem
    function redeem(IController.Order memory order, IController.Signature memory signature) internal {
        vm.prank(minter);
        controller.redeem(order, signature);
    }

    // helper function to hash an order
    function hashOrder(IController.Order memory order) internal view returns (bytes32 orderHash) {
        orderHash = controller.hashOrder(order);
    }

    // helper function to get a mint order
    function getMintOrder(IERC20 collateralToken, uint256 collateralAmount, uint256 mintAmount, uint128 nonce)
        internal
        view
        returns (IController.Order memory)
    {
        return IController.Order({
            order_type: IController.OrderType.Mint,
            expiry: block.timestamp + 1000,
            nonce: nonce,
            payer: payer,
            recipient: recipient,
            collateral_token: address(collateralToken),
            collateral_amount: collateralAmount,
            asset_amount: mintAmount
        });
    }

    // helper function to get a redeem order
    function getRedeemOrder(IERC20 collateralToken, uint256 collateralAmount, uint256 redeemAmount, uint128 nonce)
        internal
        view
        returns (IController.Order memory)
    {
        return IController.Order({
            order_type: IController.OrderType.Redeem,
            expiry: block.timestamp + 1000,
            nonce: nonce,
            payer: payer,
            recipient: recipient,
            collateral_token: address(collateralToken),
            collateral_amount: collateralAmount,
            asset_amount: redeemAmount
        });
    }

    // helper function to sign an order
    function signOrder(uint256 key, bytes32 orderHash) internal pure returns (IController.Signature memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, orderHash);
        signature = IController.Signature({
            signature_type: IController.SignatureType.EIP712, signature_bytes: abi.encodePacked(r, s, v)
        });
    }

    // helper function to set oracle adapter and tolerance
    function setOracle(address adapter, uint96 tolerance) internal {
        vm.startPrank(admin);
        controller.setOracleAdapter(adapter);
        controller.setOracleTolerance(tolerance);
        vm.stopPrank();
    }

    function makeSwapData(SwapContext memory data)
        internal
        view
        returns (
            bytes memory parameters,
            bytes memory swapData,
            IAggregationRouterV6.SwapDescription memory desc,
            ISwapModule.SwapParameters memory params
        )
    {
        params = ISwapModule.SwapParameters({
            swapType: 0,
            router: address(router),
            srcToken: data.srcToken,
            dstToken: data.dstToken,
            amount: data.amount,
            minReturnAmount: data.minReturnAmount
        });

        desc = IAggregationRouterV6.SwapDescription({
            srcToken: data.token1,
            dstToken: data.token2,
            srcReceiver: payable(address(router)),
            dstReceiver: payable(address(manager)),
            amount: data.amount,
            minReturnAmount: data.minReturnAmount,
            flags: uint256(0)
        });

        parameters = abi.encode(params);
        swapData = abi.encode(data.executor, desc, new bytes(0));
    }

    function getTestBroadcaster() internal view returns (address account) {
        string memory mnemonic = vm.envString("TEST_MNEMONIC");
        console2.log("TEST_MNEMONIC: ", mnemonic);
        string memory derivationPath = "m/44'/60'/0'/0";
        // forge-lint: disable-next-line(unsafe-cheatcode)
        uint256 privateKey = vm.deriveKey(mnemonic, derivationPath, 0);
        account = vm.addr(privateKey);
    }
}
