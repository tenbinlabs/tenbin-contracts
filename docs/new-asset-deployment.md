# Deploy a new asset's contracts suite

Use `script/DeployNewAsset.s.sol:DeployNewAsset` to deploy a fresh core, vault,
configured adapters, and staking-token/USDC Morpho market. Complete the required
on-chain follow-ups before enabling user staking or market allocation. Backend
services, runtime manifests, ongoing trading funding, and user onboarding are
outside this procedure. Use `Deploy.s.sol` for partial deployments.

## Prepare the release and configuration

Run commands from the repository root. Use Foundry v1.8.3 and
`FOUNDRY_PROFILE=production` on both Sepolia and mainnet. Record the reviewed
public repository commit and pinned `lib/morpho-blue-oracles`
revisions in the operation record. Use the same reviewed source and dependencies
for the Sepolia rehearsal and mainnet deployment. The production profile selects
this repository's core contracts with production compiler settings; it does not select the network or mock mode.

This entrypoint supports Ethereum mainnet (1), Sepolia (11155111), and local
chains (31337). It requires 18-decimal asset and staking tokens, six-decimal USDC
collateral, and exactly one new staking-token/USDC market per fresh vault.

Prepare network-specific files under `config/<network>/<asset>/`. Existing
new-asset configs can provide the file layout, but review every copied value:
changing a symbol does not select pricing or convert amounts and limits.

| Configuration | Required preparation |
| --- | --- |
| Asset TOML | Set names, symbols, collateral, governance and operational roles, custodian, limits, and pricing. Set positive `staking_dead_deposit` in 18-decimal asset units, no greater than `mint_limit`. Set distinct, nonzero `yield_signer` and `leverage_signer` addresses. Leave `vault` zero for a fresh deployment. |
| `vaults/<vault>.toml` | Set ownership, allocator, curator, sentinel, collateral asset, dead deposit, rates, and timelocks. Set `is_new_asset_vault = true`; leave `manager` zero for deployment wiring. List `adapters`, a `liquidity_adapter` from that list, and exactly one entry in `markets`. |
| `adapters/<name>.toml` | Configure each adapter's type, target, and caps; include a MARKET adapter. Leave `parent` zero for the fresh vault. Select the desired allocation destinations rather than assuming a fixed adapter count. On testnets, zero target vaults select fresh mocks. |
| `markets/<name>.toml` | Configure the staking-token/USDC market name, IRM, LLTV, and caps. Leave `collateral_token` and `oracle` zero; the script fills them with the new staking token and oracle. |

The script rejects a populated asset `vault`, market `collateral_token`, or market
`oracle`. Recorded deployment configs cannot be reused as fresh deployment inputs.
Keep the reviewed input configuration with the operation record.

On mainnet, set the asset's `oracle` to its direct asset/USD Chainlink feed and
`oracle_staleness_threshold` to a positive number of seconds. The market's
`base_feed` must match that oracle; `quote_feed` is the USDC/USD feed. Both feeds
must have 8–18 decimals. Check the deployed factories, the factory's adaptive-curve
IRM, enabled Morpho IRM/LLTV, and positive prices on the intended chain.

On Sepolia/local chains, set `mock_oracle_price` to the intended USD price in
18-decimal units. It must be at least `1e10` to remain positive after conversion
to eight decimals, and no greater than the maximum signed 256-bit integer. Leave
market `base_feed` and `quote_feed` zero for fresh mocks. The core mock and market
base feed use the configured price; the quote mock starts at $1 per USDC. The
staking token's exchange rate remains live in the market oracle.

