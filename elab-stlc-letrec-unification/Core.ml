(** {0 Core language} *)

(** {1 Names} *)

(** These names are used as hints for pretty printing binders and variables,
    but don’t impact the equality of terms. *)
type name = string


(** {1 Nameless binding structure} *)

(** The binding structure of terms is represented in the core language by
    using numbers that represent the distance to a binder, instead of by the
    names attached to those binders. *)

(** {i De Bruijn index} that represents a variable occurance by the number of
    binders between the occurance and the binder it refers to. *)
type index = int

(** {i De Bruijn level} that represents a variable occurance by the number of
    binders from the top of the environment to the binder that the ocurrance
    refers to. These do not change their meaning as new bindings are added to
    the environment. *)
type level = int

(** Converts a {!level} to an {!index} that is bound in an environment of the
    supplied size. Assumes that [ size > level ]. *)
let level_to_index size level =
  size - level - 1

(** An environment of bindings that can be looked up directly using a
    {!index}, or by inverting a {!level} using {!level_to_index}. *)
type 'a env = 'a list


(** {1 Syntax} *)

(** Metavariable identifier *)
type meta_id = int

(** Type syntax *)
type ty =
  | BoolType
  | IntType
  | FunType of ty * ty
  | MetaVar of meta_state ref

(** The state of a metavariable, updated during unification *)
and meta_state =
  | Solved of ty
  | Unsolved of meta_id

(** Primitive operations *)
type prim = [
  | `Eq   (** [Int -> Int -> Bool] *)
  | `Add  (** [Int -> Int -> Int] *)
  | `Sub  (** [Int -> Int -> Int] *)
  | `Mul  (** [Int -> Int -> Int] *)
  | `Neg  (** [Int -> Int] *)
]

(** Term syntax *)
type tm =
  | Var of index
  | Let of name * ty * tm * tm
  | Fix of name * ty * tm
  | BoolLit of bool
  | BoolElim of tm * tm * tm
  | IntLit of int
  | FunLit of name * ty * tm
  | FunApp of tm * tm
  | PrimApp of prim * tm list


module Semantics = struct

  (** Evaluation options *)
  type eval_opts = {
    unfold_fix : bool;
  }

  (** {1 Values} *)

  type vtm =
    | Neu of ntm
    | BoolLit of bool
    | IntLit of int
    | FunLit of name * ty * (eval_opts -> vtm -> vtm)

  and ntm =
    | Var of level
    | Fix of string * ty * (eval_opts -> vtm -> vtm)
    | BoolElim of ntm * vtm Lazy.t * vtm Lazy.t
    | FunApp of ntm * vtm
    | PrimApp of prim * vtm list


  (** {1 Eliminators} *)

  let bool_elim head vtm0 vtm1 =
    match head with
    | Neu ntm -> Neu (BoolElim (ntm, vtm0, vtm1))
    | BoolLit true -> Lazy.force vtm0
    | BoolLit false -> Lazy.force vtm1
    | _ -> invalid_arg "expected boolean"

  let prim_app prim args =
    match prim, args with
    | `Eq, [IntLit t1; IntLit t2] -> BoolLit (t1 = t2)
    | `Add, [IntLit t1; IntLit t2] -> IntLit (t1 + t2)
    | `Sub, [IntLit t1; IntLit t2] -> IntLit (t1 - t2)
    | `Mul, [IntLit t1; IntLit t2] -> IntLit (t1 * t2)
    | `Neg, [IntLit t1] -> IntLit (-t1)
    | prim, args -> Neu (PrimApp (prim, args))

  let fun_app opts head arg =
    match head with
    | Neu ntm -> Neu (FunApp (ntm, arg))
    | FunLit (_, _, body) -> body opts arg
    | _ -> invalid_arg "expected function"


  (** {1 Evaluation} *)

  (** Default options for evaluation *)
  let default_opts = {
    unfold_fix = true;
  }

  (** Evaluate a term from the syntax into its semantic interpretation *)
  let rec eval ?(opts = default_opts) (env : vtm env) (tm : tm) : vtm =
    match tm with
    | Var index -> begin
        match List.nth env index with
        | Neu (Fix (_, _, body)) as self when opts.unfold_fix -> body opts self
        | vtm -> vtm
    end
    | Let (_, _, def, body) ->
        let def = eval ~opts env def in
        eval ~opts (def :: env) body
    | Fix (name, self_ty, body) ->
        let body' opts self = eval ~opts (self :: env) body in
        body' opts (Neu (Fix (name, self_ty, body')))
    | BoolLit b -> BoolLit b
    | BoolElim (head, tm0, tm1) ->
        let head = eval ~opts env head in
        let vtm0 = Lazy.from_fun (fun () -> eval ~opts env tm0) in
        let vtm1 = Lazy.from_fun (fun () -> eval ~opts env tm1) in
        bool_elim head vtm0 vtm1
    | IntLit i -> IntLit i
    | PrimApp (prim, args) ->
        prim_app prim (List.map (eval ~opts env) args)
    | FunLit (name, param_ty, body) ->
        let body opts arg = eval ~opts (arg :: env) body in
        FunLit (name, param_ty, body)
    | FunApp (head, arg) ->
        let head = eval ~opts env head in
        let arg = eval ~opts env arg in
        fun_app opts head arg


  (** {1 Quotation} *)

  (** Options for evaluating under binders during quotation. *)
  let quote_opts = {
    unfold_fix = false;
  }

  (** Convert terms from the semantic domain back into syntax. *)
  let rec quote (size : int) (vtm : vtm) : tm =
    match vtm with
    | Neu ntm -> quote_neu size ntm
    | BoolLit b -> BoolLit b
    | IntLit i -> IntLit i
    | FunLit (name, param_ty, body) ->
        let body = quote (size + 1) (body quote_opts (Neu (Var size))) in
        FunLit (name, param_ty, body)

  and quote_neu (size : int) (ntm : ntm) : tm =
    match ntm with
    | Var level -> Var (level_to_index size level)
    | Fix (name, self_ty, body) ->
        let body = quote (size + 1) (body quote_opts (Neu (Var size))) in
        Fix (name, self_ty, body)
    | BoolElim (head, vtm0, vtm1) ->
        let tm0 = quote size (Lazy.force vtm0) in
        let tm1 = quote size (Lazy.force vtm1) in
        BoolElim (quote_neu size head, tm0, tm1)
    | FunApp (head, arg) -> FunApp (quote_neu size head, quote size arg)
    | PrimApp (prim, args) -> PrimApp (prim, List.map (quote size) args)


  (** {1 Normalisation} *)

  (** By evaluating a term then quoting the result, we can produce a term that
      is reduced as much as possible in the current environment. *)
  let normalise (env : vtm list) (tm : tm) : tm =
    quote (List.length env) (eval env tm)

