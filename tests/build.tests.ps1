# spell-checker:ignore excludeme
Describe 'Build' {

    BeforeAll {
        $tempDir = Join-Path $TestDrive 'TestModule'
        Copy-Item $PSScriptRoot/fixtures/TestModule $tempDir -Recurse
        Set-Location $tempDir

        # Capture any of the jobs for cleanup later
        [array]$script:jobs = @()

        $path = 'Output/TestModule/0.1.0'
        $script:testModuleOutputPath = Join-Path . $path
    }

    AfterAll {
        Set-Location $PSScriptRoot
        $jobs | Stop-Job -ErrorAction Ignore
        $jobs | Remove-Job -ErrorAction Ignore
    }

    Context 'Compile module' {
        BeforeAll {
            Write-Host "PSScriptRoot: $tempDir"
            Write-Host "OutputPath: $script:testModuleOutputPath"

            # build is PS job so psake doesn't freak out because it's nested
            $script:jobs += Start-Job -Scriptblock {
                Set-Location $using:tempDir
                $global:PSBuildCompile = $true
                ./build.ps1 -Task Build
            } -WorkingDirectory $script:testModuleSource | Wait-Job
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
            $script:jobs += Start-Job -Scriptblock {
                Set-Location $using:tempDir
                $global:PSBuildCompile = $false
                ./build.ps1 -Task Build
            } -WorkingDirectory $script:testModuleSource | Wait-Job
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
    Context 'Overwrite Docs' {
        BeforeAll {

            Write-Host "PSScriptRoot: $tempDir"
            Write-Host "OutputPath: $script:testModuleOutputPath"

            # Replace with a different string to test the overwrite
            $script:docPath = "$tempDir/docs/en-US/Get-HelloWorld.md"
            $script:original = Get-Content $docPath -Raw
            $new = $original -replace 'Hello World', 'Hello Universe'
            Set-Content $docPath -Value $new -Force

            # Update the psake file
            $psakeFile = "$tempDir/psakeFile.ps1"
            $psakeFileContent = Get-Content $psakeFile -Raw
            $psakeFileContent = $psakeFileContent -replace '\$PSBPreference.Docs.Overwrite = \$false', '$PSBPreference.Docs.Overwrite = $true'
            Set-Content $psakeFile -Value $psakeFileContent -Force

            # build is PS job so psake doesn't freak out because it's nested
            $script:jobs += Start-Job -Scriptblock {
                Set-Location $using:tempDir
                $global:PSBuildCompile = $true
                ./build.ps1 -Task Build
            } | Wait-Job
        }

        AfterAll {
            Remove-Item $script:testModuleOutputPath -Recurse -Force
        }
        It 'Can Overwrite the Docs' {
            # Test that the file reset as expected
            Get-Content $script:docPath -Raw | Should -BeExactly $script:original
        }
    }
}
