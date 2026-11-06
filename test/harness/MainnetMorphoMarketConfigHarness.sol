// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MarketParams} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {DeployBase} from "../../script/DeployBase.s.sol";
import {MorphoAdapterDeployer} from "../../script/MorphoAdapterDeployer.s.sol";

/// @notice Exposes the deploy script's config loading so checked-in TOMLs can be asserted without broadcasting
contract MainnetMorphoMarketConfigHarness is Deploy {
    function load(string memory vaultConfigDir) external {
        loadVaultConfig(vaultConfigDir);
        loadAdapterConfigs(vaultConfigDir);
        loadMarketConfigs(vaultConfigDir);
    }

    function vaultParameters() external view returns (DeployBase.VaultParameters memory) {
        return vaultParams;
    }

    function loadWithLiquidityAdapter(string memory vaultConfigDir, string memory adapter) external {
        loadVaultConfig(vaultConfigDir);
        vaultParams.liquidity_adapter = adapter;
        loadAdapterConfigs(vaultConfigDir);
    }

    function adapterParameters(uint256 index) external view returns (MorphoAdapterDeployer.AdapterParameters memory) {
        return adapterParamsList[index];
    }

    function marketParameters(uint256 index)
        external
        view
        returns (MorphoAdapterDeployer.MarketParameters memory configured, MarketParams memory params)
    {
        configured = marketConfigList[index];
        params = toMarketParams(configured);
    }

    function adapterCount() external view returns (uint256) {
        return adapterParamsList.length;
    }

    function marketCount() external view returns (uint256) {
        return marketConfigList.length;
    }
}
