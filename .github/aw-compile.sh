#!/usr/bin/env bash
set -euo pipefail

# aw-compile.sh — Compile agentic workflows and apply PAT pool rotation edits.
#
# Usage:
#   ./scripts/aw-compile.sh [workflow-name]
#
# If workflow-name is provided, only that workflow is compiled and edited.
# Otherwise, all workflows are compiled and those with metadata.copilot-pat-pool
# are edited.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"

WORKFLOW_NAME="${1:-}"

# Ensure we run from the repo root (gh aw compile requires it)
pushd "$REPO_ROOT" > /dev/null

# --- Step 1: Run gh aw compile ---
echo "=== Compiling agentic workflows ==="
if [ -n "$WORKFLOW_NAME" ]; then
    gh aw compile "$WORKFLOW_NAME"
else
    gh aw compile
fi

# --- Step 2: Apply post-compile edits ---
echo ""
echo "=== Applying post-compile PAT pool rotation edits ==="

apply_edits() {
    local name="$1"
    local md_file="$WORKFLOWS_DIR/${name}.md"
    local lock_file="$WORKFLOWS_DIR/${name}.lock.yml"

    if [ ! -f "$md_file" ]; then
        echo "  ${name}: skipped (no .md file)"
        return
    fi

    # Extract copilot-pat-pool from frontmatter
    local pool
    pool=$(sed -n '/^---$/,/^---$/p' "$md_file" | grep 'copilot-pat-pool:' | sed 's/.*copilot-pat-pool:[[:space:]]*//' | tr -d '[:space:]')

    if [ -z "$pool" ]; then
        echo "  ${name}: skipped (no copilot-pat-pool in metadata)"
        return
    fi

    if [ ! -f "$lock_file" ]; then
        echo "  ${name}: skipped (no .lock.yml after compile)"
        return
    fi

    if ! grep -q 'secrets\.COPILOT_GITHUB_TOKEN' "$lock_file"; then
        echo "  ${name}: pool=${pool}, no COPILOT_GITHUB_TOKEN references to replace"
        return
    fi

    # Build the select-copilot-pat step
    local select_step
    select_step=$(cat <<STEP_EOF
      - name: Select Copilot token from pool
        id: select-copilot-pat
        uses: ./.github/actions/select-copilot-pat
        with:
          run-number: \${{ github.run_number }}
        env:
$(for i in $(seq 0 9); do echo "          COPILOT_PAT_${i}: \${{ secrets.COPILOT_${pool}_${i} }}"; done)
STEP_EOF
    )

    # 1. Replace secret_verification_result output and add selected_token
    sed -i.bak \
        's|secret_verification_result: ${{ steps.validate-secret.outputs.verification_result }}|secret_verification_result: ${{ steps.select-copilot-pat.outputs.token != '"'"''"'"' \&\& '"'"'valid'"'"' || '"'"'missing'"'"' }}\n      selected_token: ${{ steps.select-copilot-pat.outputs.token }}|' \
        "$lock_file"

    # 2. Remove the validate-secret step entirely
    awk '
    /- name: Validate COPILOT_GITHUB_TOKEN secret/ {
        # Skip this line and the next 4 (id, run, env, COPILOT_GITHUB_TOKEN)
        for (i = 0; i < 4; i++) getline
        next
    }
    { print }
    ' "$lock_file" > "${lock_file}.tmp" && mv "${lock_file}.tmp" "$lock_file"

    # 3. Insert select-copilot-pat step after the checkout step (after fetch-depth: 1)
    awk -v step="$select_step" '
    { print }
    /fetch-depth: 1/ && !inserted {
        print step
        inserted = 1
    }
    ' "$lock_file" > "${lock_file}.tmp" && mv "${lock_file}.tmp" "$lock_file"

    # 4. Replace all remaining secrets.COPILOT_GITHUB_TOKEN references
    sed -i.bak \
        's|\${{ secrets\.COPILOT_GITHUB_TOKEN }}|\${{ needs.activation.outputs.selected_token }}|g' \
        "$lock_file"

    # Clean up backup files
    rm -f "${lock_file}.bak"

    # Verify
    local remaining
    remaining=$(grep -c 'secrets\.COPILOT_GITHUB_TOKEN' "$lock_file" || true)
    if [ "$remaining" -gt 0 ]; then
        echo "  ${name}: pool=${pool}, edited but ${remaining} COPILOT_GITHUB_TOKEN reference(s) remain"
    else
        echo "  ${name}: pool=${pool}, post-compile edits applied successfully"
    fi
}

# Process workflows
if [ -n "$WORKFLOW_NAME" ]; then
    apply_edits "$WORKFLOW_NAME"
else
    for md_file in "$WORKFLOWS_DIR"/*.md; do
        [ -f "$md_file" ] || continue
        name=$(basename "$md_file" .md)
        apply_edits "$name"
    done
fi

popd > /dev/null
