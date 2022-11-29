module Ns = Core.Ns
module Syntax = Core.Syntax
module Semantics = Core.Semantics


type var = {
  ty : Semantics.vty;
  level : Ns.tm Env.level;
}


module Context = struct

  type t = {
    size : Ns.tm Env.size;
    names : (Ns.tm, Core.name) Env.t;
    tys : (Ns.tm, Semantics.vty) Env.t;
    tms : (Ns.tm, Semantics.vtm) Env.t;
  }


  let empty = {
    size = Env.empty_size;
    names = Env.empty;
    tys = Env.empty;
    tms = Env.empty;
  }

  let extend (ctx : t) (name : Core.name) (vty : Semantics.vty) (vtm : Semantics.vtm) = {
    size = ctx.size |> Env.bind_level;
    names = ctx.names |> Env.bind_entry name;
    tys = ctx.tys |> Env.bind_entry vty;
    tms = ctx.tms |> Env.bind_entry vtm;
  }

  let lookup (ctx : t) (name : Core.name) : (Semantics.vty * Ns.tm Env.index) option =
    Env.entry_index name ctx.names
      |> Option.map (fun x -> ctx.tys |> Env.lookup x, x)


  (** Run a continuation with a definition added to the context *)
  let define (ctx : t) (name : Core.name) (ty : Semantics.vty) (tm : Semantics.vtm) (body : t -> var -> 'a) : 'a =
    let level = Env.next_level ctx.size in
    body (extend ctx name ty tm) { ty; level }

  (** Run a continuation with an assumption added to the context *)
  let assume (ctx : t) (name : Core.name) (ty : Semantics.vty) (body : t -> var -> 'a) : 'a =
    let level = Env.next_level ctx.size in
    body (extend ctx name ty (Neu (Var level))) { ty; level }


  let eval (ctx : t) (tm : Syntax.tm) : Semantics.vtm =
    Semantics.eval ctx.tms tm

  let quote (ctx : t) (vtm : Semantics.vtm) : Syntax.tm =
    Semantics.quote ctx.size vtm

  let is_convertible (ctx : t) (v0 : Semantics.vtm) (v1 : Semantics.vtm) : bool =
    Semantics.is_convertible ctx.size (v0, v1)

end


type is_ty =
  Context.t -> Core.Level.t * Syntax.tm

type synth =
  Context.t -> Semantics.vty * Syntax.tm

type check =
  Context.t -> Semantics.vty -> Syntax.tm


let run_is_ty (ty : is_ty) : Core.Level.t * Syntax.tm =
  ty Context.empty

let run_check (expected_ty : Semantics.vty) (tm : check) : Syntax.tm =
  tm Context.empty expected_ty

let run_synth (tm : synth) : Semantics.vty * Syntax.tm =
  tm Context.empty


exception Error of string


let var (x : var) : synth =
  fun ctx ->
    x.ty, Var (Env.level_to_index ctx.size x.level)

let ann ~(ty : is_ty) (tm : check) : synth =
  fun ctx ->
    let _, ty = ty ctx in
    let vty = Context.eval ctx ty in
    (vty, tm ctx vty)

let is_ty (tm : synth) : is_ty =
  fun ctx ->
    match tm ctx with
    | Univ l1, tm -> l1, tm
    | _, _ -> raise (Error "not a type")

let check (tm : synth) : check =
  fun ctx expected_ty ->
    let (ty, tm) = tm ctx in
    if Context.is_convertible ctx ty expected_ty then tm else
      raise (Error "type mismatch")


module Structure = struct

  let name (x : string) : synth =
    fun ctx ->
      match Context.lookup ctx (Some x) with
      | Some (ty, x) -> ty, Syntax.Var x
      | None -> raise (Error ("'" ^ x ^ "' was not bound in scope"))

  let let_synth ?name (def : synth) (body : synth -> synth) : synth =
    fun ctx ->
      let def_vty, def = def ctx in
      Context.define ctx name def_vty (Context.eval ctx def)
        (fun ctx x ->
          let body_ty, body = body (var x) ctx in
          body_ty, Syntax.Let (name, def, body))

  let let_check ?name (def : synth) (body : synth -> check) : check =
    fun ctx body_ty ->
      let def_vty, def = def ctx in
      Context.define ctx name def_vty (Context.eval ctx def)
        (fun ctx x ->
          Syntax.Let (name, def, body (var x) ctx body_ty))

end


module Fun = struct

  let form ?name (param_ty : is_ty) (body_ty : synth -> is_ty) : is_ty =
    fun ctx ->
      let l1, param_ty = param_ty ctx in
      Context.assume ctx name (Context.eval ctx param_ty)
        (fun ctx x ->
          let l2, body_ty = body_ty (var x) ctx in
          Core.Level.max l1 l2, Syntax.FunType (name, param_ty, body_ty))

  (* TODO: optional paramter type *)
  let intro_synth ?name (param_ty : is_ty) (body : synth -> synth) : synth =
    fun ctx ->
      let _, param_ty = param_ty ctx in
      let body_ty, body =
        Context.assume ctx name (Context.eval ctx param_ty)
          (fun ctx x ->
            let body_ty, body = body (var x) ctx in
            Context.quote ctx body_ty, body)
      in
      Context.eval ctx (Syntax.FunType (name, param_ty, body_ty)),
      Syntax.FunLit (name, param_ty, body)

  (* TODO: optional paramter type *)
  let intro_check ?name (body : synth -> check) : check =
    fun ctx ->
      function
      (* TODO: Check param type matches *)
      | Semantics.FunType (_, param_vty, body_ty) ->
          let param_ty = Context.quote ctx (Lazy.force param_vty) in
          Context.assume ctx name (Lazy.force param_vty)
            (fun ctx x ->
              let x = var x in
              let body_ty = body_ty (Context.eval ctx (x ctx |> snd)) in
              Syntax.FunLit (name, param_ty, body x ctx body_ty))
      | _ -> raise (Error "not a function type")

  let app (head : synth) (arg : check) : synth =
    fun ctx ->
      match head ctx with
      | Semantics.FunType (_, param_ty, body_ty), head ->
          let arg = arg ctx (Lazy.force param_ty) in
          let body_ty = body_ty (Context.eval ctx arg) in
          body_ty, Syntax.FunApp (head, arg)
      | _, _ -> raise (Error "expected a function type")

end


module Univ = struct

  let form (l : Core.Level.t) : is_ty =
    fun _ ->
      match l with
      | L0 -> L1, Univ L0
      | L1 -> raise (Error "Type 1 has no type")

  let univ (l : Core.Level.t) : synth =
    fun _ ->
      match l with
      | L0 -> Univ L1, Univ L0
      | L1 -> raise (Error "Type 1 has no type")

  let fun_ ?name (param_ty : synth) (body_ty : synth -> synth) : synth =
    fun ctx ->
      let l1, param_ty = is_ty param_ty ctx in
      Context.assume ctx name (Context.eval ctx param_ty)
        (fun ctx x ->
          let l2, body_ty = is_ty (body_ty (var x)) ctx in
          Semantics.Univ (Core.Level.max l1 l2),
          Syntax.FunType (name, param_ty, body_ty))

end
