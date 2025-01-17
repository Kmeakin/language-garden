# Simply typed lambda calculus with recursive let bindings

Extends [**elab-stlc-unification**](../elab-stlc-unification).

This is an implementation of recursive let bindings for the simply typed lambda
calculus. These are elaborated to a primitive fixed-point combinator in the core
language. Mutually recursive let bindings are elaborated to fixed-points over
tuples of functions.

Due to the introduction of general recursion to the language, care must be taken
when implementing quotation, as the naive approach will lead to infinite loops
when quoting under-applied recursive definitions. To avoid this, we disable the
unfolding of recursive definitions during quotation.

Thanks goes to [Karl Meakin](https://github.com/Kmeakin) for help in exploring
different approaches and pointing out bugs in my initial implementations.

## Project overview

| Module        | Description                             |
| ------------- | --------------------------------------- |
| [`Main`]      | Command line interface                  |
| [`Lexer`]     | Lexer for the surface language          |
| [`Parser`]    | Parser for the surface language         |
| [`Surface`]   | Surface language, including elaboration |
| [`Core`]      | Core language, including normalisation, unification, and pretty printing |

[`Main`]: ./Main.ml
[`Lexer`]: ./Lexer.mll
[`Parser`]: ./Parser.mly
[`Surface`]: ./Surface.ml
[`Core`]: ./Core.ml

## Todo list

- [x] singly recursive bindings
- [x] mutually recursive bindings
- [ ] optional fuel/recursion limit

## Resources

- [Many faces of the fixed-point combinator](https://okmij.org/ftp/Computation/fixed-point-combinators.html)
  by Oleg Kiselyov.
- [Fixed-point combinator](https://en.wikipedia.org/wiki/Fixed-point_combinator) on Wikipedia
- [Mutual recursion](https://en.wikipedia.org/wiki/Mutual_recursion) on Wikipedia

Some other approaches to combining fixed points with normalisation-by-evaluation
(assuming totality checking) can be found here:

- [A Compiled Implementation of Strong Reduction](https://xavierleroy.org/publi/strong-reduction.pdf)
  by Benjamin Grégoire and Xavier Leroy.
- [A simple type-theoretic language: Mini-TT](https://web.archive.org/web/20220208175952/https://www.cse.chalmers.se/~bengt/papers/GKminiTT.pdf)
  by Thierry Coquand et. al.

## Examples

More examples can be found in [`tests.t`](tests.t).

### Factorial function

Singly recursive functions are elaborated to fixed-points in the core language.

<!-- $MDX file=examples/fact.txt -->
```
-- An example of a singly recursive definition

let rec fact n :=
  if n = 0 then 1 else n * fact (n - 1);

fact 5
```

Elaborated program:

<!-- $MDX file=examples/fact.stdout -->
```
let fact : Int -> Int :=
  #fix (fact : Int -> Int) =>
    fun (n : Int) => if n = 0 then 1 else n * fact (n - 1);
fact 5 : Int
```

### Even and odd functions

Mutually recursive functions are elaborated to fixed-points using tuples:

<!-- $MDX file=examples/even-odd.txt -->
```
-- An example of mutually recursive definitions

let rec is-even n :=
      if n = 0 then true else is-odd (n - 1);
    rec is-odd n :=
      if n = 0 then false else is-even (n - 1);

is-even 6
```

Elaborated program:

<!-- $MDX file=examples/even-odd.stdout -->
```
let $is-even-is-odd : (Int -> Bool, Int -> Bool) :=
  #fix ($is-even-is-odd : (Int -> Bool, Int -> Bool)) =>
    (fun (n : Int) => if n = 0 then true else $is-even-is-odd.1 (n - 1),
    fun (n : Int) => if n = 0 then false else $is-even-is-odd.0 (n - 1));
$is-even-is-odd.0 6 : Bool
```
