#!/usr/bin/env bash
# ============================================================
# patch-hermes-squash.sh — Re-apply /squash command after Hermes updates
# ============================================================
# Run this after `hermes update` to re-apply the custom /squash command.
#
# Usage:
#   scripts/patch-hermes-squash.sh
#
# What it patches:
#   1. hermes_cli/commands.py — Add CommandDef for /squash
#   2. hermes_cli/cli_commands_mixin.py — Add _handle_squash_command()
#   3. gateway/slash_commands.py — Add _handle_squash_command() for Telegram
# ============================================================

set -euo pipefail

# Find Hermes installation
HERMES_DIR=$(dirname "$(dirname "$(which hermes)")")
if [ ! -d "$HERMES_DIR/hermes_cli" ]; then
    # Try common locations
    for dir in /usr/local/lib/hermes-agent /usr/lib/hermes-agent ~/.local/lib/hermes-agent; do
        if [ -d "$dir/hermes_cli" ]; then
            HERMES_DIR="$dir"
            break
        fi
    done
fi

if [ ! -d "$HERMES_DIR/hermes_cli" ]; then
    echo "  ❌ Could not find Hermes installation"
    exit 1
fi

echo "  Hermes directory: $HERMES_DIR"

# --- Patch 1: commands.py ---
echo "  Patching commands.py..."

if grep -q '"squash"' "$HERMES_DIR/hermes_cli/commands.py"; then
    echo "    Already patched (squash command found)"
else
    # Find the line before "# Exit" section
    LINE=$(grep -n "^    # Exit" "$HERMES_DIR/hermes_cli/commands.py" | head -1 | cut -d: -f1)
    if [ -z "$LINE" ]; then
        echo "    Could not find insertion point"
        exit 1
    fi

    # Insert the CommandDef before the Exit section
    sed -i "${LINE}i\\
\\
    # Custom Commands (agent-env-selfhosted)\\
    CommandDef(\"squash\", \"Consolidate sprint commits into one clean commit\", \"Custom\",\\
               args_hint='[\"commit message\"]'),\\
" "$HERMES_DIR/hermes_cli/commands.py"

    echo "    ✅ Added CommandDef"
fi

# --- Patch 2: cli_commands_mixin.py ---
echo "  Patching cli_commands_mixin.py..."

if grep -q "_handle_squash_command" "$HERMES_DIR/hermes_cli/cli_commands_mixin.py"; then
    echo "    Already patched (handler found)"
else
    # Add the handler at the end of the file
    cat >> "$HERMES_DIR/hermes_cli/cli_commands_mixin.py" << 'HANDLER'

    def _handle_squash_command(self, command: str):
        """Handle /squash — consolidate sprint commits into one clean commit."""
        import subprocess
        import os

        parts = command.strip().split(maxsplit=1)
        commit_msg = parts[1] if len(parts) > 1 else ""

        cwd = os.getcwd()
        repo_root = None
        for d in [cwd] + [os.path.join(cwd, p) for p in ["..", "../..", "../../.."]]:
            if os.path.isdir(os.path.join(d, ".git")):
                repo_root = os.path.abspath(d)
                break

        if not repo_root:
            print("  ❌ Not in a git repository.")
            return

        script = os.path.join(repo_root, "scripts", "sprint-finalize.sh")
        if not os.path.isfile(script):
            print(f"  ❌ Script not found: {script}")
            return

        cmd = [script]
        if commit_msg:
            cmd.append(commit_msg)

        print(f"  Running squash...")
        try:
            result = subprocess.run(cmd, cwd=repo_root, capture_output=True, text=True, timeout=60)
            if result.returncode == 0:
                print(result.stdout)
            else:
                print(f"  ❌ Failed (exit code {result.returncode})")
                if result.stderr:
                    print(result.stderr)
        except subprocess.TimeoutExpired:
            print("  ❌ Timed out after 60 seconds")
        except Exception as e:
            print(f"  ❌ Error: {e}")
HANDLER

    echo "    ✅ Added CLI handler"
fi

# --- Patch 3: gateway/slash_commands.py ---
echo "  Patching gateway/slash_commands.py..."

if grep -q "_handle_squash_command" "$HERMES_DIR/gateway/slash_commands.py"; then
    echo "    Already patched (gateway handler found)"
else
    # Add the handler at the end of the file
    cat >> "$HERMES_DIR/gateway/slash_commands.py" << 'GATEWAY_HANDLER'

    async def _handle_squash_command(self, event: MessageEvent) -> str:
        """Handle /squash — consolidate sprint commits into one clean commit."""
        import subprocess
        import os

        parts = event.text.strip().split(maxsplit=1)
        commit_msg = parts[1] if len(parts) > 1 else ""

        cwd = os.getcwd()
        repo_root = None
        for d in [cwd] + [os.path.join(cwd, p) for p in ["..", "../..", "../../.."]]:
            if os.path.isdir(os.path.join(d, ".git")):
                repo_root = os.path.abspath(d)
                break

        if not repo_root:
            return "❌ Not in a git repository."

        script = os.path.join(repo_root, "scripts", "sprint-finalize.sh")
        if not os.path.isfile(script):
            return f"❌ Script not found: {script}"

        cmd = [script]
        if commit_msg:
            cmd.append(commit_msg)

        try:
            result = subprocess.run(cmd, cwd=repo_root, capture_output=True, text=True, timeout=60)
            if result.returncode == 0:
                output = result.stdout
                lines = [l for l in output.splitlines() if l.strip()]
                summary = "\\n".join(lines[-5:]) if len(lines) > 5 else output
                return f"✅ Squash complete\\n\\n{summary}"
            else:
                error = result.stderr or result.stdout or "Unknown error"
                return f"❌ Squash failed\\n\\n{error}"
        except subprocess.TimeoutExpired:
            return "❌ Timed out after 60 seconds"
        except Exception as e:
            return f"❌ Error: {e}"
GATEWAY_HANDLER

    echo "    ✅ Added gateway handler"
fi

echo ""
echo "  ✅ Patch complete! Restart Hermes to use /squash"
