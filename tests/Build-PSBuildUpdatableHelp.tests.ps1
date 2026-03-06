Describe 'Build-PSBuildUpdatableHelp' {
    BeforeAll {
        . "$PSScriptRoot/../PowerShellBuild/Public/Build-PSBuildUpdatableHelp.ps1"
    }

    BeforeEach {
        $script:LocalizedData = @{
            MakeCabNotAvailable      = 'MakeCab not available on this platform.'
            DirectoryAlreadyExists   = 'Directory {0} already exists.'
        }

        $script:ModuleName = 'PSBuildModule'
        $script:moduleOutDir = '/tmp/module-out'
        $script:newCabCalls = @()
    }

    It 'warns and exits early when running on non-Windows hosts' {
        Mock Write-Warning {}
        Mock Get-ChildItem { throw 'should not be called' }
        Mock New-Item {}
        Mock New-ExternalHelpCab {}

        $script:IsWindows = $false

        Build-PSBuildUpdatableHelp -DocsPath '/tmp/docs' -OutputPath '/tmp/out'

        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -eq 'MakeCab not available on this platform.' }
        Should -Invoke Get-ChildItem -Times 0
        Should -Invoke New-ExternalHelpCab -Times 0
    }

    It 'creates output folder and generates one cab per locale on Windows' {
        Mock Test-Path { $false }
        Mock New-Item {}
        Mock Get-ChildItem {
            @(
                [pscustomobject]@{ Name = 'en-US' },
                [pscustomobject]@{ Name = 'fr-FR' }
            )
        } -ParameterFilter { $Path -eq '/tmp/docs' -and $Directory }
        Mock New-ExternalHelpCab {
            $script:newCabCalls += $PSBoundParameters
        }

        $script:IsWindows = $true

        Build-PSBuildUpdatableHelp -DocsPath '/tmp/docs' -OutputPath '/tmp/out' -Module 'MyModule'

        Should -Invoke New-Item -Times 1 -ParameterFilter { $Path -eq '/tmp/out' -and $ItemType -eq 'Directory' }
        $script:newCabCalls.Count | Should -Be 2

        $script:newCabCalls[0].CabFilesFolder | Should -Be ([IO.Path]::Combine('/tmp/module-out', 'en-US'))
        $script:newCabCalls[0].LandingPagePath | Should -Be ([IO.Path]::Combine('/tmp/docs', 'en-US', 'MyModule.md'))
        $script:newCabCalls[0].OutputFolder | Should -Be '/tmp/out'

        $script:newCabCalls[1].CabFilesFolder | Should -Be ([IO.Path]::Combine('/tmp/module-out', 'fr-FR'))
        $script:newCabCalls[1].LandingPagePath | Should -Be ([IO.Path]::Combine('/tmp/docs', 'fr-FR', 'MyModule.md'))
        $script:newCabCalls[1].OutputFolder | Should -Be '/tmp/out'
    }

    It 'cleans existing output folder before generating cabs on Windows' {
        Mock Test-Path { $true }
        Mock Get-ChildItem {
            @(
                [pscustomobject]@{ Name = 'en-US' }
            )
        } -ParameterFilter { $Path -eq '/tmp/docs' -and $Directory }
        Mock Get-ChildItem {
            @(
                [pscustomobject]@{ FullName = '/tmp/out/existing.cab' }
            )
        } -ParameterFilter { $Path -eq '/tmp/out' }
        Mock Remove-Item {}
        Mock New-ExternalHelpCab {
            $script:newCabCalls += $PSBoundParameters
        }
        Mock Write-Verbose {}

        $script:IsWindows = $true

        Build-PSBuildUpdatableHelp -DocsPath '/tmp/docs' -OutputPath '/tmp/out' -Module 'MyModule'

        Should -Invoke Write-Verbose -Times 1
        Should -Invoke Remove-Item -Times 1 -ParameterFilter { $Recurse -and $Force }
        Should -Invoke New-ExternalHelpCab -Times 1
    }
}
