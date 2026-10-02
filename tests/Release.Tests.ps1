#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0'; MaximumVersion = '6.*' }

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../.github/actions/publish-release/publish-release.Helpers.psm1'
    Import-Module -Name $modulePath -Force

    function New-TestEvent {
        param([string[]] $Label = @())

        @{
            action = 'closed'
            repository = @{ full_name = 'ClaweOfTheWild/Wild' }
            pull_request = @{
                number = 42
                merged = $true
                merge_commit_sha = 'a' * 40
                title = 'A useful change'
                body = "First paragraph.`n`nSecond paragraph."
                labels = @($Label | ForEach-Object { @{ name = $_ } })
                base = @{ ref = 'main'; repo = @{ full_name = 'ClaweOfTheWild/Wild' } }
                head = @{ sha = 'b' * 40; repo = @{ full_name = 'contributor/Wild' } }
            }
        }
    }
}

Describe 'Merged pull request release plan' {
    It 'bumps <Bump> from the numeric maximum, not API order or TOC version' -ForEach @(
        @{ Bump = 'default'; Label = @(); Expected = '0.0.11' }
        @{ Bump = 'patch'; Label = @('release:patch'); Expected = '0.0.11' }
        @{ Bump = 'minor'; Label = @('release:minor'); Expected = '0.1.0' }
        @{ Bump = 'major'; Label = @('release:major'); Expected = '1.0.0' }
        @{ Bump = 'unrelated'; Label = @('bug'); Expected = '0.0.11' }
    ) {
        $event = New-TestEvent -Label $Label
        $plan = Get-ReleasePlan -Event $event -TagName @('0.0.9', '0.0.10', '0.0.3')
        $plan.Version | Should -BeExactly $Expected
    }

    It 'resets lower components for <Label>' -ForEach @(
        @{ Label = 'release:major'; Expected = '13.0.0' }
        @{ Label = 'release:minor'; Expected = '12.35.0' }
        @{ Label = 'release:patch'; Expected = '12.34.57' }
    ) {
        $plan = Get-ReleasePlan -Event (New-TestEvent -Label $Label) -TagName @('12.34.56', '9.99.99')
        $plan.Version | Should -BeExactly $Expected
    }

    It 'ignores noncanonical, prerelease, and prefixed tags' {
        $tags = @('0.0.10', 'v99.0.0', '99.0.0-rc.1', '99.0.0+build', '01.0.0', 'latest')
        (Get-ReleasePlan -Event (New-TestEvent) -TagName $tags).Version | Should -BeExactly '0.0.11'
    }

    It 'fails rather than inventing a baseline when no version tags exist' {
        { Get-ReleasePlan -Event (New-TestEvent) -TagName @() } | Should -Throw '*No stable*'
    }

    It 'rejects multiple release labels' -ForEach @(
        @{ Label = @('release:major', 'release:minor') }
        @{ Label = @('release:minor', 'release:patch') }
        @{ Label = @('release:major', 'release:patch') }
        @{ Label = @('release:major', 'release:minor', 'release:patch') }
    ) {
        { Get-ReleasePlan -Event (New-TestEvent -Label $Label) -TagName @('0.0.10') } |
            Should -Throw '*Multiple release labels*'
    }

    It 'preserves title and description exactly as data' {
        $event = New-TestEvent
        $unicode = [char]::ConvertFromUtf32(0x1F680) + [char] 0x00E9
        $event.pull_request.title = 'Title "quoted" $(throw "executed") `ticks` ' + $unicode
        $event.pull_request.body = "  Leading spaces`r`n`r`n" +
            '$(touch /tmp/unsafe); $env:GH_TOKEN; ${{ secrets.TOKEN }}' + "`nTrailing spaces  `n"
        $plan = Get-ReleasePlan -Event $event -TagName @('0.0.10')
        $plan.Body | Should -BeExactly ($event.pull_request.title + "`n`n" + $event.pull_request.body)
        $plan.Version | Should -BeExactly '0.0.11'
    }

    It 'uses only the title when the description is <Name>' -ForEach @(
        @{ Name = 'null'; Body = $null }
        @{ Name = 'empty'; Body = '' }
    ) {
        $event = New-TestEvent
        $event.pull_request.body = $Body
        (Get-ReleasePlan -Event $event -TagName @('0.0.10')).Body | Should -BeExactly $event.pull_request.title
    }

    It 'uses merge_commit_sha for a <Mode>, never the head or current main SHA' -ForEach @(
        @{ Mode = 'normal merge'; Sha = 'c' * 40 }
        @{ Mode = 'squash merge'; Sha = 'd' * 40 }
    ) {
        $event = New-TestEvent
        $event.pull_request.merge_commit_sha = $Sha
        (Get-ReleasePlan -Event $event -TagName @('0.0.10')).CommitSha | Should -BeExactly $Sha
    }

    It 'skips <Scenario>' -ForEach @(
        @{ Scenario = 'unmerged closure'; Change = { param($e) $e.pull_request.merged = $false } }
        @{ Scenario = 'open PR'; Change = { param($e) $e.action = 'opened' } }
        @{ Scenario = 'another branch'; Change = { param($e) $e.pull_request.base.ref = 'develop' } }
        @{ Scenario = 'another repository'; Change = { param($e) $e.repository.full_name = 'other/Wild' } }
        @{ Scenario = 'another base repository'; Change = { param($e) $e.pull_request.base.repo.full_name = 'other/Wild' } }
    ) {
        $event = New-TestEvent
        & $Change $event
        Get-ReleasePlan -Event $event -TagName @('0.0.10') | Should -BeNullOrEmpty
    }

    It 'fails closed for a missing or invalid merge SHA' -ForEach @(
        @{ Sha = $null }
        @{ Sha = 'main' }
        @{ Sha = '$(throw "executed")' }
    ) {
        $event = New-TestEvent
        $event.pull_request.merge_commit_sha = $Sha
        { Get-ReleasePlan -Event $event -TagName @('0.0.10') } | Should -Throw '*merge commit*'
    }
}
