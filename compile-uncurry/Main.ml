(** Split the list at a given index  *)
let split_at (n : int) (xs : 'a list) : ('a list * 'a list) option =
  if n < 0 then invalid_arg "split_at" else
  let rec go n xs =
    match n, xs with
    | 0, xs -> Some ([], xs)
    | n, x :: xs ->
        go (n - 1) xs |> Option.map (fun (xs, ys) -> x :: xs, ys)
    | _, [] -> None
  in
  go n xs


(** These names are used as hints for pretty printing binders and variables. *)
type name = string

(** De Bruijn index, counting variables from the most recently bound to the
    least recently bound. *)
type index = int

(** De Bruijn level, counting variables from the least recently bound to the
    most recently bound. *)
type level = int

(** Convert a De Bruijn level to a De Bruijn index using the number of bindings
    the environment where the index will be used. *)
let level_to_index size level =
  size - level - 1


(** A language where all functions take a single argument *)
module Curried = struct

  type expr =
    | Var of index
    | Let of name * expr * expr
    | FunLit of name * expr
    | FunApp of expr * expr


  (** Return the list of parameters of a series of nested function literals,
      along with the body of that expression. *)
  let rec fun_lits : expr -> name list * expr =
    function
    | FunLit (name, body) ->
        let params, body = fun_lits body in
        name :: params, body
    | body -> [], body

  (** Return the head of a series of function applications and a list of the
      arguments that it was applied to. *)
  let rec fun_apps : expr -> expr * expr list =
    function
    | FunApp (head, arg) ->
        let head, args = fun_apps head in
        head, args @ [arg]
    | head -> head, []


  (** Pretty print an expression *)
  let rec pp_expr names fmt =
    let pp_parens ?(wrap = false) names fmt = function
      | (Let _ | FunLit _ | FunApp _) as expr when wrap ->
          Format.fprintf fmt "@[(%a)@]" (pp_expr names) expr
      | expr -> pp_expr names fmt expr
    in
    function
    | Var index ->
        Format.pp_print_string fmt (List.nth names index)
    | Let (name, def, body) ->
        let pp_name_def names fmt (name, def) =
          Format.fprintf fmt "@[let@ %s@ :=@]@ %a;" name (pp_expr names) def
        and pp_lets names fmt = function
          | Let (_, _, _) as expr -> pp_expr names fmt expr
          | expr -> Format.fprintf fmt "@[%a@]" (pp_expr names) expr
        in
        Format.fprintf fmt "@[<2>%a@]@ %a"
          (pp_name_def names) (name, def)
          (pp_lets (name :: names)) body
    | FunLit (_, _) as expr ->
        let pp_sep fmt () = Format.fprintf fmt "@ " in
        let params, body = fun_lits expr in
        Format.fprintf fmt "@[<2>@[<4>fun@ %a@ :=@]@ @[%a@]@]"
          (Format.pp_print_list ~pp_sep Format.pp_print_string) params
          (pp_expr (List.rev params @ names)) body
    | FunApp (_, _) as expr ->
        let pp_sep fmt () = Format.fprintf fmt "@ " in
        let head, args = fun_apps expr in
        Format.fprintf fmt "@[<2>%a@ %a@]"
          (pp_parens ~wrap:true names) head
          (Format.pp_print_list ~pp_sep (pp_parens ~wrap:true names)) args

end


(** A language with multi-parameter functions *)
module Uncurried = struct

  type expr =
    | Var of index * int
    (*       ^^^^^   ^^^
             |       |
             |       index into the scope’s parameter list
             |
             scope index
    *)
    | Let of name * expr * expr
    | FunLit of name list * expr
    | FunApp of expr * expr list

  (* Variables are representated with a De Bruijn index pointing to the scope
     where the variable was bound and the position of the binder in the scope's
     parameter list. For example:

     fun (a, b, c) :=
        let foo := c;
                   ^ 0, 2
        foo
        ^^^ 0, 0
  *)


  (** Pretty print an expression *)
  let rec pp_expr names fmt = function
    | Var (scope, param) ->
        Format.pp_print_string fmt (List.nth (List.nth names scope) param)
    | Let (name, def, body) ->
        let pp_name_def names fmt (name, def) =
          Format.fprintf fmt "@[let@ %s@ :=@]@ %a;" name (pp_expr names) def
        and pp_lets names fmt = function
          | Let (_, _, _) as expr -> pp_expr names fmt expr
          | expr -> Format.fprintf fmt "@[%a@]" (pp_expr names) expr
        in
        Format.fprintf fmt "@[<2>%a@]@ %a"
          (pp_name_def names) (name, def)
          (pp_lets ([name] :: names)) body
    | FunLit (params, body) ->
        let pp_sep fmt () = Format.fprintf fmt ",@ " in
        Format.fprintf fmt "@[<2>@[fun@ @[(%a)@]@ :=@]@ %a@]"
          (Format.pp_print_list ~pp_sep Format.pp_print_string) params
          (pp_expr (params :: names)) body
    | FunApp (head, args) ->
        let pp_sep fmt () = Format.fprintf fmt ",@ " in
        Format.fprintf fmt "%a(%a)"
          (pp_expr names) head
          (Format.pp_print_list ~pp_sep (pp_expr names)) args

end


module CurriedToUncurried = struct

  type binding = {
    var : level * int;    (** The scope level and parameter index of this binding *)
    arities : int list;   (** A list of arities this binding accepts *)
  }

  (** An environment that maps variable indexes in the core language to
      variables in the uncurried language. *)
  type env = {
    size : level;               (** The number of scopes that have been bound *)
    bindings : binding list;
  }

  (** The size field lets us convert the scope levels to scope indicies when
      translating variables.

      Note that the size of the environment does not neccessarily match the
      number of bindings in the envrionment, as multiple bindings can be
      introduced per scope in the uncurried language.
  *)

  (** An empty environment with no bindings *)
  let empty_env = {
    size = 0;
    bindings = [];
  }

  (** Add a new scope that binds a single definition with a given arity *)
  let bind_def env arities = {
    size = env.size + 1;
    bindings = { var = env.size, 0; arities } :: env.bindings;
  }

  (** Add a new scope that binds a sequence of parameters *)
  let bind_params env params =
    (* Add the bindings the environment, mapping each parameter to positions in
       a single parameter list. *)
    let rec go param bindings = function
      | [] -> bindings
      | _ :: params ->
          let var = env.size, param in
          go (param + 1) ({ var; arities = [] } :: bindings) params
          (*                               ^^ We might be able to pull the arity from the type
                                              of the parameter, if we had types? This would
                                              fail in the case of polymorphic types, however.
          *)
    in
    {
      (* We’re only adding a single scope, so we only need to increment the size
         of the environment once. *)
      size = env.size + 1;
      bindings = go 0 env.bindings params;
    }

  (** Collect a list of expected arities, based on what can be seen from
      function literals, and the arities of variables in the environment. *)
  let rec lookup_arities env : Curried.expr -> int list =
    function
    | Curried.Var index -> (List.nth env.bindings index).arities
    | Curried.FunLit (_, _) as expr ->
        let (params, body) = Curried.fun_lits expr in
        lookup_arities (bind_params env params) body @ [List.length params]
    | _ -> []

  let rec translate env : Curried.expr -> Uncurried.expr =
    function
    | Curried.Var index ->
        let { var = level, param; _ } = List.nth env.bindings index in
        let index = level_to_index env.size level in
        Var (index, param)

    | Curried.Let (name, def, body) ->
        let def_arity = lookup_arities env def in
        let def = translate env def in
        let body = translate (bind_def env def_arity) body in
        Let (name, def, body)

    | Curried.FunLit (_, _) as expr ->
        let params, body = Curried.fun_lits expr in
        let env = bind_params env params in
        FunLit (params, translate env body)

    (* Translate function applications to multiple argument lists,
        eg. [f a b c d e] to [f(a, b)(c)(d, e)] *)
    | Curried.FunApp _ as expr ->
        let rec go head arities args =
          match arities with
          | arity :: arities ->
              begin match split_at arity args with
              | Some ([], args) -> go head arities args
              | Some (args, args') ->
                  let args = List.map (translate env) args in
                  go (Uncurried.FunApp (head, args)) arities args'
              (* Could we wrap with a function literal here? *)
              | None -> failwith "error: under-application"
              end
          | [] ->
              begin match args with
              | _ :: _ -> failwith "error: over-application"
              | [] -> head
              end
        in
        let head, args = Curried.fun_apps expr in
        go (translate env head) (lookup_arities env head) args

end


let () =
  Printexc.record_backtrace true;

  (* TODO: Parser and proper tests *)

  let term = Curried.(
    FunLit ("a", FunLit ("b", FunLit ("c",
      Let ("a'", Var 2,
      Let ("b'", Var 2,
      Let ("c'", Var 2,
      Let ("foo", Var 3,
        Var 3)))))))) in

  Format.printf "@[%a@]\n" (Curried.pp_expr []) term;

  let term = CurriedToUncurried.(translate empty_env term) in

  Format.printf "@[%a@]\n" (Uncurried.pp_expr []) term;

  ()