Follow the [keystore setup instructions](../README.md#set-up-a-keystore-for-running-scripts)
to import the deployer and export its account name and matching broadcaster address.

Verify configured signer addresses against their actual keys, including HSM key
versions where applicable. Provide `SEPOLIA_RPC_URL`, `MAINNET_RPC_URL`,
`ETHERSCAN_API_KEY`, and an encrypted Foundry keystore account named by
`BROADCASTER_ACCOUNT`. Export its matching `BROADCASTER_ADDRESS`; the script reads
that environment variable when choosing its broadcaster. Keep credentials out of
configuration records and execution artifacts.

Fund the broadcaster with gas and, on mainnet, the configured vault dead deposit
plus 1 USDC for the Morpho market's dead supply and the USDC backing the staking
seed. Seed collateral is `ceil(staking_dead_deposit * oracle_price / 1e30)` in
six-decimal USDC units, using the Controller's asset/USD pricing convention.
Testnet mock collateral and adapter targets are funded by the script.

The broadcaster's keystore must be loaded with `--account` even for simulation:
the script signs the seed mint order and its context approval with that account.
An unlocked RPC account alone is insufficient. The script temporarily authorizes
the broadcaster as a signer and minter, sends the seed's backing through the
Controller to the custodian module and collateral manager, and restores the
previous signer, recipient, and minter permissions. Seed backing held by the
manager is not automatically allocated to its vault.

Before deployment, obtain approval for scoped release checks: the production
build, production-test artifact builds, and new-asset integration and fork tests.
The relevant suites include `DeployNewAssetTest`, `DeployNewAssetGuardsTest`,
`DeployNewAssetPricingTest`, `DeployNewAssetForkTest`, and `DeployProductionForkTest`.
Record results against the reviewed source and dependencies in the operation record.

## Simulate, then broadcast

Set the following shell variables to the explicit TOML file paths prepared above:
`SEPOLIA_ASSET_CONFIG`, `SEPOLIA_VAULT_CONFIG`, `MAINNET_ASSET_CONFIG`, and
`MAINNET_VAULT_CONFIG`. No default configuration paths are accepted by this entrypoint.

Simulate Sepolia first:

```sh
FOUNDRY_PROFILE=production forge script script/DeployNewAsset.s.sol:DeployNewAsset \
  --sig 'run(string,string,bool)' "$SEPOLIA_ASSET_CONFIG" "$SEPOLIA_VAULT_CONFIG" true \
  --rpc-url "$SEPOLIA_RPC_URL" --account "$BROADCASTER_ACCOUNT" \
  --sender "$BROADCASTER_ADDRESS" --slow
```

Review the transaction list, gas, addresses, limits, owners, and signer mapping.
Confirm the RPC chain ID, factory code, market parameters, and oracle prices.
After separate approval for the Sepolia broadcast, rerun the command with
`--skip-simulation --broadcast --verify --verifier etherscan --etherscan-api-key "$ETHERSCAN_API_KEY"`,
keeping `--slow`. In Foundry v1.8.3, `--skip-simulation` skips the second-stage
on-chain simulation and estimates gas through RPC immediately before each
transaction, with the default 130% multiplier. The script still executes locally.
Use this for Sepolia broadcasts because local gas estimates can understate the
gas limit required by the node. Complete the normal simulation above first.

Complete Sepolia verification and all follow-ups before simulating mainnet:

```sh
FOUNDRY_PROFILE=production forge script script/DeployNewAsset.s.sol:DeployNewAsset \
  --sig 'run(string,string,bool)' "$MAINNET_ASSET_CONFIG" "$MAINNET_VAULT_CONFIG" false \
  --rpc-url "$MAINNET_RPC_URL" --account "$BROADCASTER_ACCOUNT" \
  --sender "$BROADCASTER_ADDRESS" --slow
```

Mainnet requires its own broadcast approval before adding
`--broadcast --verify --verifier etherscan --etherscan-api-key "$ETHERSCAN_API_KEY"`.
The boolean argument must be `false` on mainnet and `true`
on Sepolia/local chains; mock integrations are prohibited on mainnet.

The script creates the vault and core and seeds staking before creating the
staking-aware oracle and market. It mints the configured asset amount through
the Controller and locks the same number of staking shares for `0xdead` at the
initial 1:1 exchange rate. An exact token allowance bounds the staking mint;
a donation that raises its required assets makes that transaction revert.
It supplies 1 USDC to the market for `0xdead`, configures the adapters and caps,
and sets final timelocks and owners. Mainnet uses the existing Morpho oracle
factory; testnets deploy the pinned upstream oracle with mock feeds.

## Archive execution and complete on-chain setup

The script writes `contracts.json` and `onboarding.json` under
`broadcast/DeployNewAsset.s.sol/<chain-id>/<asset-address>/artifacts/`. Simulations
also write these files; their existence does not prove any transaction succeeded.
Foundry's transaction journal is under `broadcast/DeployNewAsset.s.sol/<chain-id>/`.

Immediately after each confirmed broadcast, archive its timestamped journal,
receipts, and both artifact files under
`operations/<operation-name>/execution/<chain>-<first-confirmed-block>/`, before
running another script or test. Use stable execution filenames, not
`run-latest.json`. Match each target to its creation receipt and deployed code.
Use the archived `onboarding.json` for the following separately authorized calls:

1. The recorded owner calls `acceptOwnership()` on the asset token. A Safe owner
   executes through its Safe; the broadcaster cannot accept on its behalf.
2. The configured `yield_signer` calls `setRecipientStatus(revenue_module, true)`
   on the Controller using its own signer. An admin cannot authorize that
   signer's recipient on its behalf.
3. Verify both configured signers are authorized and that
   `recipients(yield_signer, revenue_module)` and
   `delegates(revenue_module, yield_signer)` are true. Deployment establishes the
   revenue delegation and revokes the temporary broadcaster admin grant it added.
   Signer registration authorizes the leverage signer's own address as a recipient.
4. Verify the deployment's Controller mint and staking mint receipts before
   allowing user staking or allocating vault funds. Match the dead shares and
   backing amount to `staking_dead_deposit` and `staking_seed_collateral` in
   `onboarding.json`, check the initial 1:1 exchange rate, and verify temporary
   seed permissions and allowances were removed. Do not repeat the deposit.

Verify operational roles against the reviewed configuration and preserve the
intended multisig grants. Yield and leverage signer registration does not itself
confer admin or minter authority. Before a revenue mint, the revenue keeper must
approve the required collateral through `RevenueModule.setControllerApproval`;
deployment does not establish an unlimited collateral allowance.

## Etherscan source verification

The broadcast flags above submit source verification to Etherscan. Check each
deployed address on `sepolia.etherscan.io` (chain ID `11155111`) or `etherscan.io`
(chain ID `1`), including proxy implementations, factory-created contracts,
oracle, wrapper, and testnet mocks. A successful broadcast does not prove that
every verification submission succeeded.

For an unverified contract, run the following from the repository root at the
deployment's recorded source commit and dependency revisions. Set `CHAIN_ID`,
`CONTRACT_ADDRESS`, `CONTRACT_ID` (`path/to/source.sol:ContractName`), and
`CONSTRUCTOR_ARGS` to the deployed contract's ABI-encoded constructor arguments
(`0x` for no arguments), using the archived deployment and build artifacts:

```sh
FOUNDRY_PROFILE=production forge verify-contract \
  "$CONTRACT_ADDRESS" "$CONTRACT_ID" \
  --chain "$CHAIN_ID" --constructor-args "$CONSTRUCTOR_ARGS" \
  --verifier etherscan --etherscan-api-key "$ETHERSCAN_API_KEY" --watch
```

Use the exact source and compiler settings used for deployment, including pinned
dependency sources for release contracts. This command submits verification
without a signing account or an on-chain transaction; do not redeploy to retry
verification. Record successful explorer links in the execution archive.
See Foundry's [verification reference](https://getfoundry.sh/forge/reference/verify-contract/).

## Verify and record completion

- Check every deployment and follow-up receipt succeeded on the intended chain;
  wait for finality before recording the completed operation.
- Verify token names, proxy implementations, core references, vault/gate manager,
  every configured adapter, liquidity adapter, caps, market parameters, oracle
  feeds and positive prices, roles, and timelocks. Check removal of temporary
  broadcaster roles, accepted token ownership, yield recipient authorization,
  Morpho dead supply, and the recorded dead stake before enabling market allocation.
- Complete [Etherscan source verification](#etherscan-source-verification), including proxies, oracle, wrapper,
  and testnet mocks. Check factory-created contracts and compiled artifacts
  individually; top-level command success does not establish their verification.
- Append follow-up receipts to the archived execution. Record chain ID, reviewed
  source commit, dependency revisions, and transaction hashes. Review records for
  credentials before committing; leave simulations and intermediate output in
  ignored `broadcast/` directories.
- Replace simulated core and vault `deployment_block` values in the archived
  manifest with actual creation blocks. Merge only the verified new asset's entry
  for that chain into `deployments.json`, preserving other assets and global records.
- Update the asset TOML's `vault`, vault TOML's `manager`, adapter TOMLs' `parent`,
  and market TOML's `collateral_token` and `oracle` with confirmed addresses. For
  testnets, also record mock feed addresses and deployed mock target vaults.
  Preserve display names and adapter ordering.
- After confirmed deployment, set `is_new_adapter = false` in each deployed
  adapter's TOML and `is_new_asset_vault = false` in the deployed vault's TOML.
  Keep both flags `true` in fresh deployment templates.
- Reconcile the committed manifest and TOMLs against final on-chain reads. Backend
  runtime `contracts.json` files are outside this operation.

## Recover interrupted execution

Archive the original timestamped journal, configuration, receipts, and generated
artifacts before another run overwrites them. Do not start a fresh run without
reconciling every landed transaction: salts and deployed contracts may already
exist. Use Foundry's `--resume` with the original entrypoint, chain, sender, and
journal only when the next transaction's nonce matches the broadcaster's current
nonce and subsequent nonces are consecutive, after approval for the remaining
broadcast. A mined failed transaction consumes its nonce; unchanged `--resume`
cannot retry that nonce.
Uncertain configuration or journal provenance requires reconciliation before
continuing; changing salts is not recovery.

For a Sepolia failure deploying the first mock adapter vault, a fresh run is
permitted only after confirming that the initial mock-token mint was the only
successful transaction, all planned creation addresses (including factory-created
contracts) have no code, and the broadcaster has no pending transactions. Check
the failed CREATE2 target's code and nonce at the parent block to rule out an
address collision, then compare the saved gas limit with RPC estimation and a
historical `eth_call` at a higher limit. If the higher-limit call succeeds,
regenerate and review the full deployment from the current nonce without
`--resume`, then obtain approval to broadcast with `--slow --skip-simulation`.
This repeats the test-token mint and refreshes addresses and seed signatures.
If any deployment contract already exists, prepare a reconciled remaining
transaction plan instead of restarting the full deployment.

The seed order expires one hour after simulation. If execution stops before
the seed mint and that order expires, reconcile the journal and prepare a newly
signed seed transaction; `--resume` cannot renew an expired signature. Until
the cleanup transactions succeed, temporary seed permissions may remain active.

Oracle-factory and Morpho market creation are permissionless. Another transaction
can create the same instance first, causing a planned creation to revert after
earlier deployment transactions have landed. A CREATE2 collision or
`MarketAlreadyCreated` requires receipt and parameter reconciliation. Do not
blindly resume that transaction; review and approve a corrected remaining
transaction plan. The script does not automatically recover from this case.
