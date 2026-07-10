properties {
    $settings = . ([IO.Path]::Combine($PSScriptRoot, 'build.settings.ps1'))
    if ($galleryApiKey) {
        $settings.PSGalleryApiKey = $galleryApiKey.GetNetworkCredential().password
    }
}

task default -depends Test

task Init {
    "STATUS: Testing with PowerShell $($settings.PSVersion)"
    'Build System Details:'
    Get-Item ENV:BH*
} -description 'Initialize build environment'

task Test -Depends Init, Analyze, Pester -description 'Run test suite'

task Analyze -depends Build {
    $analysis = Invoke-ScriptAnalyzer -Path $settings.ModuleOutDir -Recurse -Verbose:$false -Settings ([IO.Path]::Combine($env:BHModulePath, 'ScriptAnalyzerSettings.psd1'))
    $errors   = $analysis | Where-Object {$_.Severity -eq 'Error'}
    $warnings = $analysis | Where-Object {$_.Severity -eq 'Warning'}
    if (@($errors).Count -gt 0) {
        Write-Error -Message 'One or more Script Analyzer errors were found. Build cannot continue!'
        $errors | Format-Table -AutoSize
    }

    if (@($warnings).Count -gt 0) {
        Write-Warning -Message 'One or more Script Analyzer warnings were found. These should be corrected.'
        $warnings | Format-Table -AutoSize
    }
} -description 'Run PSScriptAnalyzer'

task Pester -depends Build {
    Remove-Module $settings.ProjectName -ErrorAction SilentlyContinue -Verbose:$false

    # Write the NUnit results to tests/out/testResults.xml so the shared CI workflow can
    # upload and publish them (its artifact step looks for ./tests/out/testResults.xml).
    $testResultsDir = [IO.Path]::Combine($settings.ProjectRoot, 'tests', 'out')
    if (-not (Test-Path -Path $testResultsDir)) {
        New-Item -Path $testResultsDir -ItemType Directory -Force > $null
    }
    $testResultsXml = [IO.Path]::Combine($testResultsDir, 'testResults.xml')

    $pesterConfiguration = New-PesterConfiguration
    $pesterConfiguration.Run.Path             = $settings.Tests.FullName
    $pesterConfiguration.Run.PassThru         = $true
    $pesterConfiguration.Output.Verbosity     = 'Detailed'
    $pesterConfiguration.TestResult.Enabled   = $true
    $pesterConfiguration.TestResult.OutputPath = $testResultsXml
    $pesterConfiguration.TestResult.OutputFormat = 'NUnitXml'

    # Track (never gate on) code coverage of the built module. The number understates real
    # coverage: tests that exercise code in child processes (the build.tests.ps1 child builds
    # and the Test-PSBuildPester subprocess matrix) are invisible to session instrumentation.
    # Publishing the JaCoCo file from CI is psake/PowerShellBuild#139.
    $pesterConfiguration.CodeCoverage.Enabled      = $true
    $pesterConfiguration.CodeCoverage.Path         = $settings.ModuleOutDir
    $pesterConfiguration.CodeCoverage.OutputPath   = [IO.Path]::Combine($testResultsDir, 'coverage.xml')
    $pesterConfiguration.CodeCoverage.OutputFormat = 'JaCoCo'

    $testResults = Invoke-Pester -Configuration $pesterConfiguration

    if ($testResults.CodeCoverage) {
        $coverageMessage = 'Code coverage: {0:p1} of analyzed commands executed ({1} of {2})' -f (
            $testResults.CodeCoverage.CoveragePercent / 100),
            $testResults.CodeCoverage.CommandsExecutedCount,
            $testResults.CodeCoverage.CommandsAnalyzedCount
        Write-Host $coverageMessage -ForegroundColor Cyan
    }

    # Result aggregates every failure category (failed tests, blocks, containers),
    # matching the gate in Test-PSBuildPester.
    if ($testResults.Result -eq 'Failed') {
        $testResults | Format-List
        Write-Error -Message 'One or more Pester tests failed. Build cannot continue!'
    }
} -description 'Run Pester tests'

task Clean -depends Init {
    if (Test-Path -Path $settings.ModuleOutDir) {
        Remove-Item -Path $settings.ModuleOutDir -Recurse -Force -Verbose:$false
    }
}

task Build -depends Init, Clean {
    New-Item -Path $settings.ModuleOutDir -ItemType Directory -Force > $null
    Copy-Item -Path "$($settings.SUT)/*" -Destination $settings.ModuleOutDir -Recurse

    # Commented out rather than removed to allow easy use in future
    # Generate Invoke-Build tasks from Psake tasks
    # $psakePath = [IO.Path]::Combine($settings.ModuleOutDir, 'psakefile.ps1')
    # $ibPath    = [IO.Path]::Combine($settings.ModuleOutDir, 'IB.tasks.ps1')
    # & .\Build\Convert-PSAke.ps1 $psakePath | Out-File -Encoding UTF8 $ibPath
}

task Publish -depends Test {
    "    Publishing version [$($settings.Manifest.ModuleVersion)] to PSGallery..."
    if ($settings.PSGalleryApiKey) {
        Publish-Module -Path $settings.ModuleOutDir -NuGetApiKey $settings.PSGalleryApiKey
    } else {
        throw 'Did not find PSGallery API key!'
    }
} -description 'Publish to PowerShellGallery'
