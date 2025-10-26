pub const app = @import("app.zig");
pub const editor = @import("editor.zig");
pub const simple_tui = @import("simple_tui.zig");
pub const grim_app = @import("grim_app.zig");
pub const file_ops = @import("file_ops.zig");
pub const editor_lsp = @import("editor_lsp.zig");
pub const vim_commands = @import("vim_commands.zig");
pub const theme = @import("theme.zig");

// New integration modules
pub const lsp_highlights = @import("lsp_highlights.zig");
pub const syntax_highlights = @import("syntax_highlights.zig");
pub const buffer_manager = @import("buffer_manager.zig");
pub const phantom_buffer = @import("phantom_buffer.zig");
pub const phantom_buffer_manager = @import("phantom_buffer_manager.zig");
pub const config = @import("config.zig");
pub const editor_integration = @import("editor_integration.zig");
pub const buffer_picker = @import("buffer_picker.zig");
pub const config_watcher = @import("config_watcher.zig");
pub const window_manager = @import("window_manager.zig");
pub const theme_customizer = @import("theme_customizer.zig");
pub const buffer_sessions = @import("buffer_sessions.zig");
pub const font_manager = @import("font_manager.zig");
pub const file_tree = @import("file_tree.zig");

// Phantom v0.6.0 LSP widgets
pub const lsp_completion_menu = @import("lsp_completion_menu.zig");
pub const lsp_diagnostics_panel = @import("lsp_diagnostics_panel.zig");
pub const lsp_hover_widget = @import("lsp_hover_widget.zig");
pub const lsp_loading_spinner = @import("lsp_loading_spinner.zig");
pub const status_bar_flex = @import("status_bar_flex.zig");

pub const App = app.App;
pub const Mode = app.Mode;
pub const Command = app.Command;
pub const Editor = editor.Editor;
pub const SimpleTUI = simple_tui.SimpleTUI;
pub const FileManager = file_ops.FileManager;
pub const FileFinder = file_ops.FileFinder;
pub const EditorLSP = editor_lsp.EditorLSP;
pub const VimEngine = vim_commands.VimEngine;
pub const Theme = theme.Theme;
pub const Color = theme.Color;

// New exports
pub const LSPHighlights = lsp_highlights.LSPHighlights;
pub const SyntaxHighlights = syntax_highlights.SyntaxHighlights;
pub const BufferManager = buffer_manager.BufferManager;
pub const PhantomBuffer = phantom_buffer.PhantomBuffer;
pub const PhantomBufferManager = phantom_buffer_manager.PhantomBufferManager;
pub const Config = config.Config;
pub const EditorIntegration = editor_integration.EditorIntegration;
pub const BufferPicker = buffer_picker.BufferPicker;
pub const ConfigWatcher = config_watcher.ConfigWatcher;
pub const WindowManager = window_manager.WindowManager;
pub const ThemeCustomizer = theme_customizer.ThemeCustomizer;
pub const BufferSessions = buffer_sessions.BufferSessions;
pub const FontManager = font_manager.FontManager;
pub const FileTree = file_tree.FileTree;

// Phantom v0.6.0 LSP widget exports
pub const LSPCompletionMenu = lsp_completion_menu.LSPCompletionMenu;
pub const LSPDiagnosticsPanel = lsp_diagnostics_panel.LSPDiagnosticsPanel;
pub const LSPHoverWidget = lsp_hover_widget.LSPHoverWidget;
pub const LSPLoadingSpinner = lsp_loading_spinner.LSPLoadingSpinner;
pub const StatusBarFlex = status_bar_flex.StatusBar;
