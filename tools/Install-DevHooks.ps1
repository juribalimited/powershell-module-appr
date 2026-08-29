<#
.SYNOPSIS
  Configures the local clone to use this repo's tracked git hooks.

.DESCRIPTION
  Sets `core.hooksPath` to `.githooks/`, so the hooks committed under
  that folder are run by git on the relevant lifecycle events. Today
  that's just `.githooks/pre-push`, which runs PSScriptAnalyzer with
  the same gate as CI and aborts a push on any finding.

  Run once after cloning. No-op if hooksPath is already pointing here.
  Does NOT touch global git config — only the per-clone setting.

.PARAMETER Disable
  Removes the per-clone hooksPath setting (reverts to git's default
  `.git/hooks/`). Use if you want to opt out of the tracked hooks for
  this clone.

.EXAMPLE
  pwsh ./tools/Install-DevHooks.ps1

.EXAMPLE
  pwsh ./tools/Install-DevHooks.ps1 -Disable
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Disable
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git not on PATH — can't configure hooks."
}

# Resolve the repo root from the script location (so it works regardless
# of cwd).
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..') | Select-Object -ExpandProperty Path
Push-Location $repoRoot
try {
    if ($Disable) {
        if ($PSCmdlet.ShouldProcess($repoRoot, 'Unset core.hooksPath')) {
            git config --unset core.hooksPath 2>$null
            Write-Host "→ core.hooksPath unset; git will use the default .git/hooks/."
        }
        return
    }

    $current = git config --get core.hooksPath 2>$null
    if ($current -eq '.githooks') {
        Write-Host "→ already using .githooks (core.hooksPath = $current). Nothing to do." -ForegroundColor DarkGray
        return
    }

    if ($PSCmdlet.ShouldProcess($repoRoot, 'Set core.hooksPath = .githooks')) {
        git config core.hooksPath .githooks
        Write-Host "→ core.hooksPath set to .githooks." -ForegroundColor Green
        Write-Host "  pre-push hook now runs PSScriptAnalyzer before every push." -ForegroundColor Green
        Write-Host "  Bypass for an emergency push with: git push --no-verify"
    }
}
finally {
    Pop-Location
}
