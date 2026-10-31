# Continuous integration

[CI](../../.github/workflows/ci.yml) runs on every push and pull request,
and can also be dispatched manually. It uses GitHub-hosted Ubuntu, the Lean
version in `lean-toolchain`, the Git revisions in `lake-manifest.json`,
checksum-verified solc 0.8.35, Foundry 1.8.1, and Python 3.14.
Actions are pinned to commit SHAs. Jobs have read-only repository access.

Every run executes these gates without case filters or skip flags:

- `lake build SolidCore SolidCoreWitness`: all core definitions, proofs,
  and every module under `SolidCore/Witness`, including witnesses that are
  absent from `SolidCore.lean`'s import list.
- `scripts/build_fast_runtime.sh`: build the source-attested native replay
  runtime. Stale binaries cannot silently test old semantics.
- `python3 scripts/run_fork_tests.py`: the dedicated fork fixture runs in
  Foundry and is imported from solc's AST for Lean assertions.
- `lake exe keccakParity` and `lake exe precompileParity`: pure/native
  cryptographic parity and known-answer controls.
- `python3 scripts/run_forge_interpreter_harness.py`: the entire manifest,
  including Forge tests, solc rejection checks, fresh AST import, and Lean
  assertions. CI uses two workers and a 900-second default per-case timeout;
  manifest-specific limits still apply.
- `python3 -m contest.run_samples`: adjudication samples, positive controls,
  and fault-injection tests of the divergence detectors.
- `python3 scripts/audit_solc_ast_frontend.py --solc "$SOLC"`: classification
  and rendering audit over every imported source in the replay corpus.
- `.venv/bin/python -m pytest tests`: harness cache/attestation safety,
  assembly-recognition boundaries, reject-gate behavior, and memoization
  checks against an independent enclosing-contract traversal.

The workflow retains test reports, Python coverage, and replay diagnostics
for seven days. Lean dependencies and successful library builds are cached;
the test commands still execute on cache hits.

## Fork feature coverage

- Existing fork witnesses cover bound methods on external results,
  discarded external returns and malformed answers, external tuple assignment,
  getters implementing sibling interfaces, internal calls in external targets,
  qualified constants, scoped struct ABI types, and adopted-world entry balances.
- The existing `closed-world-delegatecall` paired case checks delegatecall
  against ordinary call: storage ownership, address, balance, sender, value,
  return data, and call kinds.
- `src/ForkFeatures.sol`, `test/ForkFeatures.t.sol`, and `ForkFeatures.lean`
  cover storage-argument aliases, tuple argument hoisting, storage-pointer
  declarations, discarded internal calls, both forms of `abi.encodeCall`
  function pointers, and call-with-options receiver hoisting.
- The same fixture covers raw slot reads/writes, both storage-pointer
  assembly bindings, word-array reinterpretation, both revert-bubble spellings,
  and raw proxy return data and delegatecall storage.
- Reflective checks cover reentrancy through a scripted actor, recorded
  callers, deployed immutables, all four supported replay cheatcodes,
  call ordering, EOAs/value transfers, insufficient funds, and unknown targets.
- Creation checks cover constructor execution, subsequent calls to created
  code, value transfer, creation logging, constructor-revert rollback,
  and accepted/rejected `CREATE2` salts against a recorded hash/address.
- Python controls accept the supported proxy spellings and reject changed
  offsets; accept safe memory-array casts and reject observable source reuse;
  and verify raw-slot operand restrictions and `uint`/`uint256` equivalence.
- Foundry independently checks the signed-array and bytes-widening expectations
  used by the previously unbuilt storage witnesses.
- Full-corpus cases pin scalar RHS-before-index evaluation, literal shift and
  exponent widths, calldata return capture, and dirty fixed-bytes getters.

The responder's documented limits still apply: these checks do not establish
general multi-contract equivalence, static-call write protection, gas fidelity,
or creation without a recorded registry.

## Reproduce locally

Set `SOLC`, `FORGE`, and `LAKE` to the desired executables. `SOLC` must be
0.8.35. Disable Foundry dynamic test linking so `new` executes real creation
instead of a cheatcode that changes constructor-revert handling:

```sh
export SOLC=/path/to/solc-0.8.35
export FORGE=/path/to/forge
export LAKE=lake
export FOUNDRY_DYNAMIC_TEST_LINKING=false
export FOUNDRY_ISOLATE=false
python3 -m venv .venv
.venv/bin/pip install -r tests/ci/requirements.txt
.venv/bin/python -m pytest tests
lake build SolidCore SolidCoreWitness
scripts/build_fast_runtime.sh
python3 scripts/run_fork_tests.py
lake exe keccakParity
lake exe precompileParity
python3 scripts/run_forge_interpreter_harness.py --jobs 2 --timeout 900
python3 -m contest.run_samples
python3 scripts/audit_solc_ast_frontend.py --solc "$SOLC"
```
