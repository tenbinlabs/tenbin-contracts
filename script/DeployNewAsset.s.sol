// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Deploy} from "./Deploy.s.sol";
import {ChainlinkOracleAdapter} from "deploy-target/src/oracle/ChainlinkOracleAdapter.sol";
import {IOracleAdapter} from "deploy-target/src/interface/IOracleAdapter.sol";
import {IController} from "deploy-target/src/interface/IController.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockOracleAdapter} from "../test/mocks/MockOracleAdapter.sol";
import {console2} from "forge-std/console2.sol";
import {StdConfig} from "forge-std/StdConfig.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IMorpho, MarketParams} from "vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IMorphoMarketV1AdapterV2Factory} from "vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2Factory.sol";
import {ChainlinkOracleWrapper} from "deploy-target/src/oracle/ChainlinkOracleWrapper.sol";
import {MockAggregator} from "../test/mocks/MockAggregator.sol";
import {AggregatorV3Interface} from "chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";
import {IMorphoChainlinkOracleV2Factory} from "../test/external/morpho/IMorphoChainlinkOracleV2Factory.sol";
import {IERC4626 as IMorphoVault} from "../test/external/morpho/VaultLib.sol";
import {AggregatorV3Interface as IMorphoFeed} from "../test/external/morpho/ChainlinkDataFeedLib.sol";

