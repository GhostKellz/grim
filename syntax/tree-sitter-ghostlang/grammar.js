// Tree-sitter grammar for Ghostlang
// Based on the syntax demonstrated in the plugin examples

module.exports = grammar({
  name: 'ghostlang',

  rules: {
    source_file: $ => repeat($.statement),

    statement: $ => choice(
      $.variable_declaration,
      $.function_declaration,
      $.if_statement,
      $.while_statement,
      $.for_statement,
      $.expression_statement,
      $.block_statement,
      $.return_statement,
      $.empty_statement
    ),

    // Variable declarations: var x = 5;
    variable_declaration: $ => seq(
      'var',
      field('name', $.identifier),
      '=',
      field('value', $.expression),
      ';'
    ),

    // Function declarations: function name() { ... }
    function_declaration: $ => seq(
      'function',
      field('name', $.identifier),
      field('parameters', $.parameter_list),
      field('body', $.block_statement)
    ),

    parameter_list: $ => seq(
      '(',
      optional(seq(
        $.identifier,
        repeat(seq(',', $.identifier))
      )),
      ')'
    ),

    // Control flow statements
    if_statement: $ => prec.right(seq(
      'if',
      '(',
      field('condition', $.expression),
      ')',
      field('then', $.statement),
      optional(seq('else', field('else', $.statement)))
    )),

    while_statement: $ => seq(
      'while',
      '(',
      field('condition', $.expression),
      ')',
      field('body', $.statement)
    ),

    for_statement: $ => seq(
      'for',
      '(',
      choice(
        seq(
          field('init', optional($.variable_declaration)),
          ';',
          field('condition', optional($.expression)),
          ';',
          field('update', optional($.expression))
        ),
        seq(
          'var',
          field('variable', $.identifier),
          'in',
          field('iterable', $.expression)
        )
      ),
      ')',
      field('body', $.statement)
    ),

    return_statement: $ => seq(
      'return',
      optional($.expression),
      ';'
    ),

    expression_statement: $ => seq(
      $.expression,
      ';'
    ),

    block_statement: $ => seq(
      '{',
      repeat($.statement),
      '}'
    ),

    empty_statement: $ => ';',

    // Expressions
    expression: $ => choice(
      $.assignment_expression,
      $.conditional_expression
    ),

    assignment_expression: $ => prec.right(1, seq(
      field('left', $.postfix_expression),
      field('operator', choice('=', '+=', '-=', '*=', '/=')),
      field('right', $.expression)
    )),

    conditional_expression: $ => prec.right(2, seq(
      $.logical_or_expression,
      optional(seq(
        '?',
        $.expression,
        ':',
        $.conditional_expression
      ))
    )),

    logical_or_expression: $ => prec.left(3, choice(
      $.logical_and_expression,
      seq($.logical_or_expression, '||', $.logical_and_expression)
    )),

    logical_and_expression: $ => prec.left(4, choice(
      $.equality_expression,
      seq($.logical_and_expression, '&&', $.equality_expression)
    )),

    equality_expression: $ => prec.left(5, choice(
      $.relational_expression,
      seq($.equality_expression, choice('==', '!='), $.relational_expression)
    )),

    relational_expression: $ => prec.left(6, choice(
      $.additive_expression,
      seq($.relational_expression, choice('<', '>', '<=', '>='), $.additive_expression)
    )),

    additive_expression: $ => prec.left(7, choice(
      $.multiplicative_expression,
      seq($.additive_expression, choice('+', '-'), $.multiplicative_expression)
    )),

    multiplicative_expression: $ => prec.left(8, choice(
      $.unary_expression,
      seq($.multiplicative_expression, choice('*', '/', '%'), $.unary_expression)
    )),

    unary_expression: $ => choice(
      $.postfix_expression,
      seq(choice('+', '-', '!'), $.unary_expression)
    ),

    postfix_expression: $ => choice(
      $.primary_expression,
      $.call_expression,
      $.member_expression,
      $.subscript_expression
    ),

    call_expression: $ => prec.left(10, seq(
      field('function', $.postfix_expression),
      field('arguments', $.argument_list)
    )),

    member_expression: $ => prec.left(10, seq(
      field('object', $.postfix_expression),
      '.',
      field('property', $.identifier)
    )),

    subscript_expression: $ => prec.left(10, seq(
      field('object', $.postfix_expression),
      '[',
      field('index', $.expression),
      ']'
    )),

    argument_list: $ => seq(
      '(',
      optional(seq(
        $.expression,
        repeat(seq(',', $.expression))
      )),
      ')'
    ),

    primary_expression: $ => choice(
      $.identifier,
      $.number_literal,
      $.string_literal,
      $.boolean_literal,
      $.null_literal,
      $.object_literal,
      $.array_literal,
      seq('(', $.expression, ')')
    ),

    // Object literals: { key: value, ... }
    object_literal: $ => seq(
      '{',
      optional(seq(
        $.object_member,
        repeat(seq(',', $.object_member)),
        optional(',')
      )),
      '}'
    ),

    object_member: $ => seq(
      choice(
        $.identifier,
        $.string_literal
      ),
      ':',
      $.expression
    ),

    // Array literals: [1, 2, 3]
    array_literal: $ => seq(
      '[',
      optional(seq(
        $.expression,
        repeat(seq(',', $.expression)),
        optional(',')
      )),
      ']'
    ),

    // Literals
    identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,

    number_literal: $ => choice(
      /\d+/,
      /\d+\.\d+/,
      /\d*\.?\d+[eE][+-]?\d+/
    ),

    string_literal: $ => choice(
      seq('"', repeat(choice(/[^"\\]/, $.escape_sequence)), '"'),
      seq("'", repeat(choice(/[^'\\]/, $.escape_sequence)), "'")
    ),

    escape_sequence: $ => seq(
      '\\',
      choice(
        /[\\'"nrtbfav0]/,
        /x[0-9a-fA-F]{2}/,
        /u[0-9a-fA-F]{4}/,
        /U[0-9a-fA-F]{8}/
      )
    ),

    boolean_literal: $ => choice('true', 'false'),
    null_literal: $ => 'null',

    // Comments
    comment: $ => token(choice(
      seq('//', /.*/),
      seq('/*', /[^*]*\*+([^/*][^*]*\*+)*/, '/')
    )),

    // Whitespace
    _whitespace: $ => /\s+/
  },

  extras: $ => [
    $.comment,
    $._whitespace
  ],

  conflicts: $ => [
    // Handle potential ambiguities
    [$.assignment_expression, $.conditional_expression],
    [$.call_expression, $.member_expression],
    [$.block_statement, $.object_literal]
  ],

  word: $ => $.identifier
});