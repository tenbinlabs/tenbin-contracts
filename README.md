# Tenbin Smart Contracts

[tenbinlabs.xyz](https://tenbinlabs.xyz)
 
Tenbin is an asset tokenization protocol which uses futures contracts to enable highly liquid assets. Read the full docs here: [DOCS](docs/src/SUMMARY.md)

# Mainnet Addresses

| Contract | Address |
| --- | --- |
| Adapter | [0x932E0ba317897D4a3142929B95CaaDA33df5fC35](https://etherscan.io/address/0x932E0ba317897D4a3142929B95CaaDA33df5fC35) |
| AssetSilo | [0xA924A7493782c11b4E408B072367A0Fc02556092](https://etherscan.io/address/0xA924A7493782c11b4E408B072367A0Fc02556092) |
| AssetToken | [0x6a547b25534234bb79CE6961a23Db13DE154b6F4](https://etherscan.io/address/0x6a547b25534234bb79CE6961a23Db13DE154b6F4) |
| CollateralManager | [0x42F3F01D45E67294e20cE98AcFDC24dD7EA75dEa](https://etherscan.io/address/0x42F3F01D45E67294e20cE98AcFDC24dD7EA75dEa) |
| Controller | [0xcaF2cD7fd794CaAf56555Db90A5865a5FE9182f7](https://etherscan.io/address/0xcaF2cD7fd794CaAf56555Db90A5865a5FE9182f7) |
| CustodianModule | [0x97e1C8dc9a3CcA064fAA8318f9b5C7AdB26b0e89](https://etherscan.io/address/0x97e1C8dc9a3CcA064fAA8318f9b5C7AdB26b0e89) |
| Gate | [0x70056E107dFBb58B74739Ba095E1Dd77CCC7cab1](https://etherscan.io/address/0x70056E107dFBb58B74739Ba095E1Dd77CCC7cab1) |
| MultiCall | [0xdA8B85Cd62CDB3C104c80b479f9094e07EBcF7e8](https://etherscan.io/address/0xdA8B85Cd62CDB3C104c80b479f9094e07EBcF7e8) |
| StakedAsset | [0xdE80e9EC32249d4c7dBA7997fD6D6C03fb27EBf4](https://etherscan.io/address/0xdE80e9EC32249d4c7dBA7997fD6D6C03fb27EBf4) |
| Vault | [0x7290245b3e564f0Ae2dA5af0690eF4842CF13c75](https://etherscan.io/address/0x7290245b3e564f0Ae2dA5af0690eF4842CF13c75) |
| RevenueModule | [0x5D46Ec01376d218Ade3c1133a7E38976c2DBe584](https://etherscan.io/address/0x5D46Ec01376d218Ade3c1133a7E38976c2DBe584) |
| SwapModule | [0xB426bcB6028Ba1fBB746a8af11859D97007BE594](https://etherscan.io/address/0xB426bcB6028Ba1fBB746a8af11859D97007BE594) |

# Audit
Four smart contract audits were performed on the solidity codebase. An initial independent audit was conducted, followed by major audits by Spearbit, Fuzzland, and Verilog. The scope was initially created based on a monorepo, then moved to a public repository at https://github.com/tenbinlabs/contracts.

[scope](audit/scope_1_22_26.pdf)
 
[0xleastwood](audit/0xleastwood_1_22_26.pdf)
 
[fuzzland](audit/fuzzland_1_22_26.pdf)
 
[spearbit](audit/spearbit_1_22_26.pdf)
 
[verilog](audit/verilog_1_22_26.pdf)

# Setup

### Installations

Ensure rust is installed: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
 
Ensure rust is up-to-date: `rustup update`
 
Ensure foundry is installed: `curl -L https://foundry.paradigm.xyz | bash`
 
Ensure foundry is up-to-date: `foundryup`
 
Install dependencies: `forge install`
 
Build contracts: `forge build`

### Set up .env

Create .env file and fill in variables: `cp .env.example .env`
 
Set permissions for .env: `chmod 600 .env`

### Build

Build production contracts:
 
`FOUNDRY_PROFILE=production forge build`

### Testing

#### Run all tests:
 
`forge test`

#### Run tests and skip fork tests:
 
`forge test --skip test/fork/*`

#### Run invariant tests:

`forge test --match-path "test/invariant/*"`
 
#### View coverage:
 
`FOUNDRY_PROFILE=coverage forge coverage`

View coverage with uncovered branches and lines:

`FOUNDRY_PROFILE=coverage forge coverage --report debug`

#### Generate gas report:

`forge test --gas-report`

#### Generate documentation:

`forge doc`

### Fuzzing

Install echidna: https://github.com/crytic/echidna?tab=readme-ov-file#installation

Run all echidna tests: `echidna.sh`

`echidna test/echidna/<contract-file-name>.sol --contract <contract-name> --config echidna.yaml"`

### Formal Verification

#### Certora

Install Certora: https://docs.certora.com/en/latest/docs/user-guide/install.html#installation

Ensure CERTORAKEY is set in .env

Run certora: ```certoraRun contractFile:contractName --verify contractName:specFile```

### Static Analysis

#### Slither:

Install slither: https://github.com/crytic/slither?tab=readme-ov-file#how-to-install
 
Run slither: `slither .`

#### Aderyn

Install cyfrin: https://github.com/Cyfrin/up

Run `forge build && aderyn` and review report.md.

#### Mythril

Install mythril: https://mythril-classic.readthedocs.io/en/develop/installation.html

Run mythril: `myth analyze {your_contract}`

Configuration: https://getfoundry.sh/config/static-analyzers/#mythril

# Deploy

Use `config/` to configure roles and parameters when running deploy scripts. Roles and existing deployments are tracked in deployments.json. When running the deployment script, a file is created in `broadcast/{chainid}/{script_name}/deployments.json` containing the recently deployed contracts and roles.

### Deploy locally

1) Ensure BROADCASTER_KEY is not set in .env

2) Run anvil: `anvil --mnemonic $TEST_MNEMONIC`

3) Run `FOUNDRY_PROFILE=production forge script script/DeployTestnet.s.sol --rpc-url ws:/localhost:8545 --broadcast`

### Deploy morhpo v2 vault onto sepolia testnet
1) Ensure BROADCASTER_KEY is set in .env

2) `Run FOUNDRY_PROFILE=production forge script script/DeployVault.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast`

### Deploy to sepolia testnet:

Run `FOUNDRY_PROFILE=production forge script script/DeployMock.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $BROADCASTER_KEY --verifier etherscan --verifier-api-key $ETHERSCAN_API_KEY --slow`

Use `--broadcast` to broadcast

#### Minting tokens on testnet

1) Ensure `COLLATERAL_ADDRESS`, `CONTROLLER_ADDRESS`, `MINTER_ADDRESS`, `MINTER_KEY`, and `SIGNER_KEY` are set in `.env`
2) Ensure scripts/MintTestnet.s.sol has the correct addresses set as constants
3) Run `source .env`
4) Ensure approval is granted from payer key
```cast send $COLLATERAL_ADDRESS "approve(address,uint256)" $CONTROLLER_ADDRESS 1000000000000000000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $SIGNER_KEY```
5) Run the mint script
```forge script script/MintTestnet.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $MINTER_KEY --broadcast```
THIS SCRIPT IS NOT SAFE TO RUN ON MAINNET!!

### Deploying to mainnet 

```FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --private-key $BROADCASTER_KEY --rpc-url $MAINNET_RPC_URL --verify --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --slow ```

# Architecture

# Overview

Tenbin is an asset token issuance platform with the goal of creating liquid, composable financial assets. Assets in the Tenbin protocol are backed by two positions: off-chain futures contracts and on-chain collateral. The off-chain hedging system maintains a delta one exposure of an underlying asset. The on-chain collateral is used to earn low-risk yield. So long as the on-chain yield equals or exceeds the off-chain funding costs, the protocol is able to peg Tenbin assets to the spot price of the real asset.

Each asset in the Tenbin protocol has a set of contracts unique to that asset. Key contracts include the AssetToken, Controller, StakedAsset, and CollateralManager. This document is an outline of the smart contract system used to facilitate mints, redemptions, staking, and on-chain collateral management.

# AssetToken

An asset token represents an asset in the Tenbin protocol. The AssetToken contract is an immutable, non-upgradeable ERC20 token with an extension to allow minting and burning. There is an `owner` and `minter` role. The owner is a multisig that can set the minter account, and the minter can mint new tokens. In all cases, the minter will be set as the Controller contract.

# Controller

The controller contract is responsible for minting and redeeming assets. Mint and redemptions are encoded as an Order. Orders are signed by KYC-approved signers and specify order details such as collateral amount, asset amount, and deadline. To successfully execute an order, a minter account calls the `mint` or `redeem` with an order and signature. Orders are executed atomically: collateral is transferred and tokens are minted/burned in a single transaction. All orders are executed by a minter key stored in a hardware security module and controlled by the Tenbin backend.

### Order Fields

```
    struct Order {
        OrderType order_type;       // Order type (MINT or REDEEM)
        uint256 nonce;              // Payer unique nonce
        uint256 expiry;             // Order expiration timestamp
        address payer;              // Account to transfer tokens from
        address recipient;          // Account to receive tokens
        address collateral_token;   // Collateral used for this order
        uint256 collateral_amount;  // Amount of collateral tokens
        uint256 asset_amount;       // Amount of asset tokens
    }
```

### Order Lifecycle

1. Order signer goes through KYC and is added to the allowed signers list.
2. An order signer submits a signed order to the Tenbin backend.
3. The backend processes the order and calls the `mint` or `redeem` function.
4. Token are transferred accordingly and payer nonce is marked as used.

### Allowed Signers

The controller keeps track of what accounts are allowed to sign orders. An account must be on the allowed signer list in order to submit a successful order. Note that the minter account can never modify the contents of an order, and that an order can only ever be executed once by specifying a unique nonce for every order. The controller supports both EIP712 and EIP1271 signatures.

### Approved Recipients

Signers can set which accounts can receive tokens when an order is executed. This control prevents signers from sending tokens to an incorrect account. Signers can manage recipients on-chain by calling `setRecipientStatus()`. By default, a signer is approved to be a recipient for its own orders.

### Delegate Signers

Any account can delegate a signer to sign orders on its behalf. During execution of an order, the payer is checked against the delegates for a signer. This allows for EOAs or smart contracts to let a signer sign an order where the delegate pays for the order. An account can add a delegate signer by calling `setDelegateStatus()`.

### Collateral Ratio

The controller has a collateral ratio which specifies the percentage of collateral which is sent to `custodian` and `manager`. The custodian amount represents the portion of collateral which is moved off-chain to fund futures hedge positions. The manager amount represents the portion of collateral designated to earn on-chain yield. When a mint occurs, the total collateral amount is split according to the`ratio` value set in the Controller.

### Custodian Module

The custodian module receives collateral during a mint order. Custodians are added to a list of approved accounts. Only approved custodians can receive collateral from a mint event. A keeper role is assigned to interact with the custodian module and transfer collateral accordingly.

### Oracle Adapter

The controller has a configurable oracle adapter which can provide a price when executing orders. When enabled, the oracle price acts as a backstop to prevent order pricing from exceeding a threshold. The oracle DOES NOT determine the price of assets, rather it acts as a security measure to prevent minting and redeeming assets at a price off-peg. For example, with the oracle configured it is impossible to mint new assets with a price of $0.

### RestrictedRegistry

The controller uses a restricted registry of accounts which cannot interact with the controller. During order execution, the `payer` and `recipient` are checked against this registry. 

# Collateral Manager

The manager contract stores collateral to earn on-chain yield and provide liquidity for redemptions. When executing a mint order, collateral is transferred directly to the CollateralManager. The manager is non-custodial: there is no way to withdraw protocol collateral from the manager except during execution of a redemption order or a rebalancing action. For each collateral there is an associated ERC4626 vault, typically a Morpho V2 vault, used to earn yield. The manager uses accounting to separate collateral from revenue.

The main actions that can be performed by the collateral manager are:

- Deposit collateral into vaults
- Withdraw collateral from vaults
- Swap collateral tokens
- Withdraw revenue
- Rebalance collateral between on/off chain

### Deposit and Withdraw

The two main functions provided by the collateral manager are `deposit()`and `withdraw()`. Each collateral has a unique vault dedicated to earning yield for that collateral type. Depositing will deposit collateral into the vault in exchange for vault shares. Withdrawing will redeem vault shares in exchange for the underlying collateral.

### Liquidity Management

The most important role of the manager is to ensure there is sufficient liquidity to redeem assets. Collateral that is in the collateral manager is approved to be transferred by the controller when a redemption order is filled. If there is insufficient collateral in the manager, a redemption is not possible.

In order for Tenbin to optimize yield versus liquidity, a curator role is assigned by the manager to perform deposits and withdrawals. By using a multicall contract, it is possible to bundle deposits and withdrawals with mints and redemptions atomically. For example: `[mint(), deposit()]` or `[withdraw(), redeem()]`. 

### Collateral Rebalancing

Rebalancing occurs when there is a surplus or deficit of on-chain vs off-chain collateral. If the off-chain position is over-collateralized, collateral is moved on-chain through a custodian account and transferred directly to the Collateral Manager. If the off-chain position is under-collateralized, the `rebalance()` function can be called by a permissioned role to withdraw collateral from the manager.

In order to limit the amount of collateral that can be withdrawn during a rebalance, there is a cap set on the amounts that can be withdrawn during this function. Additionally, the rebalancer withdraw can only withdraw to a registered set of custodians in the CustodianModule. This design guarantees that protocol collateral is always in custody and cannot be directly controlled by protocol operators.

### Revenue Module

The RevenueModule manages revenue earned by the protocol. In most cases, revenue is transferred back to the collateral manager in order to pay for the off-chain hedging costs.

The revenue module can perform the following actions:

- Withdraw revenue from the collateral manager
- Transfer revenue back to the collateral manager
- Transfer revenue to a multisig contract
- Provide liquidity to mint new asset tokens as a reward
- Reward the staking pool with asset tokens

A keeper role is assigned by the revenue module to automate these tasks. For example, the keeper might be called 2x per day to transfer revenue back to the collateral manager, and 1x per day to reward the staking contract.

### Swap Module

The swap module is used to perform on-chain swaps between collateral types. The goal of this module is to strictly restrict what types of swaps are possible and limit the slippage between different collaterals. Each swap performed in the CollateralManager passes in a set of constraints for that swap plus the call data to perform the swap. In addition, there are configurable slippage limits in the contract storage for swaps between specific collaterals. This security measure limits the possibility of performing a poorly priced swap. Additionally, there is a swap capacity for each token. The swap cap prevents the curator from swapping an excessive amount of collateral (for instance, human or backend error)

It is possible to bundle swaps as part of a multicall. For example, if there is insufficient USDT in the manager and a redemption order is placed requesting USDT, the following bundle can be created: `[swap(), redeem()]`.

### Upgradeability 

The manager is a UUPS upgradeable smart contract. The intention of upgradeability is to support new on-chain yield structures in the future. In the case the design is considered stable and immutability is desired, the upgrade feature can be permanently disabled.

# StakedAsset

The staking contract allows accounts to stake asset tokens in exchange for a staking token. If the protocol is profitable, revenue can be used to mint new asset tokens and reward them to the staking pool. Staking allows for the creation of compounding, yield-bearing assets in the Tenbin protocol. The staking contract is implemented as a custom ERC4626 vault.

Locking assets in the staking contract has the added benefit of enabling advanced yield strategies in the manager vaults. For example, if it is known that 20% of assets are locked in the staking pool for 7 days, the portion of collateral backing those assets can be committed to locked yield strategies such as sUSDe. Additionally, understanding how much of an asset is locked allows more efficient liquidity management in the manager.

The asset value of a staking token can only increase over time. When unstaking, the staking token is burned in exchange for the original amount deposited, plus a share of any rewards earned since staking.

### Vesting

A vesting period is used for rewards in order to prevent abuse of the staking contract. The vesting period encourages depositors to remain staked through the vesting period. This mechanism prevents negative MEV actions such as sandwiching reward transactions. 

Additionally vesting spreads out rewards over a longer period of time in order to reduce reward volatility. For some assets, minting reward tokens is not always possible due to futures off-market hours. Using a longer vesting period allows stakers to earn a consistent yield despite possibly inconsistent reward schedules and amounts.

### Cooldown

A cooldown time is present in the staking contract to encourage assets to remain staked and allow response time for liquidity management. When a staker calls the `cooldown()` function, staked tokens are burned and transferred to the AssetSilo contract. After the cooldown end time has passed, a user can call `unstake()` to withdraw the underlying asset tokens.

In order to withdraw tokens, a staker needs to call `cooldown()` and wait until the cooldown period has passed to withdraw their stake. It is important to note that only one active cooldown process can be in effect simultaneously; if the user calls `cooldown()` again, it will terminate the current cooldown and initiate a new cooldown period.

Each staker can only have one cooldown at a time, and the cooldown will be reset when cooling down additional assets. Initiating a cooldown cannot be cancelled - new cooled down amounts will be added to the previous cooldown amount. The cooldown period is designed to improve collateral management and prevent abuse of the staking contracts.

### Restricted Registry

Due to legal restrictions, yield cannot be paid to stakers without regulatory compliance. For this reason, a restricted registry is present in the staking contract. Accounts added to this registry cannot stake, unstake, or transfer staked tokens. If an account is restricted, the contract default admin can burn the account’s staking tokens and withdraw the underlying assets.


### Upgradeability 

The manager is a UUPS upgradeable smart contract. The intention of upgradeability is to support new staking models in the future. In the case the design is considered stable and immutability is desired, the upgrade feature can be permanently disabled.