end


(** {1 Functions related to metavariables} *)

(** Create a fresh, unsolved metavariable *)
let fresh_meta : unit -> meta_state ref =
  let next_id = ref 0 in
  fun () ->
    let id = !next_id in
    incr next_id;
    ref (Unsolved id)

(** Force any solved metavariables on the outermost part of a type. Chains of
    metavariables will be collapsed to make forcing faster in the future. This
    is sometimes referred to as {i path compression}. *)
let rec force (ty : ty) : ty =
  match ty with
  | MetaVar m as ty -> begin
      match !m with
      | Solved ty ->
          let ty = force ty in
          m := Solved ty;
          ty
      | Unsolved _ -> ty
  end
  | ty -> ty


(** {1 Unification} *)

exception InfiniteType of meta_id
exception MismatchedTypes of ty * ty

(** Occurs check. This guards against self-referential unification problems
    that would result in infinite loops during unification. *)
let rec occurs (id : meta_id) (ty : ty) : unit =
  match force ty with
  | MetaVar m -> begin
      match !m with
      | Unsolved id' when id = id' ->
          raise (InfiniteType id)
      | Unsolved _ | Solved _-> ()
  end
  | BoolType -> ()
  | IntType -> ()
  | FunType (param_ty, body_ty) ->
      occurs id param_ty;
      occurs id body_ty

(** Check if two types are the same, updating unsolved metavaribles in one
    type with known information from the other type if possible. *)
let rec unify (ty0 : ty) (ty1 : ty) : unit =
  match force ty0, force ty1 with
  | ty0, ty1 when ty0 = ty1 -> ()
  | MetaVar m, ty | ty, MetaVar m -> unify_meta m ty
  | BoolType, BoolType -> ()
  | IntType, IntType -> ()
  | FunType (param_ty0, body_ty0), FunType (param_ty1, body_ty1) ->
      unify param_ty0 param_ty1;
      unify body_ty0 body_ty1;
  | ty1, ty2 ->
      raise (MismatchedTypes (ty1, ty2))

(** Unify a metavariable with a type *)
and unify_meta (m : meta_state ref) (ty : ty) : unit =
  match !m with
  | Unsolved id ->
      occurs id ty;
      m := Solved ty;
  | Solved mty ->
      unify ty mty


(** {1 Zonking} *)

(** These functions flatten solved metavariables in types. This is imporatant
    for pretty printing types, as we want to be able to ‘see through’
    metavariables to properly associate function types. *)

let rec zonk_ty (ty : ty) : ty =
  match force ty with
  | BoolType -> BoolType
  | IntType -> IntType
  | FunType (param_ty, body_ty) ->
      FunType (zonk_ty param_ty, zonk_ty body_ty)
  | MetaVar _ as ty -> ty

let rec zonk_tm (tm : tm) : tm =
  match tm with
  | Var index -> Var index
  | Let (name, def_ty, def, body) ->
      Let (name, zonk_ty def_ty, zonk_tm def, zonk_tm body)
  | Fix (name, self_ty, body) ->
      Fix (name, zonk_ty self_ty, zonk_tm body)
  | BoolLit b -> BoolLit b
  | BoolElim (head, tm0, tm1) ->
      BoolElim (zonk_tm head, zonk_tm tm0, zonk_tm tm1)
  | IntLit i -> IntLit i
  | PrimApp (prim, args) ->
      PrimApp (prim, List.map zonk_tm args)
  | FunLit (name, param_ty, body) ->
      FunLit (name, zonk_ty param_ty, zonk_tm body)
  | FunApp (head, arg) ->
      FunApp (zonk_tm head, zonk_tm arg)


