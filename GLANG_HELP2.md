# Grim Integration Notes (Ghostlang v0.1.2)

## Summary
- Patched Ghostlang parser so leading `--` comments (including long comment blocks) are skipped before tokenization. This unblocks every Grim plugin script that starts with documentation headers.
- Added a regression test (`script parses leading line comment`) to keep CI from regressing the parser fix in future releases.
- Bumped Ghostlang package metadata to `0.1.2`; Grim should pull this snapshot to avoid the `ParseError at line 1, column 1` that shipped in `0.1.1`.

## Impact on Grim
- All `.gza` plugin entry points can safely include top-of-file comments again. Re-run the plugin validation harness once Grim consumes the new build.
- No changes required in Grim loader code—the bug was entirely in Ghostlang’s lexer.

## Next Steps
1. Update Grim’s dependency pin to Ghostlang `0.1.2` (or latest main) and rebuild.
2. Re-run:
   - `zig build` (Ghostlang) to refresh the CLI.
   - Grim’s plugin smoke tests (e.g., `test_ghostlang_plugin`) to confirm the fix in context.
3. Optional: port over additional Ghostlang examples (`docs/examples/plugins/*.gza`) into Grim’s plugin template gallery now that comment headers are safe.

## Reference Scripts
- `docs/examples/basic/hello-world.gza` (now executes without comment parsing failures).
- `/tmp/comment_test.gza` – minimal reproduction used during the fix.
