# Tenbin Smart Contracts

[tenbinlabs.xyz](https://tenbinlabs.xyz)
 
Tenbin is an asset tokenization protocol which uses futures contracts to enable highly liquid assets. Read the full docs here: [DOCS](docs/src/SUMMARY.md)

# Mainnet Addresses

| Contract | Address |
| --- | --- |
| tGLD | [0x6a547b25534234bb79CE6961a23Db13DE154b6F4](https://etherscan.io/address/0x6a547b25534234bb79CE6961a23Db13DE154b6F4) |
| stGLD | [0x8d301801d899dC81fEabBDE69407A53b82bdBF19](https://etherscan.io/address/0x8d301801d899dC81fEabBDE69407A53b82bdBF19) |
| tBRL | [0x4C1b46adb8877E389171EC6Ef67b385094C0afaD](https://etherscan.io/address/0x4C1b46adb8877E389171EC6Ef67b385094C0afaD) |
| stBRL | [0xDaB276F6E19CCC54cA5aaA2645A94087ca776a3f](https://etherscan.io/address/0xDaB276F6E19CCC54cA5aaA2645A94087ca776a3f) |
| tMXN | [0x8d015aFcb6F437010653352EB1E58152c4e23734](https://etherscan.io/address/0x8d015aFcb6F437010653352EB1E58152c4e23734) |
| stMXN | [0x8BDf6A2DFda084bD242Cd285CF75E80de3eB00ba](https://etherscan.io/address/0x8BDf6A2DFda084bD242Cd285CF75E80de3eB00ba) |
| tPYR | [0x6dBe635c3AA75EA4C75595177EDC97B135dEd5Df](https://etherscan.io/address/0x6dBe635c3AA75EA4C75595177EDC97B135dEd5Df) |
| stPYR | [0xa29D6c1f453D1bc709C829C29c5956B1C5de2BBF](https://etherscan.io/address/0xa29D6c1f453D1bc709C829C29c5956B1C5de2BBF) |

See [deployments.json](deployments.json) for the complete core address registry and [cross-chain-deployments.json](cross-chain-deployments.json) for hub/spoke deployments.

# Audit

Tenbin uses a continuous auditing policy with a target of one audit cycle per quarter. Two rounds of audits have been conducted on the tenbin core contracts codebase. The first core protocol audits occured on 1/22/26 and the second on 4/12/26. An audit on external integrations with Morpho and Bebop occured on 8/3/26. Notable auditors include Spearbit, Zellic, Fuzzland, and Verilog. Starting after 8/3/26, tenbin will start publishing remediations in addition to the final audit reports.

## 8/3/26 Audit

The auditing firms zellic and verilog (formerly fuzzland) performed an audit focused on adapters for Morpho V2 vault and a hook contract to allow inventory-free RFQ swaps. Additionaly, the audit covered a cross chain adapter for Chainlink CCIP which can be found in this repo (pending open source): https://github.com/tenbinlabs/cross-chain-erc4626-vault

[scope](audit/8_03_26_scope.pdf)
 
[zellic](audit/8_03_26_zellic.pdf)
 
[zellic remediations](audit/8_03_26_zellic_remediations.pdf)
 
[verilog](audit/8_03_26_verilog.pdf)
  
[verilog remediations](audit/8_03_26_verilog_remediations.pdf)

## 4/12/26 Audit

The auditing firms zellic and fuzzland performed a full protocol audit. Additionally, AI audits were run using claude code and cantina's AI auditor tool.

[scope](audit/4_12_26_scope.pdf)
 
[zellic](audit/4_22_26_zellic.pdf)

[fuzzland](audit/5_4_26_fuzzland.pdf)

[claude AI](audit/4_29_26_claude_AI.pdf)

[cantina AI](audit/5_1_26_cantina_AI.pdf)

## 1/22/26 Audit
Four smart contract audits were performed on the solidity codebase. An initial independent audit was conducted, followed by three major audits by Spearbit, Fuzzland, and Verilog. The scope was initially created based on a monorepo, then moved to a public repository at https://github.com/tenbinlabs/contracts.

[scope](audit/1_22_26_scope.pdf)
 
[0xleastwood](audit/1_22_26_0xleastwood.pdf)
 
[fuzzland](audit/1_22_26_fuzzland.pdf)
 
[spearbit](audit/1_22_26_spearbit.pdf)
 
[verilog](audit/1_22_26_verilog.pdf)

# Setup

Run commands from the repository root. Install [Foundry](https://getfoundry.sh/introduction/installation/), then select the version used by CI:

```sh
foundryup --install v1.8.3
forge --version
git submodule update --init --recursive
```

### Set up .env

```sh
cp .env.example .env
chmod 600 .env
```

Set `MAINNET_RPC_URL` and `SEPOLIA_RPC_URL` for deployment forks. Existing CCIP forks also require `RPC_URL_ARBITRUM_SEPOLIA`. Forge reads `.env` automatically; variables expanded by your shell in the commands below must also be exported in that shell. `ETHERSCAN_API_KEY` is needed for explorer verification. The example includes legacy mint-script variables; deployment commands below use an encrypted keystore.

### Build

```sh
forge build
FOUNDRY_PROFILE=production forge build
```

Both production and development profiles resolve `deploy-target/` to this repository's contracts and use via-IR with 18,888 optimizer runs. They exclude tests. The default profile builds the test suite; `production-test` uses production compiler settings with tests included. The network comes from the RPC endpoint, and mock integrations are selected by the script argument, not the profile.

### Testing

These commands match the CI test lanes:

```sh
# Local unit, integration, fuzz, and invariant tests
forge test --no-match-path 'test/fork/**'

# Fork regressions (requires the RPC variables above)
forge test --match-path 'test/fork/**' --no-match-path 'test/fork/monitoring/**'

# Live deployment checks (requires MAINNET_RPC_URL)
forge test --match-path 'test/fork/monitoring/**'
```

`forge test` runs all three groups. Live monitoring reads head minus ten blocks; deployment regressions use pinned blocks except the explicitly live mock-deployment checks. CI warns when RPC credentials are absent and skips the corresponding fork or monitoring step; a skipped step is not validation of that group.

Additional commands:

```sh
forge test --match-path 'test/invariant/**'
FOUNDRY_PROFILE=coverage forge coverage
FOUNDRY_PROFILE=coverage forge coverage --report debug
forge test --gas-report
forge doc
```

`test/echidna/**` contains separate mainnet fork-mode harnesses excluded from the default profile. Use `FOUNDRY_PROFILE=echidna` for those harnesses.

### Pinning

The `pinning` job in `.github/workflows/contracts.yaml`, part of `ci-success`, fails on an action not pinned by commit SHA, a container image without a digest, a Dockerfile `FROM` without `@sha256`, a `*-latest` runner label, a release download without a `sha256sum -c` check, a download piped into a shell, or an inline `zizmor: ignore`. It runs zizmor, installed by hash from `.github/zizmor/requirements.txt`, and `scripts/check-pinning.sh`, whose fixture test is `scripts/check-pinning-test.sh`. A zizmor exception is an entry in `.github/zizmor.yml`, and a script exception is a line in `.github/pinning-exceptions.txt`. Each carries `expires YYYY-MM-DD`, which the same job checks.

### Updating dependencies

Restore the committed dependency revisions with `git submodule update --init --recursive`. When intentionally updating a dependency, commit its gitlink and matching `foundry.lock` entry together. `repair_foundry_deps.sh` is a legacy destructive recovery script with a hard-coded dependency list that does not cover the current pins; use the submodule command for this checkout.

### Fuzzing

Install echidna: https://github.com/crytic/echidna?tab=readme-ov-file#installation

Run the five local invariant harnesses listed in `echidna.sh`: `bash echidna.sh`

For one local harness: `echidna test/invariant/AssetTokenInvariant.t.sol --contract AssetTokenInvariantTest --config echidna.yaml`. The separate fork harnesses under `test/echidna/` require their mainnet RPC/fork configuration and are not run by `echidna.sh`.

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

[deployments.json](deployments.json) records core deployments; [cross-chain-deployments.json](cross-chain-deployments.json) records cross-chain deployments. The records and config snapshot originate from monorepo commit `c3bd9d6b646104e1704e590d85c26f839c26bb1e`.

Asset configs live under `config/<network>/<asset>/`. Vault TOMLs in `vaults/` declare `adapters`, a member named by `liquidity_adapter`, and `markets` for MARKET adapters. Parameter files live in sibling `adapters/` and `markets/` directories. Local fixtures use `config/local/tgld/`.

Choose the entrypoint for the operation:

| Operation | Entrypoint |
| --- | --- |
| Fresh asset, backed staking seed, vault, and new Morpho market | `DeployNewAsset.s.sol`, `run(string,string,bool)` |
| Core and vault using configured integrations | `Deploy.s.sol`, `run(string,string,bool)` |
| Core against the asset config's existing nonzero `vault` | `Deploy.s.sol`, `runCoreOnly(string,bool)` |
| Vault for an asset | `Deploy.s.sol`, `runVaultOnly(string,string)` |
| Individual adapter deployment or existing-adapter validation | `DeployMorphoAdapter.s.sol`, `run(string)` or `runExisting(string,string,address)` |

For a fresh asset such as tPYR, follow [the new-asset deployment runbook](docs/new-asset-deployment.md). It covers input preparation, pricing, the backed staking seed, permission restoration, simulation, broadcasting, verification, and recovery. Recorded deployment configs must be copied and prepared before reuse as fresh deployment inputs.

`Deploy.s.sol` writes `contracts.json` or `vault.json` under `broadcast/Deploy.s.sol/<chain-id>/`. `DeployNewAsset.s.sol` writes artifacts under `broadcast/DeployNewAsset.s.sol/<chain-id>/<asset-address>/artifacts/`. Keep confirmed execution records under `operations/<operation-name>/execution/`; leave simulations and intermediate files in `broadcast/`.

Cross-chain configs are published alongside their deployment records. Additional CCIP deployment/configuration scripts and tests are tracked in [ENG-3658](https://linear.app/tenbin/issue/ENG-3658).

## Set up a keystore for running scripts

Import the deployer interactively and export the account name and its matching address:

```sh
cast wallet import deployer --interactive
export BROADCASTER_ACCOUNT=deployer
export BROADCASTER_ADDRESS=0xYourDeployerAddress
```

`BaseScript` reads `BROADCASTER_ADDRESS` to choose its broadcaster. Pass both `--account "$BROADCASTER_ACCOUNT"` and `--sender "$BROADCASTER_ADDRESS"` so the loaded signer matches it. The new-asset flow needs that account even during simulation to sign its staking-seed order. Never use the public test mnemonic on a live network.

## Deploy locally

Use a local test mnemonic in both Anvil and the script. In a dedicated local terminal:

```sh
export MNEMONIC='ten ten ten ten ten ten ten ten ten ten ten test'
export BROADCASTER_ADDRESS=0x0000000000000000000000000000000000000000
anvil --mnemonic "$MNEMONIC"
```

In another terminal with those same exports, deploy using the local fixtures:

```sh
FOUNDRY_PROFILE=development forge script script/Deploy.s.sol:Deploy \
  --sig 'run(string,string,bool)' \
  config/local/tgld/tgld_local.toml \
  config/local/tgld/vaults/tgld_local_vault.toml true \
  --rpc-url http://127.0.0.1:8545 --broadcast
```

A zero broadcaster selects the script's mnemonic-derived test account. Keep these exports confined to local testing.

## Simulate on Sepolia or mainnet

Export `ASSET_CONFIG` and `VAULT_CONFIG` as the explicit paths to the reviewed asset and vault TOMLs. The following examples use the keystore setup above and simulate without broadcasting.

For a Sepolia core and vault using mock integrations:

```sh
FOUNDRY_PROFILE=development forge script script/Deploy.s.sol:Deploy \
  --sig 'run(string,string,bool)' "$ASSET_CONFIG" "$VAULT_CONFIG" true \
  --rpc-url "$SEPOLIA_RPC_URL" --account "$BROADCASTER_ACCOUNT" \
  --sender "$BROADCASTER_ADDRESS" --slow
```

For a Sepolia vault only, supply both config paths:

```sh
FOUNDRY_PROFILE=development forge script script/Deploy.s.sol:Deploy \
  --sig 'runVaultOnly(string,string)' "$ASSET_CONFIG" "$VAULT_CONFIG" \
  --rpc-url "$SEPOLIA_RPC_URL" --account "$BROADCASTER_ACCOUNT" \
  --sender "$BROADCASTER_ADDRESS" --slow
```

For mainnet core contracts against an existing vault:

```sh
FOUNDRY_PROFILE=production forge script script/Deploy.s.sol:Deploy \
  --sig 'runCoreOnly(string,bool)' "$ASSET_CONFIG" false \
  --rpc-url "$MAINNET_RPC_URL" --account "$BROADCASTER_ACCOUNT" \
  --sender "$BROADCASTER_ADDRESS" --slow
```

Mainnet rejects mock mode. After reviewing the simulation and approving the specific operation, add `--broadcast`; explorer verification uses `--verify --verifier etherscan --etherscan-api-key "$ETHERSCAN_API_KEY"`. Fresh-asset deployments use `DeployNewAsset.s.sol` with the production profile on both networks; follow its runbook for the Sepolia `--skip-simulation` broadcast procedure and interrupted-run recovery.

## Minting tokens on testnet

`script/MintTestnet.s.sol` is a legacy fixture tied to hard-coded controller, asset, collateral, payer, recipient, and amount values. Environment variables named after those addresses do not override the constants. Before using it, reconcile those constants with the intended Sepolia deployment, ensure the payer has collateral and has approved the controller, and check the signer's permissions.

This script reads `MINTER_ADDRESS` for its broadcaster and `SIGNER_KEY` to sign the order; the signer must match the hard-coded payer. It has not been migrated to the deployment scripts' keystore flow and is not a generic mint command. Do not use it on mainnet.

## Creating a Safe batch to restrict addresses

Set `TARGET_CONTRACT`, `RESTRICTED_STATUS` (`true` or `false`), `CSV_ADDRESSES` (comma-separated addresses), and `CONTEXT` in the shell, then generate the batch:

```sh
forge script script/BuildSafeBatch.s.sol:BuildSafeBatch \
  --sig 'run(address,bool,string,string)' \
  "$TARGET_CONTRACT" "$RESTRICTED_STATUS" "$CSV_ADDRESSES" "$CONTEXT"
```

The script prints Transaction Builder JSON for Ethereum mainnet (`chainId: "1"`) without broadcasting. Save the JSON under `operations/<operation-name>/`, review it, and import it into Safe Transaction Builder. The executing Safe must hold `RESTRICTER_ROLE` on the target contract.


# Architecture

# Overview

Tenbin is an asset token issuance platform with the goal of creating liquid, composable financial assets. Assets in the Tenbin protocol are backed by two positions: off-chain futures contracts and on-chain collateral. The off-chain hedging system maintains a delta one exposure of an underlying asset. The on-chain collateral is used to earn low-risk yield. So long as the on-chain yield equals or exceeds the off-chain funding costs, the protocol is able to peg Tenbin assets to the spot price of the real asset.

Each asset in the Tenbin protocol has a set of contracts unique to that asset. Key contracts include the AssetToken, Controller, StakedAsset, and CollateralManager. This document is an outline of the smart contract system used to facilitate mints, redemptions, staking, and on-chain collateral management.

# AssetToken

An asset token represents an asset in the Tenbin protocol. The AssetToken contract is an immutable, non-upgradeable ERC20 token with an extension to allow minting and burning. There is an `owner` and `minter` role. The owner is a multisig that can set the minter account, and the minter can mint new tokens. In all cases, the minter will be set as the Controller contract.

# Controller

The controller contract is responsible for minting and redeeming assets. Mint and redemptions are encoded as an Order. Orders are signed by KYC-approved signers and specify order details such as collateral amount, asset amount, and deadline. All orders must include a context signed by a minter key stored in a hardware security module and controlled by the Tenbin backend. Orders are executed either by a minter key or an approved signer. Orders are executed atomically: collateral is transferred and tokens are minted/burned in a single transaction. 

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
        address order_token;        // Specify AssetToken or StakedAsset
        uint256 asset_amount;       // Amount of asset tokens
    }
```

### Order Lifecycle

1. Order signer goes through KYC and is added to the allowed signers list.
2. An order signer submits an `order` and signed order `signature` to the back end
3. The back end processes the order and provides a `context` and signed context `approval`
4. Token are transferred accordingly and payer nonce is marked as used.

### Allowed Signers

The controller keeps track of what accounts are allowed to sign orders. An account must be on the allowed signer list in order to submit a successful order. Note that the minter account can never modify the contents of an order, and that an order can only ever be executed once by specifying a unique nonce for every order. The controller supports both EIP712 and EIP1271 signatures.

### Approved Recipients

Signers can set which accounts can receive tokens when an order is executed. This control prevents signers from sending tokens to an incorrect account. Signers can manage recipients on-chain by calling `setRecipientStatus()`. By default, a signer is approved to be a recipient for its own orders.

### Delegate Signers

Any account can delegate a signer to sign orders on its behalf. During execution of an order, the payer is checked against the delegates for a signer. This allows for EOAs or smart contracts to let a signer sign an order where the delegate pays for the order. An account can add a delegate signer by calling `setDelegateStatus()`.

### User Executed Orders

As long as an order is valid with a valid signature, context, and approval, any account can execute an order. All orders need an approval signed by the MINTER_ROLE to be valid. This design allows for users to execute their own orders rather then relying on a dedicated account to execute orders.

### Collateral Ratio

The controller has a collateral ratio which specifies the percentage of collateral which is sent to `custodian` and `manager`. The custodian amount represents the portion of collateral which is moved off-chain to fund futures hedge positions. The manager amount represents the portion of collateral designated to earn on-chain yield. When a mint occurs, the total collateral amount is split according to the`ratio` value set in the Controller.

### Custodian Module

The custodian module receives collateral during a mint order. Custodians are added to a list of approved accounts. Only approved custodians can receive collateral from a mint event. A keeper role is assigned to interact with the custodian module and transfer collateral accordingly.

### Oracle Adapter

The controller has a configurable oracle adapter which can provide a price when executing orders. When enabled, the oracle price acts as a backstop to prevent order pricing from exceeding a threshold. The oracle DOES NOT determine the price of assets, rather it acts as a security measure to prevent minting and redeeming assets at a price off-peg. For example, with the oracle configured it is impossible to mint new assets with a price of $0.

### On Demand Curation

The `Context` struct allows passing in a flag to indicate an order should be curated as part of the transaction. When performing an on demand curation, the CollateralManager `withdraw()` or `deposit()` function is called before a redemption or after a mint, respectively. An additional `share_price` is passed along with curated orders to act as a slippage guard when interacting with the CollateralManager vaults.

### Mint and Redemption Limits

Mint and redemption limits are configurable per block. If set to type(uint).max, limits are not enforced.

### Staked Asset Redemption

Staked assets can be redeemed directly through the controller by specifying the staked asset address as `order_token` in the Order struct. Redeeming staked assets also requires the payer approves the controller to spend staked assets on its behalf. During staked asset redemption, assets are instantly unstaked by the controller and pricing is determined by the back end pricing engine.

**Note: the asset_amount specified in order.asset_amount refers to the asset token amount burned, and is used for pricing. The actual number of shares redeemed is determined by the staking contract via `previewWithdraw(asset_amount)`**

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

The two main functions provided by the collateral manager are `deposit()`and `withdraw()`. Each collateral has a unique vault dedicated to earning yield for that collateral type. Depositing will deposit collateral into the vault in exchange for vault shares. Withdrawing will redeem vault shares in exchange for the underlying collateral. Deposit and withdraw functions include a share price which acts as a slippage guard when performing curations.

### Liquidity Management

The most important role of the manager is to ensure there is sufficient liquidity to redeem assets. Collateral that is in the collateral manager is approved to be transferred by the controller when a redemption order is filled. If there is insufficient collateral in the manager, a redemption is not possible.

In order for Tenbin to optimize yield versus liquidity, a curator role is assigned by the manager to perform deposits and withdrawals. By using a multicall contract, it is possible to bundle deposits and withdrawals with mints and redemptions atomically. For example: `[mint(), deposit()]` or `[withdraw(), redeem()]`.

Additionally, the Controller contract has the ability of performing curations as part of a mint or redemption. This allows for users to execute their own orders where the controller performs curation actions. This allows for the maximum amount of yield to be earned by the protocol while maintaining flexibility for users. Curation options for controller-curated orders are limited to `deposit()` and `withdraw()`.

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

A vesting period is used for rewards in order to prevent abuse of the staking contract. The vesting period encourages depositors to remain staked through the vesting period. This mechanism prevents negative MEV actions such as sandwiching reward transactions. Once the vesting period is set, it cannot be set below MIN_VESTING_PERIOD.

Vesting spreads out rewards over a longer period of time in order to reduce reward volatility. For some assets, minting reward tokens is not always possible due to futures off-market hours. Using a longer vesting period allows stakers to earn a consistent yield despite possibly inconsistent reward schedules and amounts. 

**note** Rewarding the contract excessively and with low reward amounts can cause vesting to reset and extend currently vesting rewards. Rewards should be distributed infrequently (once per 1-3 days) and in consistent amounts to ensure smooth vesting.

### Cooldown

A cooldown period is present in the staking contract to encourage assets to remain staked and allow response time for liquidity management. When a staker calls the `cooldownShares()` or `cooldownAssets()` function, staked tokens are burned and transferred to the AssetSilo contract. An account can have multiple cooldowns at once as determined by a unique set of IDs per account. After the cooldown end time has passed, a user can call `unstake(id)` to withdraw the underlying asset tokens.

In order to withdraw tokens, a staker needs to call `cooldownShares()` or `cooldownAssets()` and wait until the cooldown period has passed to withdraw their stake. A cooldown can be cancelled by calling `cancelCooldown(id)`. When cancelling a cooldown, new shares are minted via the AssetSilo contract and transferred to the account which cancelled the cooldown.

### Instant Unstaking

Instant unstaking is possible via a privileged role. Typically, the Controller is allowed to instant unstake when executing redemptions for staked assets. There is an instantUnstakeCap which sets a limit on the total amount that can be instantly unstaked. The instant unstake function takes in an `asset` amount and calculates how many shares to redeem via `previewWithdraw(assets)`.

### Restricted Registry

Due to legal restrictions, yield cannot be paid to stakers without regulatory compliance. For this reason, a restricted registry is present in the staking contract. Accounts added to this registry cannot stake, unstake, or transfer staked tokens. If an account is restricted, the contract default admin can burn the account’s staking tokens and withdraw the underlying assets.

### Upgradeability 

The staking contract is a UUPS upgradeable smart contract. The intention of upgradeability is to support new staking models in the future. In the case the design is considered stable and immutability is desired, the upgrade feature can be permanently disabled.

## Security

### Bug Bounty

We maintain an active bug bounty program for responsible disclosure of
security vulnerabilities.

Please report vulnerabilities through our
[cantina.review/tenbin](https://cantina.xyz/bounties/0420bc1a-9177-4e4e-8da7-826d273e3d3e).

Do not disclose potential vulnerabilities publicly or open a GitHub issue
before they have been reviewed and resolved.
