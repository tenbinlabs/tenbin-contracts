// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CollateralManager} from "tenbin-contracts/src/CollateralManager.sol";
import {Gate} from "tenbin-contracts/src/external/morpho/Gate.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {MonitorBase} from "./MonitorBase.sol";

/// @notice General vault assumptions that must always hold to ensure a healthy state
contract VaultChecksBase is MonitorBase {
    struct VaultParams {
        address allocator;
        address asset;
        address curator;
        address initial_vault;
        address owner;
        address sentinel;
        address manager;
        string name;
        string symbol;
        uint256 dead_deposit;
        uint256 initial_absolute_cap;
        uint256 initial_relative_cap;
        uint256 max_rate;
        uint256 timelock_duration;
    }

    VaultParams vaultParams;

    function setUp() public virtual override {
        super.setUp();
        loadVaultConfig(
            string.concat("./config/mainnet/", toLower(assetName), "/vaults/", toLower(assetName), "_usdc_vault.toml")
        );
    }

    // Gate
    // Manager should always be the account permitted by the gate
    function testGateResponses() public view {
        assertTrue(Gate(vaultContracts.gate).canReceiveAssets(contracts.collateral_manager));
        assertTrue(Gate(vaultContracts.gate).canReceiveShares(contracts.collateral_manager));
        assertTrue(Gate(vaultContracts.gate).canSendAssets(contracts.collateral_manager));
        assertTrue(Gate(vaultContracts.gate).canSendShares(contracts.collateral_manager));
    }

    // Vault
    // Roles are correct
    function testVaultCorrectness() public view {
        assertEq(IVaultV2(vaultContracts.vault).owner(), global.owner_multisig);
        assertEq(IVaultV2(vaultContracts.vault).curator(), global.admin_multisig);
        assertEq(IVaultV2(vaultContracts.vault).sendAssetsGate(), vaultContracts.gate);
        assertEq(IVaultV2(vaultContracts.vault).receiveAssetsGate(), vaultContracts.gate);
        assertEq(IVaultV2(vaultContracts.vault).sendSharesGate(), vaultContracts.gate);
        assertEq(IVaultV2(vaultContracts.vault).receiveSharesGate(), vaultContracts.gate);
        assertTrue(IVaultV2(vaultContracts.vault).isSentinel(vaultParams.sentinel));
        assertTrue(IVaultV2(vaultContracts.vault).isAllocator(vaultParams.allocator));
    }

    // Zero fees require zero fee recipients
    function testNoFees() public view {
        // performanceFee;
        bool hasFee = IVaultV2(vaultContracts.vault).performanceFee() > 0;
        bool hasRecipient = IVaultV2(vaultContracts.vault).performanceFeeRecipient() != address(0);
        assertTrue((hasFee && hasRecipient) || (!hasFee && !hasRecipient));

        // managementFee
        hasFee = IVaultV2(vaultContracts.vault).managementFee() > 0;
        hasRecipient = IVaultV2(vaultContracts.vault).managementFeeRecipient() != address(0);
        assertTrue((hasFee && hasRecipient) || (!hasFee && !hasRecipient));
    }

    // Vault should not get stale
    function testVaultStaleness() public view {
        uint256 dateDiff = block.timestamp - IVaultV2(vaultContracts.vault).lastUpdate();
        assertLe(dateDiff, 9 days);
    }

    // Every listed adapter must be an adapter inside the vault with a correctly
    // recorded id, and the vault's liquidity adapter must be one of them unless
    // it is disabled (address(0))
    function testVaultAdapter() public view {
        address liquidityAdapter = IVaultV2(vaultContracts.vault).liquidityAdapter();
        bool liquidityAdapterListed = false;
        for (uint256 i = 0; i < vaultAdapters.length; i++) {
            assertTrue(IVaultV2(vaultContracts.vault).isAdapter(vaultAdapters[i].addr));
            assertEq(vaultAdapters[i].id, keccak256(abi.encode("this", vaultAdapters[i].addr)));
            liquidityAdapterListed = liquidityAdapterListed || vaultAdapters[i].addr == liquidityAdapter;
        }
        assertTrue(liquidityAdapter == address(0) || liquidityAdapterListed);
    }

    // Vault asset must match accepted collateral
    function testVaultAsset() public view {
        assertEq(IVaultV2(vaultContracts.vault).asset(), vaultParams.asset);
        // we check if a token is collateral based on the vault not being the zero address
        address currentVault =
            address(CollateralManager(contracts.collateral_manager).vaults(IVaultV2(vaultContracts.vault).asset()));
        assertNotEq(currentVault, address(0));
    }

    // Vault must not exceed caps
    function testVaultSupply() public view {
        for (uint256 i = 0; i < vaultAdapters.length; i++) {
            uint256 allocation = IVaultV2(vaultContracts.vault).allocation(vaultAdapters[i].id);
            uint256 absoluteCap = IVaultV2(vaultContracts.vault).absoluteCap(vaultAdapters[i].id);
            assertLe(allocation, absoluteCap);
        }
    }

    // Name and symbol should hold
    function testVaultMetadata() public view {
        assertEq(IVaultV2(vaultContracts.vault).name(), vaultParams.name);
        assertEq(IVaultV2(vaultContracts.vault).symbol(), vaultParams.symbol);
    }

    // Supply must be at least dead deposit
    function testVaultDeposit() public view {
        assertGe(IVaultV2(vaultContracts.vault).totalSupply(), vaultParams.dead_deposit);
    }

    // helper
    function loadVaultConfig(string memory configDir) internal {
        //delete vaultParams;

        string memory toml = vm.readFile(configDir);

        // load addresses
        vaultParams.allocator = vm.parseTomlAddress(toml, ".mainnet.address.allocator");
        vaultParams.asset = vm.parseTomlAddress(toml, ".mainnet.address.asset");
        vaultParams.curator = vm.parseTomlAddress(toml, ".mainnet.address.curator");
        vaultParams.owner = vm.parseTomlAddress(toml, ".mainnet.address.owner");
        vaultParams.initial_vault = vm.parseTomlAddress(toml, ".mainnet.address.initial_vault");
        vaultParams.sentinel = vm.parseTomlAddress(toml, ".mainnet.address.sentinel");

        // load string
        vaultParams.name = vm.parseTomlString(toml, ".mainnet.string.name");
        vaultParams.symbol = vm.parseTomlString(toml, ".mainnet.string.symbol");

        // load uint
        vaultParams.dead_deposit = vm.parseTomlUint(toml, ".mainnet.uint.dead_deposit");
        vaultParams.initial_absolute_cap = vm.parseTomlUint(toml, ".mainnet.uint.initial_absolute_cap");
        vaultParams.initial_relative_cap = vm.parseTomlUint(toml, ".mainnet.uint.initial_relative_cap");
        vaultParams.max_rate = vm.parseTomlUint(toml, ".mainnet.uint.max_rate");
        vaultParams.timelock_duration = vm.parseTomlUint(toml, ".mainnet.uint.timelock_duration");
    }

    //  Lowercase a string
    function toLower(string memory str) internal pure returns (string memory) {
        bytes memory b = bytes(str);

        for (uint256 i = 0; i < b.length; ++i) {
            uint8 c = uint8(b[i]);

            if (c >= 65 && c <= 90) {
                b[i] = bytes1(c + 32);
            }
        }

        return string(b);
    }
}
