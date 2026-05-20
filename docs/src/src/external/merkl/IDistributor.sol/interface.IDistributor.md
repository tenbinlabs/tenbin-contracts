# IDistributor
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/14e4f5c2d1208a42b40e6ca6182f36f84dc88dd9/src/external/merkl/IDistributor.sol)

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

