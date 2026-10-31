/-! Appended to the imported ForkFeatures.sol AST by run_fork_tests.py.
Each guard checks observable behavior; Foundry runs the same source fixture. -/
set_option maxHeartbeats 8000000

namespace ForkChecks
open SolidCore.Solidity.Source
open SolidCore.Solidity.TypeCheck
open SolidCore.Solidity.Source.Reflective

def program : Except String CheckedProgram :=
  (CheckedInput.program ForkFixtures.importedSourceUnit).mapError reprStr

def get (name : String) : Except String CheckedContract := do
  let p ← program
  (p.contract name).mapError reprStr

def call (name : String) (args : List Value := []) : Except String CallResult := do
  let c ← get "ForkFeatures"
  (CheckedContract.callFunctionWithContext 128 c name c.core.context State.empty args).mapError reprStr

def returnsWord (r : Except String CallResult) (n : Word) : Bool :=
  match r with
  | .ok (.returned _ [.word w]) => wordEq w n
  | _ => false

def yes : Except String Bool → Bool
  | .ok true => true
  | _ => false

def data (signature : String) (words : List Word := []) : List Nat :=
  ABI.encodeSelector (ABI.selectorFromSignature signature) ++ words.flatMap (wordToBytesBE 32)

def registry : Except String Registry := do
  let f ← get "ForkFeatures"
  let proxy ← get "RawProxy"
  let impl ← get "RawImpl"
  let factory ← get "Factory"
  let child ← get "Child"
  let p ← program
  return { members := [(0x100, .code f.core [("immutableValue", 42)]),
                        (0x200, .eoa), (0x300, .code proxy.core []),
                        (0x400, .code impl.core []), (0x500, .code factory.core [])]
           blockEnv := f.core.context.blockEnv
           txEnv := f.core.context.txEnv
           templates := [("Child", child.core, p.constructorFunction? "Child", [])] }

def world (reg : Registry) : SolidCore.Solidity.Shared.OpenWorld :=
  mkWorld reg [(0x100, 10, []), (0x200, 100, []), (0x300, 0, [(0, 0x400)]),
               (0x400, 0, []), (0x500, 0, [])]

-- Fork frontend fixes: storage aliases, tuple arguments/declarations, discarded calls.
#guard returnsWord (call "storageArg") 2
#guard returnsWord (call "tupleArg") 12
#guard returnsWord (call "storageDecl") 11
#guard returnsWord (call "discarded") 1

def encodeCalls : Except String Bool := do
  let expected := data "transfer(address,uint256)" [1, 7]
  let a ← call "encodedType"
  let b ← call "encodedVariable" [.word 2]
  match a, b with
  | .returned _ [.bytes x], .returned _ [.bytes y] => return x == expected && y == expected
  | _, _ => return false
#guard yes encodeCalls

def rawStorage : Except String Bool := do
  let a ← call "rawSlot" [.word 0, .word 42]
  let b ← call "storagePointer" [.word 1, .word 17]
  match a, b with
  | .returned s [.word x], .returned t [.word y] =>
      return wordEq x 42 && wordEq (s.loadSlot 0) 42 &&
        wordEq y 17 && wordEq (t.loadSlot 1) 17
  | _, _ => return false
#guard yes rawStorage

def memoryCast : Except String Bool := do
  let r ← call "arrayCast" [.dynamicArray [.word 1, .word 2]]
  match r with
  | .returned _ [.dynamicArray [.word a, .word b]] => return wordEq a 1 && wordEq b 2
  | _ => return false
#guard yes memoryCast

def rawReverts : Except String Bool := do
  let a ← call "rawRevert" [.bytes [0x12, 0x34]]
  let b ← call "rawRevertLength" [.bytes [0x12, 0x34]]
  match a, b with
  | .reverted _ (.raw x), .reverted _ (.raw y) =>
      return x == [0x12, 0x34] && y == x
  | _, _ => return false
#guard yes rawReverts

-- The assembly proxy must halt the whole frame and return raw bytes verbatim.
def proxyOutput : Except String Bool := do
  let reg ← registry
  let req : EvmCompiler.Simulation.CallRequest :=
    { kind := .call, requestedGas := wordToU256 1000000,
      caller := wordToAddress 0x200, recipient := wordToAddress 0x300,
      codeAddress := wordToAddress 0x300, transferValue := wordToU256 0,
      apparentValue := wordToU256 0, calldata := bytesToByteArray [0xde, 0xad, 0xbe, 0xef],
      permission := true }
  let (r, cs) ← answerCall reg 16 {} (world reg) req
  let (failed, _) ← answerCall reg 16 {} (world reg)
    { req with calldata := ByteArray.empty }
  return r.success && byteArrayToBytes r.returnData == [0x12, 0x34] &&
    wordEq (loadSlot r.postWorld 0x300 0) 7 && wordEq (loadSlot r.postWorld 0x400 0) 0 &&
    cs.kinds.toList == [.call, .delegatecall] && !failed.success &&
    failed.returnData.isEmpty && wordEq (loadSlot failed.postWorld 0x300 0) 0x400
#guard yes proxyOutput

