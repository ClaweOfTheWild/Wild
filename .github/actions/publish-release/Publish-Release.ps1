#Requires -Version 7.4
<#
.SYNOPSIS
    Publish the release described by a trusted closed-PR event.
.DESCRIPTION
    Read event JSON without expanding PR text as executable code.
.EXAMPLE
    ./Publish-Release.ps1
.OUTPUTS
    None
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_EVENT_NAME -cne 'pull_request_target' -or $env:GITHUB_REPOSITORY -cne 'ClaweOfTheWild/Wild') {
    throw 'Publishing requires a trusted pull_request_target event in ClaweOfTheWild/Wild.'
}
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'publish-release.Helpers.psm1') -Force
$payload = [IO.File]::ReadAllText($env:GITHUB_EVENT_PATH) | ConvertFrom-Json -AsHashtable
if ($PSCmdlet.ShouldProcess('ClaweOfTheWild/Wild', 'Process merged PR release')) {
    $plan = Publish-MergedPullRequestRelease -WebhookEvent $payload -Verbose
    if ($null -ne $plan) {
        [IO.File]::AppendAllText($env:GITHUB_OUTPUT, "version=$($plan.Version)`n", [Text.UTF8Encoding]::new($false))
    }
}
