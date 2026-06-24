# VaultAdapter
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/3b9a2e72170c3c18199904176b97ca07122173ad/src/VaultAdapter.sol)

**Inherits:**
IAdapter, Ownable2Step

**Title:**
VaultAdapter

Adapter that connects a Vault V2 parent vault to a single ERC4626 vault.

The parent vault allocates the underlying asset to this adapter, and the adapter
deposits those assets into the configured ERC4626 vault. Accounting is reported
back to the parent vault through a single adapter-specific allocation ID.


## Constants
### parentVault
Parent vault authorized to allocate and deallocate through this adapter.


```solidity
IVaultV2 public immutable parentVault
```


### vault
ERC4626 vault used as the yield source for this adapter.


```solidity
IERC4626 public immutable vault
```


### asset
Underlying ERC20 asset managed by both the parent vault and ERC4626 vault.


```solidity
address public immutable asset
```


### adapterId
Unique allocation ID used by the parent vault to track this adapter.


```solidity
bytes32 public immutable adapterId
```


## Functions
### constructor

Deploys the adapter and grants token approvals to the ERC4626 vault and parent vault.


```solidity
constructor(address parentVault_, address vault_, address owner_) Ownable(owner_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`parentVault_`|`address`|Address of the Vault V2 parent vault that will use this adapter.|
|`vault_`|`address`|Address of the ERC4626 vault where allocated assets will be deposited.|
|`owner_`|`address`||


### allocate

Deposits allocated assets into the ERC4626 vault.

`data` must encode `minShares`, the minimum acceptable shares to receive.


```solidity
function allocate(bytes memory data, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256);
```

### deallocate

Withdraws allocated assets from the ERC4626 vault back into this adapter.

`data` must encode `maxShares`, the maximum acceptable shares to burn.


```solidity
function deallocate(bytes memory data, uint256 assets, bytes4, address)
    external
    returns (bytes32[] memory, int256);
```

### realAssets

Returns the current value of this adapter's ERC4626 share balance in underlying assets.

Uses ERC4626 conversion logic, so the result may be rounded down by the vault.


```solidity
function realAssets() public view returns (uint256);
```

### rescueToken

Rescue tokens sent to this contract

The receiver should be a trusted address to avoid external calls attack vectors


```solidity
function rescueToken(address token, address to) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the ERC20 token to be rescued|
|`to`|`address`|Recipient of rescued tokens|


## Errors
### NotAuthorized
Thrown when a caller other than the parent vault calls an adapter entrypoint.


```solidity
error NotAuthorized();
```

### AssetMismatch
Thrown when the ERC4626 vault asset does not match the parent vault asset.


```solidity
error AssetMismatch();
```

### InsufficientShares
Thrown when insufficient shares were returned by allocation vault


```solidity
error InsufficientShares();
```

### ExcessiveShares
Thrown when excessive shares were burned by deallocation vault


```solidity
error ExcessiveShares();
```

### InvalidToken
Thrown when trying to rescue a vault token


```solidity
error InvalidToken();
```

