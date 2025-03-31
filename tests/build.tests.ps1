# spell-checker:ignore excludeme
Describe 'Build' {

    BeforeAll {
        # Hack for GH Actions
        # For some reason, the TestModule build process create the output in the project root
        # and not relative to it's own build file.
        if ($env:GITHUB_ACTION) {
            $script:testModuleOutputPath = [IO.Path]::Combine($env:BHProjectPath, 'Output', 'TestModule', '0.1.0')
        } else {
            $script:testModuleOutputPath = [IO.Path]::Combine($env:BHProjectPath, 'tests', 'TestModule', 'Output', 'TestModule', '0.1.0')
        }
    }

    Context 'Compile module' {
        BeforeAll {

            Write-Host "PSScriptRoot: $PSScriptRoot"
            Write-Host "OutputPath: $script:testModuleOutputPath"

            # build is PS job so psake doesn't freak out because it's nested
            Start-Job -ScriptBlock {
                Set-Location $using:PSScriptRoot/TestModule
                $global:PSBuildCompile = $true
                ./build.ps1 -Task Build
            } | Wait-Job
        }

        AfterAll {
            Remove-Item $script:testModuleOutputPath -Recurse -Force
        }

        It 'Creates module' {
            $script:testModuleOutputPath | Should -Exist
        }

        It 'Has PSD1 and monolithic PSM1' {
            (Get-ChildItem -Path $script:testModuleOutputPath -File).Count | Should -Be 2
            "$script:testModuleOutputPath/TestModule.psd1" | Should -Exist
            "$script:testModuleOutputPath/TestModule.psm1" | Should -Exist
            "$script:testModuleOutputPath/Public" | Should -Not -Exist
            "$script:testModuleOutputPath/Private" | Should -Not -Exist
        }

        It 'Has module header text' {
            "$script:testModuleOutputPath/TestModule.psm1" | Should -FileContentMatch '# Module Header'
        }

        It 'Has module footer text' {
            "$script:testModuleOutputPath/TestModule.psm1" | Should -FileContentMatch '# Module Footer'
        }

        It 'Has function header text' {
            "$script:testModuleOutputPath/TestModule.psm1" | Should -FileContentMatch '# Function header'
        }

        It 'Has function footer text' {
            "$script:testModuleOutputPath/TestModule.psm1" | Should -FileContentMatch '# Function footer'
        }

        It 'Does not contain excluded files' {
            (Get-ChildItem -Path $script:testModuleOutputPath -File -Filter '*excludeme*' -Recurse).Count | Should -Be 0
            "$script:testModuleOutputPath/TestModule.psm1" | Should -Not -FileContentMatch '=== EXCLUDE ME ==='
        }

        It 'Has MAML help XML' {
            "$script:testModuleOutputPath/en-US/TestModule-help.xml" | Should -Exist
        }
    }

    Context 'Dot-sourced module' {
        BeforeAll {
            # build is PS job so psake doesn't freak out because it's nested
            Start-Job -ScriptBlock {
                Set-Location $using:PSScriptRoot/TestModule
                $global:PSBuildCompile = $false
                ./build.ps1 -Task Build
            } | Wait-Job
        }

        AfterAll {
            Remove-Item $script:testModuleOutputPath -Recurse -Force
        }

        It 'Creates module' {
            $script:testModuleOutputPath | Should -Exist
        }

        It 'Has PSD1 and dot-sourced functions' {
            (Get-ChildItem -Path $script:testModuleOutputPath).Count | Should -Be 6
            "$script:testModuleOutputPath/TestModule.psd1" | Should -Exist
            "$script:testModuleOutputPath/TestModule.psm1" | Should -Exist
            "$script:testModuleOutputPath/Public" | Should -Exist
            "$script:testModuleOutputPath/Private" | Should -Exist
        }

        It 'Does not contain excluded stuff' {
            (Get-ChildItem -Path $script:testModuleOutputPath -File -Filter '*excludeme*' -Recurse).Count | Should -Be 0
        }

        It 'Has MAML help XML' {
            "$script:testModuleOutputPath/en-US/TestModule-help.xml" | Should -Exist
        }
    }
}
