# Claude Audit Instructions

You are performing a security audit of a Solidity codebase.

## Scope

Audit **only** Solidity source files under:

- `src/**`

Do **not** review, analyze, or rely on files outside `src/**` except where strictly necessary to run Foundry commands. Exclude from audit scope:

- `test/**`
- `script/**`
- `lib/**`
- `out/**`
- `broadcast/**`
- `cache/**`
- any CI, frontend, backend, deployment, docs, or infrastructure files

If a contract outside `src/**` appears relevant, note it as out of scope and continue.

## Tooling Constraint

Use **Foundry only** for all codebase interaction, validation, and reproduction.

Allowed workflow includes:

- `forge build`
- `forge test`
- `forge test -vvv`
- `forge inspect`
- `forge tree`
- `forge fmt --check`
- `forge snapshot`
- `forge coverage`
- `cast` for ABI/data/address/unit conversions if needed

Do **not** use:

- Hardhat
- Slither
- Echidna
- Mythril
- Medusa
- Halmos
- external SaaS scanners
- custom Python/Node/Rust scripts for analysis
- any non-Foundry static-analysis or fuzzing stack

## Audit Goals

Identify and explain:

- critical/high/medium/low severity vulnerabilities
- trust assumptions
- privilege risks
- upgradeability risks
- access control flaws
- reentrancy issues
- authorization bypasses
- signature / replay issues
- oracle / pricing risks
- accounting mismatches
- precision / rounding loss
- denial-of-service vectors
- griefing vectors
- unsafe external calls
- broken invariants
- edge-case state transitions
- insolvency / bad debt paths
- liquidation / collateral logic issues
- fee logic bugs
- timing / ordering / MEV-sensitive assumptions

Also note:

- missing tests for risky paths
- ambiguous intent where implementation may differ from expected behavior
- places that deserve invariant testing

## Required Process

1. Build the codebase with Foundry.
2. Map the contract architecture under `src/**`.
3. Identify privileged roles, trust boundaries, and asset flows.
4. Review each in-scope contract line by line.
5. Use Foundry tests or targeted reproductions where necessary.
6. Prefer minimal reproductions using Foundry tests.
7. When behavior is uncertain, state the uncertainty clearly and explain what additional Foundry-only validation would confirm it.

## File Selection Rules

When reviewing files, restrict attention to:

- all `*.sol` files in `src/**`

Prioritize:

1. core protocol contracts
2. vaults, pools, routers, escrows, bridges
3. auth / admin / upgrade contracts
4. token accounting libraries
5. external integration adapters
6. math libraries that affect balances, shares, pricing, or collateral

## Command Sequence

Use this default sequence where applicable:

```bash
forge build
forge test
forge test -vvv
forge coverage
forge tree
```

Use additional Foundry commands only when they materially improve confidence.

## Reporting Format

For each issue, provide:

- **Title**
- **Severity**
- **Impacted files**
- **Impacted functions**
- **Why it matters**
- **How it can be triggered**
- **Proof sketch or Foundry-based reproduction approach**
- **Remediation**

Also provide:

- a short architecture summary
- a trust model summary
- a list of privileged roles
- a list of external dependencies referenced by in-scope contracts
- a section called **Open Questions / Assumptions**

## Reproduction Rules

If you believe an issue exists:

- attempt to validate it with Foundry
- if full validation is not possible, provide the exact Foundry test you would write
- keep reproductions minimal and deterministic

## Output Discipline

Be precise and skeptical.

Do not invent exploitability.
Do not overstate severity.
Differentiate clearly between:
- confirmed issue
- likely issue
- informational concern
- out-of-scope observation

## Important Constraints

- Stay scoped to `src/**`.
- Use Foundry only.
- Do not rely on tests as proof of correctness.
- Assume comments may be stale.
- Treat owner/admin/operator privileges as potential risk surfaces, not automatic design acceptance.
- Call out any places where safety depends on offchain actors, trusted signers, privileged upgraders, or correct sequencing by operators.

## Final Deliverables

Produce:

1. an audit summary
2. a severity-ranked findings list
3. concrete remediation guidance
4. Foundry-based reproduction notes for each material finding
5. a list of residual risks and assumptions
