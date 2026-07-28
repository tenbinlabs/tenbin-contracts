// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {AggregatorV3Interface} from "chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";
import {ChainlinkOracleWrapper} from "../src/oracle/ChainlinkOracleWrapper.sol";
import {BaseScript} from "./Base.s.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "../test/external/morpho/IERC4626.sol";
import {IMorphoChainlinkOracleV2Factory} from "../test/external/morpho/IMorphoChainlinkOracleV2Factory.sol";
import {IMorphoChainlinkOracleV2} from "../test/external/morpho/IMorphoChainlinkOracleV2.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

// Deploy Chainlink Oracle Wrapper and Morpho Oracle
// FOUNDRY_PROFILE=production forge script script/DeployMorphoOracle.s.sol --rpc-url $MAINNET_RPC_URL --private-key $BROADCASTER_KEY --verify --verifier etherscan --verifier-api-key $ETHERSCAN_API_KEY --slow
contract DeployMorphoOracle is BaseScript {
    using SafeERC20 for IERC20;

    address internal constant TGLD_ADDRESS = 0x6a547b25534234bb79CE6961a23Db13DE154b6F4;
    address internal constant STGLD_ADDRESS = 0x8d301801d899dC81fEabBDE69407A53b82bdBF19;
    address internal constant TGLD_USD_ORACLE = 0x369C67E8b026CC4Ef98350f332D7Dd52b85b7674;
    address internal constant USDC_USD_ORACLE = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    IMorphoChainlinkOracleV2Factory factory =
        IMorphoChainlinkOracleV2Factory(0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766);

    OracleConfig internal oracleConfig;
    ChainlinkOracleWrapper internal wrapper;

    struct OracleConfig {
        IERC4626 baseVault;
        uint256 baseVaultConversionSample;
        AggregatorV3Interface baseFeed1;
        AggregatorV3Interface baseFeed2;
        uint256 baseTokenDecimals;
        IERC4626 quoteVault;
        uint256 quoteVaultConversionSample;
        AggregatorV3Interface quoteFeed1;
        AggregatorV3Interface quoteFeed2;
        uint256 quoteTokenDecimals;
        bytes32 salt;
    }

    /// @notice Results returned when running this deployment script
    struct DeploymentResult {
        address broadcaster;
        ChainlinkOracleWrapper wrapper;
        IMorphoChainlinkOracleV2 oracle;
    }

    /// @dev The version for this deployment
    function getVersion() internal pure override returns (string memory) {
        return "1.0.1";
    }

    function run() public returns (DeploymentResult memory deployment) {
        deployment = deploy();
    }

    function deploy() internal broadcast returns (DeploymentResult memory deployment) {
        console2.log("\n========================= Accounts ==========================\n");
        console2.log("broadcaster address: ", broadcaster);

        // deploy oracle wrapper
        wrapper = new ChainlinkOracleWrapper(AggregatorV3Interface(TGLD_USD_ORACLE));

        // set up config
        oracleConfig = OracleConfig({
            baseVault: IERC4626(0x8d301801d899dC81fEabBDE69407A53b82bdBF19), // stGLD Vault
            baseVaultConversionSample: 1000000000000000000, // 1e18
            baseFeed1: AggregatorV3Interface(address(wrapper)), // tGLD/USD Feed with wrapper
            baseFeed2: AggregatorV3Interface(0x0000000000000000000000000000000000000000), // -
            baseTokenDecimals: 18, // tGLD Decimals (NOT stGLD decimals)
            quoteVault: IERC4626(0x0000000000000000000000000000000000000000), // -
            quoteVaultConversionSample: 1, // -
            quoteFeed1: AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6), // USDC/USD Feed
            quoteFeed2: AggregatorV3Interface(0x0000000000000000000000000000000000000000), // -
            quoteTokenDecimals: 6, // USDC Decimals
            salt: SALT // salt
        });

        IMorphoChainlinkOracleV2 oracle = factory.createMorphoChainlinkOracleV2(
            oracleConfig.baseVault,
            oracleConfig.baseVaultConversionSample,
            oracleConfig.baseFeed1,
            oracleConfig.baseFeed2,
            oracleConfig.baseTokenDecimals,
            oracleConfig.quoteVault,
            oracleConfig.quoteVaultConversionSample,
            oracleConfig.quoteFeed1,
            oracleConfig.quoteFeed2,
            oracleConfig.quoteTokenDecimals,
            oracleConfig.salt
        );

        // try to estimate price output
        uint256 estimatedPriceUSD =
            (IERC4626(STGLD_ADDRESS).convertToAssets(1e18) * uint256(getAnswer(AggregatorV3Interface(TGLD_USD_ORACLE))))
                / (1e18);

        uint256 estimatedPriceUSDC = estimatedPriceUSD * uint256(getAnswer(AggregatorV3Interface(USDC_USD_ORACLE)));

        // perform price tests
        console2.log("scale_factor: ", oracle.SCALE_FACTOR());
        console2.log("price.              : ", oracle.price());
        console2.log("estimated_price_usd : ", estimatedPriceUSD);
        console2.log("estimated_price_usdc: ", estimatedPriceUSDC);
        console2.log("wrapper_answer: ", getAnswer(wrapper));
        console2.log("wrapper_decimals: ", wrapper.decimals());

        DeploymentResult memory result = DeploymentResult({broadcaster: broadcaster, wrapper: wrapper, oracle: oracle});
        printContracts(result);
        return result;
    }

    function printContracts(DeploymentResult memory deployment) internal pure {
        console2.log("\n========================= Contracts =========================\n");
        console2.log("ChainlinkOracleWrapper: ", address(deployment.wrapper));
        console2.log("MorphoChainlinkOracleV2: ", address(deployment.oracle));
        console2.log("\n=============================================================\n");
    }

    // helper to get answer from a chainlink aggregator
    function getAnswer(AggregatorV3Interface oracle) internal view returns (int256 answer) {
        (, answer,,,) = oracle.latestRoundData();
    }
}

