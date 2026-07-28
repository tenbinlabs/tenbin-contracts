// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkBaseTest} from "../ForkBaseTest.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";

/// @notice Base contract to perform extraction of the deployed contracts into struct variables
contract MonitorBase is ForkBaseTest {
    /// @notice 1Inch Router address on mainnet
    address internal constant ONE_INCH_ROUTER = 0x111111125421cA6dc452d289314280a0f8842A65;

    /// @notice address of merkl.xyz rewards distributor
    address internal constant DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    /// @notice The multisig responsible for collecting the merkl.xyz rewards
    address internal constant REWARD_RECIPIENT = 0x76D1415AB9d2CB6A790499a36313F5B700CF035d;

    /// @notice tGLD collateral manger contract
    address internal constant TGLD_MANAGER = 0x42F3F01D45E67294e20cE98AcFDC24dD7EA75dEa;

    /// @notice Contracts previously deployed
    struct DeployedContracts {
        address asset_token;
        address collateral;
        address collateral_manager;
        address controller;
        address custodian_module;
        address multicall;
        address oracle_adapter;
        address revenue_module;
        address silo;
        address staked_asset;
        address swap_module;
    }

    /// @notice Correct role holders
    struct Roles {
        address[] admin_role;
        address[] cap_adjuster_role;
        address[] curator_role;
        address[] custodian_keeper_role;
        address[] default_admin_role;
        address[] gatekeeper_role;
        address[] minter_role;
        address[] multicaller_role;
        address[] rebalancer_role;
        address[] restricter_role;
        address[] revenue_keeper_role;
        address[] rewarder_role;
        address[] signer_manager_role;
    }

    /// @notice Global multisigs
    struct GlobalAccounts {
        address admin_multisig;
        bytes custodians;
        address dev_multisig;
        address owner_multisig;
        address tenbin_multisig;
    }

    /// @notice Vault related contracts
    struct VaultContracts {
        address gate;
        address vault;
    }

    /// @notice Vault liquidity adapter (field order matches alphabetized JSON keys)
    struct VaultAdapter {
        address addr;
        bytes32 id;
        string name;
    }

    DeployedContracts internal contracts;
    Roles internal roles;
    GlobalAccounts internal global;
    VaultContracts internal vaultContracts;
    VaultAdapter[] internal vaultAdapters;
    string internal assetName = "tGLD";

    function setUp() public virtual override {
        super.setUp();
        // Some tests makes changes on the fork, this is a counter meassure to avoid race conditions when running concurrent tests
        string memory rpc = vm.rpcUrl("mainnet");
        vm.createSelectFork(rpc);
        // load testnet addresses
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile("./deployments.json");

        // get system contracts
        contracts =
            abi.decode(vm.parseJson(json, string.concat(".mainnet.", assetName, ".contracts")), (DeployedContracts));

        // get vault contracts
        vaultContracts = VaultContracts({
            gate: abi.decode(
                vm.parseJson(json, string.concat(".mainnet.", assetName, ".vault.contracts.gate")), (address)
            ),
            vault: abi.decode(
                vm.parseJson(json, string.concat(".mainnet.", assetName, ".vault.contracts.vault")), (address)
            )
        });

        // get vault adapters
        VaultAdapter[] memory parsedAdapters =
            abi.decode(vm.parseJson(json, string.concat(".mainnet.", assetName, ".vault.adapters")), (VaultAdapter[]));
        assertGt(parsedAdapters.length, 0);
        for (uint256 i = 0; i < parsedAdapters.length; i++) {
            vaultAdapters.push(parsedAdapters[i]);
        }

        // get roles
        roles.admin_role =
            abi.decode(vm.parseJson(json, string.concat(".mainnet.", assetName, ".roles.admin_role")), (address[]));
        roles.cap_adjuster_role = abi.decode(
            vm.parseJson(json, string.concat(".mainnet.", assetName, ".roles.cap_adjuster_role")), (address[])
        );
        roles.curator_role =
            abi.decode(vm.parseJson(json, string.concat(".mainnet.", assetName, ".roles.curator_role")), (address[]));
        roles.custodian_keeper_role = abi.decode(
            vm.parseJson(json, string.concat(".mainnet.", assetName, ".roles.custodian_keeper_role")), (address[])
        );
        roles.default_admin_role = abi.decode(
            vm.parseJson(json, string.concat(".mainnet.", assetName, ".roles.default_admin_role")), (address[])
        );
        roles.gatekeeper_role = abi.decode(
            vm.parseJson(json, string.concat(".mainnet.", assetName, ".roles.gatekeeper_role")), (address[])
        );
        roles.minter_role =
            abi.decode(vm.parseJson(json, string.concat(".mainnet.", assetName, ".roles.minter_role")), (address[]));
        roles.multicaller_role = abi.decode(
            vm.parseJson(json, string.concat(".mainnet.", assetName, ".roles.multicaller_role")), (address[])
        );
        roles.rebalancer_role = abi.decode(
            vm.parseJson(json, string.concat(".mainnet.", assetName, ".roles.rebalancer_role")), (address[])
        );
        roles.restricter_role = abi.decode(
            vm.parseJson(json, string.concat(".mainnet.", assetName, ".roles.restricter_role")), (address[])
        );
        roles.revenue_keeper_role = abi.decode(
            vm.parseJson(json, string.concat(".mainnet.", assetName, ".roles.revenue_keeper_role")), (address[])
        );
        roles.rewarder_role =
            abi.decode(vm.parseJson(json, string.concat(".mainnet.", assetName, ".roles.rewarder_role")), (address[]));
        roles.signer_manager_role = abi.decode(
            vm.parseJson(json, string.concat(".mainnet.", assetName, ".roles.signer_manager_role")), (address[])
        );

        // get global accounts
        global = abi.decode(vm.parseJson(json, ".mainnet.global"), (GlobalAccounts));
    }

    // Helper to call hasRole on each address
    function _hasRole(address deployedContract, bytes32 roleId, address[] memory addresses)
        internal
        view
        returns (bool res)
    {
        res = true;
        for (uint256 i = 0; i < addresses.length; i++) {
            if (!AccessControl(deployedContract).hasRole(roleId, addresses[i])) {
                res = false;
                break;
            }
        }

        return res;
    }
}
