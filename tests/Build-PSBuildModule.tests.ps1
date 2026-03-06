Describe 'Build-PSBuildModule' {
    BeforeAll {
        . "$PSScriptRoot/../PowerShellBuild/Public/Build-PSBuildModule.ps1"
    }

    BeforeEach {
        $script:LocalizedData = @{
            AddingFileToPsm1 = 'Adding file {0}'
        }
    }

    It 'copies README into culture about-help file when ReadMePath is provided' {
        Mock Test-Path {
            if ($LiteralPath -eq '/tmp/out') { return $false }
            if ($Path -eq '/tmp/out/en-US' -and $PathType -eq 'Container') { return $false }
            return $false
        }
        Mock New-Item {}
        Mock Get-ChildItem { @() }
        Mock Copy-Item {}
        Mock Update-Metadata {}

        Build-PSBuildModule \
            -Path '/tmp/src' \
            -DestinationPath '/tmp/out' \
            -ModuleName 'TestModule' \
            -ReadMePath '/tmp/src/README.md' \
            -Culture 'en-US'

        Should -Invoke New-Item -Times 1 -ParameterFilter { $Path -eq '/tmp/out' -and $ItemType -eq 'Directory' }
        Should -Invoke New-Item -Times 1 -ParameterFilter { $Path -eq '/tmp/out/en-US' -and $Type -eq 'Directory' -and $Force }
        Should -Invoke Copy-Item -Times 1 -ParameterFilter {
            $LiteralPath -eq '/tmp/src/README.md' -and
            $Destination -eq '/tmp/out/en-US/about_TestModule.help.txt' -and
            $Force
        }
    }

    It 'updates manifest FunctionsToExport from Public/*.ps1 basenames' {
        Mock Test-Path { $true }
        Mock Copy-Item {}
        Mock Remove-Item {}
        Mock Update-Metadata {}

        Mock Get-ChildItem {
            @()
        } -ParameterFilter { $Path -eq '/tmp/src' -and $Include -contains '*.psm1' }

        Mock Get-ChildItem {
            @(
                [pscustomobject]@{ Name = 'skip.tmp'; FullName = '/tmp/out/skip.tmp' }
            )
        } -ParameterFilter { $Path -eq '/tmp/out' -and $Recurse }

        Mock Get-ChildItem {
            @(
                [pscustomobject]@{ BaseName = 'Get-Foo' },
                [pscustomobject]@{ BaseName = 'Set-Bar' }
            )
        } -ParameterFilter { $Path -eq '/tmp/src/Public/*.ps1' -and $Recurse }

        Build-PSBuildModule \
            -Path '/tmp/src' \
            -DestinationPath '/tmp/out' \
            -ModuleName 'TestModule' \
            -Exclude @('\\.tmp$')

        Should -Invoke Update-Metadata -Times 1 -ParameterFilter {
            $Path -eq '/tmp/out/TestModule.psd1' -and
            $PropertyName -eq 'FunctionsToExport' -and
            $Value.Count -eq 2 -and
            $Value[0] -eq 'Get-Foo' -and
            $Value[1] -eq 'Set-Bar'
        }
    }
}
