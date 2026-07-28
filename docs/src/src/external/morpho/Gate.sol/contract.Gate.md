# Gate
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/64004be494549e5de52bb55a6490bd85d73a4f57/src/external/morpho/Gate.sol)

**Inherits:**
IReceiveSharesGate, ISendSharesGate, IReceiveAssetsGate, ISendAssetsGate, Ownable

Gate used to restrict vault deposits/withdrawals to a single manager account
https://docs.morpho.org/curate/concepts/gates/#gates-in-vault-v2


## State Variables
### manager
Manager can receive/send shares and receive/send assets


```solidity
address manager
```


## Functions
### constructor


```solidity
constructor(address owner_) Ownable(owner_);
```

### setManager


```solidity
function setManager(address newManager) external onlyOwner;
```

### canReceiveShares


```solidity
function canReceiveShares(address account) external view returns (bool);
```

### canSendShares


```solidity
function canSendShares(address account) external view returns (bool);
```

### canReceiveAssets


```solidity
function canReceiveAssets(address account) external view returns (bool);
```

### canSendAssets


```solidity
function canSendAssets(address account) external view returns (bool);
```

