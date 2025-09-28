; Local scope queries for Ghostlang
; These help Grove understand variable scoping and references

; Scopes
(source_file) @local.scope
(function_declaration body: (_) @local.scope)
(block_statement) @local.scope

; Function definitions create their own scope
(function_declaration
  name: (identifier) @local.definition.function
  body: (_) @local.scope)

; Variable definitions
(variable_declaration
  name: (identifier) @local.definition.variable)

; Parameter definitions
(parameter_list
  (identifier) @local.definition.parameter)

; Variable references
(identifier) @local.reference

; Member access doesn't count as variable reference
(member_expression
  property: (identifier) @_not_reference)

; Function calls - function name is a reference
(call_expression
  function: (postfix_expression
    (primary_expression
      (identifier) @local.reference)))

; Assignment targets are references (they must exist)
(assignment_expression
  left: (postfix_expression
    (primary_expression
      (identifier) @local.reference)))