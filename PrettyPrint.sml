(*  Celf
 *  Copyright (C) 2008 Anders Schack-Nielsen and Carsten Sch�rmann
 *
 *  This file is part of Celf.
 *
 *  Celf is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  Celf is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with Celf.  If not, see <http://www.gnu.org/licenses/>.
 *)

signature TLU_PrettyPrint = TOP_LEVEL_UTIL
structure PrettyPrint :> PRETTYPRINT =
struct

open Syntax

val printImpl = ref false
val printLVarCtx = ref false

fun join' [] = []
  | join' [x] = x
  | join' (x::xs) = x @ ["] ["] @ join' xs
val join = (fn [] => [] | xs => ["[["] @ xs @ ["]]"]) o join'

fun paren false x = x
  | paren true x = ["("] @ x @ [")"]

fun lookup (x::ctx) 1 = x
  | lookup (_::ctx) n = lookup ctx (n-1)
  | lookup [] n = Int.toString n (*raise Fail "Internal error: de Bruijn index out of range\n"*)

fun add x ctx =
	let fun eq (x : string) y = x=y
		fun add1 n x =
			let val tryname = x ^ Int.toString n
			in if List.exists (eq tryname) ctx then add1 (n+1) x else (tryname, tryname::ctx) end
		fun add' x = if List.exists (eq x) ctx then add1 1 (x^"_") else (x, x::ctx)
	in if x="" then add1 1 "X" else add' x end

fun addNoOccur ctx = "? Error ?"::ctx

val noSkip = ref false
fun getImplLength c = if !noSkip then 0 else Signatur.getImplLength c

