<#
.SYNOPSIS
    Compile agentic workflows and apply PAT pool rotation edits.

.DESCRIPTION
    Runs `gh aw compile` then applies post-compile edits to lock files
    for workflows that define metadata.copilot-pat-pool in their frontmatter.

.PARAMETER WorkflowName
    Optional. Compile and edit a single workflow. If omitted, all workflows
    are compiled and those with copilot-pat-pool metadata are edited.

.EXAMPLE
    .\scripts\aw-compile.ps1
    .\scripts\aw-compile.ps1 hello-world
#>
param(
    [Parameter(Position = 0)]
    [string]$WorkflowName
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$WorkflowsDir = Join-Path $RepoRoot '.github' 'workflows'

# Ensure we run from the repo root (gh aw compile requires it)
Push-Location $RepoRoot

# --- Step 1: Run gh aw compile ---
Write-Host '=== Compiling agentic workflows ==='
if ($WorkflowName) {
    gh aw compile $WorkflowName
} else {
    gh aw compile
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# --- Step 2: Apply post-compile edits ---
Write-Host ''
Write-Host '=== Applying post-compile PAT pool rotation edits ==='

function Apply-Edits {
    param([string]$Name)

    $mdFile = Join-Path $WorkflowsDir "$Name.md"
    $lockFile = Join-Path $WorkflowsDir "$Name.lock.yml"

    if (-not (Test-Path $mdFile)) {
        Write-Host "  ${Name}: skipped (no .md file)"
        return
    }

    # Extract copilot-pat-pool from frontmatter
    $mdContent = Get-Content $mdFile -Raw
    $pool = $null
    if ($mdContent -match '(?s)^---\r?\n.*?copilot-pat-pool:\s*(\S+).*?\r?\n---') {
        $pool = $Matches[1]
    }

    if (-not $pool) {
        Write-Host "  ${Name}: skipped (no copilot-pat-pool in metadata)"
        return
    }

    if (-not (Test-Path $lockFile)) {
        Write-Host "  ${Name}: skipped (no .lock.yml after compile)"
        return
    }

    $lockContent = Get-Content $lockFile -Raw

    if ($lockContent -notmatch 'secrets\.COPILOT_GITHUB_TOKEN') {
        Write-Host "  ${Name}: pool=${pool}, no COPILOT_GITHUB_TOKEN references to replace"
        return
    }

    # 1. Replace secret_verification_result output to use select-copilot-pat step
    $lockContent = $lockContent -replace `
        'secret_verification_result: \$\{\{ steps\.validate-secret\.outputs\.verification_result \}\}', `
        "secret_verification_result: `${{ steps.select-copilot-pat.outputs.token != '' && 'valid' || 'missing' }}"

    # 2. Remove the validate-secret step entirely
    $validatePattern = '(?s)      - name: Validate COPILOT_GITHUB_TOKEN secret\r?\n        id: validate-secret\r?\n        run: [^\n]+\r?\n        env:\r?\n          COPILOT_GITHUB_TOKEN: \$\{\{ secrets\.COPILOT_GITHUB_TOKEN \}\}\r?\n'
    $lockContent = $lockContent -replace $validatePattern, ''

    # 3. Insert select-copilot-pat step after the checkout step
    $secretEnvLines = (0..9 | ForEach-Object {
        $i = $_
        '          COPILOT_PAT_{0}: ${{{{ secrets.COPILOT_{1}_{0} }}}}' -f $i, $pool
    }) -join "`n"

    $selectStep = @"
      - name: Select Copilot token from pool
        id: select-copilot-pat
        uses: ./.github/actions/select-copilot-pat
        with:
          run-number: `${{ github.run_number }}
        env:
$secretEnvLines
"@

    # Insert after the first "fetch-depth: 1" line (end of activation checkout step)
    $insertAfter = '          fetch-depth: 1'
    $idx = $lockContent.IndexOf($insertAfter)
    if ($idx -ge 0) {
        $insertPos = $idx + $insertAfter.Length
        # Skip past the newline
        if ($insertPos -lt $lockContent.Length -and $lockContent[$insertPos] -eq "`r") { $insertPos++ }
        if ($insertPos -lt $lockContent.Length -and $lockContent[$insertPos] -eq "`n") { $insertPos++ }
        $lockContent = $lockContent.Substring(0, $insertPos) + $selectStep + "`n" + $lockContent.Substring($insertPos)
    }

    # 4. Insert select-copilot-pat in the agent job after its checkout step.
    #    The agent job's checkout is "Checkout repository" with persist-credentials: false
    #    and no further with: properties. Find "Checkout repository" then insert after the
    #    next "persist-credentials: false" line.
    $checkoutRepoIdx = $lockContent.IndexOf('- name: Checkout repository')
    if ($checkoutRepoIdx -ge 0) {
        $persistIdx = $lockContent.IndexOf('persist-credentials: false', $checkoutRepoIdx)
        if ($persistIdx -ge 0) {
            $insertPos = $persistIdx + 'persist-credentials: false'.Length
            if ($insertPos -lt $lockContent.Length -and $lockContent[$insertPos] -eq "`r") { $insertPos++ }
            if ($insertPos -lt $lockContent.Length -and $lockContent[$insertPos] -eq "`n") { $insertPos++ }
            $lockContent = $lockContent.Substring(0, $insertPos) + $selectStep + "`n" + $lockContent.Substring($insertPos)
        }
    }

    # 5. Replace all secrets.COPILOT_GITHUB_TOKEN references
    $lockContent = $lockContent -replace `
        '\$\{\{ secrets\.COPILOT_GITHUB_TOKEN \}\}', `
        '${{ steps.select-copilot-pat.outputs.token }}'

    Set-Content -Path $lockFile -Value $lockContent -NoNewline

    # Verify
    $remaining = ([regex]::Matches($lockContent, 'secrets\.COPILOT_GITHUB_TOKEN')).Count
    if ($remaining -gt 0) {
        Write-Host "  ${Name}: pool=${pool}, edited but ${remaining} COPILOT_GITHUB_TOKEN reference(s) remain"
    } else {
        Write-Host "  ${Name}: pool=${pool}, post-compile edits applied successfully"
    }
}

# Process workflows
if ($WorkflowName) {
    Apply-Edits -Name $WorkflowName
} else {
    Get-ChildItem -Path $WorkflowsDir -Filter '*.md' | ForEach-Object {
        $name = $_.BaseName
        Apply-Edits -Name $name
    }
}

Pop-Location
