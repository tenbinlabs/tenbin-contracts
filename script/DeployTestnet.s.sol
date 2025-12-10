// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console} from "forge-std/console.sol";
import {AssetSilo} from "src/AssetSilo.sol";
import {AssetToken} from "src/AssetToken.sol";
import {BaseScript} from "script/Base.s.sol";
import {CollateralManager} from "src/CollateralManager.sol";
import {Config} from "forge-std/Config.sol";
import {Controller} from "src/Controller.sol";
import {CustodianModule} from "src/CustodianModule.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Mock1InchRouter} from "test/mocks/Mock1InchRouter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";
import {MultiCall} from "src/MultiCall.sol";
import {RevenueModule} from "src/RevenueModule.sol";
import {StakedAsset} from "src/StakedAsset.sol";
import {SwapModule} from "src/SwapModule.sol";

/// @notice Deploy the protocol and initial configuration
/// If the broadcaster is DEFAULT_EOA, all permissions will be granted to that account.
contract DeployTestnet is BaseScript, Config {
    /// @notice Default ratio is 10%
    uint256 public constant DEFAULT_RATIO = 1e17;
    /// @notice Default cooldown length for testnet is 180 seconds
    uint128 public constant DEFAULT_COOLDOWN_PERIOD = 180 seconds;
    /// @notice Default vesting length for testnet is 1200 seconds
    uint128 public constant DEFAULT_VESTING_PERIOD = 1200 seconds;
    /// @notice USDC address
    address public constant COLLATERAL_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    /// @notice Steakhouse USDC Vault address
    address public constant VAULT_ADDRESS = 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB;
    /// @notice Default EOA when none are provided in .env
    address constant DEFAULT_EOA = 0x635ECB1700d52a1FbC395c5C92b845A00AF56a38;
    /// @notice 1Inch Aggregation Router V6
    address constant ROUTER_1INCH = 0x111111125421cA6dc452d289314280a0f8842A65;

    // Default accounts
    address internal immutable CUSTODIAN_ADDRESS;
    address internal immutable MINTER_ADDRESS;
    address internal immutable GATEKEEPER_ADDRESS;
    address internal immutable ADMIN_ADDRESS;
    address internal immutable CURATOR_ADDRESS;
    address internal immutable COLLECTOR_ADDRESS;
    address internal immutable REBALANCE_ADDRESS;
    address internal immutable MULTICALLER_ADDRESS;
    address internal immutable OWNER_ADDRESS;
    address internal immutable SIGNER_MANAGER_ADDRESS;
    address internal immutable CAP_ADJUSTER_ADDRESS;
    address internal immutable REWARDER_ADDRESS;
    address internal immutable SIGNER_ADDRESS;
    address internal immutable MULTISIG_ADDRESS;
    address internal immutable DEPLOYER_ADDRESS;
    address internal immutable KEEPER_ADDRESS;
    address internal immutable RESTRICTER_ADDRESS;

    // Roles
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant CURATOR_ROLE = keccak256("CURATOR_ROLE");
    bytes32 internal constant COLLECTOR_ROLE = keccak256("COLLECTOR_ROLE");
    bytes32 internal constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    bytes32 internal constant MULTICALLER_ROLE = keccak256("MULTICALLER_ROLE");
    bytes32 internal constant SIGNER_MANAGER_ROLE = keccak256("SIGNER_MANAGER_ROLE");
    bytes32 internal constant CAP_ADJUSTER_ROLE = keccak256("CAP_ADJUSTER_ROLE");
    bytes32 internal constant REWARDER_ROLE = keccak256("REWARDER_ROLE");
    bytes32 internal constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 internal constant RESTRICTER_ROLE = keccak256("RESTRICTER_ROLE");
    bytes32 internal constant MULTISIG_ROLE = keccak256("MULTISIG_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    /// @notice Contracts deployed by this script
    struct DeploymentResult {
        Controller controller;
        CollateralManager manager;
        AssetToken asset;
        MultiCall multicall;
        StakedAsset staking;
        SwapModule swapModule;
        MockERC20 collateral;
        MockERC4626 vault;
        Mock1InchRouter router;
        RevenueModule revenueModule;
        AssetSilo silo;
        CustodianModule custodianModule;
    }

    /// @notice Load addresses from .env or use default EOA
    constructor() {
        console.log("deploying...");
        console.log(block.chainid);
        _loadConfig("./deployments.toml", false);
        DEPLOYER_ADDRESS = config.get("deployer").toAddress();
        // require(broadcaster == DEPLOYER_ADDRESS, "broadcaster must be deployer address");
        CUSTODIAN_ADDRESS = config.get("custodian").toAddress();
        MINTER_ADDRESS = config.get("minter").toAddress();
        SIGNER_ADDRESS = config.get("signer").toAddress();
        GATEKEEPER_ADDRESS = config.get("gatekeeper").toAddress();
        ADMIN_ADDRESS = config.get("admin").toAddress();
        CURATOR_ADDRESS = config.get("curator").toAddress();
        COLLECTOR_ADDRESS = config.get("collector").toAddress();
        REBALANCE_ADDRESS = config.get("rebalancer").toAddress();
        MULTICALLER_ADDRESS = config.get("multicaller").toAddress();
        SIGNER_MANAGER_ADDRESS = config.get("signer_manager").toAddress();
        CAP_ADJUSTER_ADDRESS = config.get("cap_adjuster").toAddress();
        REWARDER_ADDRESS = config.get("rewarder").toAddress();
        OWNER_ADDRESS = config.get("owner").toAddress();
        MULTISIG_ADDRESS = config.get("multisig").toAddress();
        KEEPER_ADDRESS = config.get("keeper").toAddress();
        RESTRICTER_ADDRESS = config.get("restricter").toAddress();
    }

    function run() public broadcast returns (DeploymentResult memory deployment) {
        // deploy contracts
        deployment.asset = new AssetToken{salt: SALT}("Tenbin Gold", "tGOLD", broadcaster);
        deployment.custodianModule = new CustodianModule(broadcaster);
        deployment.controller = new Controller{salt: SALT}(
            address(deployment.asset), DEFAULT_RATIO, address(deployment.custodianModule), broadcaster
        );
        deployment.multicall = new MultiCall{salt: SALT}(broadcaster);

        // deploy manager behind a proxy
        address managerImplementation = address(new CollateralManager{salt: SALT}());
        bytes memory data =
            abi.encodeWithSelector(CollateralManager.initialize.selector, address(deployment.controller), broadcaster);
        ERC1967Proxy proxy = new ERC1967Proxy{salt: SALT}(managerImplementation, data);
        deployment.manager = CollateralManager(address(proxy));

        // deploy staking behind a proxy
        address stakingImplementation = address(new StakedAsset{salt: SALT}());
        data = abi.encodeWithSelector(
            StakedAsset.initialize.selector, "Staked Tenbin Gold", "stGOLD", deployment.asset, broadcaster
        );
        proxy = new ERC1967Proxy{salt: SALT}(stakingImplementation, data);
        deployment.staking = StakedAsset(address(proxy));
        deployment.silo = deployment.staking.silo();

        // deploy remaining contracts
        deployment.router = new Mock1InchRouter();
        deployment.swapModule = new SwapModule{salt: SALT}(address(deployment.manager), address(deployment.router));
        deployment.collateral = new MockERC20{salt: SALT}("Mock USDC", "USDC", 6);
        deployment.vault = new MockERC4626{salt: SALT}("Mock USDC Vault", "vUSDC", deployment.collateral);
        deployment.revenueModule = new RevenueModule{salt: SALT}(
            address(deployment.manager),
            address(deployment.staking),
            broadcaster,
            address(deployment.controller),
            address(deployment.asset)
        );

        console.log("\n========================= Accounts ==========================\n");
        console.log("broadcaster address: ", broadcaster);
        console.log("minter address: ", MINTER_ADDRESS);
        console.log("signer address: ", SIGNER_ADDRESS);

        // mint mock usdc
        deployment.collateral.mint(OWNER_ADDRESS, 1_000_000e6);

        // set permissions
        deployment.asset.setMinter(address(deployment.controller));
        deployment.controller.grantRole(ADMIN_ROLE, ADMIN_ADDRESS);
        deployment.controller.grantRole(MINTER_ROLE, MINTER_ADDRESS);
        deployment.controller.grantRole(MINTER_ROLE, address(deployment.multicall));
        deployment.controller.grantRole(GATEKEEPER_ROLE, GATEKEEPER_ADDRESS);
        deployment.controller.grantRole(SIGNER_MANAGER_ROLE, SIGNER_MANAGER_ADDRESS);
        deployment.controller.grantRole(RESTRICTER_ROLE, RESTRICTER_ADDRESS);
        deployment.manager.grantRole(ADMIN_ROLE, ADMIN_ADDRESS);
        deployment.manager.grantRole(CURATOR_ROLE, CURATOR_ADDRESS);
        deployment.manager.grantRole(COLLECTOR_ROLE, COLLECTOR_ADDRESS);
        deployment.manager.grantRole(REBALANCER_ROLE, REBALANCE_ADDRESS);
        deployment.manager.grantRole(CAP_ADJUSTER_ROLE, CAP_ADJUSTER_ADDRESS);
        deployment.manager.grantRole(CURATOR_ROLE, address(deployment.multicall));
        deployment.manager.grantRole(GATEKEEPER_ROLE, GATEKEEPER_ADDRESS);
        deployment.manager.grantRole(COLLECTOR_ROLE, address(deployment.revenueModule));
        deployment.multicall.grantRole(MULTICALLER_ROLE, MULTICALLER_ADDRESS);
        deployment.staking.grantRole(ADMIN_ROLE, ADMIN_ADDRESS);
        deployment.staking.grantRole(REWARDER_ROLE, MULTISIG_ADDRESS);
        deployment.staking.grantRole(REWARDER_ROLE, address(deployment.revenueModule));
        deployment.staking.grantRole(RESTRICTER_ROLE, RESTRICTER_ADDRESS);
        deployment.revenueModule.grantRole(KEEPER_ROLE, KEEPER_ADDRESS);
        deployment.revenueModule.grantRole(MULTISIG_ROLE, MULTISIG_ADDRESS);
        deployment.custodianModule.grantRole(KEEPER_ROLE, KEEPER_ADDRESS);

        // configuration
        deployment.controller.grantRole(ADMIN_ROLE, broadcaster);
        deployment.controller.grantRole(SIGNER_MANAGER_ROLE, broadcaster);
        deployment.controller.setSignerStatus(SIGNER_ADDRESS, true);
        deployment.manager.grantRole(ADMIN_ROLE, broadcaster);
        deployment.manager.addCollateral(address(deployment.collateral), address(deployment.vault));
        deployment.manager.setSwapModule(address(deployment.swapModule));
        deployment.controller.setIsCollateral(address(deployment.collateral), true);
        deployment.controller.setManager(address(deployment.manager));
        deployment.staking.grantRole(ADMIN_ROLE, broadcaster);
        deployment.staking.setCooldownPeriod(DEFAULT_COOLDOWN_PERIOD);
        deployment.staking.setVestingPeriod(DEFAULT_VESTING_PERIOD);
        deployment.custodianModule.setCustodianStatus(CUSTODIAN_ADDRESS, true);

        // transfer ownership
        deployment.manager.grantRole(DEFAULT_ADMIN_ROLE, OWNER_ADDRESS);
        deployment.controller.grantRole(DEFAULT_ADMIN_ROLE, OWNER_ADDRESS);
        deployment.multicall.grantRole(DEFAULT_ADMIN_ROLE, OWNER_ADDRESS);
        deployment.staking.grantRole(DEFAULT_ADMIN_ROLE, OWNER_ADDRESS);
        deployment.revenueModule.grantRole(DEFAULT_ADMIN_ROLE, OWNER_ADDRESS);
        deployment.custodianModule.grantRole(DEFAULT_ADMIN_ROLE, OWNER_ADDRESS);
        deployment.asset.transferOwnership(OWNER_ADDRESS);

        // additionally allow multisig to manage ownership on testnet
        deployment.manager.grantRole(DEFAULT_ADMIN_ROLE, MULTISIG_ADDRESS);
        deployment.controller.grantRole(DEFAULT_ADMIN_ROLE, MULTISIG_ADDRESS);
        deployment.multicall.grantRole(DEFAULT_ADMIN_ROLE, MULTISIG_ADDRESS);
        deployment.staking.grantRole(DEFAULT_ADMIN_ROLE, MULTISIG_ADDRESS);
        deployment.revenueModule.grantRole(DEFAULT_ADMIN_ROLE, MULTISIG_ADDRESS);
        deployment.custodianModule.grantRole(DEFAULT_ADMIN_ROLE, MULTISIG_ADDRESS);

        // renounce deployer roles (except for local dev)
        if (block.chainid != 31337) {
            deployment.controller.revokeRole(ADMIN_ROLE, broadcaster);
            deployment.controller.revokeRole(SIGNER_MANAGER_ROLE, broadcaster);
            deployment.manager.revokeRole(ADMIN_ROLE, broadcaster);
            deployment.manager.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.controller.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.multicall.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.staking.revokeRole(ADMIN_ROLE, broadcaster);
            deployment.staking.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.revenueModule.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
            deployment.custodianModule.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);
        }

        // mint some tokens to deployer
        deployment.collateral.mint(broadcaster, 1_000_000e6);
        deployment.collateral.approve(address(deployment.controller), 1_000_000e6);

        console.log("\n========================= Domain ============================\n");
        console.log("domain separator: ");
        console.logBytes32(deployment.controller.getDomainSeparator());
        console.log("order typehash: ");
        console.logBytes32(
            keccak256(
                "Order(uint8 order_type,uint256 nonce,uint256 expiry,address payer,address recipient,address collateral_token,uint256 collateral_amount,uint256 asset_amount)"
            )
        );
        console.log("\n========================= Contracts =========================\n");
        console.log("Controller: ", address(deployment.controller));
        console.log("CollateralManager: ", address(deployment.manager));
        console.log("AssetToken: ", address(deployment.asset));
        console.log("MultiCall: ", address(deployment.multicall));
        console.log("StakedAsset: ", address(deployment.staking));
        console.log("AssetSilo : ", address(deployment.silo));
        console.log("SwapModule: ", address(deployment.swapModule));
        console.log("MockERC20: ", address(deployment.collateral));
        console.log("MockERC4626: ", address(deployment.vault));
        console.log("Mock1InchRouter: ", address(deployment.router));
        console.log("RevenueModule : ", address(deployment.revenueModule));
        console.log("CustodianModule : ", address(deployment.custodianModule));

        console.log("\n=============================================================\n");
        console.log("\nSerializing json...\n");
        string memory key = "deployments";
        string memory obj = "{}";
        obj = vm.serializeAddress(key, "collateral_manager", address(deployment.manager));
        obj = vm.serializeAddress(key, "controller", address(deployment.controller));
        obj = vm.serializeAddress(key, "multicall", address(deployment.multicall));
        obj = vm.serializeAddress(key, "staked_asset", address(deployment.staking));
        obj = vm.serializeAddress(key, "swap_module", address(deployment.swapModule));
        obj = vm.serializeAddress(key, "asset_token", address(deployment.asset));
        obj = vm.serializeAddress(key, "collateral", address(deployment.collateral));
        obj = vm.serializeAddress(key, "revenue_module", address(deployment.revenueModule));
        obj = vm.serializeAddress(key, "custodian_module", address(deployment.custodianModule));
        obj = vm.serializeAddress(key, "silo", address(deployment.silo));
        obj = vm.serializeAddress(key, "deployer", DEPLOYER_ADDRESS);
        obj = vm.serializeAddress(key, "multisig", MULTISIG_ADDRESS);
        obj = vm.serializeAddress(key, "keeper", KEEPER_ADDRESS);
        obj = vm.serializeAddress(key, "owner", OWNER_ADDRESS);
        obj = vm.serializeAddress(key, "custodian", CUSTODIAN_ADDRESS);
        obj = vm.serializeAddress(key, "minter", MINTER_ADDRESS);
        obj = vm.serializeAddress(key, "multicaller", MULTICALLER_ADDRESS);
        obj = vm.serializeAddress(key, "signer", SIGNER_ADDRESS);
        obj = vm.serializeAddress(key, "rebalance", REBALANCE_ADDRESS);
        obj = vm.serializeAddress(key, "gatekeeper", GATEKEEPER_ADDRESS);
        obj = vm.serializeAddress(key, "admin", ADMIN_ADDRESS);
        obj = vm.serializeAddress(key, "curator", CURATOR_ADDRESS);
        obj = vm.serializeAddress(key, "collector", COLLECTOR_ADDRESS);
        obj = vm.serializeAddress(key, "signer_manager", SIGNER_MANAGER_ADDRESS);
        obj = vm.serializeAddress(key, "cap_adjuster", CAP_ADJUSTER_ADDRESS);
        obj = vm.serializeAddress(key, "rewarder", REWARDER_ADDRESS);
        obj = vm.serializeAddress(key, "restricter", RESTRICTER_ADDRESS);

        string memory path = string.concat("broadcast/DeployTestnet.s.sol/", vm.toString(block.chainid));
        vm.createDir(path, true);
        vm.writeJson(obj, string.concat(path, "/deployments.json"));

        console.log("\n=============================================================\n");
        console.log(
            "\n  __/\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\__________________________/\\\\\\____________________________        "
        );
        console.log(" _\\///////\\\\\\/////__________________________\\/\\\\\\____________________________       ");
        console.log("  _______\\/\\\\\\_______________________________\\/\\\\\\_________/\\\\\\_______________      ");
        console.log(
            "   _______\\/\\\\\\______/\\\\\\\\\\\\\\\\___/\\\\/\\\\\\\\\\\\___\\/\\\\\\________\\///___/\\\\/\\\\\\\\\\\\___     "
        );
        console.log(
            "    _______\\/\\\\\\____/\\\\\\/////\\\\\\_\\/\\\\\\////\\\\\\__\\/\\\\\\\\\\\\\\\\\\___/\\\\\\_\\/\\\\\\////\\\\\\__    "
        );
        console.log(
            "     _______\\/\\\\\\___/\\\\\\\\\\\\\\\\\\\\\\__\\/\\\\\\__\\//\\\\\\_\\/\\\\\\////\\\\\\_\\/\\\\\\_\\/\\\\\\__\\//\\\\\\_   "
        );
        console.log(
            "      _______\\/\\\\\\__\\//\\\\///////___\\/\\\\\\___\\/\\\\\\_\\/\\\\\\__\\/\\\\\\_\\/\\\\\\_\\/\\\\\\___\\/\\\\\\_  "
        );
        console.log(
            "       _______\\/\\\\\\___\\//\\\\\\\\\\\\\\\\\\\\_\\/\\\\\\___\\/\\\\\\_\\/\\\\\\\\\\\\\\\\\\__\\/\\\\\\_\\/\\\\\\___\\/\\\\\\_ "
        );
        console.log("        _______\\///_____\\//////////__\\///____\\///__\\/////////___\\///__\\///____\\///__\n");
    }

    // mark this as a test contract
    function test() public {}
}
