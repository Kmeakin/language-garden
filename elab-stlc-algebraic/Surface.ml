(** {1 Syntax} *)

(** The start and end position in a source file *)
type loc =
  Lexing.position * Lexing.position

(** Located nodes *)
type 'a located = {
  loc : loc;
  data : 'a;
}

type ty = Core.ty =
  | A
  | B
  | C
  | FunTy of ty * ty

type tm =
  tm_data located
and tm_data =
  | Var of string
  | Ann of tm * ty
  | Let of string located * ty * tm * tm
  | FunLit of string located * ty option * tm
  | FunApp of tm * tm


(** {1 Elaboration} *)

(* TODO: collect errors instead of failing at the first error *)

exception Error of loc * string
exception Bug of loc * string

let error loc msg = raise (Error (loc, msg))
let bug loc msg = raise (Bug (loc, msg))

type context = (string * Core.var) list

let rec check (ctx : context) (tm : tm) : Core.check =
  fun ty ->
    match tm.data with
    | Let (n, def_ty, def_tm, body_tm) ->
        Core.let_check
          (n.data, def_ty, check ctx def_tm)
          (fun v -> check ((n.data, v) :: ctx) body_tm)
          ty
    | FunLit (n, None, body_tm) ->
        Core.fun_intro_check n.data (fun v -> check ((n.data, v) :: ctx) body_tm) ty
        |> Core.handle (function
          | Core.UnexpectedFunLit ->
              error tm.loc
                (Format.asprintf "found function, expected `%a`"
                  Core.pp_ty ty)
          | _ -> None)
    | FunLit (n, Some param_ty, body_tm) -> begin
        (* TODO: this feels messy :[ *)
        match ty with
        | FunTy (param_ty', _) when param_ty' = param_ty ->
            Core.fun_intro_check n.data (fun v -> check ((n.data, v) :: ctx) body_tm) ty
            |> Core.handle (function
              | Core.UnexpectedFunLit -> bug tm.loc "unexpected function literal"
              | _ -> None)
        | FunTy (param_ty', _) ->
            error n.loc
              (Format.asprintf "unexpected parameter type, found `%a`, expected: `%a`"
                Core.pp_ty param_ty
                Core.pp_ty param_ty')
        | ty ->
            error tm.loc
              (Format.asprintf "found function, expected: `%a`"
                Core.pp_ty ty)
    end
    | _ ->
        Core.conv (synth ctx tm) ty
        |> Core.handle (function
          | Core.TypeMismatch { found_ty; expected_ty } ->
              error tm.loc
                (Format.asprintf "type mismatch, found `%a` expected `%a`"
                  Core.pp_ty expected_ty
                  Core.pp_ty found_ty)
          | _ -> None)

and synth (ctx : context) (tm : tm) : Core.synth =
  match tm.data with
  | Var n -> begin
      match List.assoc_opt n ctx with
      | Some i ->
          Core.var i
          |> Core.handle (function
            | Core.UnboundVar -> bug tm.loc "unbound core variable"
            | _ -> None)
      | None ->
          error tm.loc (Format.asprintf "unbound variable `%s`" n)
  end
  | Ann (tm, ty) ->
      Core.ann (check ctx tm) ty
  | Let (n, def_ty, def_tm, body_tm) ->
      Core.let_synth
        (n.data, def_ty, check ctx def_tm)
        (fun v -> synth ((n.data, v) :: ctx) body_tm)
  | FunLit (n, None, _) ->
      error n.loc "annotation required"
  | FunLit (n, Some param_ty, body_tm) ->
      Core.fun_intro_synth
        (n.data, param_ty)
        (fun v -> synth ((n.data, v) :: ctx) body_tm)
  | FunApp (head_tm, arg_tm) ->
      Core.fun_elim (synth ctx head_tm) (synth ctx arg_tm)
      |> Core.handle (function
        | Core.UnexpectedArg { head_ty } ->
            error head_tm.loc
              (Format.asprintf "unexpected argument applied to `%a`"
                Core.pp_ty head_ty)
        | Core.TypeMismatch { found_ty; expected_ty } ->
          error arg_tm.loc
            (Format.asprintf "mismatched argument type, found `%a` expected `%a`"
              Core.pp_ty expected_ty
              Core.pp_ty found_ty)
        | _ -> None)

let elab_check (tm : tm) (ty : ty) : Core.tm =
  Core.run (check [] tm ty)

let elab_synth (tm : tm) : Core.tm * Core.ty =
  Core.run (synth [] tm)
