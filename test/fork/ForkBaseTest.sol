// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract ForkBaseTest is BaseTest {
    using SafeERC20 for IERC20;

    // fork block
    uint256 internal constant FORK_BLOCK = 24_235_159;

    // source chain fork id
    uint256 sourceFork;

    // mainnet contracts
    IERC20 internal usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    // contracts
    IERC4626 internal usdcVault;
    IERC4626 internal usdtVault;

    // accounts
    address dealer;

    function setUp() public virtual override {
        setUpFork();
        super.setUp();
    }

    function setUpFork() internal {
        // fork mainnet
        string memory rpc = vm.rpcUrl("mainnet");
        sourceFork = vm.createFork(rpc, FORK_BLOCK);
        vm.selectFork(sourceFork);

        // setup
        dealer = vm.addr(0xFFFF);
        usdcVault = new MockERC4626("USDC Vault", "vUSDC", usdc);
        usdtVault = new MockERC4626("USDT Vault", "vUSDT", usdt);

        // labels
        label(address(usdc), "usdc");
        label(address(usdt), "usdt");
        label(dealer, "dealer");
        label(address(usdcVault), "usdcVault");
        label(address(usdtVault), "usdtVault");
    }

    function testFork_Config() internal view {
        assertEq(block.number, FORK_BLOCK);
    }

    // helper function to mock token balances in fork tests
    function dealTo(IERC20 token, address to, uint256 amount) internal {
        deal(address(token), dealer, amount);
        resetPrank(dealer);
        IERC20(token).safeTransfer(to, amount);
        vm.stopPrank();
    }
}
