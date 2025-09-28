; Text object queries for Ghostlang
; These help Grove with smart text selection and navigation

; Functions
(function_declaration) @function.outer
(function_declaration body: (_) @function.inner)

; Blocks
(block_statement) @block.outer
(block_statement
  "{" @_start
  "}" @_end
  (#make-range! "block.inner" @_start @_end))

; Conditional statements
(if_statement) @conditional.outer
(if_statement then: (_) @conditional.inner)
(if_statement else: (_) @conditional.inner)

; Loops
(while_statement) @loop.outer
(while_statement body: (_) @loop.inner)
(for_statement) @loop.outer
(for_statement body: (_) @loop.inner)

; Function calls
(call_expression) @call.outer
(call_expression arguments: (_) @call.inner)

; Parameters
(parameter_list) @parameter.outer
(parameter_list
  "(" @_start
  ")" @_end
  (#make-range! "parameter.inner" @_start @_end))

; Arguments
(argument_list) @argument.outer
(argument_list
  "(" @_start
  ")" @_end
  (#make-range! "argument.inner" @_start @_end))

; Object literals
(object_literal) @object.outer
(object_literal
  "{" @_start
  "}" @_end
  (#make-range! "object.inner" @_start @_end))

; Array literals
(array_literal) @array.outer
(array_literal
  "[" @_start
  "]" @_end
  (#make-range! "array.inner" @_start @_end))

; String literals
(string_literal) @string.outer
(string_literal) @string.inner

; Comments
(comment) @comment.outer
(comment) @comment.inner