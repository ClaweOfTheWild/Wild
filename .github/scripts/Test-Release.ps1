#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0'; MaximumVersion = '6.*' }
#Requires -Modules @{ ModuleName = 'PSScriptAnalyzer'; ModuleVersion = '1.25.0'; MaximumVersion = '1.*' }
<#
.SYNOPSIS
    Run offline release tests and workflow checks without publishing.
.DESCRIPTION
    Require the developer tools declared in the release-checks workflow.
    Mock every publishing HTTP request and lint the actual workflow files.
.EXAMPLE
    ./.github/scripts/Test-Release.ps1
.OUTPUTS
    None
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$root = [IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '../..'))
Push-Location -Path $root
try {
    $result = Invoke-Pester -Path (Join-Path -Path $root -ChildPath 'tests/Release.Tests.ps1') -PassThru
    if ($result.FailedCount -gt 0 -or $result.FailedContainersCount -gt 0) {
        throw 'Release tests failed.'
    }
    $findings = @(
        Invoke-ScriptAnalyzer -Path (Join-Path -Path $root -ChildPath '.github') -Recurse -Severity Warning, Error
        Invoke-ScriptAnalyzer -Path (Join-Path -Path $root -ChildPath 'tests/Release.Tests.ps1') -Severity Warning, Error
    )
    if ($findings.Count -gt 0) {
        $findings | Format-Table | Out-String | Write-Information -InformationAction Continue
        throw 'PowerShell analysis failed.'
    }
    python -B -m unittest discover -s tests -p test_release_workflow.py -v
    python -m yamllint -c .github/linters/yamllint.yml .github
    go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 -color
    zizmor --offline .github
} finally {
    Pop-Location
}
