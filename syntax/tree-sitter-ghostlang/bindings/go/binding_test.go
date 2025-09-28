package tree_sitter_ghostlang_test

import (
	"testing"

	tree_sitter "github.com/smacker/go-tree-sitter"
	"github.com/tree-sitter/tree-sitter-ghostlang"
)

func TestCanLoadGrammar(t *testing.T) {
	language := tree_sitter.NewLanguage(tree_sitter_ghostlang.Language())
	if language == nil {
		t.Errorf("Error loading Ghostlang grammar")
	}
}
