// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PyriteFixtures} from "../helpers/PyriteFixtures.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {NewAssetDeployer} from "../helpers/NewAssetDeployer.sol";
import {IController} from "deploy-target/src/interface/IController.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ChainlinkOracleWrapper} from "deploy-target/src/oracle/ChainlinkOracleWrapper.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";
import {IMorpho, MarketParams} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "vault-v2/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {IMorphoChainlinkOracleV2} from "../external/morpho/IMorphoChainlinkOracleV2.sol";

/// @dev Deployment spans multiple transactions; do not impose a single block gas budget.
/// forge-config: default.isolate = false
contract DeployNewAssetTest is PyriteFixtures {
    using MarketParamsLib for MarketParams;

    string internal fixtures;
    string internal assetConfig;
    string internal vaultConfig;
    address internal constant ADMIN = 0x794eBfe3B3C92409f72F569ADb3e44913a056a54;
    address internal constant KEEPER = 0x489f4E4c67a024f2f06b7E674fff328dcb809A92;
    address internal constant YIELD_SIGNER = 0xE0314BC955477fE95C406DB18a885A3d8C0612AC;
    address internal constant LEVERAGE_SIGNER = 0xDBC08aad7C82d6e09acCD043c5f968eeD7980495;
    uint256 internal constant USER_KEY = 0x1234;
    uint256 internal constant APPROVER_KEY = 0x2345;

    Deploy.CoreDeploymentResult internal core;
    NewAssetDeployer internal deployer;

    function setUp() public {
        vm.chainId(31337);
    }

    function prepareDeployment() internal {
        fixtures = string.concat("cache/test/pyrite/", vm.toString(bytes32(msg.sig)), "/");
        (assetConfig, vaultConfig) = writePyriteFixtures("sepolia", fixtures, "31337");
        deployer = new NewAssetDeployer(vm.addr(0x3456), string.concat(fixtures, "output"));
    }

    function deploy() internal returns (Deploy.VaultDeploymentResult memory vault) {
        prepareDeployment();
        (core, vault) = deployer.run(assetConfig, vaultConfig, true);
    }

    function test_NewMarketUsesStPyriteAndAllCaps() public {
        Deploy.VaultDeploymentResult memory vault = deploy();
        assertEq(core.asset.symbol(), "tPYR");
        assertEq(core.staked_asset.symbol(), "stPYR");
        assertEq(vault.adapters.length, 4);
        assertEq(vault.markets.length, 1);
        MarketParams memory params = vault.markets[0].params;
        assertEq(params.collateralToken, address(core.staked_asset));
        assertEq(params.loanToken, address(core.collateral));
        assertEq(params.lltv, 860000000000000000);
        address adapter = address(vault.adapters[0].adapter);
        IMorpho morpho = IMorpho(IMorphoMarketV1AdapterV2(adapter).morpho());
        assertEq(abi.encode(morpho.idToMarketParams(params.id())), abi.encode(params));
        assertEq(morpho.market(params.id()).totalSupplyAssets, 1e6);
        assertGt(morpho.position(params.id(), address(0xDEAD)).supplyShares, 0);
        bytes32[3] memory ids = [
            keccak256(abi.encode("this", adapter)),
            keccak256(abi.encode("collateralToken", params.collateralToken)),
            keccak256(abi.encode("this/marketParams", adapter, params))
        ];
        for (uint256 i; i < ids.length; i++) {
            assertEq(vault.vault.absoluteCap(ids[i]), 1_000_000e6);
            assertEq(vault.vault.relativeCap(ids[i]), 0.2e18);
        }
        assertEq(vault.vault.owner(), ADMIN);
        assertEq(vault.vault.curator(), ADMIN);
        assertTrue(vault.gate.canReceiveAssets(address(core.manager)));
        assertFalse(vault.gate.canReceiveAssets(address(this)));
        assertTrue(vault.vault.isAllocator(KEEPER));
        assertFalse(vault.vault.isAllocator(core.broadcaster));
        string memory onboarding = vm.readFile(string.concat(fixtures, "output/onboarding.json"));
        assertEq(vm.parseJsonAddress(onboarding, ".controller"), address(core.controller));
        assertEq(vm.parseJsonAddress(onboarding, ".yield_signer"), YIELD_SIGNER);
    }

    function test_AllFiveKeysAndRequiredOnboarding() public {
        deploy();
        assertTrue(core.controller.hasRole(keccak256("MINTER_ROLE"), 0x56Acd1c1c2961A82Bc842209D4E2b08F13e04943));
        assertTrue(core.multicall.hasRole(keccak256("MULTICALLER_ROLE"), 0x56Acd1c1c2961A82Bc842209D4E2b08F13e04943));
        assertTrue(core.manager.hasRole(keccak256("REBALANCER_ROLE"), KEEPER));
        assertTrue(core.controller.hasRole(keccak256("GATEKEEPER_ROLE"), 0xd1fb442aE62f0C829aa7f0946A173c39F9515213));
        assertTrue(core.controller.signers(YIELD_SIGNER));
        assertTrue(core.controller.signers(LEVERAGE_SIGNER));
        assertTrue(core.controller.delegates(address(core.revenue_module), YIELD_SIGNER));
        assertFalse(core.revenue_module.hasRole(keccak256("ADMIN_ROLE"), core.broadcaster));
        assertFalse(core.controller.recipients(YIELD_SIGNER, address(core.revenue_module)));
        vm.prank(YIELD_SIGNER);
        core.controller.setRecipientStatus(address(core.revenue_module), true);
        assertTrue(core.controller.recipients(YIELD_SIGNER, address(core.revenue_module)));
        assertEq(core.asset.pendingOwner(), ADMIN);
        vm.prank(ADMIN);
        core.asset.acceptOwnership();
        assertEq(core.asset.owner(), ADMIN);
    }

    function test_StakingSeedIsBackedAndTemporaryPermissionsAreRemoved() public {
        deploy();
        assertEq(core.asset.totalSupply(), 1e15);
        assertEq(core.staked_asset.balanceOf(address(0xDEAD)), 1e15);
        assertEq(core.staked_asset.totalSupply(), 1e15);
        assertEq(core.staked_asset.totalAssets(), 1e15);
        assertEq(core.staked_asset.convertToAssets(1e18), 1e18);
        assertEq(core.asset.balanceOf(core.broadcaster), 0);
        assertEq(core.collateral.balanceOf(address(core.custodian_module)), 595_000);
        assertEq(core.collateral.balanceOf(address(core.manager)), 2_905_000);
        assertEq(core.asset.allowance(core.broadcaster, address(core.staked_asset)), 0);
        assertEq(core.collateral.allowance(core.broadcaster, address(core.controller)), 0);
        assertFalse(core.controller.hasRole(keccak256("MINTER_ROLE"), core.broadcaster));
        assertFalse(core.controller.signers(core.broadcaster));
        assertFalse(core.controller.recipients(core.broadcaster, core.broadcaster));
        string memory onboarding = vm.readFile(string.concat(fixtures, "output/onboarding.json"));
        assertEq(vm.parseJsonUint(onboarding, ".staking_dead_deposit"), 1e15);
        assertEq(vm.parseJsonUint(onboarding, ".staking_seed_collateral"), 3_500_000);
    }

    function test_StakingSeedPreservesConfiguredBroadcasterPermissions() public {
        prepareDeployment();
        string memory account = string.concat('"', vm.toString(vm.addr(0x3456)), '"');
        vm.writeToml(account, assetConfig, ".31337.address.leverage_signer");
        vm.writeToml(account, assetConfig, ".31337.address.minter_role");
        (core,) = deployer.run(assetConfig, vaultConfig, true);
        assertTrue(core.controller.hasRole(keccak256("MINTER_ROLE"), core.broadcaster));
        assertTrue(core.controller.signers(core.broadcaster));
        assertTrue(core.controller.recipients(core.broadcaster, core.broadcaster));
        assertEq(core.staked_asset.balanceOf(address(0xDEAD)), 1e15);
    }

    function test_StakingSeedRoundsBackingUpAtMintLimit() public {
        prepareDeployment();
        vm.writeToml('"3500000000000000000001"', assetConfig, ".31337.uint.mock_oracle_price");
        vm.writeToml('"1000000000000000"', assetConfig, ".31337.string.mint_limit");
        (core,) = deployer.run(assetConfig, vaultConfig, true);
        assertEq(core.staked_asset.balanceOf(address(0xDEAD)), 1e15);
        assertEq(
            core.collateral.balanceOf(address(core.custodian_module))
                + core.collateral.balanceOf(address(core.manager)),
            3_500_001
        );
    }

    function test_OracleTracksFeedsAndStakingExchangeRate() public {
        Deploy.VaultDeploymentResult memory vault = deploy();
        MarketParams memory params = vault.markets[0].params;
        IMorphoChainlinkOracleV2 oracle = IMorphoChainlinkOracleV2(params.oracle);
        assertEq(address(oracle.BASE_VAULT()), address(core.staked_asset));
        assertEq(oracle.price(), 3500e24);
        vm.prank(address(core.controller));
        core.asset.mint(address(this), 20e18 + 1e15);
        core.asset.approve(address(core.staked_asset), 10e18);
        core.staked_asset.deposit(10e18, address(this));
        core.asset.transfer(address(core.staked_asset), 10e18 + 1e15);
        assertApproxEqAbs(oracle.price(), 7000e24, 1e10);
        MockAggregator base = MockAggregator(address(ChainlinkOracleWrapper(address(oracle.BASE_FEED_1())).oracle()));
        MockAggregator quote = MockAggregator(address(oracle.QUOTE_FEED_1()));
        base.setAnswer(4000e18);
        assertApproxEqAbs(oracle.price(), 8000e24, 1e10);
        quote.setAnswer(2e8);
        assertApproxEqAbs(oracle.price(), 4000e24, 1e10);
        quote.setAnswer(0);
        vm.expectRevert();
        oracle.price();
    }

    function test_MarketAllocateBorrowRepayAndDeallocate() public {
        Deploy.VaultDeploymentResult memory vault = deploy();
        uint256 seedBacking = core.collateral.balanceOf(address(core.manager));
        MarketParams memory params = vault.markets[0].params;
        address adapter = address(vault.adapters[0].adapter);
        IMorpho morpho = IMorpho(IMorphoMarketV1AdapterV2(adapter).morpho());
        MockERC20(address(core.collateral)).mint(address(core.manager), 1000e6);
        vm.startPrank(address(core.manager));
        core.collateral.approve(address(vault.vault), 1000e6);
        vault.vault.deposit(1000e6, address(core.manager));
        vm.stopPrank();
        vm.startPrank(KEEPER);
        vault.vault.deallocate(address(vault.liquidity_adapter), abi.encode(uint256(0)), 100_000);
        vault.vault.allocate(adapter, abi.encode(params), 100_000);
        vm.stopPrank();
        vm.prank(address(core.controller));
        core.asset.mint(address(this), 1e18);
        core.asset.approve(address(core.staked_asset), 1e18);
        core.staked_asset.deposit(1e18, address(this));
        core.staked_asset.approve(address(morpho), 1e18);
        morpho.supplyCollateral(params, 1e18, address(this), "");
        morpho.borrow(params, 10_000, 0, address(this), address(this));
        assertEq(core.collateral.balanceOf(address(this)), 10_000);
        core.collateral.approve(address(morpho), 10_000);
        morpho.repay(params, 10_000, 0, address(this), "");
        morpho.withdrawCollateral(params, 1e18, address(this), address(this));
        vm.prank(KEEPER);
        vault.vault.deallocate(adapter, abi.encode(params), 100_000);
        assertEq(vault.vault.allocation(keccak256(abi.encode("this/marketParams", adapter, params))), 0);
        vm.prank(address(core.manager));
        vault.vault.withdraw(100_000, address(core.manager), address(core.manager));
        assertEq(core.collateral.balanceOf(address(core.manager)), seedBacking + 100_000);
    }

    function test_MintStakeUnstakeRedeem() public {
        deploy();
        address user = vm.addr(USER_KEY);
        vm.startPrank(ADMIN);
        core.controller.setSignerStatus(user, true);
        core.controller.grantRole(keccak256("MINTER_ROLE"), vm.addr(APPROVER_KEY));
        vm.stopPrank();
        MockERC20(address(core.collateral)).mint(user, 3500e6);
        vm.prank(user);
        core.collateral.approve(address(core.controller), 3500e6);
        executeOrder(user, IController.OrderType.Mint, 3500e6, 1);
        assertEq(core.asset.balanceOf(user), 1e18);
        vm.startPrank(user);
        core.asset.approve(address(core.staked_asset), 1e18);
        core.staked_asset.deposit(1e18, user);
        (, uint256 id) = core.staked_asset.cooldownShares(1e18);
        vm.warp(block.timestamp + 601);
        core.staked_asset.unstake(user, id);
        core.asset.approve(address(core.controller), 1e18);
        vm.stopPrank();
        executeOrder(user, IController.OrderType.Redeem, 2905e6, 2);
        assertEq(core.asset.balanceOf(user), 0);
        assertEq(core.collateral.balanceOf(user), 2905e6);
    }

    function test_RevenueRewardUsesConfiguredYieldDelegation() public {
        prepareDeployment();
        string memory config = string.concat(fixtures, "reward.toml");
        vm.writeFile(config, vm.readFile(assetConfig));
        vm.writeToml(string.concat('"', vm.toString(vm.addr(USER_KEY)), '"'), config, ".31337.address.yield_signer");
        vm.writeToml(string.concat('"', vm.toString(vm.addr(APPROVER_KEY)), '"'), config, ".31337.address.minter_role");
        (core,) = deployer.run(config, vaultConfig, true);
        address revenue = address(core.revenue_module);
        assertTrue(core.controller.delegates(revenue, vm.addr(USER_KEY)));
        vm.prank(vm.addr(USER_KEY));
        core.controller.setRecipientStatus(revenue, true);
        MockERC20(address(core.collateral)).mint(revenue, 3500e6);
        vm.prank(KEEPER);
        core.revenue_module.setControllerApproval(address(core.collateral), 3500e6);
        executeOrder(revenue, IController.OrderType.Mint, 3500e6, 1);
        assertEq(core.asset.balanceOf(revenue), 1e18);
        vm.prank(KEEPER);
        core.revenue_module.reward(1e18);
        assertEq(core.asset.balanceOf(revenue), 0);
        assertEq(core.asset.balanceOf(address(core.staked_asset)), 1e18 + 1e15);
    }

    function executeOrder(address user, IController.OrderType kind, uint256 collateralAmount, uint256 nonce) internal {
        IController.Order memory order = IController.Order({
            order_type: kind,
            nonce: nonce,
            expiry: vm.getBlockTimestamp() + 100,
            payer: user,
            recipient: user,
            collateral_token: address(core.collateral),
            collateral_amount: collateralAmount,
            order_token: address(core.asset),
            asset_amount: 1e18
        });
        bytes32 orderHash = keccak256(
            abi.encodePacked(
                "\x19\x01", core.controller.getDomainSeparator(), keccak256(core.controller.encodeOrder(order))
            )
        );
        IController.Context memory context = IController.Context(orderHash, 1e18, false);
        bytes32 contextHash = keccak256(
            abi.encodePacked(
                "\x19\x01", core.controller.getDomainSeparator(), keccak256(core.controller.encodeContext(context))
            )
        );
        IController.Signature memory signature = sign(USER_KEY, orderHash);
        IController.Signature memory approval = sign(APPROVER_KEY, contextHash);
        if (kind == IController.OrderType.Mint) core.controller.mint(order, signature, context, approval);
        else core.controller.redeem(order, signature, context, approval);
    }

    function sign(uint256 key, bytes32 digest) internal pure returns (IController.Signature memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return IController.Signature(IController.SignatureType.EIP712, abi.encodePacked(r, s, v));
    }

    function test_RejectsWrongModeAndPreviouslyDeployedConfig() public {
        prepareDeployment();
        vm.expectRevert("incorrect mock mode");
        deployer.run(assetConfig, vaultConfig, false);
        vm.writeFile(
            string.concat(fixtures, "already_deployed.toml"),
            vm.replace(
                vm.readFile(assetConfig),
                'vault = "0x0000000000000000000000000000000000000000"',
                'vault = "0x0000000000000000000000000000000000000001"'
            )
        );
        vm.expectRevert("asset already has a vault");
        deployer.run(string.concat(fixtures, "already_deployed.toml"), vaultConfig, true);
    }

    function test_RejectsUnsupportedChainAndImplicitConfigs() public {
        prepareDeployment();
        vm.expectRevert("explicit configs required");
        deployer.run("", vaultConfig, true);
        vm.chainId(1);
        vm.expectRevert("incorrect mock mode");
        deployer.run(assetConfig, vaultConfig, true);
        vm.chainId(10);
        vm.expectRevert("chain not supported");
        deployer.run(assetConfig, vaultConfig, true);
    }

    function test_RejectsInvalidSigners() public {
        prepareDeployment();
        string memory invalid = string.concat(fixtures, "invalid_asset.toml");
        string memory original = vm.readFile(assetConfig);
        vm.writeFile(invalid, vm.replace(original, vm.toString(YIELD_SIGNER), vm.toString(address(0))));
        vm.expectRevert("signers not set");
        deployer.run(invalid, vaultConfig, true);
        vm.writeFile(invalid, vm.replace(original, vm.toString(YIELD_SIGNER), vm.toString(LEVERAGE_SIGNER)));
        vm.expectRevert("signers must differ");
        deployer.run(invalid, vaultConfig, true);
    }
}
