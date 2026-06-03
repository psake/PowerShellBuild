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
    $analyzerSettings = [IO.Path]::Combine($env:BHModulePath, 'ScriptAnalyzerSettings.psd1')
    $analysis = Invoke-ScriptAnalyzer -Path $settings.ModuleOutDir -Recurse -Verbose:$false -Settings $analyzerSettings
    $errors   = $analysis | Where-Object { $_.Severity -eq 'Error' }

    # Cross-version compatibility violations (PSUseCompatibleSyntax/Commands/Types) are reported at
    # Warning severity, but must always fail the build. A PowerShell 7+-only construct such as the
    # ternary operator parses fine under pwsh yet breaks module import on Windows PowerShell 5.1,
    # which the manifest still supports. PSUseCompatibleSyntax checks the target language versions
    # regardless of the engine the analyzer runs under, so this gate catches such a regression even
    # though CI runs the analysis from pwsh.
    $compatibilityIssues = $analysis | Where-Object { $_.RuleName -like 'PSUseCompatible*' }

    # Remaining warnings are reported but, per project policy, do not fail the build.
    $warnings = $analysis | Where-Object { $_.Severity -eq 'Warning' -and $_.RuleName -notlike 'PSUseCompatible*' }

    if (@($compatibilityIssues).Count -gt 0) {
        $compatibilityIssues | Format-Table RuleName, ScriptName, Line, Message -AutoSize -Wrap
        Write-Error -Message 'One or more cross-version compatibility issues were found. Build cannot continue!'
    }

    if (@($errors).Count -gt 0) {
        $errors | Format-Table -AutoSize
        Write-Error -Message 'One or more Script Analyzer errors were found. Build cannot continue!'
    }

    if (@($warnings).Count -gt 0) {
        Write-Warning -Message 'One or more Script Analyzer warnings were found. These should be corrected.'
        $warnings | Format-Table -AutoSize
    }
} -description 'Run PSScriptAnalyzer'

task Pester -depends Build {
    Remove-Module $settings.ProjectName -ErrorAction SilentlyContinue -Verbose:$false

    $testResultsXml = [IO.Path]::Combine($settings.OutputDir, 'testResults.xml')
    $testResults    = Invoke-Pester -Path $settings.Tests -Output Detailed -PassThru

    if ($testResults.FailedCount -gt 0) {
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
