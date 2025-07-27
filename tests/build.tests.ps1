# spell-checker:ignore excludeme
BeforeDiscovery {
    if ($null -eq $env:BHProjectPath) {
        $path = Join-Path -Path $PSScriptRoot -ChildPath '..\build.ps1'
        . $path -Task Build
    }
    $manifest = Import-PowerShellDataFile -Path $env:BHPSModuleManifest
    $outputDir = Join-Path -Path $env:BHProjectPath -ChildPath 'Output'
    $outputModDir = Join-Path -Path $outputDir -ChildPath $env:BHProjectName
    $outputModVerDir = Join-Path -Path $outputModDir -ChildPath $manifest.ModuleVersion
    $global:outputModVerManifest = Join-Path -Path $outputModVerDir -ChildPath "$($env:BHProjectName).psd1"

    # Get module commands
    # Remove all versions of the module from the session. Pester can't handle multiple versions.
    Get-Module $env:BHProjectName | Remove-Module -Force -ErrorAction Ignore
    Import-Module -Name $outputModVerManifest -Verbose:$false -ErrorAction Stop
}
Describe 'Build' {
    BeforeAll {
        <#
        We prepare the tests by copying the TestModule to a temporary location
        and setting the output path to a known location.
        #>

        $script:testModuleSource = Join-Path $TestDrive 'TestModule'
        Copy-Item $PSScriptRoot/fixtures/TestModule $script:testModuleSource -Recurse
        Set-Location $script:testModuleSource
        # Hack for GH Actions
        # For some reason, the TestModule build process create the output in the project root
        # and not relative to it's own build file.
        if ($env:GITHUB_ACTION) {
            $script:testModuleOutputPath = [IO.Path]::Combine($env:BHProjectPath, 'Output', 'TestModule', '0.1.0')
        } else {
            $script:testModuleOutputPath = [IO.Path]::Combine($script:testModuleSource, 'Output', 'TestModule', '0.1.0')
        }

        # Capture any of the jobs for cleanup later
        [array]$script:jobs = @()
    }

    AfterAll {
        Set-Location $PSScriptRoot
    }

    Context 'Compile module' {
        BeforeAll {
            Write-Host "PSScriptRoot: $script:testModuleSource"
            Write-Host "OutputPath: $script:testModuleOutputPath"

            # build is PS job so psake doesn't freak out because it's nested
            $script:jobs += Start-Job -ScriptBlock {
                param($testModuleSource, $outputModVerManifest)
                Set-Location -Path $using:testModuleSource
                # We want to load the current build of PowerShellBuild so we use a
                # global variable to store the output path.
                $global:PSBOutput = $outputModVerManifest
                $global:PSBuildCompile = $true
                ./build.ps1 -Task Build
            } -WorkingDirectory $script:testModuleSource -ArgumentList $testModuleSource, $outputModVerManifest | Wait-Job
        }
        AfterAll {
            Remove-Item $script:testModuleOutputPath -Recurse -Force
            $jobs | Stop-Job -ErrorAction Ignore
            $jobs | Remove-Job -ErrorAction Ignore
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
            $copyItemSplat = @{
                Path        = "$PSScriptRoot/fixtures/DotSource.psm1"
                Destination = "$script:testModuleSource/TestModule/TestModule.psm1"
                Force       = $true
            }
            # Overwrite the existing PSM1 with the dot-sourced version
            Copy-Item @copyItemSplat
            # build is PS job so psake doesn't freak out because it's nested
            $script:jobs += Start-Job -ScriptBlock {
                param($testModuleSource, $outputModVerManifest)
                Set-Location -Path $testModuleSource
                # We want to load the current build of PowerShellBuild so we use a
                # global variable to store the output path.
                $global:PSBOutput = $outputModVerManifest
                $global:PSBuildCompile = $false
                ./build.ps1 -Task Build
            } -WorkingDirectory $script:testModuleSource -ArgumentList $testModuleSource, $outputModVerManifest | Wait-Job
        }
        AfterAll {
            Remove-Item $script:testModuleOutputPath -Recurse -Force
            $jobs | Stop-Job -ErrorAction Ignore
            $jobs | Remove-Job -ErrorAction Ignore
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
            [IO.Path]::Combine($script:testModuleOutputPath, "en-US", "TestModule-help.xml") | Should -Exist
        }
    }
    Context 'Overwrite Docs' {
        BeforeAll {

            Write-Host "PSScriptRoot: $script:testModuleSource"
            Write-Host "OutputPath: $script:testModuleOutputPath"

            $copyItemSplat = @{
                Path        = "$PSScriptRoot/fixtures/DotSource.psm1"
                Destination = "$script:testModuleSource/TestModule/TestModule.psm1"
                Force       = $true
            }
            # Overwrite the existing PSM1 with the dot-sourced version
            Copy-Item @copyItemSplat
            # Build once, and then we'll modify
            $script:jobs += Start-Job -ScriptBlock {
                param($testModuleSource, $outputModVerManifest)
                Set-Location -Path $using:testModuleSource
                # We want to load the current build of PowerShellBuild so we use a
                # global variable to store the output path.
                $global:PSBOutput = $global:outputModVerManifest
                $global:PSBuildCompile = $false
                ./build.ps1 -Task Build
            } -WorkingDirectory $script:testModuleSource -ArgumentList $testModuleSource, $outputModVerManifest | Wait-Job

            # Replace with a different string to test the overwrite
            $script:docPath = [IO.Path]::Combine($script:testModuleSource, "docs", "en-US", "Get-HelloWorld.md")
            $script:original = Get-Content $docPath -Raw
            $new = $original -replace 'Hello World', 'Hello Universe'
            Set-Content $docPath -Value $new -Force

            # Update the psake file
            $psakeFile = [IO.Path]::Combine($script:testModuleSource, "psakeFile.ps1")
            $psakeFileContent = Get-Content $psakeFile -Raw
            $psakeFileContent = $psakeFileContent -replace '\$PSBPreference.Docs.Overwrite = \$false', '$PSBPreference.Docs.Overwrite = $true'
            Set-Content $psakeFile -Value $psakeFileContent -Force

            # build is PS job so psake doesn't freak out because it's nested
            $script:jobs += Start-Job -ScriptBlock {
                param($testModuleSource, $outputModVerManifest)
                Set-Location -Path $using:testModuleSource
                # We want to load the current build of PowerShellBuild so we use a
                # global variable to store the output path.
                $global:PSBOutput = $global:outputModVerManifest
                $global:PSBuildCompile = $false
                ./build.ps1 -Task Build
            } -WorkingDirectory $script:testModuleSource -ArgumentList $testModuleSource, $outputModVerManifest | Wait-Job
        }

        AfterAll {
            Remove-Item $script:testModuleOutputPath -Recurse -Force
            $jobs | Stop-Job -ErrorAction Ignore
            $jobs | Remove-Job -ErrorAction Ignore
        }

        It 'Can Overwrite the Docs' {
            # Test that the file reset as expected
            Get-Content $script:docPath -Raw | Should -BeExactly $script:original
        }
    }
}
