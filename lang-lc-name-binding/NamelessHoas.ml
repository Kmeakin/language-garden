(** The lambda calculus, implemented using normalisation-by-evaluation with de
    Bruijn indices in the syntax, and levels with  higher-order abstract syntax
    (HOAS) in the semantic domain.
*)

(** [elem_index x xs] returns the index of the first occurance of [x] in [xs]. *)
let elem_index (a : 'a) (xs : 'a list) =
  let rec go i = function
    | [] -> None
    | x :: xs -> if x = a then Some i else go (i + 1) xs in
  go 0 xs


(** {1 Syntax} *)

type expr =
  | Var of int (* de Bruijn index *)
  | Let of string * expr * expr
  | FunLit of string * expr
  | FunApp of expr * expr

(** {2 Conversions} *)

let of_named (e : Named.expr) : expr =
  let rec go (ns : string list) (e : Named.expr) : expr =
    match e with
    | Var x -> Var (elem_index x ns |> Option.get)
    | Let (x, def, body) -> Let (x, go ns def, go (x :: ns) body)
    | FunLit (x, body) -> FunLit (x, go (x :: ns) body)
    | FunApp (head, arg) -> FunApp (go ns head, go ns arg)
  in
  go [] e

let to_named (e : expr) : Named.expr =
  let rec fresh (ns : string list) (x : string) : string =
    match List.mem x ns with
    | true -> fresh ns (x ^ "'")
    | false -> x
  in
  let rec go (ns : string list) (e : expr) : Named.expr =
    match e with
    | Var i -> Var (List.nth ns i)
    | Let (x, def, body) -> let x = fresh ns x in Let (x, go ns def, go (x :: ns) body)
    | FunLit (x, body) -> let x = fresh ns x in FunLit (x, go (x :: ns) body)
    | FunApp (head, arg) -> FunApp (go ns head, go ns arg)
  in
  go [] e

(** {2 Alpha Equivalence} *)

(** Compare the syntactic structure of two expressions, taking into account
    binding structure while ignoring differences in names. *)
let rec alpha_equiv (e1 : expr) (e2 : expr) =
  match e1, e2 with
  | Var i1, Var i2 -> i1 = i2
  | Let (_, def1, body1), Let (_, def2, body2) ->
      alpha_equiv def1 def2 && alpha_equiv body1 body2
  | FunLit (_, body1), FunLit (_, body2) ->
      alpha_equiv body1 body2
  | FunApp (head1, arg1), FunApp (head2, arg2) ->
      alpha_equiv head1 head2 && alpha_equiv arg1 arg2
  | _, _ -> false


(** {1 Semantics} *)

type value =
  | Neu of neu
  | FunLit of string * (value -> value)
and neu =
  | Var of int (* de Bruijn level *)
  | FunApp of neu * value

type env = value list

(** {2 Evaluation} *)

let rec eval (vs : env) (e : expr) : value =
  match e with
  | Var i -> List.nth vs i
  | Let (_, def, body) -> eval (eval vs def :: vs) body
  | FunLit (x, body) -> FunLit (x, fun v -> eval (v :: vs) body)
  | FunApp (head, arg) -> begin
      match eval vs head with
      | FunLit (_, body) -> body (eval vs arg)
      | Neu nv -> Neu (FunApp (nv, eval vs arg))
  end

(** {2 Quotation} *)

let rec quote (size : int) (v : value) : expr =
  match v with
  | Neu nv -> quote_neu size nv
  | FunLit (x, body) -> FunLit (x, quote (size + 1) (body (Neu (Var size))))
and quote_neu (size : int) (nv : neu) : expr =
  match nv with
  | Var l -> Var (size - l - 1)
  | FunApp (head, arg) -> FunApp (quote_neu size head, quote size arg)

(** {2 Normalisation-by-evaluation} *)

let normalise (vs : env) (e : expr) : expr =
  quote (List.length vs) (eval vs e)
