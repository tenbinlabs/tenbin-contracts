# VaultAdapterFactory
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/eb2d102704c08124f1036e9b92cd46f9cf41203f/src/VaultAdapterFactory.sol)

**Title:**
VaultAdapterFactory

Factory for deploying VaultAdapter contracts for parent vault / ERC4626 vault pairs.


## State Variables
### vaultAdapter
Returns the adapter deployed for a given parent vault and ERC4626 vault.


```solidity
mapping(address parentVault => mapping(address vault => address adapter)) public vaultAdapter
```


### isVaultAdapter
Tracks whether an address was deployed by this factory as a VaultAdapter.


```solidity
mapping(address account => bool) public isVaultAdapter
```


## Functions
### createVaultAdapter

Deploys a VaultAdapter for a parent vault and ERC4626 vault.

Reverts if the same constructor arguments have already been deployed with this factory.


```solidity
function createVaultAdapter(address parentVault, address vault, address owner) external returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`parentVault`|`address`|Address of the parent vault that will own/use the adapter.|
|`vault`|`address`|Address of the ERC4626 vault the adapter will allocate into.|
|`owner`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the deployed VaultAdapter.|


## Events
### CreateVaultAdapter
Emitted when a new VaultAdapter is deployed.


```solidity
event CreateVaultAdapter(address indexed parentVault, address indexed vault, address indexed vaultAdapter);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`parentVault`|`address`|Parent vault that will use the adapter.|
|`vault`|`address`|ERC4626 vault connected to the adapter.|
|`vaultAdapter`|`address`|Address of the deployed adapter.|

