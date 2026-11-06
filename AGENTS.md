# contracts

## Description

Tenbin's smart contracts — an asset-tokenization protocol using futures to back highly liquid assets
(tGLD/stGLD, tBRL/stBRL, tMXN/stMXN, tPYR/stPYR). Foundry project, continuously audited (Spearbit, Zellic,
Fuzzland). See `README.md` for mainnet addresses and audit history.

## Structure

- **src/** — protocol contracts: `AssetToken.sol`, `StakedAsset.sol`, `AssetSilo.sol`, `Controller.sol`, `CollateralManager.sol`, `CustodianModule.sol`, `RevenueModule.sol`, `SwapModule.sol`, `MultiCall.sol`, plus `interface/`, `oracle/`, and `external/` (incl. `external/morpho/`: `GenericMorphoAdapter.sol` + `GenericMorphoAdapterFactory.sol`).
- **test/** — Foundry tests. **script/** — deploy / ops scripts. **out/**, **cache/** — Foundry build output (generated).
- **lib/** — pinned upstream dependencies, including Morpho oracle artifacts; do not edit dependency sources.
- **audit/**, **certora/**, **echidna.yaml** + **echidna.sh**, **slither.config.json** — audit, formal verification, fuzzing, static analysis.
- **foundry.toml**, **remappings.txt**, **foundry.lock** — Foundry config. **deployments.json** — core addresses. **cross-chain-deployments.json** — cross-chain addresses. **docs/**, **config/**.

## Globals

@../../AGENTS.md

<https://github.com/tenbinlabs/monorepo/blob/master/AGENTS.md>

## Customizations

### Build / test (Foundry)

- Foundry v1.8.3 matches CI. Build: `forge build`. Test: `forge test`. Fuzz: `./echidna.sh`. Static analysis: `slither .`.
- `test/echidna/**` holds Echidna fork-mode harnesses (live mainnet addresses, hevm cheatcodes). `[profile.default] skip` excludes them so `forge test` never collects their `invariant_*`; they are compiled and fuzzed only under `FOUNDRY_PROFILE=echidna`.
- Deploy development contracts with `FOUNDRY_PROFILE=development`; deploy production contracts with `FOUNDRY_PROFILE=production`. Both use `script/Deploy.s.sol` and resolve `deploy-target/` to this repository. Vault configs declare `adapters`, `liquidity_adapter`, and `markets`; sibling adapter/market TOMLs supply their parameters.
- `script/DeployNewAsset.s.sol` creates and seeds a new asset and vault; see `docs/new-asset-deployment.md`. It requires explicit asset/vault configs.
- `script/DeployMorphoAdapter.s.sol` deploys or validates individual adapters. New MARKET adapters require `run(string,string)` with explicit adapter and vault configs to print registration and cap payloads.
- Fork regressions pin blocks; live monitoring trails head by ten blocks.
- CCIP records/configs are published; additional scripts and tests are tracked by ENG-3658.
- Restore dependencies: `git submodule update --init --recursive`.

### Where to make a change

- Protocol logic → `src/<Contract>.sol` (+ matching `interface/`), then add/extend `test/`.
- New deployment / address → `script/` + `deployments.json`.
- Generated `out/` and `cache/` are build artifacts — never hand-edit; do not modify `lib/` submodules.

Load the `smart-contract-solidity-implementation` skill (root index) before writing or auditing
Solidity. Touch contracts surgically — this code is audited and on mainnet.
