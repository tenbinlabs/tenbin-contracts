// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkBaseTest} from "./ForkBaseTest.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {IVaultV2Factory} from "vault-v2/src/interfaces/IVaultV2Factory.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {GenericMorphoAdapter} from "../../src/external/morpho/GenericMorphoAdapter.sol";
import {GenericMorphoAdapterFactory} from "../../src/external/morpho/GenericMorphoAdapterFactory.sol";

contract GenericMorphoAdapterForkTest is ForkBaseTest {
    // accounts
    address unauthorized;
    address allocator;

    // contracts
    IVaultV2 parentVault;
    GenericMorphoAdapter adapter;

    bytes32 constant SALT = bytes32(abi.encodePacked("salt"));

    function setUp() public override {
        super.setUp();
        GenericMorphoAdapterFactory adapterFactory = new GenericMorphoAdapterFactory();
        unauthorized = address(0xBEEF);
        allocator = vm.addr(0xC001);
        IVaultV2Factory factory = IVaultV2Factory(VAULT_V2_FACTORY_ADDRESS);
        parentVault = IVaultV2(factory.createVaultV2(owner, address(collateral), bytes32(abi.encodePacked("salt"))));
        adapter = GenericMorphoAdapter(
            adapterFactory.createGenericMorphoAdapter(address(parentVault), address(vault), owner)
        );

        collateral.mint(address(adapter), 100e18);
        collateral.mint(address(parentVault), 100e18);

        setUpAdapterLabels();

        // set curator
        vm.prank(owner);
        parentVault.setCurator(curator);

        // set allocator
        vm.startPrank(curator);
        parentVault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (allocator, true)));
        parentVault.setIsAllocator(allocator, true);

        // add adapter
        parentVault.submit(abi.encodeCall(IVaultV2.addAdapter, address(adapter)));
        parentVault.addAdapter(address(adapter));

        // set caps
        bytes memory adapterId = abi.encode("this", address(adapter));
        parentVault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterId, 100000000e18)));
        parentVault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterId, 1e18)));
        parentVault.increaseAbsoluteCap(adapterId, 100000000e18);
        parentVault.increaseRelativeCap(adapterId, 1e18);
        vm.stopPrank();
    }

    function test_SetUp() public view {
        assertEq(address(adapter.parentVault()), address(parentVault), "Invalid parent vault");
        assertEq(address(adapter.vault()), address(vault), "Invalid adapter vault");
        assertEq(adapter.asset(), address(collateral), "Invalid adapter asset");
        assertEq(adapter.adapterId(), keccak256(abi.encode("this", address(adapter))), "Invalid adapter Id");
        assertEq(parentVault.asset(), vault.asset(), "Invalid parent vault asset");
    }

    function test_Revert_Deploy() public {
        // vault with different asset
        vm.expectRevert(GenericMorphoAdapter.AssetMismatch.selector);
        new GenericMorphoAdapter(address(parentVault), address(vault2), owner);
    }

    function test_Revert_Allocates() public {
        uint256 minShares = vault.previewDeposit(100e18);
        // Min Shares not reached
        vm.startPrank(address(parentVault));
        vm.expectRevert(GenericMorphoAdapter.InsufficientShares.selector);
        adapter.allocate(abi.encode(minShares * 2), 100e18, bytes4(0), address(0));
        vm.stopPrank();

        // Call from unauthorized account
        vm.prank(unauthorized);
        vm.expectRevert(GenericMorphoAdapter.NotAuthorized.selector);
        adapter.allocate(abi.encode(minShares), 100e18, bytes4(0), address(0));
    }

    function test_Allocate() public {
        bytes32 adapterId = keccak256(abi.encode("this", address(adapter)));
        uint256 minShares = vault.previewDeposit(100e18);
        vm.prank(allocator);
        parentVault.allocate(address(adapter), abi.encode(minShares), 100e18);

        assertEq(vault.balanceOf(address(adapter)), 100e18, "Incorrect vault balance of adapter");
        assertEq(parentVault.allocation(adapterId), 100e18, "Incorrect allocation");
        assertEq(adapter.realAssets(), 100e18, "Incorrect adapter real assets");
    }

    function test_Revert_Deallocate() public {
        // Max Shares not reached
        uint256 minShares = vault.previewDeposit(100e18);
        vm.prank(allocator);
        parentVault.allocate(address(adapter), abi.encode(minShares), 100e18);

        uint256 maxShares = vault.previewWithdraw(50e18) / 2;
        vm.prank(address(parentVault));
        vm.expectRevert(GenericMorphoAdapter.ExcessiveShares.selector);
        adapter.deallocate(abi.encode(maxShares), 50e18, bytes4(0), address(0));
        vm.stopPrank();

        // Call from unauthorized account
        vm.prank(unauthorized);
        vm.expectRevert(GenericMorphoAdapter.NotAuthorized.selector);
        adapter.deallocate(abi.encode(maxShares), 100e18, bytes4(0), address(0));
    }

    function test_Deallocate() public {
        bytes32 adapterId = keccak256(abi.encode("this", address(adapter)));
        uint256 minShares = vault.previewDeposit(100e18);
        uint256 maxShares = vault.previewWithdraw(50e18);
        vm.startPrank(allocator);
        parentVault.allocate(address(adapter), abi.encode(minShares), 100e18);

        parentVault.deallocate(address(adapter), abi.encode(maxShares), 50e18);

        assertEq(vault.balanceOf(address(adapter)), 50e18, "Incorrect vault balance of adapter");
        assertEq(parentVault.allocation(adapterId), 50e18, "Incorrect allocation");
        assertEq(adapter.realAssets(), 50e18, "Incorrect adapter real assets");
    }

    function test_SparkIntegration() public {
        // sUSDS Vault contract on Ethereum Mainnet
        IERC4626 sUSDS = IERC4626(0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD);
        // USDS coin Ethereum Mainnet
        address usds = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

        // set up
        IVaultV2Factory factory = IVaultV2Factory(VAULT_V2_FACTORY_ADDRESS);
        parentVault = IVaultV2(factory.createVaultV2(owner, usds, bytes32(abi.encodePacked("salt"))));
        GenericMorphoAdapter sUSDSadapter = new GenericMorphoAdapter(address(parentVault), address(sUSDS), owner);
        bytes memory idData = abi.encode("this", address(sUSDSadapter));

        dealTo(IERC20(usds), address(parentVault), 100e18);
        setUpMorphoVault(parentVault, sUSDSadapter, 100000000e18, 1e18);

        // allocate
        bytes32 adapterId = keccak256(idData);
        uint256 shares = sUSDS.previewDeposit(100e18);
        vm.startPrank(allocator);
        parentVault.allocate(address(sUSDSadapter), abi.encode(shares), 100e18);

        assertApproxEqAbs(sUSDS.balanceOf(address(sUSDSadapter)), shares, 2);
        assertApproxEqAbs(sUSDSadapter.realAssets(), 100e18, 2, "Incorrect adapter real assets");
        assertApproxEqAbs(parentVault.allocation(adapterId), 100e18, 2, "Incorrect allocation");

        // deallocate
        shares = sUSDS.previewWithdraw(50e18);
        parentVault.deallocate(address(sUSDSadapter), abi.encode(shares), 50e18);

        assertApproxEqAbs(sUSDS.balanceOf(address(sUSDSadapter)), shares, 2);
        assertApproxEqAbs(sUSDSadapter.realAssets(), 50e18, 2, "Incorrect adapter real assets");
        assertApproxEqAbs(parentVault.allocation(adapterId), 50e18, 2, "Incorrect allocation");
        vm.stopPrank();
    }

    function test_ATokenIntegration() public {
        // STATAToken Vault contract on Ethereum Mainnet
        IERC4626 STATAToken = IERC4626(0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E);
        // AToken contract on Ethereum Mainnet
        address aToken = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

        // set up
        IVaultV2Factory factory = IVaultV2Factory(VAULT_V2_FACTORY_ADDRESS);
        parentVault = IVaultV2(factory.createVaultV2(owner, address(usdc), bytes32(abi.encodePacked("salt"))));
        GenericMorphoAdapter STATATokenAdapter =
            new GenericMorphoAdapter(address(parentVault), address(STATAToken), owner);
        bytes memory idData = abi.encode("this", address(STATATokenAdapter));

        dealTo(usdc, address(parentVault), 100e6);

        setUpMorphoVault(parentVault, STATATokenAdapter, 100000000e6, 1e18);
        // allocate
        bytes32 adapterId = keccak256(idData);
        uint256 shares = STATAToken.previewDeposit(100e6);
        uint256 initSupply = MockERC20(aToken).totalSupply();
        vm.startPrank(allocator);
        parentVault.allocate(address(STATATokenAdapter), abi.encode(shares), 100e6);

        assertLt(initSupply, MockERC20(aToken).totalSupply(), "aToken supply not increased after allocation");
        assertApproxEqAbs(STATAToken.balanceOf(address(STATATokenAdapter)), shares, 2, "Incorrect share amount");
        assertApproxEqAbs(STATATokenAdapter.realAssets(), 100e6, 2, "Incorrect adapter real assets");
        assertApproxEqAbs(parentVault.allocation(adapterId), 100e6, 2, "Incorrect allocation");

        // deallocate
        shares = STATAToken.previewWithdraw(50e6);
        parentVault.deallocate(address(STATATokenAdapter), abi.encode(shares), 50e6);

        assertApproxEqAbs(STATAToken.balanceOf(address(STATATokenAdapter)), shares, 2, "Incorrect share amount");
        assertApproxEqAbs(STATATokenAdapter.realAssets(), 50e6, 2, "Incorrect adapter real assets");
        assertApproxEqAbs(parentVault.allocation(adapterId), 50e6, 2, "Incorrect allocation");
        vm.stopPrank();
    }

    function setUpAdapterLabels() internal {
        label(address(adapter), "adapter");
        label(address(parentVault), "ParentVault");
    }

    function test_Revert_RescueToken() public {
        // Allocate to earn shares
        uint256 minShares = vault.previewDeposit(100e18);
        vm.prank(allocator);
        parentVault.allocate(address(adapter), abi.encode(minShares), 100e18);

        // Try to steal the vault shares
        vm.prank(owner);
        vm.expectRevert(GenericMorphoAdapter.InvalidToken.selector);
        adapter.rescueToken(address(vault), address(this));
    }

    function test_RescueToken() public {
        address to = address(1);
        uint256 amount = 1e18;

        // Send token
        collateral2.mint(address(adapter), amount);
        assertEq(collateral2.balanceOf(to), 0);
        assertEq(collateral2.balanceOf(address(adapter)), amount);

        // Rescue tokens
        vm.prank(owner);
        adapter.rescueToken(address(collateral2), to);
        assertEq(collateral2.balanceOf(to), amount);
        assertEq(collateral2.balanceOf(address(adapter)), 0);
    }

    function setUpMorphoVault(
        IVaultV2 morphoVault,
        GenericMorphoAdapter morphoAdapter,
        uint256 absoluteCap,
        uint256 relativeCap
    ) public {
        // set curator
        vm.startPrank(owner);
        morphoVault.setCurator(curator);

        // set allocator
        vm.startPrank(curator);
        morphoVault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (allocator, true)));
        morphoVault.setIsAllocator(allocator, true);

        // add adapter
        morphoVault.submit(abi.encodeCall(IVaultV2.addAdapter, address(morphoAdapter)));
        morphoVault.addAdapter(address(morphoAdapter));

        // set caps
        bytes memory adapterId = abi.encode("this", address(morphoAdapter));
        morphoVault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterId, absoluteCap)));
        morphoVault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterId, relativeCap)));
        morphoVault.increaseAbsoluteCap(adapterId, absoluteCap);
        morphoVault.increaseRelativeCap(adapterId, relativeCap);
        vm.stopPrank();
    }

    function testSharesDonationResistanceIfNoAllocation() public {
        bytes32 id = adapter.adapterId();

        uint256 donatedAssets = 10e18;
        uint256 allocatedAssets = 20e18;
        address donor = address(0xD0D0);

        // Start with zero recorded allocation

        assertEq(parentVault.allocation(id), 0, "allocation should start at zero");
        assertEq(adapter.realAssets(), 0, "realAssets should start at zero");

        // Donate shares directly to the adapter.
        collateral.mint(donor, donatedAssets);

        vm.startPrank(donor);
        collateral.approve(address(vault), donatedAssets);

        uint256 donatedShares = vault.deposit(donatedAssets, address(adapter));

        vm.stopPrank();

        assertGt(donatedShares, 0, "donation should mint shares");
        assertGt(vault.balanceOf(address(adapter)), 0, "adapter should hold donated shares");

        // The parent still has no allocation recorded for this adapter.
        assertEq(parentVault.allocation(id), 0, "donation must not create allocation");

        // donated shares must NOT be counted by realAssets while allocation == 0.
        assertEq(adapter.realAssets(), 0, "realAssets must ignore donation at zero allocation");

        // Perform the first legitimate allocation after the donation.
        uint256 minShares = vault.previewDeposit(allocatedAssets);

        vm.prank(allocator);
        parentVault.allocate(address(adapter), abi.encode(minShares), allocatedAssets);

        uint256 recordedAllocation = parentVault.allocation(id);

        assertGt(recordedAllocation, 0, "first allocation after donation must register a nonzero change");
        assertGt(adapter.realAssets(), 0, "realAssets should become nonzero once allocation exists");

        assertEq(
            adapter.realAssets(),
            vault.previewRedeem(vault.balanceOf(address(adapter))),
            "realAssets should equal fee-aware position value"
        );

        // Verify the position is actually deallocatable
        vm.prank(allocator);
        parentVault.deallocate(address(adapter), abi.encode(type(uint256).max), recordedAllocation);

        assertEq(parentVault.allocation(id), 0, "allocation should return to zero");
        assertEq(adapter.realAssets(), 0, "realAssets should return to zero with zero allocation");
    }

    function test_Allocate_SkipsSlippageCheckWhenMinSharesIsZero() public {
        bytes32 adapterId = adapter.adapterId();

        vm.prank(allocator);
        parentVault.allocate(address(adapter), abi.encode(uint256(0)), 100e18);

        assertEq(vault.balanceOf(address(adapter)), 100e18, "Incorrect vault balance of adapter");
        assertEq(parentVault.allocation(adapterId), 100e18, "Incorrect allocation");
        assertEq(adapter.realAssets(), 100e18, "Incorrect adapter real assets");
    }

    function test_Deallocate_SkipsSlippageCheckWhenMaxSharesIsZero() public {
        bytes32 adapterId = adapter.adapterId();

        uint256 minShares = vault.previewDeposit(100e18);

        vm.startPrank(allocator);

        // First create an allocation.
        parentVault.allocate(address(adapter), abi.encode(minShares), 100e18);

        // maxShares == 0 should disable the slippage check.
        parentVault.deallocate(address(adapter), abi.encode(uint256(0)), 50e18);

        vm.stopPrank();

        assertEq(vault.balanceOf(address(adapter)), 50e18, "Incorrect vault balance of adapter");
        assertEq(parentVault.allocation(adapterId), 50e18, "Incorrect allocation");
        assertEq(adapter.realAssets(), 50e18, "Incorrect adapter real assets");
    }
}
