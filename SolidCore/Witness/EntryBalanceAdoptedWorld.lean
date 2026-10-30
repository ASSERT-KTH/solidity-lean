import SolidCore.Solidity.Checked
import SolidCore.Witness.Checked

/-! An external entry into a State that carries an adopted world reads
`address(this).balance` from that world, not from the Context seed map.

After the first adoption the Context maps are seed-only (Interpreter §2.3):
`a.balance` for every other account already reads the adopted world. The entry
re-base of `selfBalance` used the seed `accountBalances` regardless, so a State
whose adopted world gives `self` 7 wei entered with the stale seed (1000), while
other accounts kept their adopted balances. Pre-adoption entries are unchanged. -/

namespace SolidCore.Solidity.Witness.EntryBalanceAdoptedWorld

open SolidCore.Solidity.Source
open SolidCore.Solidity.TypeCheck

private def selfBalanceExpr : Expr :=
  Expr.member
    (Expr.call (Expr.typeName (Ty.address false))
      [Arg.positional (Expr.ident "this")])
    "balance"

private def balancesFn : FunctionDecl :=
  { name := some "balances"
    visibility := some Visibility.external_
    mutability := StateMutability.payable
    returns :=
      [ { name := some "selfBalance", ty := Ty.uint 256 }
      , { name := some "otherBalance", ty := Ty.uint 256 } ]
    body :=
      some
        (Stmt.returnValues
          (some
            (Expr.tuple
              [ TupleItem.value selfBalanceExpr
              , TupleItem.value
                  (Expr.member (Expr.literal (Literal.address 0xbeef))
                    "balance") ]))) }

def contract : ContractDecl :=
  { name := "EntryBalance"
    items := [ContractItem.function balancesFn] }

/-- The seed says self has 1000 and 0xbeef has 77. -/
def seedContext (checked : CheckedContract) (value : Word) : Context :=
  { checked.core.context with
    self := 0xcafe
    value := value
    accountBalances := [(0xcafe, 1000), (0xbeef, 77)] }

/-- A world in which self holds 7 and 0xbeef holds 5 (e.g. after self paid
    out through an external call), adopted into an otherwise empty State. -/
def adoptedState (context : Context) : State :=
  let world :=
    snapshotWorldSeed { context with accountBalances := [(0xbeef, 5)] }
      { State.empty with selfBalance := 7 }
  adoptWorld world context State.empty

def balancesMatch (adopted : Bool) (value expectedSelf expectedOther : Word) :
    Except TypeError Bool := do
  let checked ← ContractDecl.checkedContract contract
  let context := seedContext checked value
  let state := if adopted then adoptedState context else State.empty
  let result ←
    CheckedContract.callFunctionWithContext 16 checked "balances" context
      state []
  match result with
  | CallResult.returned _ [Value.word selfBalance, Value.word otherBalance] =>
      Except.ok
        (wordEq selfBalance expectedSelf && wordEq otherBalance expectedOther)
  | _ => Except.ok false

private def isOkTrue : Except TypeError Bool -> Bool
  | Except.ok true => true
  | _ => false

-- Pre-adoption: unchanged, both balances come from the seed (+ msg.value).
#guard isOkTrue (balancesMatch false 0 1000 77)
#guard isOkTrue (balancesMatch false 3 1003 77)
-- Adopted world: self and 0xbeef both come from the world (+ msg.value).
#guard isOkTrue (balancesMatch true 0 7 5)
#guard isOkTrue (balancesMatch true 3 10 5)
-- The pre-fix observable (stale seed for self only) is refused.
#guard !isOkTrue (balancesMatch true 0 1000 5)

end SolidCore.Solidity.Witness.EntryBalanceAdoptedWorld
