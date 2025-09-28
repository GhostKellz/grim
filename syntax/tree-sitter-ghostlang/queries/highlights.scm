; Syntax highlighting queries for Ghostlang
; These queries define how Grove should highlight different syntax elements

; Keywords
[
  "var"
  "function"
  "if"
  "else"
  "while"
  "for"
  "in"
  "return"
  "true"
  "false"
] @keyword

; Operators
[
  "="
  "+="
  "-="
  "*="
  "/="
  "+"
  "-"
  "*"
  "/"
  "%"
  "=="
  "!="
  "<"
  ">"
  "<="
  ">="
  "&&"
  "||"
  "!"
  "?"
  ":"
] @operator

; Punctuation
[
  ";"
  ","
  "."
] @punctuation.delimiter

; Brackets
[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

; Function names
(function_declaration
  name: (identifier) @function)

(call_expression
  function: (postfix_expression
    (primary_expression
      (identifier) @function.call)))

(call_expression
  function: (postfix_expression
    (member_expression
      property: (identifier) @function.call)))

; Parameters
(parameter_list
  (identifier) @parameter)

; Variables
(variable_declaration
  name: (identifier) @variable)

(assignment_expression
  left: (postfix_expression
    (primary_expression
      (identifier) @variable)))

; Properties and methods
(member_expression
  property: (identifier) @property)

; Object keys
(object_member
  (identifier) @property)

; Literals
(number_literal) @number
(string_literal) @string
(boolean_literal) @boolean
(null_literal) @constant.builtin

; Comments
(comment) @comment

; Built-in functions (common editor APIs)
((identifier) @function.builtin
 (#match? @function.builtin "^(getCurrentLine|getLineText|setLineText|insertText|getAllText|replaceAllText|getCursorPosition|setCursorPosition|getSelection|setSelection|getSelectedText|replaceSelection|getFilename|getFileLanguage|isModified|notify|log|prompt|findAll|replaceAll|split|join|substring|indexOf|replace|createArray|arrayPush|arrayLength|arrayGet|createObject|objectSet|objectGet)$"))

; String interpolation and escapes
(escape_sequence) @string.escape

; Error highlighting for undefined constructs
(ERROR) @error