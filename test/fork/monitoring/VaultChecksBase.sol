// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CollateralManager} from "tenbin-contracts/src/CollateralManager.sol";
import {Gate} from "tenbin-contracts/src/external/morpho/Gate.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAdapter} from "vault-v2/src/interfaces/IAdapter.sol";
import {IMorpho, Id, Market} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {MonitorBase} from "./MonitorBase.sol";

/// @notice General vault assumptions that must always hold to ensure a healthy state
abstract contract VaultChecksBase is MonitorBase {
    struct VaultParams {
        address allocator;
        address asset;
        address curator;
        address owner;
        address sentinel;
        address manager;
        string name;
        string symbol;
        uint256 dead_deposit;
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

        address stranger = address(0xBEEF);
        assertFalse(Gate(vaultContracts.gate).canReceiveAssets(stranger));
        assertFalse(Gate(vaultContracts.gate).canReceiveShares(stranger));
        assertFalse(Gate(vaultContracts.gate).canSendAssets(stranger));
        assertFalse(Gate(vaultContracts.gate).canSendShares(stranger));
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
        for (uint256 i = 0; i < roles.rebalancer_role.length; i++) {
            assertTrue(IVaultV2(vaultContracts.vault).isAllocator(roles.rebalancer_role[i]));
        }
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

    // Every listed adapter must be registered with the correct allocation id.
    // A nonzero liquidity adapter must be listed and registered.
    function testVaultAdapter() public view {
        address liquidityAdapter = IVaultV2(vaultContracts.vault).liquidityAdapter();
        assertEq(IVaultV2(vaultContracts.vault).adaptersLength(), vaultAdapters.length);
        bool liquidityAdapterListed = false;
        for (uint256 i = 0; i < vaultAdapters.length; i++) {
            assertEq(vaultAdapters[i].id, keccak256(abi.encode("this", vaultAdapters[i].addr)));
            bool registered = IVaultV2(vaultContracts.vault).isAdapter(vaultAdapters[i].addr);
            assertTrue(registered);
            liquidityAdapterListed = liquidityAdapterListed || vaultAdapters[i].addr == liquidityAdapter;
        }
        assertTrue(liquidityAdapter == address(0) || liquidityAdapterListed);
    }

    // Vault asset must match accepted collateral
    function testVaultAsset() public view {
        assertEq(IVaultV2(vaultContracts.vault).asset(), vaultParams.asset);
        address currentVault =
            address(CollateralManager(contracts.collateral_manager).vaults(IVaultV2(vaultContracts.vault).asset()));
        assertEq(currentVault, vaultContracts.vault);
    }

    // Max rate and timelocks must match config, with no timelock abdicated
    function testVaultRateAndTimelocks() public view {
        IVaultV2 vault = IVaultV2(vaultContracts.vault);
        assertEq(vault.maxRate(), vaultParams.max_rate);
        bytes4[] memory selectors = vaultTimelockSelectors();
        for (uint256 i = 0; i < selectors.length; i++) {
            // TODO(ENG-3174): check setSendAssetsGate once its timelock is set on mainnet
            if (selectors[i] == IVaultV2.setSendAssetsGate.selector) continue;
            assertEq(vault.timelock(selectors[i]), vaultParams.timelock_duration);
            assertFalse(vault.abdicated(selectors[i]));
        }
    }

    // Recorded total assets must be backed by idle plus adapter assets, allowing one wei of rounding per adapter
    function testNoPendingLoss() public view {
        IVaultV2 vault = IVaultV2(vaultContracts.vault);
        uint256 realAssets = IERC20(vault.asset()).balanceOf(address(vault));
        uint256 adaptersLength = vault.adaptersLength();
        for (uint256 i = 0; i < adaptersLength; i++) {
            realAssets += IAdapter(vault.adapters(i)).realAssets();
        }
        assertLe(vault._totalAssets(), realAssets + adaptersLength);
    }

    // Disabled adapters may retain residuals while remaining registered and accounted for.
    function testVaultSupply() public view {
        for (uint256 i = 0; i < vaultAdapters.length; i++) {
            uint256 allocation = IVaultV2(vaultContracts.vault).allocation(vaultAdapters[i].id);
            uint256 absoluteCap = IVaultV2(vaultContracts.vault).absoluteCap(vaultAdapters[i].id);
            if (absoluteCap == 0) {
                assertEq(IVaultV2(vaultContracts.vault).relativeCap(vaultAdapters[i].id), 0);
                assertNotEq(IVaultV2(vaultContracts.vault).liquidityAdapter(), vaultAdapters[i].addr);
            } else {
                assertLe(allocation, absoluteCap);
            }
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

    // Vault utilization should not exceed 99%
    function testVaultUtilization() public view {
        // Ethereum mainnet Morpho Blue
        IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

        assertGt(marketIds.length, 0, "No configured markets");
        for (uint256 i = 0; i < marketIds.length; i++) {
            Market memory market = morpho.market(Id.wrap(marketIds[i]));
            if (market.totalSupplyAssets == 0) continue;

            assertLt(
                uint256(market.totalBorrowAssets) * 100,
                uint256(market.totalSupplyAssets) * 99,
                "Morpho market utilization exceeds 99%"
            );
        }
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
        vaultParams.sentinel = vm.parseTomlAddress(toml, ".mainnet.address.sentinel");

        // load string
        vaultParams.name = vm.parseTomlString(toml, ".mainnet.string.name");
        vaultParams.symbol = vm.parseTomlString(toml, ".mainnet.string.symbol");

        // load uint
        vaultParams.dead_deposit = vm.parseTomlUint(toml, ".mainnet.uint.dead_deposit");
        vaultParams.max_rate = vm.parseTomlUint(toml, ".mainnet.uint.max_rate");
        vaultParams.timelock_duration = vm.parseTomlUint(toml, ".mainnet.uint.timelock_duration");
    }

    // Vault selectors timelocked by Deploy.configureTimelock
    function vaultTimelockSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](11);
        selectors[0] = IVaultV2.setReceiveSharesGate.selector;
        selectors[1] = IVaultV2.setSendSharesGate.selector;
        selectors[2] = IVaultV2.setReceiveAssetsGate.selector;
        selectors[3] = IVaultV2.setSendAssetsGate.selector;
        selectors[4] = IVaultV2.addAdapter.selector;
        selectors[5] = IVaultV2.increaseAbsoluteCap.selector;
        selectors[6] = IVaultV2.increaseRelativeCap.selector;
        selectors[7] = IVaultV2.setForceDeallocatePenalty.selector;
        selectors[8] = IVaultV2.abdicate.selector;
        selectors[9] = IVaultV2.removeAdapter.selector;
        selectors[10] = IVaultV2.increaseTimelock.selector;
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
