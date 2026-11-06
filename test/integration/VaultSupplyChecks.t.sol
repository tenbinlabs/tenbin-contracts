// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {IMorphoVaultV1Adapter} from "vault-v2/src/adapters/interfaces/IMorphoVaultV1Adapter.sol";
import {VaultChecksBase} from "../fork/monitoring/VaultChecksBase.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";

contract VaultSupplyChecksHarness is VaultChecksBase {
    constructor(address vault, address adapter) {
        vaultContracts.vault = vault;
        vaultAdapters.push(VaultAdapter("VAULT", adapter, keccak256(abi.encode("this", adapter)), "Legacy"));
    }
}

contract VaultSupplyChecksTest is Test {
    IVaultV2 vault;
    IMorphoVaultV1Adapter adapter;
    VaultSupplyChecksHarness checks;
    bytes idData;

    function setUp() public {
        MockERC20 asset = new MockERC20("USDC", "USDC", 6);
        vault = IVaultV2(deployCode("out/VaultV2.sol/VaultV2.json", abi.encode(address(this), address(asset))));
        adapter = IMorphoVaultV1Adapter(
            deployCode(
                "out/MorphoVaultV1Adapter.sol/MorphoVaultV1Adapter.json",
                abi.encode(address(vault), address(new MockERC4626("Legacy", "LEG", asset)))
            )
        );
        checks = new VaultSupplyChecksHarness(address(vault), address(adapter));
        idData = abi.encode("this", address(adapter));
        vault.setCurator(address(this));
        vault.submit(abi.encodeCall(vault.setIsAllocator, (address(this), true)));
        vault.setIsAllocator(address(this), true);
        vault.submit(abi.encodeCall(vault.addAdapter, (address(adapter))));
        vault.addAdapter(address(adapter));
        vault.submit(abi.encodeCall(vault.increaseAbsoluteCap, (idData, 100e6)));
        vault.increaseAbsoluteCap(idData, 100e6);
        vault.submit(abi.encodeCall(vault.increaseRelativeCap, (idData, 1e18)));
        vault.increaseRelativeCap(idData, 1e18);
        asset.mint(address(this), 100e6);
        asset.approve(address(vault), 100e6);
        vault.deposit(100e6, address(this));
        vault.allocate(address(adapter), hex"", 100e6);
    }

    function test_RetainedZeroCapResidualRemainsAccountedFor() public {
        vault.deallocate(address(adapter), hex"", 99e6);
        vault.decreaseAbsoluteCap(idData, 0);
        vault.decreaseRelativeCap(idData, 0);

        checks.testVaultAdapter();
        checks.testVaultSupply();
        assertEq(vault.allocation(keccak256(idData)), 1e6);
        assertEq(adapter.realAssets(), 1e6);
        assertEq(vault.totalAssets(), 100e6);
    }

    function test_AllocationAtCapPasses() public view {
        checks.testVaultSupply();
    }

    function test_AllocationAboveNonzeroCapFails() public {
        vault.decreaseAbsoluteCap(idData, 99e6);
        vm.expectRevert();
        checks.testVaultSupply();
    }

    function test_ZeroAbsoluteCapWithRelativeCapFails() public {
        vault.decreaseAbsoluteCap(idData, 0);
        vm.expectRevert();
        checks.testVaultSupply();
    }

    function test_DisabledLiquidityAdapterFails() public {
        vault.decreaseAbsoluteCap(idData, 0);
        vault.decreaseRelativeCap(idData, 0);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");
        vm.expectRevert();
        checks.testVaultSupply();
    }

    function test_RemovedAdapterFailsRegistrationCheck() public {
        vault.submit(abi.encodeCall(vault.removeAdapter, (address(adapter))));
        vault.removeAdapter(address(adapter));
        vm.expectRevert();
        checks.testVaultAdapter();
    }
}
