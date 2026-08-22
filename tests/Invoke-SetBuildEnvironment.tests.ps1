# Regression tests for the BuildHelpers Invoke-Git deadlock (psake/PowerShellBuild#167).
#
# BuildHelpers' Invoke-Git waits for git to exit before reading its redirected output, so a commit
# message larger than the pipe buffer deadlocks: git blocks on the full pipe, BuildHelpers blocks
# on the process. Without the workaround these tests do not fail, they hang forever, so every call
# runs in a separate process that is killed if it overruns -- a run that does not finish is the
# failure.
#
# The child must be a process rather than a Start-Job: Invoke-Git hangs inside a background job
# whatever the output size, so a job-based harness would hang even with the workaround in place.
#
# The child also clears the build system variables it inherits before applying the ones a test
# asks for. Without that the results depend on where the suite runs: on a developer's machine
# there is no build system, while in CI the runner's own variables decide which branch of
# Get-BuildVariable is taken.
#
# The repository fixture is generated into $TestDrive at runtime, never checked in.

BeforeDiscovery {
    # -Skip is evaluated during discovery, so this cannot be read from the BeforeAll below.
    $script:gitAvailable = [bool](Get-Command -Name 'git' -CommandType 'Application' -ErrorAction 'SilentlyContinue')
}

