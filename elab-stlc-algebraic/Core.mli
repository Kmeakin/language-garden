(** The core language. *)

module Void := Basis.Void


type name = string
(** These names are used as hints for pretty printing binders and variables,
    but don’t impact the equality of terms. *)


(** {1 Syntax} *)

type ty =
  | A
  | B
  | C
  | FunTy of ty * ty

type tm

(** {2 Pretty printing} *)

val pp_ty : Format.formatter -> ty -> unit
val pp_tm : Format.formatter -> tm -> unit


(** {1 Elaboration effect} *)

type ('a, 'e) elab_err
type 'a elab = ('a, Void.t) elab_err

val run_err : ('a, 'e) elab_err -> ('a, 'e) result
val run : 'a elab -> 'a

(** {2 Error handling} *)

val fail : 'e -> ('a, 'e) elab_err
val handle : ('e1 -> ('a, 'e2) elab_err) -> ('a, 'e1) elab_err ->  ('a, 'e2) elab_err
val handle_absurd : 'a elab -> ('a, 'e2) elab_err


(** {1 Forms of judgement} *)

type var

type check = ty -> tm elab
type synth = (tm * ty) elab

type 'e check_err = ty -> (tm, 'e) elab_err
type 'e synth_err = (tm * ty, 'e) elab_err


(** {1 Inference rules} *)

(** {2 Directional rules} *)

val conv : synth -> [> `TypeMismatch of ty * ty] check_err
val ann : check -> ty -> synth

(** {2 Structural rules} *)

val var : var -> [> `UnboundVar] synth_err
val let_synth : name * ty * check -> (var -> synth) -> synth
val let_check : name * ty * check -> (var -> check) -> check

(** {2 Function rules} *)

val fun_intro_check : name -> (var -> check) -> [> `UnexpectedFunLit] check_err
val fun_intro_synth : name * ty -> (var -> synth) -> synth
val fun_elim : synth -> synth -> [> `UnexpectedArg of ty  | `TypeMismatch of ty * ty] synth_err