(** {1 Pretty printing} *)

let rec fresh (ns : string env) (n : string) : string =
  match List.mem n ns with
  | true -> fresh ns (n ^ "'")
  | false -> n

let rec pp_ty (fmt : Format.formatter) (ty : ty) : unit =
  match ty with
  | FunType (param_ty, body_ty) ->
      Format.fprintf fmt "%a -> %a"
        pp_atomic_ty param_ty
        pp_ty body_ty
  | ty ->
      pp_atomic_ty fmt ty
and pp_atomic_ty fmt ty =
  match ty with
  | BoolType -> Format.fprintf fmt "Bool"
  | IntType -> Format.fprintf fmt "Int"
  | MetaVar m -> begin
      match !m with
      | Solved ty -> pp_atomic_ty fmt ty
      | Unsolved id -> Format.fprintf fmt "?%i" id
  end
  | ty -> Format.fprintf fmt "@[(%a)@]" pp_ty ty

let pp_name_ann fmt (name, ty) =
  Format.fprintf fmt "@[<2>@[%s :@]@ %a@]" name pp_ty ty

let pp_param fmt (name, ty) =
  Format.fprintf fmt "@[<2>(@[%s :@]@ %a)@]" name pp_ty ty

let rec pp_tm (names : name env) (fmt : Format.formatter) (tm : tm) : unit =
  match tm with
  | Let _ as tm ->
      let rec go names fmt tm =
        match tm with
        | Let (name, def_ty, def, body) ->
            let name = fresh names name in
            Format.fprintf fmt "@[<2>@[let %a@ :=@]@ @[%a;@]@]@ %a"
              pp_name_ann (name, def_ty)
              (pp_tm names) def
              (go (name :: names)) body
        | tm -> Format.fprintf fmt "@[%a@]" (pp_tm names) tm
      in
      Format.fprintf fmt "@[<hv>%a@]" (go names) tm
  | Fix (name, self_ty, body) ->
      let name = fresh names name in
      Format.fprintf fmt "@[<2>@[#fix@ %a@ =>@]@ %a@]"
        pp_param (name, self_ty)
        (pp_tm (name :: names)) body
  | FunLit (name, param_ty, body) ->
      let name = fresh names name in
      Format.fprintf fmt "@[<2>@[fun@ %a@ =>@]@ %a@]"
        pp_param (name, param_ty)
        (pp_tm (name :: names)) body
  | tm -> pp_if_tm names fmt tm
and pp_if_tm names fmt tm =
  match tm with
  | BoolElim (head, tm0, tm1) ->
      Format.fprintf fmt "@[if@ %a@ then@]@ %a@ else@ %a"
        (pp_eq_tm names) head
        (pp_eq_tm names) tm0
        (pp_if_tm names) tm1
  | tm ->
      pp_eq_tm names fmt tm
and pp_eq_tm names fmt tm =
  match tm with
  | PrimApp (`Eq, [arg1; arg2]) ->
      Format.fprintf fmt "@[%a@ =@ %a@]"
        (pp_add_tm names) arg1
        (pp_eq_tm names) arg2
  | tm ->
      pp_add_tm names fmt tm
and pp_add_tm names fmt tm =
  match tm with
  | PrimApp (`Add, [arg1; arg2]) ->
      Format.fprintf fmt "@[%a@ +@ %a@]"
        (pp_mul_tm names) arg1
        (pp_add_tm names) arg2
  | PrimApp (`Sub, [arg1; arg2]) ->
      Format.fprintf fmt "@[%a@ -@ %a@]"
        (pp_mul_tm names) arg1
        (pp_add_tm names) arg2
  | tm ->
      pp_mul_tm names fmt tm
and pp_mul_tm names fmt tm =
  match tm with
  | PrimApp (`Mul, [arg1; arg2]) ->
      Format.fprintf fmt "@[%a@ *@ %a@]"
        (pp_app_tm names) arg1
        (pp_mul_tm names) arg2
  | tm ->
      pp_app_tm names fmt tm
and pp_app_tm names fmt tm =
  match tm with
  | FunApp (head, arg) ->
      Format.fprintf fmt "@[%a@ %a@]"
        (pp_app_tm names) head
        (pp_atomic_tm names) arg
  | PrimApp (`Neg, [arg]) ->
      Format.fprintf fmt "@[-%a@]"
        (pp_atomic_tm names) arg
  | tm ->
      pp_atomic_tm names fmt tm
and pp_atomic_tm names fmt tm =
  match tm with
  | Var index -> Format.fprintf fmt "%s" (List.nth names index)
  | BoolLit true -> Format.fprintf fmt "true"
  | BoolLit false -> Format.fprintf fmt "false"
  | IntLit i -> Format.fprintf fmt "%i" i
  (* FIXME: Will loop forever on invalid primitive applications *)
  | tm -> Format.fprintf fmt "@[(%a)@]" (pp_tm names) tm
