# solidity-lean — a machine-checked Solidity semantics (SolidCore)

**SolidCore** is an executable, machine-checked semantics of Solidity written in
[Lean 4](https://lean-lang.org/). It typechecks, lowers, and *runs* real
Solidity programs inside Lean, and its behavior is continuously
validated against the reference toolchain: **pinned `solc` 0.8.35 + the real
EVM** (via [Foundry](https://github.com/foundry-rs/foundry)).

The claim this repo makes is narrow and falsifiable: **for programs in scope,
the on-chain observable computed by the Lean semantics — return data,
revert/panic data, emitted events, final storage — is byte-identical to what
solc-compiled bytecode produces on the EVM.** When that claim fails, it's a
bug here, and we fix it at the root.

## ASSERT-KTH fork: changes

This fork lives at [ASSERT-KTH/solidity-lean](https://github.com/ASSERT-KTH/solidity-lean)
on the default branch **`assert`**. The list below covers the changes added on
top of upstream commit
[`5623941`](https://github.com/paradigmxyz/solidity-lean/commit/56239411a17669d1cb87394d73b861a91ddc2a47).
Merge-only commits and the duplicate storage-argument patch are consolidated
with the changes they incorporate.

### Multi-contract execution and replay

- Add the [closed-world reflective responder](SolidCore/Solidity/Reflective.lean):
  execute registered Solidity callees in Lean, share storage and balances through
  world adoption/snapshotting, recurse through nested calls and reentrancy with
  a depth bound, replay scripted actors, accept registered EOAs, and fail closed
  for unregistered targets. Export the responder from `SolidCore.lean`.
  ([`2ff9cea`](https://github.com/ASSERT-KTH/solidity-lean/commit/2ff9cea))
- Preserve recorded callers in actor child calls, including Foundry `vm.prank`;
  carry deployed immutable values for executed contracts and coerce them to
  their declared types. Include caller, selector, and depth in unregistered-call
  errors. ([`061e6f3`](https://github.com/ASSERT-KTH/solidity-lean/commit/061e6f3))
- Seed callee entry balances from the shared world, accounting for `msg.value`,
  so contracts retain their existing ETH when called.
  ([`605556a`](https://github.com/ASSERT-KTH/solidity-lean/commit/605556a))
- Replay actor calls to `vm.warp`, `vm.roll`, `vm.store`, and `vm.deal` as block
  environment, storage, and balance edits.
  ([`605556a`](https://github.com/ASSERT-KTH/solidity-lean/commit/605556a))
- Record calls in pre-order with caller, target, selector, success, and responder
  failure notes; expose logged execution through `runTopLog`.
  ([`605556a`](https://github.com/ASSERT-KTH/solidity-lean/commit/605556a))
- Fix external entry into an adopted world to use that world's self balance
  instead of a stale context seed, then credit `msg.value`; update the rollback
  theorem to use the same entry-state helper.
  ([`0aebd18`](https://github.com/ASSERT-KTH/solidity-lean/commit/0aebd18))
- Execute `DELEGATECALL` code in the delegating contract's storage, address, and
  balance while preserving its frame's `msg.sender` and `msg.value`; use the
  issuing account in scripts and logs, and expose call kinds through
  `runTopCursors` while retaining the `runTop` and `runTopLog` signatures.
  ([`fc59742`](https://github.com/ASSERT-KTH/solidity-lean/commit/fc59742))
- Execute contract creation from Lean-executed code using named registry
  templates and ordered recorded creator/address pairs: transfer value, run the
  constructor, install code, and make successful creations callable in the same
  run. A reverting constructor returns address zero; unsupported creation fails
  closed. ([`0e4d5ab`](https://github.com/ASSERT-KTH/solidity-lean/commit/0e4d5ab))
- Include contract creation frames in the call log.
  ([`607ef6b`](https://github.com/ASSERT-KTH/solidity-lean/commit/607ef6b))
- Check recorded `CREATE2` addresses against the creator, the salt computed in
  this run, and the recorded init-code hash.
  ([`5faa05b`](https://github.com/ASSERT-KTH/solidity-lean/commit/5faa05b))

### Recognized assembly and core semantics

- Add `Stmt.forwardDelegatecall` and `Result.exited` for whole-frame termination
  with raw return data, including propagation out of internal calls, raw revert
  data on failure, verbatim ABI output, and corresponding fuel-monotonicity
  proof cases. ([`6db0408`](https://github.com/ASSERT-KTH/solidity-lean/commit/6db0408))
- Recognize canonical proxy forwarding assembly from solc's structured Yul AST:
  calldata copy, `delegatecall`, returndata copy, then raw revert or return.
  Accept the supported `switch`, `if iszero`, and `if eq` spellings with an
  address-typed local/parameter target; typecheck and lower the recognized marker.
  ([`45f7b4`](https://github.com/ASSERT-KTH/solidity-lean/commit/45f7b4))
- Exempt recognized proxy forwarding assembly from the reject gate's `X-ASM`
  classification. ([`dc98e1b`](https://github.com/ASSERT-KTH/solidity-lean/commit/dc98e1b))
- Recognize `d := sload(s)` and `sstore(s, v)` for supported word-width locals,
  and lower them to raw storage-slot reads and writes.
  ([`38a380d`](https://github.com/ASSERT-KTH/solidity-lean/commit/38a380d))
- Recognize memory-bytes revert bubbling via
  `let n := mload(b); revert(add(32, b), n)` and lower it to raw revert bytes.
  ([`38a380d`](https://github.com/ASSERT-KTH/solidity-lean/commit/38a380d))
- Also recognize the direct rethrow spelling `revert(add(b, 32), mload(b))`.
  ([`8f9c7a7`](https://github.com/ASSERT-KTH/solidity-lean/commit/8f9c7a7))
- Recognize the `EnumerableSet.values` memory-array reinterpretation `d := s`
  between one-dimensional dynamic arrays of `address`, `uint256`, or `bytes32`
  when the source is not subsequently read; copy words with destination-type
  cleanup. ([`d600148`](https://github.com/ASSERT-KTH/solidity-lean/commit/d600148))
- Recognize StorageSlot-style struct pointers `r.slot := slot` and
  `r.slot := p.slot`; bind/rebind storage references using the destination struct
  layout and count these bindings as definite assignments in pointer-flow checks.
  ([`8878956`](https://github.com/ASSERT-KTH/solidity-lean/commit/8878956))

### Solidity frontend, ABI, and evaluation order

- Resolve `using` library methods on external-call results such as
  `IERC20(t).balanceOf(x).sub(r)` using the callee's declared return type.
  ([`472383b`](https://github.com/ASSERT-KTH/solidity-lean/commit/472383b))
- Hoist a call-bearing member receiver/target before the arguments, including
  external-call results and `I(pf(a)).get()`; classify the rewritten call with
  its temporary's type. ([`472383b`](https://github.com/ASSERT-KTH/solidity-lean/commit/472383b))
- Bind and decode discarded high-level external-call results, including calls
  with options and multiple return values, so malformed return data still reverts.
  ([`472383b`](https://github.com/ASSERT-KTH/solidity-lean/commit/472383b))
- Lower tuple assignments from external calls, including omitted components
  such as `(r0, r1, ) = IP(p).getReserves()`, through decoded temporaries.
  ([`472383b`](https://github.com/ASSERT-KTH/solidity-lean/commit/472383b))
- Accept a public state-variable getter implementing an interface function
  reached through sibling inheritance paths, while retaining unrelated-name
  clash checks. ([`472383b`](https://github.com/ASSERT-KTH/solidity-lean/commit/472383b))
- Treat qualified constants such as `D.ONE` as values when resolving bound
  library calls like `D.ONE.sub(k)`.
  ([`472383b`](https://github.com/ASSERT-KTH/solidity-lean/commit/472383b))
- Resolve unqualified sibling types in contract/library-scoped struct fields
  when computing ABI types, including enum fields and array element types.
  ([`472383b`](https://github.com/ASSERT-KTH/solidity-lean/commit/472383b))
- Materialize arguments bound to `storage` parameters as storage aliases rather
  than memory copies when hoisting later argument calls, preserving mutations
  such as those in `f(o, g())`.
  ([`41f516f`](https://github.com/ASSERT-KTH/solidity-lean/commit/41f516f), equivalent patch [`706abda`](https://github.com/ASSERT-KTH/solidity-lean/commit/706abda))
- Hoist nested argument calls in multi-return internal-call tuple assignments
  such as `(a, b) = f(g())`, retaining RHS-before-LHS-index evaluation.
  ([`ba0ce7a`](https://github.com/ASSERT-KTH/solidity-lean/commit/ba0ce7a))
- Hoist argument calls in storage-pointer declarations such as
  `(T storage p, ...) = f(g())`.
  ([`d9ee5f4`](https://github.com/ASSERT-KTH/solidity-lean/commit/d9ee5f4))
- Hoist argument calls in discarded value-returning call statements such as
  `L.f(I(t).g(), d);`. ([`0c306e4`](https://github.com/ASSERT-KTH/solidity-lean/commit/0c306e4))
- Accept solc statement-documentation fields as importer metadata.
  ([`0c306e4`](https://github.com/ASSERT-KTH/solidity-lean/commit/0c306e4))
- Resolve interface functions named `transfer`, `call`, or `send` in
  type-qualified `abi.encodeCall` arguments instead of treating them as address
  builtins. ([`1b3bdde`](https://github.com/ASSERT-KTH/solidity-lean/commit/1b3bdde))
- Support the corresponding variable-base function pointers, such as
  `abi.encodeCall(token.transfer, ...)`.
  ([`8f9c7a7`](https://github.com/ASSERT-KTH/solidity-lean/commit/8f9c7a7))
- Hoist the receiver call of calls with options, such as
  `entryPoint().depositTo{value: v}(a)`.
  ([`e6d6ed9`](https://github.com/ASSERT-KTH/solidity-lean/commit/e6d6ed9))

### Performance and regression coverage

- Memoize AST-node-to-enclosing-contract lookup in the reject gate, replacing
  repeated full-AST walks that became quadratic on assembly-heavy sources.
  ([`0904564`](https://github.com/ASSERT-KTH/solidity-lean/commit/0904564))
- Add Lean witnesses for bound calls on external results, discarded external
  returns, external tuple assignment, getters implementing sibling interfaces,
  internal calls in external targets, qualified constant receivers, and scoped
  struct ABI encoding. ([`472383b`](https://github.com/ASSERT-KTH/solidity-lean/commit/472383b))
- Add the adopted-world entry-balance witness, including seed-only entries,
  adopted entries with and without value, and rejection of the stale balance.
  ([`0aebd18`](https://github.com/ASSERT-KTH/solidity-lean/commit/0aebd18))
- Add the `closed-world-delegatecall` Solidity/Foundry replay case and manifest
  checks for proxy-frame storage, balances, sender/value, return data, and call
  kinds, with a contrasting ordinary `CALL` case.
  ([`fc59742`](https://github.com/ASSERT-KTH/solidity-lean/commit/fc59742))

The reflective responder is an executable model implemented with `partial`
definitions, not a proved multi-contract equivalence result. Creation uses
recorded addresses and templates; `CREATE2` checks a recorded init-code hash
rather than generating bytecode. Static-call write protection is not enforced,
and resource queries use canonical defaults, so gas-dependent behavior is
outside this responder's scope. The contest's v1 scope remains separate.

## Spec Hunt — find a divergence, get credited

This repo is the subject of **[Spec Hunt](https://www.paradigm.xyz/puzzles/spec-hunt)**:
submit a Solidity program where this semantics disagrees with real
solc + EVM. Every accepted divergence is a concrete, credited bug in the
formal model — and its fix lands here, in public, with a regression witness.

- **How to submit:** [contest/SUBMITTING.md](contest/SUBMITTING.md)
  (submission layout, `claim.json` schema, local adjudication via
  `python -m contest.adjudicate`)
- **What's in scope:** [contest/README.md](contest/README.md) and the
  [exclusion register](contest/exclusion_register.py) (versioned; currently
  single-contract v1 scope — no external calls, no inline assembly, no gas
  introspection; precompile `staticcall`s to literal addresses are in scope)
- **Known/fixed divergences:** [DIVERGENCE-LOG.md](DIVERGENCE-LOG.md) and the
  fingerprint registry (`contest/known_gaps.py`) — submissions matching an
  already-known gap don't score

## Validation, continuously

- **Witness modules** (`SolidCore/Witness/`) pin end-to-end behavior of
  fixed programs and regression cases.
- **Replay corpus** (`tests/forge-harness/`): each case compiles with
  pinned solc, executes on a real EVM via `forge`, and must match the Lean
  observable byte-for-byte
  (`scripts/run_forge_interpreter_harness.py`).
- **Proof obligations** (`FuelMonotonicity`, `AdoptionLaws`) are checked on
  every build — Lean will not compile a module whose proofs don't close.
- **Contest sample suite** (`python3 -m contest.run_samples`): ~85 end-to-end
  adjudication checks, including fault-injection selftests of the detectors
  themselves.

## Building

Prerequisites: [elan](https://github.com/leanprover/elan) (Lean toolchain is
pinned by `lean-toolchain`), pinned **solc 0.8.35**
(`solc-select install 0.8.35`), and **Foundry** (`foundryup`) for the EVM side.

```sh
lake build                      # full build: semantics + proofs + all witnesses
scripts/fast_inner_gate.sh      # fast inner loop: semantic spine + laws only
scripts/compare_forge_solc_interpreter.sh   # replay corpus vs real EVM
python3 -m contest.run_samples  # contest harness end-to-end suite
```

## Repository map

| Path | What |
|---|---|
| `SolidCore/Solidity/` | The semantics: importer, `TypeCheck`, `Interface` (lowering), `Interpreter`, ABI, proofs |
| `SolidCore/Witness/` | Pinned end-to-end behavior witnesses (one per fixed bug family) |
| `contest/` | The Spec Hunt adjudication harness: reject gate, exclusion register, observable comparator, dedup fingerprints, sample suite |
| `tests/forge-harness/` | The solc+EVM replay corpus |
| `scripts/` | Build/replay/measurement tooling |
| `docs/`, `*_DESIGN.md` | Design notes and decision records |

## Scope

The contest's v1 scope is deliberately **single-contract**: one contract, one
entrypoint call, a pinned environment (Foundry defaults). Its exclusions cover
external calls, contract creation, general inline assembly, and gas
introspection — see the exclusion register and reject gate for the precise
rules, including recognized assembly handling in this fork.

Beyond that contest scope, this fork implements closed-world multi-contract
execution in [Reflective.lean](SolidCore/Solidity/Reflective.lean), including
reentrancy, delegatecall, and recorded contract creation. The fork changes and
limitations are listed above.

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or
[MIT License](LICENSE-MIT) at your option.

Unless you explicitly state otherwise, any contribution intentionally
submitted for inclusion in this work by you, as defined in the Apache-2.0
license, shall be dual licensed as above, without any additional terms or
conditions.
