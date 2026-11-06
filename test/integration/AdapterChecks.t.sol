// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {AdapterChecksBase} from "../fork/monitoring/AdapterChecksBase.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";

contract AdapterChecksHarness is AdapterChecksBase {
    constructor(address vault, address asset, address adapter, address target) {
        bytes32 id = keccak256(abi.encode("this", adapter));
        vaultContracts.vault = vault;
        vaultParams.asset = asset;
        vaultAdapters.push(VaultAdapter("VAULT", adapter, id, "Legacy"));
        adapterConfigs.push(AdapterConfig("VAULT", "Legacy", adapter, id, target, address(0), 100e6, 1e18));
        configuredLiquidityAdapter = adapter;
    }

    function addVaultAdapter(address adapter, address target) external {
        bytes32 id = keccak256(abi.encode("this", adapter));
        vaultAdapters.push(VaultAdapter("VAULT", adapter, id, "Secondary"));
        adapterConfigs.push(AdapterConfig("VAULT", "Secondary", adapter, id, target, address(0), 100e6, 1e18));
    }

    function removeLastConfig() external {
        adapterConfigs.pop();
    }

    function duplicateFirstConfig() external {
        adapterConfigs.push(adapterConfigs[0]);
    }

    function reverseConfigs() external {
        AdapterConfig memory first = adapterConfigs[0];
        adapterConfigs[0] = adapterConfigs[1];
        adapterConfigs[1] = first;
    }

    function setAdapterType(string memory adapterType) external {
        adapterConfigs[0].adapterType = adapterType;
    }

    function setAdapterTarget(address target) external {
        adapterConfigs[0].target = target;
    }

    function setAbsoluteCap(uint256 absoluteCap) external {
        adapterConfigs[0].absoluteCap = absoluteCap;
    }

    function setTimelockDuration(uint256 duration) external {
        vaultParams.timelock_duration = duration;
    }
}

