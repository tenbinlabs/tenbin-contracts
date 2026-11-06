// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {MorphoAdapterDeployer} from "./MorphoAdapterDeployer.s.sol";

/// @notice Deploy a morpho adapter for an existing morpho v2 parent vault, driven by a TOML config file
/// (config/{chain}/{asset}/adapters/{adapter}.toml). See MorphoAdapterDeployer for the adapter_type
/// dispatch and per-chain factory resolution.
/// Supported chains: mainnet (1), sepolia (11155111), local dev (31337).
/// Configs with is_new_adapter = false are skipped without deploying anything.
///
/// FOUNDRY_PROFILE=production forge script script/DeployMorphoAdapter.s.sol --sig "run(string)" $ADAPTER_CONFIG --rpc-url $MAINNET_RPC_URL --account "$BROADCASTER_ACCOUNT" --sender "$BROADCASTER_ADDRESS" --verify --verifier etherscan --verifier-api-key $ETHERSCAN_API_KEY --slow
/// Add --broadcast to broadcast. Record the adapter address in deployments.json afterwards;
/// For adapters deployed for existing vaults, a timelock tx will need to be created to add the adapter to its respective vault
/// Validate a deployed MARKET adapter (`$ADAPTER` is its address and the adapter config must set
/// `is_new_adapter = false`): `forge script script/DeployMorphoAdapter.s.sol --sig
/// "runExisting(string,string,address)" $ADAPTER_CONFIG $VAULT_CONFIG $ADAPTER --rpc-url $MAINNET_RPC_URL`.
/// This read-only path must never be run with `--broadcast`.
contract DeployMorphoAdapter is MorphoAdapterDeployer {
    // configuration
    string constant TARGET_VERSION = "1.4.3";

    /// @notice Results returned when running this deployment script
    struct DeploymentResult {
        address broadcaster;
        address factory;
        address adapter;
    }

    /// @notice Validated addresses and ids for an already-deployed market adapter
    struct ExistingAdapterResult {
        address factory;
        address adapter;
        bytes32 adapter_id;
        bytes32 market_id;
        bytes32 collateral_cap_id;
        bytes32 market_cap_id;
    }

    /// @notice Adapter parameters loaded from the adapter config file
    AdapterParameters internal adapterParams;

    /// @dev The version for this deployment
    function getVersion() internal pure override returns (string memory) {
        return TARGET_VERSION;
    }

    function run(string memory configDir) public returns (DeploymentResult memory deployment) {
        require(block.chainid == 1 || block.chainid == 11155111 || block.chainid == 31337, "chain not supported");

        adapterParams = loadAdapterParams(configDir);

        if (!adapterParams.is_new_adapter) {
            console2.log("is_new_adapter = false, skipping deployment");
            deployment.broadcaster = broadcaster;
            return deployment;
        }

        deployment = deploy();
    }

    /// @notice Validate an existing mainnet market adapter and print every timelocked registration payload.
    /// This path never broadcasts or calls a state-changing function.
    function runExisting(string memory adapterConfigDir, string memory vaultConfigDir, address adapter)
        public
        returns (ExistingAdapterResult memory result)
    {
        ExistingMarketAdapterData memory data;
        (adapterParams, data) = loadAndValidateExistingMarketAdapter(adapterConfigDir, vaultConfigDir, adapter);
        require(!IVaultV2(adapterParams.parent).isAdapter(adapter), "adapter already registered with parent");
        result = ExistingAdapterResult({
            factory: data.factory,
            adapter: adapter,
            adapter_id: data.adapter_id,
            market_id: data.market_id,
            collateral_cap_id: data.collateral_cap_id,
            market_cap_id: data.market_cap_id
        });

        printExistingPayloads(
            result,
            data.adapter_id_data,
            data.collateral_cap_id_data,
            data.market_cap_id_data,
            data.absolute_cap,
            data.relative_cap
        );
    }

    function deploy() internal broadcast returns (DeploymentResult memory deployment) {
        console2.log("\n========================= Accounts ==========================\n");
        console2.log("broadcaster address: ", broadcaster);

        // save broadcaster
        deployment.broadcaster = broadcaster;

        (deployment.factory, deployment.adapter) = deployAdapter(adapterParams);

        printContracts(deployment);
        printLogo();
    }

    function printContracts(DeploymentResult memory deployment) internal view {
        console2.log("\n========================= Contracts =========================\n");
        console2.log("adapter type: ", adapterParams.adapter_type);
        console2.log("adapter name: ", adapterParams.name);
        console2.log("factory: ", deployment.factory);
        console2.log("adapter: ", deployment.adapter);
        console2.log("absolute cap: ", adapterParams.absolute_cap);
        console2.log("relative cap: ", adapterParams.relative_cap);

        console2.log("\n================== Curator submit payloads ==================\n");
        bytes memory adapterId = abi.encode("this", deployment.adapter);
        console2.log("addAdapter:");
        console2.logBytes(abi.encodeCall(IVaultV2.addAdapter, (deployment.adapter)));

        // TODO ENG-2553: Log curator submit payloads when running individual adapter deploy scripts
        if (stringMatches(adapterParams.adapter_type, "MARKET")) {
            console2.log("Individual curator submit payloads required for setting market caps");
        } else {
            console2.log("increaseRelativeCap:");
            console2.logBytes(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterId, adapterParams.relative_cap)));
            console2.log("\n=============================================================\n");
            console2.log("increaseAbsoluteCap:");
            console2.logBytes(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterId, adapterParams.absolute_cap)));
        }
    }

    /// @notice Print submit and post-timelock execution calldata for an existing market adapter.
    function printExistingPayloads(
        ExistingAdapterResult memory result,
        bytes memory adapterId,
        bytes memory collateralCapId,
        bytes memory marketCapId,
        uint256 marketAbsoluteCap,
        uint256 marketRelativeCap
    ) internal view {
        console2.log("\n================ Existing market adapter ===================\n");
        console2.log("factory:", result.factory);
        console2.log("adapter:", result.adapter);
        console2.log("parent vault:", adapterParams.parent);
        console2.log("market id:");
        console2.logBytes32(result.market_id);

        bytes4[] memory selectors = marketAdapterTimelockSelectors();
        for (uint256 i = 0; i < selectors.length; i++) {
            bytes memory executionPayload = abi.encodeCall(
                IMorphoMarketV1AdapterV2.increaseTimelock, (selectors[i], vaultParams.timelock_duration)
            );
            console2.log("\nmarket adapter timelock selector:");
            console2.logBytes4(selectors[i]);
            console2.log("target:", result.adapter);
            console2.log("submit calldata:");
            console2.logBytes(abi.encodeCall(IMorphoMarketV1AdapterV2.submit, (executionPayload)));
            console2.log("post-timelock execution calldata:");
            console2.logBytes(executionPayload);
        }

        printVaultOperation("add adapter", abi.encodeCall(IVaultV2.addAdapter, (result.adapter)));
        printCapOperations("adapter", adapterId, adapterParams.absolute_cap, adapterParams.relative_cap);
        printCapOperations("collateral", collateralCapId, marketAbsoluteCap, marketRelativeCap);
        printCapOperations("market", marketCapId, marketAbsoluteCap, marketRelativeCap);
    }

    /// @notice Print the absolute and relative cap operations for one vault cap id.
    function printCapOperations(string memory scope, bytes memory id, uint256 absoluteCap, uint256 relativeCap)
        internal
        view
    {
        console2.log(string.concat("\n", scope, " absolute cap:"), absoluteCap);
        printVaultOperation(
            string.concat(scope, " absolute cap"), abi.encodeCall(IVaultV2.increaseAbsoluteCap, (id, absoluteCap))
        );
        console2.log(string.concat("\n", scope, " relative cap:"), relativeCap);
        printVaultOperation(
            string.concat(scope, " relative cap"), abi.encodeCall(IVaultV2.increaseRelativeCap, (id, relativeCap))
        );
    }

    /// @notice Print the parent-vault target plus submit and execution calldata for one operation.
    function printVaultOperation(string memory label, bytes memory executionPayload) internal view {
        console2.log(string.concat("\n", label));
        console2.log("target:", adapterParams.parent);
        console2.log("submit calldata:");
        console2.logBytes(abi.encodeCall(IVaultV2.submit, (executionPayload)));
        console2.log("post-timelock execution calldata:");
        console2.logBytes(executionPayload);
    }
}