fun pKind ctx ki = case Kind.prj ki of
	  Type => ["type"]
	| KPi (NONE, A, K) => pType ctx true A @ [" -> "] @ pKind ctx K
	| KPi (SOME x, A, K) =>
			let val (x', ctx') = add x ctx
			in ["Pi "^x'^": "] @ pType ctx false A @ [". "] @ pKind ctx' K end
and pType ctx pa ty = if isUnknown ty then ["???"] else case AsyncType.prj ty of
	  TLPi (p, S, B) => paren pa (case (Pattern.prj p, SyncType.prj S) of
		  (PBang NONE, TBang A) =>
			pType ctx true A @ [" -> "] @ pType (addNoOccur ctx) false B
		| (PBang (SOME x), TBang A) =>
			let val (x', ctx') = add x ctx
			in ["Pi "^x'^": "] @ pType ctx false A @ [". "] @ pType ctx' false B end
		| (PAffi (), TAffi A) =>
			pType ctx true A @ [" -@ "] @ pType (addNoOccur ctx) false B
		| _ =>
			let val (pP, ctx', d) = pTPattern ctx p
			in if d then ["PI "] @ pP @ [": "] @ pSyncType ctx false S @ [". "] @ pType ctx' false B
			else pSyncType ctx true S @ [" -o "] @ pType ctx' false B
			end)
	| AddProd (A, B) => paren pa (pType ctx true A @ [" & "] @ pType ctx true B)
	| TMonad S => ["{"] @ pSyncType ctx false S @ ["}"]
	| TAtomic (a, S) => (*(fn (a', []) => a' | (a', ts) => paren pa (a' @ ts)) ([a] @ join (map (pObj ctx true) impl), pTypeSpine ctx S)*)
			[a] @ (*join (map (pObj ctx false) impl) @*) pTypeSpineSkip ctx S (getImplLength a)
	| TAbbrev (a, ty) => [a]
and pTypeSpineSkip ctx sp n = if n=0 then pTypeSpine ctx sp else case TypeSpine.prj sp of
	  TNil => raise Fail "Internal error: pTypeSpineSkip\n"
	| TApp (N, S) =>
		(if !printImpl then [" <"] @ pObj ctx false N @ [">"] else [])
		@ pTypeSpineSkip ctx S (n-1)
and pTypeSpine ctx sp = case TypeSpine.prj sp of
	  TNil => []
	| TApp (N, S) => [" "] @ pObj ctx true N @ pTypeSpine ctx S
and pSyncType ctx pa sty = case SyncType.prj sty of
	  LExists (p, S1, S2) => paren pa (case (Pattern.prj p, SyncType.prj S1) of
		  (PBang (SOME x), TBang A) =>
			let val (x', ctx') = add x ctx
			in ["Exists "^x'^": "] @ pType ctx false A @ [". "] @ pSyncType ctx' false S2 end
		| _ =>
			let val (pP, ctx', d) = pTPattern ctx p
			in if d then ["EXISTS "] @ pP @ [": "] @ pSyncType ctx false S1 @ [". "]
				@ pSyncType ctx' false S2
			else pSyncType ctx true S1 @ [" * "] @ pSyncType ctx' true S2
			end)
	| TOne => ["1"]
	| TDown A => pType ctx pa A
	| TAffi A => ["@"] @ pType ctx true A
	| TBang A => ["!"] @ pType ctx true A
and pObj ctx pa ob = case Obj.prj ob of
	  LLam (p, N) =>
			let val (pP, ctx') = pOPattern ctx p
			in paren pa (["\\"] @ pP @ [". "] @ pObj ctx' false N) end
	| AddPair (N1, N2) => ["<"] @ pObj ctx false N1 @ [", "] @ pObj ctx false N2 @ [">"]
	| Monad E => ["{"] @ pExp ctx E @ ["}"]
	| Atomic (H, S) =>
			let val skip = case H of Const c => getImplLength c | _ => 0
			in case (pHead ctx H, pSpineSkip ctx S skip) of
				  (h, []) => h
				| (h, s) => paren pa (h @ s)
			end
	| Redex (N, _, S) =>
			(fn [] => pObj ctx pa N | s => paren pa (pObj ctx true N @ s)) (pSpine ctx S)
	| Constraint (N, A) => pObj ctx pa N
and pHead ctx h = case h of
	  Const c => [c] (*@ join (map (pObj ctx false) impl)*)
	| Var (M, n) => [lookup ctx n (*, case M of Context.INT => "!" | Context.LIN => "L"*)]
	| UCVar v => ["#"^v]
	| LogicVar {ty, s, ctx=ref G, tag, ...} =>
		["$", Word.toString tag] @
		(if !printLVarCtx then
			["<"] @ pContext ctx G @ [", "] @ pType ctx false (TClos (ty, s)) @ [">"] else [])
		@ [Subst.substToStr (String.concat o (pObj ctx true) o unnormalizeObj) s]
and pContext ctx NONE = ["--"]
  | pContext ctx (SOME G) =
		join $ map (fn (_, A, m) => pType ctx false A
					@ [case m of
						  NONE => " NO"
						| SOME Context.INT => " !"
						| SOME Context.AFF => " @"
						| SOME Context.LIN => " L"])
				(Context.ctx2list G)
and pSpineSkip ctx sp n = if n=0 then pSpine ctx sp else case Spine.prj sp of
	  LApp (M, S) =>
		(if !printImpl then [" <"] @ pMonadObj ctx false M @ [">"] else [])
		@ pSpineSkip ctx S (n-1)
	| _ => raise Fail "Internal error: pSpineSkip\n"
and pSpine ctx sp = case Spine.prj sp of
	  Nil => []
	| LApp (M, S) => [" "] @ pMonadObj ctx true M @ pSpine ctx S
	| ProjLeft S => [" pi_1"] @ pSpine ctx S
	| ProjRight S => [" pi_2"] @ pSpine ctx S
and pExp ctx e = case ExpObj.prj e of
	  LetRedex (p, _, N, E) => pLet ctx (p, N, E)
	| Let (p, hS, E) => pLet ctx (p, Atomic' hS, E)
	| Mon M => pMonadObj ctx false M
and pLet ctx (p, N, E) =
	let val (pP, ctx') = pOPattern ctx p
	in ["\n    let {"] @ pP @ ["} = "] @ pObj ctx false N @ [" in "] @ pExp ctx' E end
and pMonadObj ctx pa m = case MonadObj.prj m of
	  DepPair (M1, M2) => ["["] @ pMonadObj ctx false M1 @ [", "] @ pMonadObj ctx false M2 @ ["]"]
	| One => ["1"]
	| Down N => pObj ctx pa N
	| Affi N => ["@"] @ pObj ctx true N
	| Bang N => ["!"] @ pObj ctx true N
and pOPattern bctx p = case Pattern.prj p of
	  PDepTensor (p1, p2) =>
			let val (pP1, bctx') = pOPattern bctx p1
				val (pP2, bctx'') = pOPattern bctx' p2
			in (["["] @ pP1 @ [", "] @ pP2 @ ["]"], bctx'') end
	| POne => (["1"], bctx)
	| PDown x => map1 (fn x => [x]) (add x bctx)
	| PAffi x => map1 (fn x => ["@"^x]) (add x bctx)
	| PBang x => map1 (fn x => ["!"^x]) (add x bctx)
and pTPattern bctx p = case Pattern.prj p of
	  PDepTensor (p1, p2) =>
			let val (pP1, bctx', d1) = pTPattern bctx p1
				val (pP2, bctx'', d2) = pTPattern bctx' p2
			in (["["] @ pP1 @ [", "] @ pP2 @ ["]"], bctx'', d1 orelse d2) end
	| POne => (["1"], bctx, false)
	| PDown () => (["_"], addNoOccur bctx, false)
	| PAffi () => (["@_"], addNoOccur bctx, false)
	| PBang NONE => (["!_"], addNoOccur bctx, false)
	| PBang (SOME x) => let val (x', bctx') = add x bctx in (["!"^x'], bctx', true) end
(*and pPattern ctx bctx pa p = case Pattern.prj p of
	  PTensor (p1, p2) =>
			let val (pP1, bctx') = pPattern ctx bctx true p1
				val (pP2, bctx'') = pPattern ctx bctx' true p2
			in (paren pa (pP1 @ [" * "] @ pP2), bctx'') end
	| POne => (["1"], bctx)
	| PDepPair (x, A, p) =>
			let val (x', bctx') = add x bctx
				val (x'', ctx') = add x' ctx
				val () = if x' = x'' then () else raise Fail "Internal error: pPattern\n"
				val (pP, bctx'') = pPattern ctx' bctx' false p
			in (["["^x'^": "] @ pType ctx false A @ [", "] @ pP @ ["]"], bctx'') end
	| PVar (x, A) =>
			let val (x', bctx') = add x bctx
			in ([x'^": "] @ pType ctx false A, bctx') end*)

val printKind = String.concat o (pKind [])
val printType = String.concat o (pType [] false)
val printSyncType = String.concat o (pSyncType [] false)
val printObj = String.concat o (pObj [] false)
val printMonadObj = String.concat o (pMonadObj [] false)

fun printPreType ty = ( noSkip := true; printType ty before noSkip := false )
fun printPreObj ob = ( noSkip := true; printObj ob before noSkip := false )

end