def receiverOptions : Except String Bool := do
  let reg ← registry
  let (ok, w, _) ← runTopCursors reg (world reg) [(0x200, 0x100, 0, data "withOptions()")]
  return ok == [true] && wordEq (loadSlot w 0x100 0) 1 && wordEq (loadSlot w 0x100 1) 3
#guard yes receiverOptions

-- Scripted actors reenter executed code and preserve an explicitly recorded caller.
def reentryAndPrank : Except String Bool := do
  let base ← registry
  let reg := { base with members := (0x600, .actor
      [{ calls := [(0x600, 0x100, 0, data "callback()") ] },
       { calls := [(0x777, 0x100, 0, data "recordSender()") ] }]) :: base.members }
  let w := mkWorld reg [(0x100, 10, []), (0x200, 100, []), (0x600, 0, [])]
  let (oks, w, cs) ← runTopCursors reg w [(0x200, 0x100, 0, data "enter(address)" [0x600])]
  if oks != [true] || !wordEq (loadSlot w 0x100 0) 12 || cs.log.size != 3 then return false
  let (oks, w, cs) ← runTopCursors reg w [(0x200, 0x600, 0, []) , (0x200, 0x600, 0, [])]
  return oks == [true, true] && wordEq (loadSlot w 0x100 0) 0x777 && cs.log.size == 4
#guard yes reentryAndPrank

def cheatcodes : Except String Bool := do
  let base ← registry
  let reg := { base with members := (0x600, .actor [{ calls :=
      [(0x600, cheatAddress, 0, data "warp(uint256)" [100]),
       (0x600, cheatAddress, 0, data "roll(uint256)" [7]),
       (0x600, cheatAddress, 0, data "store(address,bytes32,bytes32)" [0x100, 3, 99]),
       (0x600, cheatAddress, 0, data "deal(address,uint256)" [0x100, 25]),
       (0x600, 0x100, 0, data "observe()") ] }]) :: base.members }
  let (oks, w, cs) ← runTopCursors reg (world reg) [(0x200, 0x600, 0, [])]
  return oks == [true] && wordEq (loadSlot w 0x100 0) 42 &&
    wordEq (loadSlot w 0x100 1) 107 && wordEq (loadSlot w 0x100 3) 99 &&
    wordEq (balanceOf w 0x100) 25 && cs.notes.isEmpty
#guard yes cheatcodes

def eoaAndUnknown : Except String Bool := do
  let reg ← registry
  let reg := { reg with members := (0x700, .eoa) :: reg.members }
  let (oks, w) ← runTop reg (world reg) [(0x200, 0x700, 3, []), (0x200, 0x700, 1000, [])]
  let missing := runTop reg w [(0x200, 0x999, 0, [])]
  return oks == [true, false] && wordEq (balanceOf w 0x200) 97 &&
    wordEq (balanceOf w 0x700) 3 && (match missing with | .error _ => true | _ => false)
#guard yes eoaAndUnknown

def creation (n : Word) : Except String Bool := do
  let reg ← registry
  let reg := { reg with creations := [(0x500, 0x800, none)] }
  let (oks, w, cs) ← runTopCursors reg (world reg) [(0x200, 0x500, 3, data "make(uint256)" [n])]
  if n == 0 then
    return oks == [false] && wordEq (balanceOf w 0x200) 100 &&
      wordEq (balanceOf w 0x800) 0 && wordEq (loadSlot w 0x500 0) 0
  return oks == [true] && wordEq (loadSlot w 0x800 0) n &&
    wordEq (loadSlot w 0x500 0) n && wordEq (balanceOf w 0x800) 3 &&
    cs.created.length == 1 && cs.log.size == 3 &&
    cs.log[1]!.2.1 == 0x800 && cs.log[1]!.2.2.2
#guard yes (creation 7)
#guard yes (creation 0)

def recordedCreationGuards : Except String Bool := do
  let reg ← registry
  let invoke := fun (r : Registry) =>
    runTop r (world reg) [(0x200, 0x500, 0, data "make(uint256)" [7])]
  let wrongCreator := invoke { reg with creations := [(0x999, 0x800, none)] }
  let missingRecord := invoke reg
  let missingTemplate := invoke
    { reg with creations := [(0x500, 0x800, none)], templates := [] }
  return [wrongCreator, missingRecord, missingTemplate].all
    (fun r => match r with | .error _ => true | _ => false)
#guard yes recordedCreationGuards

def create2 (wrongSalt : Bool) : Except String Bool := do
  let reg ← registry
  let hash := 123
  -- Independently pinned by Foundry's EVM keccak256 and `cast keccak`,
  -- rather than calculated with the implementation being checked.
  let addr := 0x48acc88f821691c8fb9f469db7efd32058126db9
  let reg := { reg with creations := [(0x500, addr, some hash)] }
  let r := runTopCursors reg (world reg) [(0x200, 0x500, 0,
    data "make2(uint256,bytes32)" [9, if wrongSalt then 6 else 5])]
  if wrongSalt then return (match r with | .error _ => true | _ => false)
  let (oks, w, _) ← r
  return oks == [true] && wordEq (loadSlot w addr 0) 9 && wordEq (loadSlot w 0x500 0) 9
#guard yes (create2 false)
#guard yes (create2 true)

end ForkChecks
