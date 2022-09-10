A number
  $ compile-arith <<< "1"
  code  = 1
  tree  = 1
  stack = 1

Negating numbers
  $ compile-arith <<< "-32"
  code  = 32 neg
  tree  = -32
  stack = -32

Adding numbers
  $ compile-arith <<< "1 + 2"
  code  = 1 2 add
  tree  = 3
  stack = 3

Subtracting numbers
  $ compile-arith <<< "1 - 2"
  code  = 1 2 sub
  tree  = -1
  stack = -1

Multiplying numbers
  $ compile-arith <<< "1 * 2"
  code  = 1 2 mul
  tree  = 2
  stack = 2

Dividing numbers
  $ compile-arith <<< "1 / 2"
  code  = 1 2 div
  tree  = 0
  stack = 0

Complicated stuff
  $ compile-arith <<< "1 * -2 + (3 + 4) - 8 / 4"
  code  = 1 2 neg mul 3 4 add 8 4 div sub add
  tree  = 3
  stack = 3

Something broken
  $ compile-arith <<< "1 + 2 + (3 +"
  <input>:1:13: syntax error
  [1]