/// @notice Deploy a new asset and its staking-token/USDC market before finalizing vault permissions.
contract DeployNewAsset is Deploy {
    address internal constant ORACLE_FACTORY_MAINNET = 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766;
    uint256 internal constant MARKET_SEED_USDC = 1e6;

    address internal yieldSigner;
    address internal leverageSigner;
    address internal baseFeed;
    address internal quoteFeed;
    address internal oracleWrapper;
    address internal deployedAsset;
    uint256 internal oracleStalenessThreshold;
    uint256 internal configuredMockPrice;
    uint256 internal stakingDeadDeposit;
    uint256 internal stakingSeedCollateral;

    function run(string memory assetConfigDir, string memory vaultConfigDir, bool useMockIntegrations)
        public
        override
        returns (CoreDeploymentResult memory core, VaultDeploymentResult memory vault)
    {
        require(block.chainid == 1 || block.chainid == 11155111 || block.chainid == 31337, "chain not supported");
        require(useMockIntegrations == (block.chainid != 1), "incorrect mock mode");
        require(bytes(assetConfigDir).length > 0 && bytes(vaultConfigDir).length > 0, "explicit configs required");
        loadCoreConfig(assetConfigDir);
        require(assetConfig.get("vault").toAddress() == address(0), "asset already has a vault");
        stakingDeadDeposit = assetConfig.get("staking_dead_deposit").toUint256();
        require(stakingDeadDeposit > 0 && stakingDeadDeposit <= coreParams.mint_limit, "invalid staking dead deposit");
        loadRolesConfig();
        loadVaultConfig(vaultConfigDir);
        loadAdapterConfigs(vaultConfigDir);
        loadNewMarket(vaultConfigDir);

        vault = createNewVault();
        core = deployCore(IERC4626(address(vault.vault)), useMockIntegrations);
        deployedAsset = address(core.asset);
        createNewMarket(core);
        configureNewVault(vault);
        finalizeGate(vault, address(core.manager));
        serialize(core, vault);
        writeOnboarding(core);
        printCoreDeployment(core);
        printVaultDeployment(vault);
    }

    function runCoreOnly(string memory, bool) public pure override returns (CoreDeploymentResult memory) {
        revert("use Deploy for partial deployment");
    }

    function runVaultOnly(string memory, string memory) public pure override returns (VaultDeploymentResult memory) {
        revert("use Deploy for partial deployment");
    }

    function loadNewMarket(string memory vaultConfigDir) internal {
        require(hasMarketAdapter(), "market adapter required");
        string[] memory names = vaultConfig.get("markets").toStringArray();
        require(names.length == 1, "exactly one new market required");
        StdConfig marketConfig = new StdConfig(marketConfigPath(vaultConfigDir, names[0]), false);
        require(marketConfig.get("collateral_token").toAddress() == address(0), "market collateral already set");
        require(marketConfig.get("oracle").toAddress() == address(0), "market oracle already set");
        delete marketConfigList;
        marketConfigList.push(
            MarketParameters({
                name: marketConfig.get("name").toString(),
                collateral_token: address(0),
                oracle: address(0),
                irm: marketConfig.get("irm").toAddress(),
                lltv: marketConfig.get("lltv").toUint256(),
                absolute_cap: marketConfig.get("absolute_cap").toUint256(),
                relative_cap: marketConfig.get("relative_cap").toUint256()
            })
        );
        yieldSigner = assetConfig.get("yield_signer").toAddress();
        leverageSigner = assetConfig.get("leverage_signer").toAddress();
        require(yieldSigner != address(0) && leverageSigner != address(0), "signers not set");
        require(yieldSigner != leverageSigner, "signers must differ");
        baseFeed = marketConfig.get("base_feed").toAddress();
        quoteFeed = marketConfig.get("quote_feed").toAddress();
        if (block.chainid == 1) {
            oracleStalenessThreshold = assetConfig.get("oracle_staleness_threshold").toUint256();
            require(oracleStalenessThreshold > 0, "staleness threshold not set");
            require(baseFeed != address(0) && quoteFeed != address(0), "feeds not set");
            require(baseFeed == coreParams.oracle, "base feed must match protocol oracle");
            require(ORACLE_FACTORY_MAINNET.code.length > 0, "oracle factory not deployed");
            require(quoteFeed.code.length > 0 && baseFeed.code.length > 0, "feeds not deployed");
            uint8 baseDecimals = AggregatorV3Interface(baseFeed).decimals();
            uint8 quoteDecimals = AggregatorV3Interface(quoteFeed).decimals();
            require(baseDecimals >= 8 && baseDecimals <= 18, "unsupported base feed decimals");
            require(quoteDecimals >= 8 && quoteDecimals <= 18, "unsupported quote feed decimals");
        } else {
            require(baseFeed == address(0) && quoteFeed == address(0), "mock feeds must be fresh");
            configuredMockPrice = assetConfig.get("mock_oracle_price").toUint256();
            // The market wrapper truncates 18-decimal prices to eight decimals.
            require(
                configuredMockPrice >= 1e10 && configuredMockPrice <= uint256(type(int256).max), "invalid mock price"
            );
        }
        if (block.chainid != 31337) {
            require(IERC20Metadata(coreParams.collateral).decimals() == 6, "collateral must have 6 decimals");
            IMorphoMarketV1AdapterV2Factory factory = resolveMarketV1V2Factory();
            morphoBlue = factory.morpho();
            require(marketConfigList[0].irm == factory.adaptiveCurveIrm(), "incorrect market irm");
            require(IMorpho(morphoBlue).isIrmEnabled(marketConfigList[0].irm), "irm not enabled");
            require(IMorpho(morphoBlue).isLltvEnabled(marketConfigList[0].lltv), "lltv not enabled");
        }
    }

    function createNewVault() internal broadcast returns (VaultDeploymentResult memory vault) {
        vault = createVault(false);
    }

    function configureNewVault(VaultDeploymentResult memory vault) internal broadcast {
        configureVault(vault);
    }

    function configureSigners(CoreDeploymentResult memory core, bool useMockIntegrations) internal override {
        super.configureSigners(core, useMockIntegrations);
        core.controller.setSignerStatus(yieldSigner, true);
        core.controller.setSignerStatus(leverageSigner, true);
        bool hadAdminRole = core.revenue_module.hasRole(ADMIN_ROLE, broadcaster);
        if (!hadAdminRole) core.revenue_module.grantRole(ADMIN_ROLE, broadcaster);
        core.revenue_module.delegateSigner(yieldSigner, true);
        if (!hadAdminRole) core.revenue_module.revokeRole(ADMIN_ROLE, broadcaster);
    }

    function initializeStaking(CoreDeploymentResult memory core) internal override {
        require(core.staked_asset.totalSupply() == 0, "staking already seeded");
        require(core.asset.balanceOf(address(core.staked_asset)) == 0, "staking already funded");
        // Round backing up to six-decimal USDC using the Controller's asset/USD pricing convention.
        stakingSeedCollateral =
            Math.mulDiv(stakingDeadDeposit, core.oracle_adapter.getPrice(), 1e30, Math.Rounding.Ceil);
        require(
            core.collateral.balanceOf(broadcaster)
                >= stakingSeedCollateral + MARKET_SEED_USDC + vaultParams.dead_deposit,
            "insufficient USDC for deployment seeds"
        );

        bool wasSigner = core.controller.signers(broadcaster);
        bool wasRecipient = core.controller.recipients(broadcaster, broadcaster);
        bool wasMinter = core.controller.hasRole(MINTER_ROLE, broadcaster);
        if (!wasSigner) core.controller.setSignerStatus(broadcaster, true);
        if (!wasRecipient) core.controller.setRecipientStatus(broadcaster, true);
        if (!wasMinter) core.controller.grantRole(MINTER_ROLE, broadcaster);

        IController.Order memory order = IController.Order({
            order_type: IController.OrderType.Mint,
            nonce: 0,
            expiry: block.timestamp + 1 hours,
            payer: broadcaster,
            recipient: broadcaster,
            collateral_token: address(core.collateral),
            collateral_amount: stakingSeedCollateral,
            order_token: address(core.asset),
            asset_amount: stakingDeadDeposit
        });
        bytes32 orderHash = core.controller.hashOrder(order);
        IController.Context memory context = IController.Context(orderHash, 0, false);
        IController.Signature memory signature = signStakingSeed(orderHash);
        IController.Signature memory approval = signStakingSeed(core.controller.hashContext(context));
        core.collateral.approve(address(core.controller), stakingSeedCollateral);
        core.controller.mint(order, signature, context, approval);

        core.asset.approve(address(core.staked_asset), stakingDeadDeposit);
        // Exact shares and a bounded allowance reject donations that increase the required assets on-chain.
        uint256 assets = core.staked_asset.mint(stakingDeadDeposit, address(0xDEAD));
        require(assets == stakingDeadDeposit, "unexpected staking seed exchange rate");
        if (!wasMinter) core.controller.revokeRole(MINTER_ROLE, broadcaster);
        if (!wasRecipient) core.controller.setRecipientStatus(broadcaster, false);
        if (!wasSigner) core.controller.setSignerStatus(broadcaster, false);
    }

    function signStakingSeed(bytes32 digest) internal view returns (IController.Signature memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(broadcaster, digest);
        return IController.Signature(IController.SignatureType.EIP712, abi.encodePacked(r, s, v));
    }

    function deployOracleAdapter(bool useMockIntegrations) internal override returns (IOracleAdapter) {
        if (useMockIntegrations) return IOracleAdapter(address(new MockOracleAdapter(configuredMockPrice)));
        return IOracleAdapter(address(new ChainlinkOracleAdapter(coreParams.oracle, oracleStalenessThreshold)));
    }

    function createNewMarket(CoreDeploymentResult memory core) internal broadcast {
        if (block.chainid == 31337) {
            resolveLocalMorphoSingletons();
            marketConfigList[0].irm = adaptiveCurveIrm;
            IMorpho(morphoBlue).enableIrm(adaptiveCurveIrm);
            IMorpho(morphoBlue).enableLltv(marketConfigList[0].lltv);
        }
        if (block.chainid != 1) {
            MockAggregator assetFeed = new MockAggregator();
            assetFeed.setDecimals(18);
            assetFeed.setAnswer(configuredMockPrice);
            baseFeed = address(assetFeed);
            MockAggregator usdc = new MockAggregator();
            usdc.setAnswer(1e8);
            quoteFeed = address(usdc);
        }
        oracleWrapper = address(new ChainlinkOracleWrapper(AggregatorV3Interface(baseFeed)));
        address oracle;
        if (block.chainid == 1) {
            oracle = address(
                IMorphoChainlinkOracleV2Factory(ORACLE_FACTORY_MAINNET)
                    .createMorphoChainlinkOracleV2(
                        IMorphoVault(address(core.staked_asset)),
                        1e18,
                        IMorphoFeed(oracleWrapper),
                        IMorphoFeed(address(0)),
                        18,
                        IMorphoVault(address(0)),
                        1,
                        IMorphoFeed(quoteFeed),
                        IMorphoFeed(address(0)),
                        6,
                        keccak256(abi.encode(SALT, address(core.staked_asset)))
                    )
            );
        } else {
            oracle = deployCode(
                "out/MorphoChainlinkOracleV2.sol/MorphoChainlinkOracleV2.json",
                abi.encode(
                    address(core.staked_asset),
                    1e18,
                    oracleWrapper,
                    address(0),
                    18,
                    address(0),
                    1,
                    quoteFeed,
                    address(0),
                    6
                )
            );
        }
        marketConfigList[0].collateral_token = address(core.staked_asset);
        marketConfigList[0].oracle = oracle;
        MarketParams memory params = toMarketParams(marketConfigList[0]);
        IMorpho(morphoBlue).createMarket(params);
        requireMarketExists(IMorpho(morphoBlue), params);
        core.collateral.approve(morphoBlue, MARKET_SEED_USDC);
        IMorpho(morphoBlue).supply(params, MARKET_SEED_USDC, 0, address(0xDEAD), hex"");
    }

    function outputDirectory() internal view virtual override returns (string memory) {
        return string.concat(
            "broadcast/DeployNewAsset.s.sol/", vm.toString(block.chainid), "/", vm.toString(deployedAsset), "/artifacts"
        );
    }

    function writeOnboarding(CoreDeploymentResult memory core) internal {
        string memory key = "new_asset_onboarding";
        vm.serializeAddress(key, "yield_signer", yieldSigner);
        vm.serializeAddress(key, "leverage_signer", leverageSigner);
        vm.serializeAddress(key, "base_feed", baseFeed);
        vm.serializeAddress(key, "quote_feed", quoteFeed);
        vm.serializeAddress(key, "oracle_wrapper", oracleWrapper);
        vm.serializeUint(key, "staking_dead_deposit", stakingDeadDeposit);
        vm.serializeUint(key, "staking_seed_collateral", stakingSeedCollateral);
        vm.serializeAddress(key, "staking_dead_receiver", address(0xDEAD));
        vm.serializeAddress(key, "morpho", morphoBlue);
        vm.serializeAddress(key, "owner", roles.default_admin_role);
        vm.serializeAddress(key, "asset_token", address(core.asset));
        vm.serializeBytes(key, "accept_ownership_calldata", abi.encodeWithSignature("acceptOwnership()"));
        vm.serializeAddress(key, "controller", address(core.controller));
        vm.serializeAddress(key, "revenue_module", address(core.revenue_module));
        string memory json = vm.serializeBytes(
            key,
            "yield_recipient_calldata",
            abi.encodeWithSignature("setRecipientStatus(address,bool)", address(core.revenue_module), true)
        );
        vm.writeJson(json, string.concat(outputDirectory(), "/onboarding.json"));
        console2.log("Owner must accept token ownership; yield signer must authorize the revenue recipient.");
    }
}
