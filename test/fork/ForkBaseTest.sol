// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../BaseTest.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract ForkBaseTest is BaseTest {
    using SafeERC20 for IERC20;

    // source chain fork id
    uint256 sourceFork;

    // mainnet contracts
    IERC20 internal usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    // see: https://docs.morpho.org/get-started/resources/addresses/#morpho-v2-contracts
    address internal constant VAULT_V2_FACTORY_ADDRESS = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    address internal constant VAULT_V1_ADAPTER_FACTORY_ADDRESS = 0xD1B8E2dee25c2b89DCD2f98448a7ce87d6F63394;

    // contracts
    IERC4626 internal usdcVault;
    IERC4626 internal usdtVault;

    // accounts
    address dealer;

    // default fork block
    uint256 forkBlock = 24398000;

    function setUp() public virtual override {
        setUpFork();
        super.setUp();
    }

    function setUpFork() internal {
        // fork mainnet
        string memory rpc = vm.rpcUrl("mainnet");
        vm.createSelectFork(rpc, forkBlock);

        // accounts
        dealer = vm.addr(0xE000);

        // labels
        label(address(usdc), "usdc");
        label(address(usdt), "usdt");
        label(dealer, "dealer");
    }

    function setUpMockVaults() internal {
        // setup mock vaults
        usdcVault = new MockERC4626("USDC Vault", "vUSDC", usdc);
        usdtVault = new MockERC4626("USDT Vault", "vUSDT", usdt);
        label(address(usdcVault), "usdcVault");
        label(address(usdtVault), "usdtVault");
    }

    // helper function to mock token balances in fork tests
    function dealTo(IERC20 token, address to, uint256 amount) internal {
        deal(address(token), dealer, amount);
        resetPrank(dealer);
        IERC20(token).safeTransfer(to, amount);
        vm.stopPrank();
    }
}
