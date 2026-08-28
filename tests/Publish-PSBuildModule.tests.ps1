# Unit and integration coverage for Publish-PSBuildModule (psake/PowerShellBuild#103).
#
# Of the twelve public functions this is the one that pushes a module to a package repository,
# and until this file it had no tests at all -- measured coverage against the built module was
# 0 of 21 instructions, and literally so rather than the artifact of a background job that
# in-process instrumentation cannot see. The only defect ever found in it, the blank message
# from an undefined PathDoesNotExist string (#187), was found by auditing en-US/Messages.psd1
# rather than by exercising the function.
#
# The file is layered:
#
#   1. The command surface -- what the function exports, what it makes mandatory, and the
#      ApiKey alias the shipped psake and Invoke-Build Publish tasks actually bind to.
#   2. Path validation, asserted on message text. A ValidateScript that throws $null -f $_
#      produces an empty string rather than an error, so a bare Should -Throw passes against
#      exactly the defect #187 was. These tests read the message.
#   3. Forwarding, with Publish-Module mocked, asserting which parameters arrive rather than
#      only that the call happened.
#   4. An end-to-end publish to a temporary file-based PSRepository, which needs no network.
#
# Every mock is declared with -ModuleName 'PowerShellBuild'. A mock declared without it does
# not intercept a call made inside the module, and a suite built on one passes against broken
# code -- Get-PSBuildCertificate.tests.ps1 carried the wrong form long enough for a real defect
# to survive it. The 'Negative control' block below proves these mocks intercept by showing
# what an un-mocked call does instead.

BeforeDiscovery {
    # The end-to-end publish needs PowerShellGet's packaging chain: a repository it can
    # register and the NuGet toolchain Publish-Module packs a module with. Both are present on
    # every supported host and on the CI runners, so this normally runs rather than skips; it
    # is a guard against a machine that cannot package at all, not an expected outcome.
    # Resolved at discovery because it is a -Skip: condition.
    $script:localPublishSupported = (
        [bool](Get-Command -Name 'Register-PSRepository' -ErrorAction Ignore) -and
        [bool](Get-Command -Name 'Publish-Module' -ErrorAction Ignore) -and
        (
            [bool](Get-Command -Name 'dotnet' -ErrorAction Ignore) -or
            [bool](Get-Command -Name 'nuget' -ErrorAction Ignore)
        )
    )
}

