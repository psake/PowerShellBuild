# spell-checker:ignore excludeme
BeforeDiscovery {
    # Cabinet generation shells out to makecab.exe. $IsWindows does not exist on Windows
    # PowerShell 5.1, so its absence also means Windows.
    $script:onWindows = $IsWindows -or $null -eq $IsWindows
}

Describe 'Build' {

    BeforeAll {
        # Hack for GH Actions
        # For some reason, the TestModule build process create the output in the project root
        # and not relative to it's own build file.
        if ($env:GITHUB_ACTION) {
            $script:testModuleSource = [IO.Path]::Combine($PSScriptRoot, 'TestModule')
            $script:testModuleOutputPath = [IO.Path]::Combine($env:BHProjectPath, 'Output', 'TestModule', '0.1.0')
        } else {
            $script:testModuleSource = [IO.Path]::Combine($PSScriptRoot, 'TestModule')
            $script:testModuleOutputPath = [IO.Path]::Combine($script:testModuleSource, 'Output', 'TestModule', '0.1.0')
        }
    }

    Context 'Compile module' {
        BeforeAll {

            Write-Host "PSScriptRoot: $PSScriptRoot"
            Write-Host "OutputPath: $script:testModuleOutputPath"

            # build is PS job so psake doesn't freak out because it's nested
            # NOTE: the scriptblock Set-Location handles the working directory;
            # Start-Job -WorkingDirectory is PS 6+ only and breaks on Windows PowerShell 5.1.
            Start-Job -Scriptblock {
                Set-Location -Path $using:testModuleSource
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
            # NOTE: the scriptblock Set-Location handles the working directory;
            # Start-Job -WorkingDirectory is PS 6+ only and breaks on Windows PowerShell 5.1.
            Start-Job -Scriptblock {
                Set-Location -Path $using:testModuleSource
                $global:PSBuildCompile = $false
                ./build.ps1 -Task Build
            } | Wait-Job
            Write-Debug "TestModule output path: $script:testModuleSource"
            $items = Get-ChildItem -Path $script:testModuleSource -Recurse -File
            Write-Debug ($items | Format-Table FullName | Out-String)
            Write-Debug "TestModule output path: $script:testModuleOutputPath"
            $items = Get-ChildItem -Path $script:testModuleOutputPath -Recurse -File
            Write-Debug ($items | Format-Table FullName | Out-String)
        }

        AfterAll {
            Remove-Item $script:testModuleOutputPath -Recurse -Force
        }

        It 'Creates module' {
            $script:testModuleOutputPath | Should -Exist
        }

        It '<_> should exist' -ForEach @(
            "TestModule.psd1",
            "TestModule.psm1",
            "Public",
            "Private"
        ) {
            Join-Path -Path $script:testModuleOutputPath -ChildPath $_ | Should -Exist
        }

        It 'Does not contain excluded stuff' {
            (Get-ChildItem -Path $script:testModuleOutputPath -File -Filter '*excludeme*' -Recurse).Count | Should -Be 0
        }

        It 'Has MAML help XML' {
            "$script:testModuleOutputPath/en-US/TestModule-help.xml" | Should -Exist
        }
    }

    Context 'Updatable help task' -Skip:(-not $script:onWindows) {

        # Exercises the GenerateUpdatableHelp TASK, not just Build-PSBuildUpdatableHelp.
        # psake/PowerShellBuild#169 defect 3 lived in the wiring rather than the function: the
        # task passed neither the module name nor the module output path, so every
        # function-level fix could pass while the task stayed broken. Only running the task
        # catches that, and psake cannot nest, so it runs in a job like the builds above.
        BeforeAll {
            $script:updatableHelpOutputPath = if ($env:GITHUB_ACTION) {
                [IO.Path]::Combine($env:BHProjectPath, 'Output', 'UpdatableHelp')
            } else {
                [IO.Path]::Combine($script:testModuleSource, 'Output', 'UpdatableHelp')
            }

            # Not received, matching the contexts above -- psake writes its task banner and
            # build report to the host, and receiving them here would interleave that with
            # Pester's own output.
            Start-Job -ScriptBlock {
                Set-Location -Path $using:testModuleSource
                ./build.ps1 -Task GenerateUpdatableHelp
            } | Wait-Job > $null
        }

        AfterAll {
            Remove-Item $script:updatableHelpOutputPath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $script:testModuleOutputPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Produces a help cabinet' {
            Get-ChildItem -Path $script:updatableHelpOutputPath -Filter '*.cab' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Produces the help info manifest' {
            Get-ChildItem -Path $script:updatableHelpOutputPath -Filter '*HelpInfo.xml' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }
    }
}
