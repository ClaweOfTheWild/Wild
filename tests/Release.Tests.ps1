#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0'; MaximumVersion = '6.*' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares fixtures across lifecycle blocks.')]
param()

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../.github/actions/publish-release/publish-release.Helpers.psm1'
    Import-Module -Name $modulePath -Force

    function New-TestEvent {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only returns an in-memory test fixture.')]
        [CmdletBinding()]
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

Describe 'Release automation' {
    It 'bumps <Bump> from the numeric maximum, not API order or TOC version' -ForEach @(
        @{ Bump = 'default'; Label = @(); Expected = '0.0.11' }
        @{ Bump = 'patch'; Label = @('release:patch'); Expected = '0.0.11' }
        @{ Bump = 'minor'; Label = @('release:minor'); Expected = '0.1.0' }
        @{ Bump = 'major'; Label = @('release:major'); Expected = '1.0.0' }
        @{ Bump = 'unrelated'; Label = @('bug'); Expected = '0.0.11' }
    ) {
        $payload = New-TestEvent -Label $Label
        $plan = Get-ReleasePlan -WebhookEvent $payload -TagName @('0.0.9', '0.0.10', '0.0.3')
        $plan.Version | Should -BeExactly $Expected
    }

    Describe 'Release publishing transaction with a fake GitHub API' {
        BeforeAll {
            $originalToken = $env:GH_TOKEN
            $env:GH_TOKEN = 'test-token-not-a-credential'
        }

        AfterAll {
            $env:GH_TOKEN = $originalToken
        }

        BeforeEach {
            $script:state = @{
                Tags = [Collections.Generic.List[object]]::new()
                Refs = @{}
                Annotations = @{}
                Releases = @{}
                Requests = [Collections.Generic.List[object]]::new()
                Failure = ''
                GetStatus = 0
            }
            $script:state.Tags.Add(@{ name = '0.0.10'; commit = @{ sha = 'e' * 40 } })
            $payload = New-TestEvent

            Mock -CommandName Invoke-WebRequest -ModuleName publish-release.Helpers -MockWith {
                param($Uri, $Method, $Headers, $Body)

                $path = ([uri] $Uri).PathAndQuery.Replace('/repos/ClaweOfTheWild/Wild/', '')
                $data = $null
                if ($null -ne $Body) {
                    $data = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json -AsHashtable
                }
                $script:state.Requests.Add(@{ Method = $Method; Path = $path; Data = $data; Headers = $Headers })
                $status = 200
                $result = @{}
                if ($script:state.GetStatus -ne 0 -and $Method -eq 'GET') {
                    $status = $script:state.GetStatus
                } elseif ($Method -eq 'GET' -and $path -match '^tags\?per_page=100&page=(\d+)$') {
                    $offset = ([int] $Matches[1] - 1) * 100
                    $result = @($script:state.Tags | Select-Object -Skip $offset -First 100)
                } elseif ($Method -eq 'GET' -and $path -match '^git/ref/tags/(.+)$') {
                    $result = $script:state.Refs[$Matches[1]]
                } elseif ($Method -eq 'GET' -and $path -match '^git/tags/(.+)$') {
                    $result = $script:state.Annotations[$Matches[1]]
                } elseif ($Method -eq 'GET' -and $path -match '^releases/tags/(.+)$') {
                    $result = $script:state.Releases[$Matches[1]]
                    if ($null -eq $result) {
                        $status = 404
                    }
                } elseif ($Method -eq 'POST' -and $path -eq 'git/tags') {
                    $sha = ($script:state.Annotations.Count + 1).ToString('x40')
                    $result = @{
                        sha = $sha
                        tag = $data.tag
                        message = $data.message
                        object = @{ type = $data.type; sha = $data.object }
                    }
                    $script:state.Annotations[$sha] = $result
                    if ($script:state.Failure -eq 'after-tag') {
                        $script:state.Failure = ''
                        throw 'Simulated connection loss after tag object.'
                    }
                } elseif ($Method -eq 'POST' -and $path -eq 'git/refs') {
                    $version = $data.ref.Replace('refs/tags/', '')
                    if ($script:state.Failure -eq 'competing-ref') {
                        $script:state.Tags.Add(@{ name = $version; commit = @{ sha = 'f' * 40 } })
                        $script:state.Failure = ''
                        $status = 422
                    } elseif ($script:state.Refs.ContainsKey($version)) {
                        $status = 422
                    } else {
                        $annotation = $script:state.Annotations[$data.sha]
                        $script:state.Refs[$version] = @{ object = @{ type = 'tag'; sha = $data.sha } }
                        $script:state.Tags.Add(@{ name = $version; commit = @{ sha = $annotation.object.sha } })
                        if ($script:state.Failure -eq 'after-ref') {
                            $script:state.Failure = ''
                            throw 'Simulated connection loss after ref creation.'
                        }
                    }
                } elseif ($Method -eq 'POST' -and $path -eq 'releases') {
                    if ($script:state.Failure -eq 'before-release') {
                        $script:state.Failure = ''
                        throw 'Simulated connection loss before release creation.'
                    }
                    if ($script:state.Releases.ContainsKey($data.tag_name)) {
                        $status = 422
                    } else {
                        $script:state.Releases[$data.tag_name] = $data
                        if ($script:state.Failure -eq 'after-release') {
                            $script:state.Failure = ''
                            throw 'Simulated connection loss after release creation.'
                        }
                    }
                } else {
                    throw "Unexpected fake API request: $Method $path"
                }
                @{
                    StatusCode = $status
                    Content = ConvertTo-Json -InputObject $result -Depth 20 -Compress
                }
            }
        }

        It 'publishes an exact numeric title, tag, commit, and UTF-8 body' {
            $payload.pull_request.title = 'Quotes "here" and $(throw "executed") ' + [char] 0x00E9
            $payload.pull_request.body = "Line 1`r`n`n" + '`${{ secrets.VALUE }}; $(echo test)' + "`n  "
            $result = Publish-MergedPullRequestRelease -WebhookEvent $payload
            $result.Version | Should -BeExactly '0.0.11'
            $release = $script:state.Releases['0.0.11']
            $release.name | Should -BeExactly '0.0.11'
            $release.tag_name | Should -BeExactly '0.0.11'
            $release.target_commitish | Should -BeExactly $payload.pull_request.merge_commit_sha
            $release.body | Should -BeExactly ($payload.pull_request.title + "`n`n" + $payload.pull_request.body)
            $release.draft | Should -BeFalse
            $release.prerelease | Should -BeFalse
            $release.generate_release_notes | Should -BeFalse
            $script:state.Tags[1].commit.sha | Should -BeExactly $payload.pull_request.merge_commit_sha
            @($script:state.Requests | Where-Object Method -EQ 'POST').Path |
                Should -Be @('git/tags', 'git/refs', 'releases')
        }

        It 'does no writes when a completed PR is rerun' {
            $null = Publish-MergedPullRequestRelease -WebhookEvent $payload
            $script:state.Requests.Clear()
            $result = Publish-MergedPullRequestRelease -WebhookEvent $payload
            $result.Version | Should -BeExactly '0.0.11'
            @($script:state.Requests | Where-Object Method -EQ 'POST').Count | Should -Be 0
            $script:state.Releases.Count | Should -Be 1
        }

        It 'recovers without another version after <Failure>' -ForEach @(
            @{ Failure = 'after-tag' }
            @{ Failure = 'after-ref' }
            @{ Failure = 'before-release' }
            @{ Failure = 'after-release' }
        ) {
            $script:state.Failure = $Failure
            { Publish-MergedPullRequestRelease -WebhookEvent $payload } | Should -Throw '*Simulated connection loss*'
            (Publish-MergedPullRequestRelease -WebhookEvent $payload).Version | Should -BeExactly '0.0.11'
            $script:state.Tags.Count | Should -Be 2
            $script:state.Releases.Count | Should -Be 1
        }

        It 'retains every serialized merge and reuses an older PR version on retry' {
            $first = Publish-MergedPullRequestRelease -WebhookEvent $payload
            $secondPayload = New-TestEvent -Label 'release:minor'
            $secondPayload.pull_request.number = 43
            $secondPayload.pull_request.merge_commit_sha = 'c' * 40
            $second = Publish-MergedPullRequestRelease -WebhookEvent $secondPayload
            $thirdPayload = New-TestEvent
            $thirdPayload.pull_request.number = 44
            $thirdPayload.pull_request.merge_commit_sha = 'd' * 40
            $third = Publish-MergedPullRequestRelease -WebhookEvent $thirdPayload
            @($first.Version, $second.Version, $third.Version) | Should -Be @('0.0.11', '0.1.0', '0.1.1')
            (Publish-MergedPullRequestRelease -WebhookEvent $payload).Version | Should -BeExactly '0.0.11'
            $script:state.Releases.Count | Should -Be 3
        }

        It 'resumes an interrupted older PR after another PR has published' {
            $script:state.Failure = 'before-release'
            { Publish-MergedPullRequestRelease -WebhookEvent $payload } | Should -Throw
            $later = New-TestEvent
            $later.pull_request.number = 43
            $later.pull_request.merge_commit_sha = 'c' * 40
            (Publish-MergedPullRequestRelease -WebhookEvent $later).Version | Should -BeExactly '0.0.12'
            (Publish-MergedPullRequestRelease -WebhookEvent $payload).Version | Should -BeExactly '0.0.11'
            $script:state.Releases['0.0.11'].make_latest | Should -BeExactly 'legacy'
        }

        It 'fails an atomic reservation race without publishing the other commit' {
            $script:state.Failure = 'competing-ref'
            { Publish-MergedPullRequestRelease -WebhookEvent $payload } | Should -Throw '*HTTP 422*'
            $script:state.Releases.Count | Should -Be 0
            $script:state.Tags[1].commit.sha | Should -BeExactly ('f' * 40)
            (Publish-MergedPullRequestRelease -WebhookEvent $payload).Version | Should -BeExactly '0.0.12'
            $script:state.Releases['0.0.12'].target_commitish | Should -BeExactly ('a' * 40)
        }

        It 'refuses an existing release without a matching owned tag' {
            $script:state.Releases['0.0.11'] = @{ name = 'Other release'; target_commitish = 'f' * 40 }
            { Publish-MergedPullRequestRelease -WebhookEvent $payload } | Should -Throw '*Refusing to overwrite*'
            @($script:state.Requests | Where-Object Method -EQ 'POST').Count | Should -Be 0
        }

        It 'refuses a manual lightweight tag on the same commit' {
            $script:state.Tags.Add(@{ name = '0.0.11'; commit = @{ sha = 'a' * 40 } })
            $script:state.Refs['0.0.11'] = @{ object = @{ type = 'commit'; sha = 'a' * 40 } }
            { Publish-MergedPullRequestRelease -WebhookEvent $payload } | Should -Throw '*not owned by this PR*'
            $script:state.Releases.Count | Should -Be 0
        }

        It 'refuses mismatched ownership or release content on retry' -ForEach @(
            @{ Change = { $script:state.Annotations[('1'.PadLeft(40, '0'))].message = 'Another PR owns this tag' } }
            @{ Change = { $script:state.Annotations[('1'.PadLeft(40, '0'))].object.sha = 'f' * 40 } }
            @{ Change = { $script:state.Releases['0.0.11'].body = 'Manual changes' } }
            @{ Change = { $script:state.Releases['0.0.11'].draft = $true } }
        ) {
            $null = Publish-MergedPullRequestRelease -WebhookEvent $payload
            $script:state.Requests.Clear()
            & $Change
            { Publish-MergedPullRequestRelease -WebhookEvent $payload } | Should -Throw '*Refusing to overwrite*'
            @($script:state.Requests | Where-Object Method -EQ 'POST').Count | Should -Be 0
        }

        It 'reads all tag pages before computing the numeric maximum' {
            $script:state.Tags.Clear()
            foreach ($patch in 1..101) {
                $script:state.Tags.Add(@{ name = "0.0.$patch"; commit = @{ sha = 'e' * 40 } })
            }
            (Publish-MergedPullRequestRelease -WebhookEvent $payload).Version | Should -BeExactly '0.0.102'
            @($script:state.Requests | Where-Object Path -Like 'tags?*').Count | Should -Be 2
        }

        It 'does not contact GitHub for unmerged PRs or invalid label combinations' {
            $payload.pull_request.merged = $false
            Publish-MergedPullRequestRelease -WebhookEvent $payload | Should -BeNullOrEmpty
            $payload = New-TestEvent -Label @('release:minor', 'release:patch')
            { Publish-MergedPullRequestRelease -WebhookEvent $payload } | Should -Throw '*Multiple release labels*'
            $script:state.Requests.Count | Should -Be 0
        }

        It 'treats HTTP <Status> as failure, not an absent tag or release' -ForEach @(
            @{ Status = 401 }
            @{ Status = 403 }
            @{ Status = 404 }
            @{ Status = 429 }
            @{ Status = 500 }
        ) {
            $script:state.GetStatus = $Status
            { Publish-MergedPullRequestRelease -WebhookEvent $payload } | Should -Throw "*HTTP $Status*"
            $script:state.Tags.Count | Should -Be 1
        }

        It 'supports read-only WhatIf without reserving or publishing' {
            Publish-MergedPullRequestRelease -WebhookEvent $payload -WhatIf | Should -BeNullOrEmpty
            @($script:state.Requests | Where-Object Method -EQ 'POST').Count | Should -Be 0
        }
    }

    It 'resets lower components for <Label>' -ForEach @(
        @{ Label = 'release:major'; Expected = '13.0.0' }
        @{ Label = 'release:minor'; Expected = '12.35.0' }
        @{ Label = 'release:patch'; Expected = '12.34.57' }
    ) {
        $plan = Get-ReleasePlan -WebhookEvent (New-TestEvent -Label $Label) -TagName @('12.34.56', '9.99.99')
        $plan.Version | Should -BeExactly $Expected
    }

    It 'ignores noncanonical, prerelease, and prefixed tags' {
        $tags = @('0.0.10', 'v99.0.0', '99.0.0-rc.1', '99.0.0+build', '01.0.0', 'latest')
        (Get-ReleasePlan -WebhookEvent (New-TestEvent) -TagName $tags).Version | Should -BeExactly '0.0.11'
    }

    It 'fails rather than inventing a baseline when no version tags exist' {
        { Get-ReleasePlan -WebhookEvent (New-TestEvent) -TagName @() } | Should -Throw '*No stable*'
    }

    It 'rejects multiple release labels' -ForEach @(
        @{ Label = @('release:major', 'release:minor') }
        @{ Label = @('release:minor', 'release:patch') }
        @{ Label = @('release:major', 'release:patch') }
        @{ Label = @('release:major', 'release:minor', 'release:patch') }
    ) {
        { Get-ReleasePlan -WebhookEvent (New-TestEvent -Label $Label) -TagName @('0.0.10') } |
            Should -Throw '*Multiple release labels*'
    }

    It 'preserves title and description exactly as data' {
        $payload = New-TestEvent
        $unicode = [char]::ConvertFromUtf32(0x1F680) + [char] 0x00E9
        $payload.pull_request.title = 'Title "quoted" $(throw "executed") `ticks` ' + $unicode
        $payload.pull_request.body = "  Leading spaces`r`n`r`n" +
            '$(touch /tmp/unsafe); $env:GH_TOKEN; ${{ secrets.TOKEN }}' + "`nTrailing spaces  `n"
        $plan = Get-ReleasePlan -WebhookEvent $payload -TagName @('0.0.10')
        $plan.Body | Should -BeExactly ($payload.pull_request.title + "`n`n" + $payload.pull_request.body)
        $plan.Version | Should -BeExactly '0.0.11'
    }

    It 'uses only the title when the description is <Name>' -ForEach @(
        @{ Name = 'null'; Body = $null }
        @{ Name = 'empty'; Body = '' }
    ) {
        $payload = New-TestEvent
        $payload.pull_request.body = $Body
        (Get-ReleasePlan -WebhookEvent $payload -TagName @('0.0.10')).Body | Should -BeExactly $payload.pull_request.title
    }

    It 'uses merge_commit_sha for a <Mode>, never the head or current main SHA' -ForEach @(
        @{ Mode = 'normal merge'; Sha = 'c' * 40 }
        @{ Mode = 'squash merge'; Sha = 'd' * 40 }
    ) {
        $payload = New-TestEvent
        $payload.pull_request.merge_commit_sha = $Sha
        (Get-ReleasePlan -WebhookEvent $payload -TagName @('0.0.10')).CommitSha | Should -BeExactly $Sha
    }

    It 'skips <Scenario>' -ForEach @(
        @{ Scenario = 'unmerged closure'; Change = { param($e) $e.pull_request.merged = $false } }
        @{ Scenario = 'open PR'; Change = { param($e) $e.action = 'opened' } }
        @{ Scenario = 'another branch'; Change = { param($e) $e.pull_request.base.ref = 'develop' } }
        @{ Scenario = 'another repository'; Change = { param($e) $e.repository.full_name = 'other/Wild' } }
        @{ Scenario = 'another base repository'; Change = { param($e) $e.pull_request.base.repo.full_name = 'other/Wild' } }
    ) {
        $payload = New-TestEvent
        & $Change $payload
        Get-ReleasePlan -WebhookEvent $payload -TagName @('0.0.10') | Should -BeNullOrEmpty
    }

    It 'fails closed for a missing or invalid merge SHA' -ForEach @(
        @{ Sha = $null }
        @{ Sha = 'main' }
        @{ Sha = '$(throw "executed")' }
    ) {
        $payload = New-TestEvent
        $payload.pull_request.merge_commit_sha = $Sha
        { Get-ReleasePlan -WebhookEvent $payload -TagName @('0.0.10') } | Should -Throw '*merge commit*'
    }
}
