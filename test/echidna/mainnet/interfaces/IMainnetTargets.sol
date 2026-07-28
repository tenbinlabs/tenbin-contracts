// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Narrow interfaces for the live mainnet deployment.
//
// The harnesses deliberately do NOT import from src/. Deployed bytecode lags the
// repo -- live tGLD is v1.4.0 and has no `CollateralManager.distributor()`, while
// src/CollateralManager.sol declares it, and tBRL/tMXN are on v1.4.3. Binding
// src/ types to live addresses therefore reverts mid-run on any member added
// since deployment.
//
// Every selector below is verified present on-chain by
// test/fork/echidna/MainnetAbiProbe.t.sol -- add nothing here without adding it
// to that probe.

interface IAssetTokenLike {
    error OnlyMinter();

    function minter() external view returns (address);
    function owner() external view returns (address);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner_, address spender) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function burn(uint256 amount) external;
    function mint(address account, uint256 amount) external;
    function setMinter(address newMinter) external;
}

interface IStakedAssetLike {
    function asset() external view returns (address);
    function silo() external view returns (address);
    function totalSupply() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function cooldownPeriod() external view returns (uint256);
    function cooldownIds(address account) external view returns (uint256);
    function cooldowns(address account, uint256 id) external view returns (uint160 assets, uint96 end);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function maxRedeem(address owner_) external view returns (uint256);
    function maxWithdraw(address owner_) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner_) external returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function cooldownShares(uint256 shares) external returns (uint256 assets, uint256 id);
    function cooldownAssets(uint256 assets) external returns (uint256 shares, uint256 id);
    function cancelCooldown(uint256 id) external returns (uint256 shares);
    function unstake(address receiver, uint256 id) external;
}

interface IControllerLike {
    function pauseStatus() external view returns (uint8);
    function custodian() external view returns (address);
    function manager() external view returns (address);
    function ratio() external view returns (uint256);
    function blockMintLimit() external view returns (uint128);
    function blockRedeemLimit() external view returns (uint128);
    function delegates(address account, address signer) external view returns (bool);
    function nonces(address payer, uint256 nonce) external view returns (bool);

    // Permissionless
    function invalidateNonce(uint256 nonce) external;
    function setDelegateStatus(address signer, bool status) external;

    // Privileged -- must revert for unprivileged callers
    function setIsRestricted(address account, bool status) external;
    function setRatio(uint256 newRatio) external;
    function setOracleAdapter(address newAdapter) external;
    function setCustodian(address newCustodian) external;
    function setBlockMintLimit(uint128 newBlockMintLimit) external;
}

interface ICollateralManagerLike {
    error FMLPause();

    function controller() external view returns (address);
    function swapModule() external view returns (address);
    function revenueModule() external view returns (address);
    function pauseStatus() external view returns (uint8);

    // Privileged -- must revert for unprivileged callers
    function addCollateral(address collateral, address vault) external;
    function removeCollateral(address collateral) external;
    function setRebalanceCap(address collateral, uint256 amount) external;
    function setSwapCap(address collateral, uint256 newSwapCap) external;
    function withdraw(address collateral, uint256 amount, uint256 maxShares) external;
    function rescueToken(address token, address to) external;
    function setPauseStatus(uint8 status) external;
}
