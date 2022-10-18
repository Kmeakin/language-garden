module Functor = struct

  module type S = sig

    type 'a t

    val map : ('a -> 'b) -> 'a t -> 'b t

  end


  (** Operators to make working with functors more pleasant *)
  module type Notation = sig

    type 'a t

    val ( let+ ) : 'a t -> ('a -> 'b) -> 'b t

  end


  module Notation (F : S) : Notation

    with type 'a t = 'a F.t

  = struct

    type 'a t = 'a F.t

    let ( let+ ) t f = F.map f t

  end

end


module Monad = struct

  module type S = sig

    type 'a t

    include Functor.S with type 'a t := 'a t

    val pure : 'a -> 'a t
    val bind : 'a t -> ('a -> 'b t) -> 'b t

  end


  (** Operators to make working with monads more pleasant *)
  module type Notation = sig

    type 'a t

    include Functor.Notation with type 'a t := 'a t

    val ( let* ) : 'a t -> ('a -> 'b t) -> 'b t
    val ( and* ) : 'a t -> 'b t -> ('a * 'b) t
    val ( and+ ) : 'a t -> 'b t -> ('a * 'b) t

  end


  module Notation (M : S) : Notation

    with type 'a t = 'a M.t

  = struct

    include Functor.Notation (M)

    let ( let* ) = M.bind

    let ( and* ) t n =
      let* x = t in
      let* y = n in
      M.pure (x, y)

    let ( and+ ) t n = ( and* ) t n

  end


  (** Utility functions derived from a monad *)
  module Util (M : S) = struct

    open Notation (M)

    let map2 f x1 x2 =
      let* x1 = x1 in
      let* x2 = x2 in
      M.pure (f x1 x2)

    let map3 f x1 x2 x3 =
      let* x1 = x1 in
      let* x2 = x2 in
      let* x3 = x3 in
      M.pure (f x1 x2 x3)

    let map4 f x1 x2 x3 x4 =
      let* x1 = x1 in
      let* x2 = x2 in
      let* x3 = x3 in
      let* x4 = x4 in
      M.pure (f x1 x2 x3 x4)

  end


  (** An environment with access to a shared value *)
  module type Reader = sig

    type value

    include S

    (** Access the shared value *)
    val read : value t

    (** Execute a computation in an environment that has been altered by a function *)
    val scope : (value -> value) -> 'a t -> 'a t

    (** Run a computation with the value *)
    val run : value -> 'a t -> 'a

  end


  (** A reader implemented for functions *)
  module FunctionReader (V : sig type t end) : Reader

    with type value = V.t
    with type 'a t = V.t -> 'a

  = struct

    type value = V.t

    type 'a t = value -> 'a

    let map f x = fun v ->  f (x v)
    let bind t f = fun v -> f (t v) v
    let pure v = fun _ -> v

    let read = fun v -> v
    let scope f t = fun v -> t (f v)

    let run v t = t v

  end


  (** A reader with an abstract implementation *)
  module Reader (V : sig type t end) : Reader with type value = V.t =
    FunctionReader (V)


  (** An environment that can access and update some shared state *)
  module type State = sig

    type state

    include S

    (** Access the shared state from the environment *)
    val get : state t

    (** Replace the shared state of the environment *)
    val put : state -> unit t

    (** Embed a state action in the environment *)
    val embed : (state -> 'a * state) -> 'a t

    (** Run a stateful computation using an initial state.
        This is the inverse of the {!state} function. *)
    val run : 'a t -> state -> 'a * state

  end


  (** A state monad implemented for functions *)
  module FunctionState (S : sig type t end) : State

    with type state = S.t
    with type 'a t = S.t -> 'a * S.t

  = struct

    type state = S.t

    type 'a t = state -> 'a * state

    let map f x = fun s ->
      let x, s = x s in
      f x, s

    let bind x f = fun s ->
      let x', s = x s in
      f x' s

    let pure x = fun s -> x, s

    let get = fun s -> s, s
    let put s = fun _ -> (), s

    let embed f = fun s -> f s
    let run x s = x s

  end


  (** A state monad with an abstract implementation *)
  module State (S : sig type t end) : State with type state = S.t =
    FunctionState (S)

end
