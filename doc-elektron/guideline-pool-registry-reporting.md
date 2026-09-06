# Elektron Net - `elektron-net-stack` Pool Registry Reporting Guideline

- **Version:** 0.1 (planning, nothing implemented yet)
- **Date:** September 6, 2026
- **Audience:** `elektron-net-stack` maintainers, stack operators
- **Reference implementation:** `install-elektron-stack.sh` (config prompts and generated `.env` files), `elektron-stack.conf.example`
- **See also:** the identical-in-substance planning documents `doc-elektron/guideline-pool-registry-reporting.md` in `elektron-net-mempool`, `elektron-net-pool`, and `elektron-net-ppool` (this document only covers what the install script needs to wire, not the feature's own design, which those documents own)

- Never use the em dash character in this document or its follow-up code comments; use a hyphen and spaces instead, as done throughout.

---

## 1. What This Is

`elektron-net-mempool`, `elektron-net-pool`, and `elektron-net-ppool` are planning a free, network-wide, wallet-independent way to attribute self-reported pool blocks in the block explorer (replacing the reverted on-chain approach documented in each repo's own `fix-report-pool-identity-utxo-attestation.md`). It works by having pools and mempool explorer instances read two plain text lists from a new repository, `github.com/kutlusoy/elektron-net-registry` (not created yet), and report/verify found blocks over HTTP between themselves. See the sibling documents for the actual design; this document only tracks what this stack's install script needs to configure once that lands.

## 2. What Changes in This Repo

- A single new config value (name to be finalized with the other repos, e.g. `POOL_REGISTRY_URL`) needs to be threaded through to both the pool/ppool `.env` and the mempool `.env`, defaulting to the new registry repo once it exists.
- Add it to `CONFIG_VARS` in `install-elektron-stack.sh` (the existing whitelist of prompt/config-file-settable variables) and to `elektron-stack.conf.example`, following the same pattern as every other pass-through variable in that script (see e.g. `POOL_IDENTIFIER`/`POOL_URL` right next to where this would go).
- Likely no new prompt is needed if a single sensible default (the official registry repo) covers the vast majority of operators; a config-file override is enough for anyone running a private fork of the registry.
- README update once the feature lands, in the same section reverted by this stack's own `fix-report-pool-identity-utxo-attestation.md`-adjacent changes (the "Pool identity (dashboard only)" section), to describe the new, working cross-explorer attribution instead of just the off-chain dashboard display.

## 3. Open Questions

1. Final env var name, to be settled once the other three repos agree on their own config surface.
2. Whether this needs to be prompted interactively at all, or is a sensible-default-only, config-file-only setting (leaning toward the latter, following `MEMPOOL_POOLS_JSON_URL`'s own precedent of not being interactively prompted).

## 4. Checklist

- [ ] `elektron-net-registry` repository exists
- [ ] Config var name finalized with `elektron-net-mempool` / `elektron-net-pool` / `elektron-net-ppool`
- [ ] Wired into `CONFIG_VARS`, `elektron-stack.conf.example`, and the generated `.env` files for pool/ppool and mempool
- [ ] README updated
