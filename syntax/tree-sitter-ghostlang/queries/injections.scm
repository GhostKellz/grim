; Injection queries for Ghostlang
; These allow Grove to highlight embedded languages within Ghostlang strings

; Regular expressions in string literals (for pattern matching)
((string_literal) @injection.content
 (#match? @injection.content "^[\"']/.*?/[gimuy]*[\"']$")
 (#set! injection.language "regex")
 (#set! injection.include-children))

; JSON in object literals or string literals
((object_literal) @injection.content
 (#set! injection.language "json")
 (#set! injection.include-children))

; SQL queries in string literals (common in editor plugins)
((string_literal) @injection.content
 (#match? @injection.content "(?i)(select|insert|update|delete|create|drop|alter)")
 (#set! injection.language "sql")
 (#set! injection.include-children))

; CSS in string literals (for style manipulation)
((string_literal) @injection.content
 (#match? @injection.content "(?i)(color|background|font|margin|padding|border)")
 (#set! injection.language "css")
 (#set! injection.include-children))

; Shell commands in string literals
((string_literal) @injection.content
 (#match? @injection.content "^[\"'](cd|ls|grep|find|cat|echo|git)")
 (#set! injection.language "bash")
 (#set! injection.include-children))