Describe 'Invoke-SetBuildEnvironment' {

    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:builtModulePath = [IO.Path]::Combine($script:moduleRoot, 'Output', 'PowerShellBuild')
        $script:gitAvailable = [bool](Get-Command -Name 'git' -CommandType 'Application' -ErrorAction 'SilentlyContinue')

        # A repository whose HEAD commit message is far larger than any platform's pipe buffer.
        # 8 KB is roughly a third of what a squashed pull request body reaches in this repository.
        $script:repositoryPath = Join-Path -Path $TestDrive -ChildPath 'BigCommitMessage'
        $script:commitSubject = 'subject line of an oversized commit message'
        $script:commitBodyLine = 'body line that exists only to push this message past the pipe buffer'
        $script:commitMessageLineCount = 120
        $script:expectedCommitMessage = (@($script:commitSubject) + (1..$script:commitMessageLineCount).ForEach({ $script:commitBodyLine })) -join "`n"
        $script:commitHash = $null

        if ($script:gitAvailable) {
            $manifestDirectory = Join-Path -Path $script:repositoryPath -ChildPath 'BigCommitMessage'
            New-Item -Path $manifestDirectory -ItemType 'Directory' -Force > $null
            Set-Content -Path (Join-Path -Path $manifestDirectory -ChildPath 'BigCommitMessage.psm1') -Value ''
            $newModuleManifestParameters = @{
                Path          = Join-Path -Path $manifestDirectory -ChildPath 'BigCommitMessage.psd1'
                RootModule    = 'BigCommitMessage.psm1'
                ModuleVersion = '1.0.0'
            }
            New-ModuleManifest @newModuleManifestParameters

            $messageFile = Join-Path -Path $TestDrive -ChildPath 'commit-message.txt'
            $messageLines = @($script:commitSubject, '') + (1..$script:commitMessageLineCount).ForEach({ $script:commitBodyLine })
            Set-Content -Path $messageFile -Value $messageLines

            # BuildHelpers falls back to the origin remote when it cannot resolve a project name,
            # so the fixture declares one. It is never contacted.
            Push-Location -LiteralPath $script:repositoryPath
            try {
                git init --initial-branch 'main' . *> $null
                git config user.email 'fixture@example.invalid' *> $null
                git config user.name 'PowerShellBuild fixture' *> $null
                git remote add origin 'https://example.invalid/BigCommitMessage.git' *> $null
                git add --all *> $null
                git commit --file $messageFile *> $null
                $script:commitHash = (git rev-parse HEAD).Trim()
            } finally {
                Pop-Location
            }
        }

        # Script run by each child process. Everything it needs arrives in one JSON file, which
        # keeps quoting out of the argument list, and it reports back the same way.
        $script:runnerPath = Join-Path -Path $TestDrive -ChildPath 'Invoke-SetBuildEnvironmentRunner.ps1'
        Set-Content -Path $script:runnerPath -Value @'
param(
    [string]$RequestPath
)

$request = Get-Content -Path $RequestPath -Raw | ConvertFrom-Json

# Start from a known environment rather than whatever build system is running the suite.
$buildSystemVariablePattern = '^(GITHUB_|CI_|CI$|BUILD_|SYSTEM_|TF_BUILD|APPVEYOR|TRAVIS|JENKINS_URL|TEAMCITY_|BAMBOO|GOCD_|GITLAB_CI|GO_REVISION|WORKSPACE$|GIT_COMMIT$|GIT_BRANCH$)'
Get-ChildItem -Path 'Env:' |
    Where-Object { $_.Name -match $buildSystemVariablePattern } |
    ForEach-Object { Remove-Item -Path "Env:$($_.Name)" -ErrorAction SilentlyContinue }

foreach ($property in $request.PresetEnvironment.PSObject.Properties) {
    Set-Item -Path "Env:$($property.Name)" -Value $property.Value
}

Import-Module -Name $request.ModulePath -Force -ErrorAction Stop
Set-Location -LiteralPath $request.RepositoryPath

$module = Get-Module -Name 'PowerShellBuild'
& $module { Invoke-SetBuildEnvironment -Parameter @{ Force = $true } }

$result = [PSCustomObject]@{
    CommitMessage        = $env:BHCommitMessage
    CommitHash           = $env:BHCommitHash
    BuildSystem          = $env:BHBuildSystem
    ProjectName          = $env:BHProjectName
    BranchName           = $env:BHBranchName
    AzureCommitMessage   = $env:BUILD_SOURCEVERSIONMESSAGE
    AzureVariablePresent = [bool](Test-Path -Path 'Env:BUILD_SOURCEVERSIONMESSAGE')
    GitHubSha            = $env:GITHUB_SHA
    GitHubShaPresent     = [bool](Test-Path -Path 'Env:GITHUB_SHA')
}
$result | ConvertTo-Json | Set-Content -Path $request.ResultPath
'@

        # Runs the runner against the fixture and returns what it reported, or $null when it had
        # to be killed -- which is what the deadlock looks like.
        function script:Invoke-SetBuildEnvironmentProcess {
            param(
                [hashtable]$PresetEnvironment = @{},
                [int]$TimeoutSecond = 120
            )

            $identifier = [Guid]::NewGuid().ToString('N')
            $resultPath = Join-Path -Path $TestDrive -ChildPath "result-$identifier.json"
            $requestPath = Join-Path -Path $TestDrive -ChildPath "request-$identifier.json"
            $request = [PSCustomObject]@{
                ModulePath        = $script:builtModulePath
                RepositoryPath    = $script:repositoryPath
                ResultPath        = $resultPath
                PresetEnvironment = $PresetEnvironment
            }
            $request | ConvertTo-Json | Set-Content -Path $requestPath

            # The same host the tests are running under, so the Windows PowerShell 5.1 leg
            # exercises Windows PowerShell.
            $startProcessParameters = @{
                FilePath     = (Get-Process -Id $PID).Path
                ArgumentList = @('-NoProfile', '-File', "`"$script:runnerPath`"", "`"$requestPath`"")
                PassThru     = $true
                NoNewWindow  = $true
            }
            $process = Start-Process @startProcessParameters

            if (-not $process.WaitForExit($TimeoutSecond * 1000)) {
                $process.Kill()
                return
            }
            if (-not (Test-Path -Path $resultPath)) {
                return
            }
            Get-Content -Path $resultPath -Raw | ConvertFrom-Json
        }
    }

    Context 'with a commit message larger than the pipe buffer' -Skip:(-not $script:gitAvailable) {

        BeforeAll {
            $script:result = Invoke-SetBuildEnvironmentProcess
        }

        It 'completes instead of hanging' {
            # Regression: #167. A $null result means the process had to be killed.
            $script:result | Should -Not -BeNullOrEmpty
        }

        It 'reports the whole commit message' {
            $script:result.CommitMessage | Should -Be $script:expectedCommitMessage
        }

        It 'still detects the build system correctly' {
            # The workaround borrows an Azure Pipelines variable; borrowing it must not make
            # BuildHelpers believe this is an Azure Pipelines build.
            $script:result.BuildSystem | Should -Be 'Unknown'
        }

        It 'still populates the other build variables' {
            $script:result.ProjectName | Should -Be 'BigCommitMessage'
            $script:result.BranchName | Should -Be 'main'
            $script:result.CommitHash | Should -Be $script:commitHash
        }

        It 'removes the borrowed environment variable' {
            $script:result.AzureVariablePresent | Should -BeFalse
        }
    }

    Context 'when the build system publishes a commit SHA' -Skip:(-not $script:gitAvailable) {

        BeforeAll {
            # GitHub Actions is the case that hung main: its branch of Get-BuildVariable runs git
            # against $env:GITHUB_SHA, and the switch picks it out of an unordered collection, so
            # supplying a message without hiding this variable is a coin toss.
            $presetEnvironment = @{
                GITHUB_SHA      = $script:commitHash
                GITHUB_WORKFLOW = 'ci'
                GITHUB_REF      = 'refs/heads/main'
            }
            $script:actionsResult = Invoke-SetBuildEnvironmentProcess -PresetEnvironment $presetEnvironment
        }

        It 'completes instead of hanging' {
            # Regression: #167, the CI half. This is the combination that hung both Windows legs.
            $script:actionsResult | Should -Not -BeNullOrEmpty
        }

        It 'reports the whole commit message' {
            $script:actionsResult.CommitMessage | Should -Be $script:expectedCommitMessage
        }

        It 'still detects the build system correctly' {
            $script:actionsResult.BuildSystem | Should -Be 'GitHub Actions'
        }

        It 'reports the commit hash the build system supplied' {
            $script:actionsResult.CommitHash | Should -Be $script:commitHash
        }

        It 'restores the suppressed variable' {
            $script:actionsResult.GitHubShaPresent | Should -BeTrue
            $script:actionsResult.GitHubSha | Should -Be $script:commitHash
        }
    }

    Context 'when the environment already supplies a commit message' -Skip:(-not $script:gitAvailable) {

        BeforeAll {
            $script:presetMessage = 'commit message supplied by the build system'
            $presetEnvironment = @{
                BUILD_SOURCEVERSIONMESSAGE = $script:presetMessage
            }
            $script:presetResult = Invoke-SetBuildEnvironmentProcess -PresetEnvironment $presetEnvironment
        }

        It 'completes instead of hanging' {
            $script:presetResult | Should -Not -BeNullOrEmpty
        }

        It 'leaves the supplied variable in place' {
            # A real Azure Pipelines build owns this variable. The workaround must not delete it.
            $script:presetResult.AzureVariablePresent | Should -BeTrue
            $script:presetResult.AzureCommitMessage | Should -Be $script:presetMessage
        }

        It 'uses the supplied message rather than reading the repository' {
            $script:presetResult.CommitMessage | Should -Be $script:presetMessage
        }
    }
}
