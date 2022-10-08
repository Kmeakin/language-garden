module TreeLang = struct
  include TreeLang

  module Lexer = TreeLangLexer
  module Parser = TreeLangParser
end

module StackLang = StackLang
module AnfLang = AnfLang

module TreeToStack = TreeToStack
module TreeToAnf = TreeToAnf
