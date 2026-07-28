# contracts

## Description

Tenbin's smart contracts — an asset-tokenization protocol using futures to back highly liquid assets
(tGLD/stGLD, tBRL/stBRL, tMXN/stMXN). Foundry project, continuously audited (Spearbit, Zellic,
Fuzzland). See `README.md` for mainnet addresses and audit history.

## Structure

- **src/** — protocol contracts: `AssetToken.sol`, `StakedAsset.sol`, `AssetSilo.sol`, `Controller.sol`, `CollateralManager.sol`, `CustodianModule.sol`, `RevenueModule.sol`, `SwapModule.sol`, `MultiCall.sol`, plus `interface/`, `oracle/`, and `external/` (incl. `external/morpho/`: `GenericMorphoAdapter.sol` + `GenericMorphoAdapterFactory.sol`).
- **test/** — Foundry tests. **script/** — deploy / ops scripts. **out/**, **cache/** — Foundry build output (generated).
- **lib/** — dependencies as submodules (incl. upstream `tenbin-contracts/` — **exception repo, do not modify; see root index**).
- **audit/**, **certora/**, **echidna.yaml** + **echidna.sh**, **slither.config.json** — audit, formal verification, fuzzing, static analysis.
- **foundry.toml**, **remappings.txt**, **foundry.lock** — Foundry config. **deployments.json** — deployed addresses. **docs/**, **config/**.

## Globals

@../../AGENTS.md

<https://github.com/tenbinlabs/monorepo/blob/master/AGENTS.md>

## Customizations

### Build / test (Foundry)

- Build: `forge build`. Test: `forge test`. Fuzz: `./echidna.sh`. Static analysis: `slither .`.
- `test/echidna/**` holds Echidna fork-mode harnesses (live mainnet addresses, hevm cheatcodes). `[profile.default] skip` excludes them so `forge test` never collects their `invariant_*`; they are compiled and fuzzed only under `FOUNDRY_PROFILE=echidna`.
- Deploy development contracts with `FOUNDRY_PROFILE=development`; deploy pinned production contracts with `FOUNDRY_PROFILE=production`. Both use `script/Deploy.s.sol`.
- Restore / sync deps: `./sync_foundry_deps.sh` (repair: `./repair_foundry_deps.sh`).

### Where to make a change

- Protocol logic → `src/<Contract>.sol` (+ matching `interface/`), then add/extend `test/`.
- New deployment / address → `script/` + `deployments.json`.
- Generated `out/` and `cache/` are build artifacts — never hand-edit; do not modify `lib/` submodules.

Load the `smart-contract-implementation-solidity` skill (root index) before writing or auditing
Solidity. Touch contracts surgically — this code is audited and on mainnet.
