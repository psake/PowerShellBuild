Describe 'Build-PSBuildMarkdown' {
    BeforeAll {
        . "$PSScriptRoot/../PowerShellBuild/Public/Build-PSBuildMarkdown.ps1"
    }

    BeforeEach {
        $script:LocalizedData = @{
            NoCommandsExported          = 'No commands exported.'
            FailedToGenerateMarkdownHelp = 'Failed to generate markdown help: {0}'
        }

        $script:newMarkdownParams = $null
        $script:updateMarkdownParams = @()
    }

    It 'warns and exits when module exports no commands' {
        Mock Import-Module {
            [pscustomobject]@{ ExportedCommands = @() }
        }
        Mock Write-Warning {}
        Mock New-MarkdownHelp {}
        Mock Remove-Module {}

        Build-PSBuildMarkdown \
            -ModulePath '/tmp/module' \
            -ModuleName 'MyModule' \
            -DocsPath '/tmp/docs' \
            -Locale 'en-US' \
            -Overwrite:$false \
            -AlphabeticParamsOrder:$true \
            -ExcludeDontShow:$false \
            -UseFullTypeName:$false

        Should -Invoke Write-Warning -Times 1
        Should -Invoke New-MarkdownHelp -Times 0
        Should -Invoke Remove-Module -Times 1 -ParameterFilter { $Name -eq 'MyModule' }
    }

    It 'generates markdown help without force when overwrite is false' {
        Mock Import-Module {
            [pscustomobject]@{ ExportedCommands = @{ Test = 'Test-Command' } }
        }
        Mock Test-Path { $false }
        Mock New-Item {}
        Mock Get-ChildItem { @() }
        Mock New-MarkdownHelp {
            $script:newMarkdownParams = $PSBoundParameters
        }
        Mock Remove-Module {}

        Build-PSBuildMarkdown \
            -ModulePath '/tmp/module' \
            -ModuleName 'MyModule' \
            -DocsPath '/tmp/docs' \
            -Locale 'en-US' \
            -Overwrite:$false \
            -AlphabeticParamsOrder:$true \
            -ExcludeDontShow:$true \
            -UseFullTypeName:$false

        Should -Invoke New-Item -Times 1 -ParameterFilter { $Path -eq '/tmp/docs' -and $ItemType -eq 'Directory' }
        $script:newMarkdownParams.Module | Should -Be 'MyModule'
        $script:newMarkdownParams.Locale | Should -Be 'en-US'
        $script:newMarkdownParams.OutputFolder | Should -Be ([IO.Path]::Combine('/tmp/docs', 'en-US'))
        $script:newMarkdownParams.ErrorAction | Should -Be 'SilentlyContinue'
        $script:newMarkdownParams.ContainsKey('Force') | Should -BeFalse
    }

    It 'updates existing markdown and forces generation when overwrite is true' {
        Mock Import-Module {
            [pscustomobject]@{ ExportedCommands = @{ Test = 'Test-Command' } }
        }
        Mock Test-Path { $true }
        Mock Get-ChildItem {
            @('existing.md')
        } -ParameterFilter { $LiteralPath -eq '/tmp/docs' -and $Filter -eq '*.md' -and $Recurse }
        Mock Get-ChildItem {
            @([pscustomobject]@{ FullName = '/tmp/docs/en-US' })
        } -ParameterFilter { $LiteralPath -eq '/tmp/docs' -and $Directory }
        Mock Update-MarkdownHelp {
            $script:updateMarkdownParams += $PSBoundParameters
        }
        Mock New-MarkdownHelp {
            $script:newMarkdownParams = $PSBoundParameters
        }
        Mock Remove-Module {}

        Build-PSBuildMarkdown \
            -ModulePath '/tmp/module' \
            -ModuleName 'MyModule' \
            -DocsPath '/tmp/docs' \
            -Locale 'en-US' \
            -Overwrite:$true \
            -AlphabeticParamsOrder:$false \
            -ExcludeDontShow:$false \
            -UseFullTypeName:$true

        Should -Invoke Update-MarkdownHelp -Times 1 -ParameterFilter { $Path -eq '/tmp/docs/en-US' }
        $script:newMarkdownParams.ContainsKey('Force') | Should -BeTrue
        $script:newMarkdownParams.Force | Should -BeTrue
        $script:newMarkdownParams.ContainsKey('ErrorAction') | Should -BeFalse
    }
}