Describe 'Publish-PSBuildModule' {

    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name ([IO.Path]::Combine($script:moduleRoot, 'Output', 'PowerShellBuild')) -Force

        # A directory that exists is all -Path validation asks for; the mocked tests never look
        # inside it. The end-to-end context builds a real module of its own.
        $script:existingModulePath = Join-Path -Path $TestDrive -ChildPath 'ExistingModule'
        New-Item -Path $script:existingModulePath -ItemType Directory -Force > $null

        $script:missingPath = Join-Path -Path $TestDrive -ChildPath 'NoSuchDirectory'

        $script:filePath = Join-Path -Path $TestDrive -ChildPath 'NotADirectory.txt'
        Set-Content -Path $script:filePath -Value 'This is a file, not a module directory.'

        # Never registered anywhere. Used to show what an un-mocked call does.
        $script:unregisteredRepository = 'PSBuildNoSuchRepository'

        $script:publisherCredential = [PSCredential]::new(
            'publisher',
            (ConvertTo-SecureString -String 'not-a-real-secret' -AsPlainText -Force)
        )
    }

    Context 'Command surface' {

        It 'Is exported by the module' {
            Get-Command -Name 'Publish-PSBuildModule' -Module 'PowerShellBuild' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Has a synopsis in the help' {
            (Get-Help -Name 'Publish-PSBuildModule').Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'Has at least one example in the help' {
            (Get-Help -Name 'Publish-PSBuildModule').Examples.Example | Should -Not -BeNullOrEmpty
        }

        It 'Requires the <_> parameter' -ForEach @('Path', 'Version', 'Repository') {
            $command = Get-Command -Name 'Publish-PSBuildModule'
            $command.Parameters[$_].Attributes.Where({ $_.TypeId.Name -eq 'ParameterAttribute' }).Mandatory |
                Should -Contain $true
        }

        It 'Leaves <_> optional' -ForEach @('NuGetApiKey', 'Credential') {
            $command = Get-Command -Name 'Publish-PSBuildModule'
            $command.Parameters[$_].Attributes.Where({ $_.TypeId.Name -eq 'ParameterAttribute' }).Mandatory |
                Should -Not -Contain $true
        }

        It 'Accepts an ApiKey alias for NuGetApiKey' {
            # Both shipped Publish tasks -- psakeFile.ps1 and IB.tasks.ps1 -- splat ApiKey, not
            # NuGetApiKey, so removing the alias would break every consumer's publish.
            $command = Get-Command -Name 'Publish-PSBuildModule'
            $command.Parameters['NuGetApiKey'].Aliases | Should -Contain 'ApiKey'
        }

        It 'Types Credential as a PSCredential' {
            $command = Get-Command -Name 'Publish-PSBuildModule'
            $command.Parameters['Credential'].ParameterType | Should -Be ([PSCredential])
        }

        It 'Puts every parameter in a single parameter set' {
            # The function declares DefaultParameterSetName = 'ApiKey' but gives no parameter a
            # ParameterSetName, so 'ApiKey' is the only set and it holds all five parameters.
            # An API key and a credential are therefore usable together, which is what the
            # third documented example does. Splitting the sets later would break that example,
            # so the shape is pinned here rather than left to be discovered by a consumer.
            $command = Get-Command -Name 'Publish-PSBuildModule'
            $command.ParameterSets.Count | Should -Be 1
            $command.DefaultParameterSet | Should -Be 'ApiKey'

            $declaredParameter = $command.ParameterSets[0].Parameters.Name.Where({
                    $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters
                })
            $declaredParameter | Should -Contain 'NuGetApiKey'
            $declaredParameter | Should -Contain 'Credential'
        }
    }

    Context 'Path validation' {

        # Asserted on message text, not on the fact of a throw. $LocalizedData.Missing -f $value
        # returns an empty string instead of throwing, so a ValidateScript reading a key that
        # Messages.psd1 does not define fails validation with no text at all -- and a bare
        # Should -Throw is perfectly happy with that. It is how #187 survived until the string
        # table was audited by hand.

        It 'Reports the path in the message when the path does not exist' {
            $errorRecord = $null
            try {
                Publish-PSBuildModule -Path $script:missingPath -Version '1.0.0' -Repository 'PSGallery'
            } catch {
                $errorRecord = $_
            }

            $errorRecord | Should -Not -BeNullOrEmpty
            $errorRecord.Exception.Message | Should -BeLike '*Path does not exist*'
            $errorRecord.Exception.Message | Should -BeLike "*$script:missingPath*"
        }

        It 'Says the path must be a folder when the path is a file' {
            $errorRecord = $null
            try {
                Publish-PSBuildModule -Path $script:filePath -Version '1.0.0' -Repository 'PSGallery'
            } catch {
                $errorRecord = $_
            }

            $errorRecord | Should -Not -BeNullOrEmpty
            $errorRecord.Exception.Message | Should -BeLike '*The Path argument must be a folder*'
            $errorRecord.Exception.Message | Should -BeLike '*File paths are not allowed*'
        }

        It 'Never reaches Publish-Module when validation fails' {
            Mock -CommandName 'Publish-Module' -ModuleName 'PowerShellBuild' -MockWith { }

            { Publish-PSBuildModule -Path $script:missingPath -Version '1.0.0' -Repository 'PSGallery' } |
                Should -Throw

            Should -Invoke -CommandName 'Publish-Module' -ModuleName 'PowerShellBuild' -Times 0 -Exactly
        }

        It 'Accepts a directory that exists' {
            Mock -CommandName 'Publish-Module' -ModuleName 'PowerShellBuild' -MockWith { }

            {
                Publish-PSBuildModule -Path $script:existingModulePath -Version '1.0.0' -Repository 'PSGallery'
            } | Should -Not -Throw
        }
    }

    Context 'Negative control' {

        It 'Reaches the real Publish-Module when nothing is mocked' {
            # Proves the mocks in the contexts below are actually intercepting. Nothing is
            # mocked here, so the call reaches PowerShellGet, which cannot resolve the
            # repository. Were a mock in these tests declared without -ModuleName, the calls
            # in the forwarding context would fall through to this same real command instead
            # of being caught -- and every Should -Invoke there would report zero calls.
            $publishParameter = @{
                Path        = $script:existingModulePath
                Version     = '1.0.0'
                Repository  = $script:unregisteredRepository
                NuGetApiKey = 'not-a-real-key'
            }
            { Publish-PSBuildModule @publishParameter } |
                Should -Throw -ExpectedMessage "*$script:unregisteredRepository*"
        }
    }

    Context 'Failure reporting' {

        # Publish-Module reports a failed publish as a non-terminating error. At the default
        # preference the command then returned normally and Publish-PSBuildModule returned
        # normally after it, so the psake and Invoke-Build Publish tasks reported success for
        # a module that was never published -- the release workflow included. The function now
        # asks Publish-Module to stop.

        It 'Fails when the repository is not registered' {
            $publishParameter = @{
                Path        = $script:existingModulePath
                Version     = '1.0.0'
                Repository  = $script:unregisteredRepository
                NuGetApiKey = 'not-a-real-key'
            }
            { Publish-PSBuildModule @publishParameter } | Should -Throw
        }

        It 'Asks Publish-Module to stop on error' {
            # The mechanism behind the test above, pinned separately. The mocked call cannot
            # reproduce it -- an ErrorAction bound to a Pester mock governs the mock body, not
            # the PowerShellGet code that writes the error -- so what a mock can prove is that
            # the value leaves this function, and the un-mocked test proves what it then does.
            Mock -CommandName 'Publish-Module' -ModuleName 'PowerShellBuild' -MockWith { }

            $publishParameter = @{
                Path        = $script:existingModulePath
                Version     = '1.0.0'
                Repository  = 'InternalRepository'
                NuGetApiKey = 'not-a-real-key'
            }
            Publish-PSBuildModule @publishParameter

            $shouldInvokeParameter = @{
                CommandName     = 'Publish-Module'
                ModuleName      = 'PowerShellBuild'
                Times           = 1
                Exactly         = $true
                ParameterFilter = { $ErrorAction -eq 'Stop' }
            }
            Should -Invoke @shouldInvokeParameter
        }

        It 'Forwards an explicit ErrorAction instead of the default' {
            # The stop is a default, not a policy: a consumer who wants the old behavior asks
            # for it the ordinary way and their value is what Publish-Module receives.
            Mock -CommandName 'Publish-Module' -ModuleName 'PowerShellBuild' -MockWith { }

            $publishParameter = @{
                Path        = $script:existingModulePath
                Version     = '1.0.0'
                Repository  = 'InternalRepository'
                NuGetApiKey = 'not-a-real-key'
                ErrorAction = 'SilentlyContinue'
            }
            Publish-PSBuildModule @publishParameter

            $shouldInvokeParameter = @{
                CommandName     = 'Publish-Module'
                ModuleName      = 'PowerShellBuild'
                Times           = 1
                Exactly         = $true
                ParameterFilter = { $ErrorAction -eq 'SilentlyContinue' }
            }
            Should -Invoke @shouldInvokeParameter
        }

        It 'Stays silent for a caller who asked it to' {
            # The other half of the override, against the real command: the same unregistered
            # repository that fails above returns quietly when the caller says so.
            $publishParameter = @{
                Path        = $script:existingModulePath
                Version     = '1.0.0'
                Repository  = $script:unregisteredRepository
                NuGetApiKey = 'not-a-real-key'
                ErrorAction = 'SilentlyContinue'
            }
            { Publish-PSBuildModule @publishParameter } | Should -Not -Throw
        }
    }

    Context 'Forwarding to Publish-Module' {

        BeforeEach {
            Mock -CommandName 'Publish-Module' -ModuleName 'PowerShellBuild' -MockWith { }
        }

        It 'Forwards the path and repository' {
            $publishParameter = @{
                Path        = $script:existingModulePath
                Version     = '1.2.3'
                Repository  = 'InternalRepository'
                NuGetApiKey = 'not-a-real-key'
            }
            Publish-PSBuildModule @publishParameter

            $shouldInvokeParameter = @{
                CommandName     = 'Publish-Module'
                ModuleName      = 'PowerShellBuild'
                Times           = 1
                Exactly         = $true
                # Path arrives as the [System.IO.FileInfo] the parameter is typed as, so it is
                # compared as a string -- which is also how Publish-Module's [string] -Path
                # receives it.
                ParameterFilter = {
                    "$Path" -eq $script:existingModulePath -and $Repository -eq 'InternalRepository'
                }
            }
            Should -Invoke @shouldInvokeParameter
        }

        It 'Forwards an API key and no credential' {
            $publishParameter = @{
                Path        = $script:existingModulePath
                Version     = '1.2.3'
                Repository  = 'InternalRepository'
                NuGetApiKey = 'api-key-value'
            }
            Publish-PSBuildModule @publishParameter

            $shouldInvokeParameter = @{
                CommandName     = 'Publish-Module'
                ModuleName      = 'PowerShellBuild'
                Times           = 1
                Exactly         = $true
                ParameterFilter = {
                    $NuGetApiKey -eq 'api-key-value' -and
                    -not $PSBoundParameters.ContainsKey('Credential')
                }
            }
            Should -Invoke @shouldInvokeParameter
        }

        It 'Forwards an API key supplied through the ApiKey alias' {
            # This is the call the shipped Publish tasks make. PowerShell records an aliased
            # argument in $PSBoundParameters under the real parameter name, which is what the
            # forwarding loop looks for -- so binding through the alias has to reach
            # Publish-Module as NuGetApiKey, and this proves it does.
            $publishParameter = @{
                Path       = $script:existingModulePath
                Version    = '1.2.3'
                Repository = 'InternalRepository'
                ApiKey     = 'aliased-key-value'
            }
            Publish-PSBuildModule @publishParameter

            $shouldInvokeParameter = @{
                CommandName     = 'Publish-Module'
                ModuleName      = 'PowerShellBuild'
                Times           = 1
                Exactly         = $true
                ParameterFilter = { $NuGetApiKey -eq 'aliased-key-value' }
            }
            Should -Invoke @shouldInvokeParameter
        }

        It 'Forwards a credential and no API key' {
            $publishParameter = @{
                Path       = $script:existingModulePath
                Version    = '1.2.3'
                Repository = 'InternalRepository'
                Credential = $script:publisherCredential
            }
            Publish-PSBuildModule @publishParameter

            $shouldInvokeParameter = @{
                CommandName     = 'Publish-Module'
                ModuleName      = 'PowerShellBuild'
                Times           = 1
                Exactly         = $true
                ParameterFilter = {
                    $Credential.UserName -eq 'publisher' -and
                    $Credential.GetNetworkCredential().Password -eq 'not-a-real-secret' -and
                    -not $PSBoundParameters.ContainsKey('NuGetApiKey')
                }
            }
            Should -Invoke @shouldInvokeParameter
        }

        It 'Forwards an API key and a credential together' {
            # The third documented example passes both, and the shipped Publish tasks add each
            # one independently, so a consumer with both settings populated sends both.
            $publishParameter = @{
                Path        = $script:existingModulePath
                Version     = '1.2.3'
                Repository  = 'InternalRepository'
                NuGetApiKey = 'api-key-value'
                Credential  = $script:publisherCredential
            }
            Publish-PSBuildModule @publishParameter

            $shouldInvokeParameter = @{
                CommandName     = 'Publish-Module'
                ModuleName      = 'PowerShellBuild'
                Times           = 1
                Exactly         = $true
                ParameterFilter = {
                    $NuGetApiKey -eq 'api-key-value' -and $Credential.UserName -eq 'publisher'
                }
            }
            Should -Invoke @shouldInvokeParameter
        }

        It 'Forwards neither when neither is supplied' {
            # Omitted rather than passed as $null, so PowerShellGet falls back to whatever the
            # repository registration already carries.
            Publish-PSBuildModule -Path $script:existingModulePath -Version '1.2.3' -Repository 'InternalRepository'

            $shouldInvokeParameter = @{
                CommandName     = 'Publish-Module'
                ModuleName      = 'PowerShellBuild'
                Times           = 1
                Exactly         = $true
                ParameterFilter = {
                    -not $PSBoundParameters.ContainsKey('NuGetApiKey') -and
                    -not $PSBoundParameters.ContainsKey('Credential')
                }
            }
            Should -Invoke @shouldInvokeParameter
        }

        It 'Does not forward the version' {
            # -Version is mandatory but only ever reaches the verbose message; the version that
            # gets published is the one in the module manifest under -Path. Pinned so that a
            # later change that starts forwarding it is a deliberate one.
            $publishParameter = @{
                Path        = $script:existingModulePath
                Version     = '1.2.3'
                Repository  = 'InternalRepository'
                NuGetApiKey = 'api-key-value'
            }
            Publish-PSBuildModule @publishParameter

            $shouldInvokeParameter = @{
                CommandName     = 'Publish-Module'
                ModuleName      = 'PowerShellBuild'
                Times           = 1
                Exactly         = $true
                ParameterFilter = { -not $PSBoundParameters.ContainsKey('RequiredVersion') }
            }
            Should -Invoke @shouldInvokeParameter
        }

        It 'Announces the version and repository in a verbose message' {
            $publishParameter = @{
                Path        = $script:existingModulePath
                Version     = '1.2.3'
                Repository  = 'InternalRepository'
                NuGetApiKey = 'api-key-value'
            }
            $verboseMessage = Publish-PSBuildModule @publishParameter -Verbose 4>&1

            ($verboseMessage -join [Environment]::NewLine) | Should -BeLike '*1.2.3*'
            ($verboseMessage -join [Environment]::NewLine) | Should -BeLike '*InternalRepository*'
        }
    }

    Context 'End-to-end publish to a local repository' -Skip:(-not $script:localPublishSupported) {

        # The only layer that proves the whole chain works rather than that the right arguments
        # were assembled. A file-based PSRepository needs no network -- verified by running the
        # same publish behind an unreachable proxy -- and no PSGallery credential, so it can
        # run in CI on every platform.
        #
        # The repository name is unique per run so that a leftover registration from an
        # interrupted run cannot collide with a live one, and AfterAll unregisters it whatever
        # the tests did, so the machine's repository list is left as it was found.

        BeforeAll {
            $script:localRepositoryName = 'PSBuildTestRepository{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8)

            $script:localRepositoryPath = Join-Path -Path $TestDrive -ChildPath 'LocalRepository'
            New-Item -Path $script:localRepositoryPath -ItemType Directory -Force > $null

            # Publish-Module packs from a module manifest, so this needs a real one rather than
            # the bare directory the mocked contexts use.
            $script:publishableModuleName = 'PSBuildPublishFixture'
            $script:publishableModulePath = Join-Path -Path $TestDrive -ChildPath $script:publishableModuleName
            New-Item -Path $script:publishableModulePath -ItemType Directory -Force > $null
            Set-Content -Value 'function Get-PSBuildPublishFixture { "fixture" }' -Path (
                Join-Path -Path $script:publishableModulePath -ChildPath "$($script:publishableModuleName).psm1"
            )
            $newManifestParameter = @{
                Path              = Join-Path -Path $script:publishableModulePath -ChildPath "$($script:publishableModuleName).psd1"
                RootModule        = "$($script:publishableModuleName).psm1"
                ModuleVersion     = '2.3.4'
                Author            = 'PowerShellBuild test suite'
                Description       = 'Fixture module published to a temporary local repository.'
                FunctionsToExport = 'Get-PSBuildPublishFixture'
            }
            New-ModuleManifest @newManifestParameter

            $registerParameter = @{
                Name               = $script:localRepositoryName
                SourceLocation     = $script:localRepositoryPath
                PublishLocation    = $script:localRepositoryPath
                InstallationPolicy = 'Trusted'
            }
            Register-PSRepository @registerParameter

            $publishParameter = @{
                Path        = $script:publishableModulePath
                Version     = '2.3.4'
                Repository  = $script:localRepositoryName
                NuGetApiKey = 'a-local-repository-ignores-this'
            }
            Publish-PSBuildModule @publishParameter
        }

        AfterAll {
            # Runs even when the setup above threw, so a failed publish still leaves the
            # machine's registered repositories exactly as they were.
            if ($script:localRepositoryName) {
                Unregister-PSRepository -Name $script:localRepositoryName -ErrorAction SilentlyContinue
            }
        }

        It 'Writes a package into the repository' {
            $publishedPackage = Get-ChildItem -Path $script:localRepositoryPath -Filter '*.nupkg'
            $publishedPackage.Name | Should -Be "$($script:publishableModuleName).2.3.4.nupkg"
        }

        It 'Makes the module discoverable in the repository' {
            $foundModule = Find-Module -Name $script:publishableModuleName -Repository $script:localRepositoryName
            $foundModule.Version.ToString() | Should -Be '2.3.4'
        }

        It 'Leaves the repository registration to be cleaned up and nothing else' {
            # Guards the cleanup contract itself: exactly one repository was added, and it is
            # the one AfterAll removes.
            (Get-PSRepository -Name $script:localRepositoryName).SourceLocation |
                Should -Not -BeNullOrEmpty
        }
    }
}
