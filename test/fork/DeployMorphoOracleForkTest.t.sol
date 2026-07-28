// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {AggregatorV3Interface} from "chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";
import {ChainlinkOracleWrapper} from "../../src/oracle/ChainlinkOracleWrapper.sol";
import {DeployMorphoOracle} from "script/DeployMorphoOracle.s.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "../external/morpho/IERC4626.sol";
import {IMorphoChainlinkOracleV2Factory} from "../external/morpho/IMorphoChainlinkOracleV2Factory.sol";
import {IMorphoChainlinkOracleV2} from "../external/morpho/IMorphoChainlinkOracleV2.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

// test deployment of morpho oracle
// forge test --mt test_DeployMorphoOracle -vvvv
contract DeployMorphoOracleForkTest is ForkBaseTest {
    using SafeERC20 for IERC20;

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

    address internal constant TGLD_ADDRESS = 0x6a547b25534234bb79CE6961a23Db13DE154b6F4;
    address internal constant STGLD_ADDRESS = 0x8d301801d899dC81fEabBDE69407A53b82bdBF19;
    address internal constant TGLD_USD_ORACLE = 0x369C67E8b026CC4Ef98350f332D7Dd52b85b7674;
    address internal constant USDC_USD_ORACLE = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    IMorphoChainlinkOracleV2Factory factory =
        IMorphoChainlinkOracleV2Factory(0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766);

    OracleConfig internal config;
    ChainlinkOracleWrapper internal wrapper;
    IMorphoChainlinkOracleV2 internal oracle;

    function setUp() public override {
        forkBlock = 25269173;
        super.setUp();
    }

    function test_DeployMorphoOracle() public {
        // deploy oracle and wrapper
        DeployMorphoOracle deployer = new DeployMorphoOracle();
        DeployMorphoOracle.DeploymentResult memory result = deployer.run();
        wrapper = result.wrapper;
        oracle = result.oracle;

        // try to estimate price output
        uint256 estimatedPriceUSD =
            (IERC4626(STGLD_ADDRESS).convertToAssets(1e18) * uint256(getAnswer(AggregatorV3Interface(TGLD_USD_ORACLE))))
                / (1e18);
        uint256 estimatedPriceUSDC =
            (estimatedPriceUSD * 1e14) / uint256(getAnswer(AggregatorV3Interface(USDC_USD_ORACLE)));

        // log prices
        console2.log("scale_factor: ", oracle.SCALE_FACTOR());
        console2.log("price               : ", oracle.price());
        console2.log("estimated_price_usdc: ", estimatedPriceUSDC);
        console2.log("wrapper_answer: ", getAnswer(wrapper));
        console2.log("wrapper_decimals: ", wrapper.decimals());

        // ensure price matches estimated price
        assertApproxEqAbs(oracle.price(), estimatedPriceUSDC, oracle.SCALE_FACTOR());
    }

    // helper to get answer from a chainlink aggregator
    function getAnswer(AggregatorV3Interface chainlinkAggregator) internal view returns (int256 answer) {
        (, answer,,,) = chainlinkAggregator.latestRoundData();
    }
}