contract AdapterChecksTest is Test {
    MockERC20 asset;
    MockERC4626 target;
    IVaultV2 vault;
    address adapter;
    AdapterChecksHarness checks;
    bytes idData;

    function setUp() public {
        asset = new MockERC20("USDC", "USDC", 6);
        target = new MockERC4626("Legacy", "LEG", asset);
        vault = IVaultV2(deployCode("out/VaultV2.sol/VaultV2.json", abi.encode(address(this), address(asset))));
        adapter = deployCode(
            "out/MorphoVaultV1Adapter.sol/MorphoVaultV1Adapter.json", abi.encode(address(vault), address(target))
        );
        checks = new AdapterChecksHarness(address(vault), address(asset), adapter, address(target));
        idData = abi.encode("this", adapter);
        vault.setCurator(address(this));
        vault.submit(abi.encodeCall(vault.setIsAllocator, (address(this), true)));
        vault.setIsAllocator(address(this), true);
        vault.submit(abi.encodeCall(vault.addAdapter, (adapter)));
        vault.addAdapter(adapter);
        vault.submit(abi.encodeCall(vault.increaseAbsoluteCap, (idData, 100e6)));
        vault.increaseAbsoluteCap(idData, 100e6);
        vault.submit(abi.encodeCall(vault.increaseRelativeCap, (idData, 1e18)));
        vault.increaseRelativeCap(idData, 1e18);
        asset.mint(address(this), 100e6);
        asset.approve(address(vault), 100e6);
        vault.deposit(100e6, address(this));
        vault.allocate(adapter, hex"", 50e6);
        vault.setLiquidityAdapterAndData(adapter, hex"");
    }

    function test_MatchingConfigPasses() public view {
        checks.testAdapterConfigCoverage();
        checks.testAdapterCaps();
        checks.testLiquidityAdapterConfig();
        checks.testAdapterIdentity();
        checks.testEngineReadPath();
        checks.testVaultRateAndTimelocks();
        checks.testNoPendingLoss();
    }

    function addSecondaryAdapter() internal returns (bytes memory data) {
        address secondary = deployCode(
            "out/MorphoVaultV1Adapter.sol/MorphoVaultV1Adapter.json", abi.encode(address(vault), address(target))
        );
        vault.submit(abi.encodeCall(vault.addAdapter, (secondary)));
        vault.addAdapter(secondary);
        checks.addVaultAdapter(secondary, address(target));
        data = abi.encode("this", secondary);
        vault.submit(abi.encodeCall(vault.increaseAbsoluteCap, (data, 100e6)));
        vault.increaseAbsoluteCap(data, 100e6);
        vault.submit(abi.encodeCall(vault.increaseRelativeCap, (data, 1e18)));
        vault.increaseRelativeCap(data, 1e18);
    }

    function test_ConfigOrderDoesNotAffectCoverage() public {
        addSecondaryAdapter();
        checks.reverseConfigs();
        checks.testAdapterConfigCoverage();
    }

    function test_OmittedNonLiquidityAdapterFailsCoverage() public {
        addSecondaryAdapter();
        checks.testAdapterConfigCoverage();
        checks.removeLastConfig();
        checks.testVaultAdapter();
        vm.expectRevert(bytes("adapter not configured"));
        checks.testAdapterConfigCoverage();
    }

    function test_DuplicateConfigCannotHideOmittedAdapter() public {
        addSecondaryAdapter();
        checks.removeLastConfig();
        checks.duplicateFirstConfig();
        vm.expectRevert(bytes("adapter not configured"));
        checks.testAdapterConfigCoverage();
    }

    function test_EmptyConfigFailsCoverage() public {
        checks.removeLastConfig();
        vm.expectRevert(bytes("adapter not configured"));
        checks.testAdapterConfigCoverage();
    }

    function test_DisabledAdapterMayDropConfig() public {
        bytes memory data = addSecondaryAdapter();
        vault.decreaseAbsoluteCap(data, 0);
        vault.decreaseRelativeCap(data, 0);
        checks.removeLastConfig();
        checks.testVaultAdapter();
        checks.testAdapterConfigCoverage();
        checks.testAdapterCaps();
    }

    function test_CapMismatchFails() public {
        checks.setAbsoluteCap(99e6);
        vm.expectRevert();
        checks.testAdapterCaps();
    }

    function test_DisabledAdapterSkipsCapCheck() public {
        checks.setAbsoluteCap(99e6);
        vault.decreaseAbsoluteCap(idData, 0);
        vault.decreaseRelativeCap(idData, 0);
        checks.testAdapterCaps();
    }

    function test_LiquidityAdapterMismatchFails() public {
        vault.setLiquidityAdapterAndData(address(0), hex"");
        vm.expectRevert();
        checks.testLiquidityAdapterConfig();
    }

    function test_LiquidityDataMismatchFails() public {
        vault.setLiquidityAdapterAndData(adapter, abi.encode(uint256(0)));
        vm.expectRevert();
        checks.testLiquidityAdapterConfig();
    }

    function test_AdapterTargetMismatchFails() public {
        checks.setAdapterTarget(address(0xBEEF));
        vm.expectRevert();
        checks.testAdapterIdentity();
    }

    function test_UnknownAdapterTypeFails() public {
        checks.setAdapterType("AAVE");
        vm.expectRevert(bytes("unknown adapter type: AAVE"));
        checks.testAdapterIdentity();
    }

    function test_TimelockMismatchFails() public {
        checks.setTimelockDuration(1 days);
        vm.expectRevert();
        checks.testVaultRateAndTimelocks();
    }

    function test_SendAssetsGateTimelockIgnored() public {
        bytes4 selector = IVaultV2.setSendAssetsGate.selector;
        vault.submit(abi.encodeCall(vault.increaseTimelock, (selector, 1 days)));
        vault.increaseTimelock(selector, 1 days);
        checks.testVaultRateAndTimelocks();
    }

    function test_AdapterLossFails() public {
        asset.burn(address(target), 10e6);
        vm.expectRevert();
        checks.testNoPendingLoss();
    }
}
