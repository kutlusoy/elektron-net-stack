# Elektron Net - `elektron-net-stack` Pool Registry Reporting Guideline

- **Version:** 0.2 (implemented on `reporegistry`, pending review/merge and live testing before `main`)
- **Date:** September 6, 2026
- **Audience:** `elektron-net-stack` maintainers, stack operators
- **Reference implementation:** `install-elektron-stack.sh` (config prompts and generated `.env` files), `elektron-stack.conf.example`
- **See also:** the identical-in-substance planning documents `doc-elektron/guideline-pool-registry-reporting.md` in `elektron-net-mempool`, `elektron-net-pool`, and `elektron-net-ppool` (this document only covers what the install script needs to wire, not the feature's own design, which those documents own)

- Never use the em dash character in this document or its follow-up code comments; use a hyphen and spaces instead, as done throughout.

---

## 1. What This Is

`elektron-net-mempool`, `elektron-net-pool`, and `elektron-net-ppool` are planning a free, network-wide, wallet-independent way to attribute self-reported pool blocks in the block explorer (replacing the reverted on-chain approach documented in each repo's own `fix-report-pool-identity-utxo-attestation.md`). It works by having pools and mempool explorer instances read two plain text lists from a new repository, `github.com/kutlusoy/elektron-net-registry` (not created yet), and report/verify found blocks over HTTP between themselves. See the sibling documents for the actual design; this document only tracks what this stack's install script needs to configure once that lands.

## 2. What Changed in This Repo

- `MEMPOOL_REGISTRY_URL` (pool/ppool side) and `MEMPOOL_POOL_REGISTRY_URL` (mempool side) added as real shell-variable defaults, both defaulting to `https://raw.githubusercontent.com/kutlusoy/elektron-net-registry/main`, referenced via `${VAR}` (not hardcoded) in the generated `.env` heredocs for both pool types and for `elektron-net-mempool`.
- Both added to `CONFIG_VARS` in `install-elektron-stack.sh`, so either is overridable via `elektron-stack.conf` for anyone running a private fork of the registry.
- Not prompted interactively, following `MEMPOOL_POOLS_JSON_URL`'s own precedent - a sensible default covers the vast majority of operators.
- `elektron-stack.conf.example` and `README.md` updated with the new variables and a short pointer to each repo's own `doc-elektron/guideline-pool-registry-reporting.md`.

## 3. Checklist

- [x] `elektron-net-registry` repository exists
- [x] Config var names decided (`MEMPOOL_REGISTRY_URL` / `MEMPOOL_POOL_REGISTRY_URL`, matching each side's own env var naming)
- [x] Wired into `CONFIG_VARS`, `elektron-stack.conf.example`, and the generated `.env` files for pool/ppool and mempool
- [x] README updated
- [ ] Live-test on a real stack install once the other three repos' `reporegistry` branches are merged to `main`
