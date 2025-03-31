Properties {
    $settings = . ([IO.Path]::Combine($PSScriptRoot, 'build.settings.ps1'))
    if ($galleryApiKey) {
        $settings.PSGalleryApiKey = $galleryApiKey.GetNetworkCredential().password
    }
}

Task default -depends Test

Task Init {
    "STATUS: Testing with PowerShell $($settings.PSVersion)"
    'Build System Details:'
    Get-Item ENV:BH*
} -description 'Initialize build environment'

Task Test -depends Init, Analyze, Pester -description 'Run test suite'

Task Analyze -depends Build {
    $analysis = Invoke-ScriptAnalyzer -Path $settings.ModuleOutDir -Recurse -Verbose:$false -Settings './tests/ScriptAnalyzerSettings.psd1'
    $errors = $analysis | Where-Object { $_.Severity -eq 'Error' }
    $warnings = $analysis | Where-Object { $_.Severity -eq 'Warning' }
    if (@($errors).Count -gt 0) {
        Write-Error -Message 'One or more Script Analyzer errors were found. Build cannot continue!'
        $errors | Format-Table -AutoSize
    }

    if (@($warnings).Count -gt 0) {
        Write-Warning -Message 'One or more Script Analyzer warnings were found. These should be corrected.'
        $warnings | Format-Table -AutoSize
    }
} -description 'Run PSScriptAnalyzer'

Task Pester -depends Build {
    Remove-Module $settings.ProjectName -ErrorAction SilentlyContinue -Verbose:$false

    $testResultsXml = [IO.Path]::Combine($settings.OutputDir, 'testResults.xml')
    $testResults = Invoke-Pester -Path $settings.Tests -Output Detailed -PassThru

    if ($testResults.FailedCount -gt 0) {
        $testResults | Format-List
        Write-Error -Message 'One or more Pester tests failed. Build cannot continue!'
    }
} -description 'Run Pester tests'

Task Clean -depends Init {
    if (Test-Path -Path $settings.ModuleOutDir) {
        Remove-Item -Path $settings.ModuleOutDir -Recurse -Force -Verbose:$false
    }
}

Task Build -depends Init, Clean {
    New-Item -Path $settings.ModuleOutDir -ItemType Directory -Force > $null
    Copy-Item -Path "$($settings.SUT)/*" -Destination $settings.ModuleOutDir -Recurse

    # Commented out rather than removed to allow easy use in future
    # Generate Invoke-Build tasks from Psake tasks
    # $psakePath = [IO.Path]::Combine($settings.ModuleOutDir, 'psakefile.ps1')
    # $ibPath    = [IO.Path]::Combine($settings.ModuleOutDir, 'IB.tasks.ps1')
    # & .\Build\Convert-PSAke.ps1 $psakePath | Out-File -Encoding UTF8 $ibPath
}

Task Publish -depends Test {
    "    Publishing version [$($settings.Manifest.ModuleVersion)] to PSGallery..."
    if ($settings.PSGalleryApiKey) {
        Publish-Module -Path $settings.ModuleOutDir -NuGetApiKey $settings.PSGalleryApiKey
    } else {
        throw 'Did not find PSGallery API key!'
    }
} -description 'Publish to PowerShellGallery'
