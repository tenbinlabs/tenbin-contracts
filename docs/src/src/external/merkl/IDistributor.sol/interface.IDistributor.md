# IDistributor
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/64004be494549e5de52bb55a6490bd85d73a4f57/src/external/merkl/IDistributor.sol)

Minimal version of Merkl's rewards distributor contract at 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae


## Functions
### claim


```solidity
function claim(
    address[] calldata users,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[][] calldata proofs
) external;
```

### claimWithRecipient


```solidity
function claimWithRecipient(
    address[] calldata users,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[][] calldata proofs,
    address[] calldata recipients,
    bytes[] memory datas
) external;
```

### setClaimRecipient


```solidity
function setClaimRecipient(address recipient, address token) external;
```

### toggleOperator


```solidity
function toggleOperator(address user, address operator) external;
```

### claimRecipient


```solidity
function claimRecipient(address user, address token) external returns (address);
```

