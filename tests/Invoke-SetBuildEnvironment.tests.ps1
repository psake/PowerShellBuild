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

            # BuildHelpers resolves the project name from the origin remote when it cannot find a
            # manifest, so the fixture declares one. It is never contacted.
            Push-Location -LiteralPath $script:repositoryPath
            try {
                git init --initial-branch 'main' . *> $null
                git config user.email 'fixture@example.invalid' *> $null
                git config user.name 'PowerShellBuild fixture' *> $null
                git remote add origin 'https://example.invalid/BigCommitMessage.git' *> $null
                git add --all *> $null
                git commit --file $messageFile *> $null
            } finally {
                Pop-Location
            }
        }

        # Script run by each child process. Reporting through a file keeps the assertions
        # independent of anything the child writes to its own output streams.
        $script:runnerPath = Join-Path -Path $TestDrive -ChildPath 'Invoke-SetBuildEnvironmentRunner.ps1'
        Set-Content -Path $script:runnerPath -Value @'
param(
    [string]$ModulePath,
    [string]$RepositoryPath,
    [string]$ResultPath,
    [string]$PresetCommitMessage
)

if ($PresetCommitMessage) {
    Set-Item -Path 'Env:BUILD_SOURCEVERSIONMESSAGE' -Value $PresetCommitMessage
}

Import-Module -Name $ModulePath -Force -ErrorAction Stop
Set-Location -LiteralPath $RepositoryPath

$module = Get-Module -Name 'PowerShellBuild'
& $module { Invoke-SetBuildEnvironment -Parameter @{ Force = $true } }

$result = [PSCustomObject]@{
    CommitMessage        = $env:BHCommitMessage
    BuildSystem          = $env:BHBuildSystem
    ProjectName          = $env:BHProjectName
    BranchName           = $env:BHBranchName
    AzureCommitMessage   = $env:BUILD_SOURCEVERSIONMESSAGE
    AzureVariablePresent = [bool](Test-Path -Path 'Env:BUILD_SOURCEVERSIONMESSAGE')
}
$result | ConvertTo-Json | Set-Content -Path $ResultPath
'@

        # Runs the runner against the fixture and returns what it reported, or $null when it had
        # to be killed -- which is what the deadlock looks like.
        function script:Invoke-SetBuildEnvironmentProcess {
            param(
                [string]$PresetCommitMessage,
                [int]$TimeoutSecond = 120
            )

            $resultPath = Join-Path -Path $TestDrive -ChildPath ('result-{0}.json' -f [Guid]::NewGuid())
            # Start-Process passes the argument list as one string, so every value that could
            # contain a space -- a path, or the message itself -- has to arrive quoted.
            $quote = { '"{0}"' -f $args[0] }
            $arguments = @(
                '-NoProfile'
                '-File', (& $quote $script:runnerPath)
                '-ModulePath', (& $quote $script:builtModulePath)
                '-RepositoryPath', (& $quote $script:repositoryPath)
                '-ResultPath', (& $quote $resultPath)
            )
            if ($PresetCommitMessage) {
                $arguments += @('-PresetCommitMessage', (& $quote $PresetCommitMessage))
            }

            # The same host the tests are running under, so the Windows PowerShell 5.1 leg
            # exercises Windows PowerShell.
            $hostExecutable = (Get-Process -Id $PID).Path
            $startProcessParameters = @{
                FilePath     = $hostExecutable
                ArgumentList = $arguments
                PassThru     = $true
                NoNewWindow  = $true
            }
            $process = Start-Process @startProcessParameters

            $exited = $process.WaitForExit($TimeoutSecond * 1000)
            if (-not $exited) {
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
            $expectedMessage = (@($script:commitSubject) + (1..$script:commitMessageLineCount).ForEach({ $script:commitBodyLine })) -join "`n"

            $script:result.CommitMessage | Should -Be $expectedMessage
        }

        It 'still detects the build system correctly' {
            # The workaround borrows an Azure Pipelines variable; borrowing it must not make
            # BuildHelpers believe this is an Azure Pipelines build.
            $script:result.BuildSystem | Should -Be 'Unknown'
        }

        It 'still populates the other build variables' {
            $script:result.ProjectName | Should -Be 'BigCommitMessage'
            $script:result.BranchName | Should -Be 'main'
        }

        It 'removes the borrowed environment variable' {
            $script:result.AzureVariablePresent | Should -BeFalse
        }
    }

    Context 'when the environment already supplies a commit message' -Skip:(-not $script:gitAvailable) {

        BeforeAll {
            $script:presetMessage = 'commit message supplied by the build system'
            $script:presetResult = Invoke-SetBuildEnvironmentProcess -PresetCommitMessage $script:presetMessage
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
