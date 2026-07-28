// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetSilo} from "tenbin-contracts/src/AssetSilo.sol";
import {console2} from "forge-std/console2.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {ERC1967Proxy} from "tenbin-contracts/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "tenbin-contracts/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {StakedAsset} from "tenbin-contracts/src/StakedAsset.sol";

/// @notice Deploy and configure new staking contract using config/*.toml
/// @dev Deploy a new staking contract and perform dead deposit for 0.001 tokens
/// 1. Ensure addresses and version are correctly set in `scripts/DeployStaking.s.sol`
/// 2. Ensure the deployer address has at least 0.001 asset tokens
/// 3. Run script to deploy new StakedAsset
/// 4. Deploy a new Controller and RevenueModule
/// 5. Grant REWARDER_ROLE to new RevenueModule
/// 6. Grant INSTANT_UNSTAKER_ROLE to new Controller
///
/// Running this script:
/// FOUNDRY_PROFILE=production forge script script/DeployStaking.s.sol $CONFIG_DIR --rpc-url $MAINNET_RPC_URL --private-key $BROADCASTER_KEY --verify --verifier etherscan --verifier-api-key $ETHERSCAN_API_KEY --slow
contract DeployStaking is DeployBase {
    /// @notice Default mainnet config directory to be used if none was specified
    string constant DEFAULT_DIR = "./config/mainnet/tgld/tgld.toml";

    // configuration
    string constant TARGET_VERSION = "1.4.3";
    address constant ASSET_TOKEN_ADDRESS = 0x6a547b25534234bb79CE6961a23Db13DE154b6F4;
    uint256 public constant DEAD_DEPOSIT_AMOUNT = 0.001e18; // 0.001 asset tokens

    /// @notice Results returned when running this deployment script
    struct DeploymentResult {
        address broadcaster;
        StakedAsset staked_asset;
        AssetSilo silo;
    }

    /// @dev The version for this deployment
    function getVersion() internal pure override returns (string memory) {
        return TARGET_VERSION;
    }

    function run(string memory configDir) public returns (DeploymentResult memory deployment) {
        loadCoreConfig(configDir);
        loadRolesConfig();
        deployment = deploy();
    }

    function deploy() internal broadcast returns (DeploymentResult memory deployment) {
        console2.log("\n========================= Accounts ==========================\n");
        console2.log("broadcaster address: ", broadcaster);

        // save broadcaster
        deployment.broadcaster = broadcaster;

        // ensure broadcaster has sufficient balance
        if (IERC20(ASSET_TOKEN_ADDRESS).balanceOf(broadcaster) < DEAD_DEPOSIT_AMOUNT) {
            revert("Insufficient balance for dead deposit.");
        }

        // deploy staking behind a proxy
        address stakingImplementation = address(new StakedAsset{salt: SALT}());
        bytes memory data = abi.encodeWithSelector(
            StakedAsset.initialize.selector,
            coreParams.staked_asset_name,
            coreParams.staked_asset_symbol,
            ASSET_TOKEN_ADDRESS,
            broadcaster
        );
        ERC1967Proxy proxy = new ERC1967Proxy{salt: SALT}(stakingImplementation, data);
        deployment.staked_asset = StakedAsset(address(proxy));
        deployment.silo = AssetSilo(address(deployment.staked_asset.silo()));

        deployment.staked_asset.grantRole(DEFAULT_ADMIN_ROLE, roles.default_admin_role);
        deployment.staked_asset.grantRole(ADMIN_ROLE, roles.admin_role);
        deployment.staked_asset.grantRole(REWARDER_ROLE, coreParams.multisig);
        deployment.staked_asset.grantRole(RESTRICTER_ROLE, roles.restricter_role);
        deployment.staked_asset.grantRole(CAP_ADJUSTER_ROLE, roles.cap_adjuster_role);

        // give temporary permissions to broadcaster
        deployment.staked_asset.grantRole(ADMIN_ROLE, broadcaster);
        deployment.staked_asset.grantRole(CAP_ADJUSTER_ROLE, broadcaster);

        // configure staking
        deployment.staked_asset.setCooldownPeriod(coreParams.cooldown_period);
        deployment.staked_asset.setVestingPeriod(uint128(coreParams.vesting_period));
        deployment.staked_asset.setInstantUnstakeCap(coreParams.instant_unstake_cap);

        // revoke permissions from broadcaster
        deployment.staked_asset.revokeRole(ADMIN_ROLE, broadcaster);
        deployment.staked_asset.revokeRole(CAP_ADJUSTER_ROLE, broadcaster);
        deployment.staked_asset.revokeRole(DEFAULT_ADMIN_ROLE, broadcaster);

        // Perform dead deposit
        IERC20(ASSET_TOKEN_ADDRESS).approve(address(deployment.staked_asset), DEAD_DEPOSIT_AMOUNT);
        deployment.staked_asset.deposit(DEAD_DEPOSIT_AMOUNT, address(0xDEAD));

        // Serialize json and print contracts
        serialize(deployment);
        printContracts(deployment);
        printLogo();
    }

    function serialize(DeploymentResult memory deployment) internal {
        console2.log("\nSerializing json...\n");

        // Build objects and keys
        string memory obj = "{}";
        string memory chainKey = "mainnet";

        string memory assetKey = "tGLD";
        string memory contractsObj = "{}";
        string memory contractsKey = "contracts";
        string memory configKey = "config";
        string memory configObj = "{}";

        // serialize contracts
        contractsObj = vm.serializeAddress(contractsKey, "staked_asset", address(deployment.staked_asset));
        contractsObj = vm.serializeAddress(contractsKey, "silo", address(deployment.silo));

        // serialize config
        configObj = vm.serializeUint(configKey, "deployment_block", block.number);
        configObj = vm.serializeString(configKey, "version", TARGET_VERSION);
        configObj = vm.serializeAddress(configKey, "deployer", broadcaster);

        // build final object
        vm.serializeString(assetKey, configKey, configObj);
        string memory assetJson = vm.serializeString(assetKey, contractsKey, contractsObj);
        string memory chainJson = vm.serializeString(chainKey, assetKey, assetJson);

        // Wrap under chainKey
        obj = vm.serializeString("root", chainKey, chainJson);

        // save to file
        string memory path = string.concat("broadcast/DeployStaking.s.sol/", vm.toString(block.chainid));
        vm.createDir(path, true);
        vm.writeJson(obj, string.concat(path, "/contracts.json"));
    }

    function printContracts(DeploymentResult memory deployment) internal pure {
        console2.log("\n========================= Contracts =========================\n");
        console2.log("StakedAsset: ", address(deployment.staked_asset));
        console2.log("AssetSilo: ", address(deployment.silo));
        console2.log("\n=============================================================\n");
    }
}
