pub const treesitter = @import("treesitter.zig");
pub const grove = @import("grove.zig");
pub const highlighter = @import("highlighter.zig");
pub const features = @import("features.zig");

// Use Grove as primary parser, Tree-sitter as fallback
pub const Parser = grove.GroveParser;
pub const Language = Parser.Language;
pub const HighlightType = Parser.HighlightType;
pub const Highlight = Parser.Highlight;
pub const detectLanguage = grove.detectLanguage;
pub const createParser = grove.createParser;

// Syntax highlighting integration
pub const SyntaxHighlighter = highlighter.SyntaxHighlighter;
pub const HighlightRange = highlighter.HighlightRange;
pub const convertHighlightsToRanges = highlighter.convertHighlightsToRanges;

// Advanced features: folding and incremental selection
pub const Features = features.Features;
pub const FoldRegion = features.Features.FoldRegion;
pub const SelectionRange = features.Features.SelectionRange;

// Legacy Tree-sitter support
pub const TreeSitterParser = treesitter.Parser;
pub const createTreeSitterParser = treesitter.Parser.init;