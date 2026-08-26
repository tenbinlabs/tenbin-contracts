# GenericMorphoAdapterFactory
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/51cfcc3be55c1fc66666f437e8175c7820cc2918/src/external/morpho/GenericMorphoAdapterFactory.sol)

**Title:**
GenericMorphoAdapterFactory

Factory for deploying GenericMorphoAdapter contracts for parent vault / ERC4626 vault pairs.


## State Variables
### genericMorphoAdapter
Returns the adapter deployed for a given parent vault and ERC4626 vault.


```solidity
mapping(address parentVault => mapping(address vault => address adapter)) public genericMorphoAdapter
```


### isGenericMorphoAdapter
Tracks whether an address was deployed by this factory as a GenericMorphoAdapter.


```solidity
mapping(address account => bool) public isGenericMorphoAdapter
```


## Functions
### createGenericMorphoAdapter

Deploys a GenericMorphoAdapter for a parent vault and ERC4626 vault.

Reverts if the same constructor arguments have already been deployed with this factory.


```solidity
function createGenericMorphoAdapter(address parentVault, address vault, address owner) external returns (address);
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
|`<none>`|`address`|The address of the deployed GenericMorphoAdapter.|


## Events
### CreateGenericMorphoAdapter
Emitted when a new GenericMorphoAdapter is deployed.


```solidity
event CreateGenericMorphoAdapter(
    address indexed parentVault, address indexed vault, address indexed genericMorphoAdapter
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`parentVault`|`address`|Parent vault that will use the adapter.|
|`vault`|`address`|ERC4626 vault connected to the adapter.|
|`genericMorphoAdapter`|`address`|Address of the deployed adapter.|

