properties {
    $settings = . (Join-Path -path $PSScriptRoot -ChildPath build.settings.ps1)
}

task default -depends Test

task Init {
    "STATUS: Testing with PowerShell $($settings.PSVersion)"
    'Build System Details:'
    Get-Item ENV:BH*
} -description 'Initialize build environment'

task Test -Depends Init, Analyze, Pester -description 'Run test suite'

task Analyze -depends Init {
    $analysis = Invoke-ScriptAnalyzer -Path $settings.SUT -Recurse -Verbose:$false
    $errors = $analysis | Where-Object {$_.Severity -eq 'Error'}
    $warnings = $analysis | Where-Object {$_.Severity -eq 'Warning'}
    if (@($errors).Count -gt 0) {
        Write-Error -Message 'One or more Script Analyzer errors were found. Build cannot continue!'
        $errors | Format-Table
    }

    if (@($warnings).Count -gt 0) {
        Write-Warning -Message 'One or more Script Analyzer warnings were found. These should be corrected.'
        $warnings | Format-Table
    }
} -description 'Run PSScriptAnalyzer'

task Pester -depends Init {
    Remove-Module $settings.ProjectName -ErrorAction SilentlyContinue -Verbose:$false
    Import-Module -Name $settings.ManifestPath -Force -Verbose:$false

    if (Test-Path -Path $settings.Tests) {
        Invoke-Pester -Path $settings.Tests -PassThru -EnableExit
    }
} -description 'Run Pester tests'

task Publish -depends Init {
    "    Publishing version [$($settings.Manifest.ModuleVersion)] to PSGallery..."
    if ($settings.PSGalleryApiKey) {
        Publish-Module -Path $settings.SUT -NuGetApiKey $settings.PSGalleryApiKey -Repository PSGallery
    } else {
        throw 'Did not find PSGallery API key!'
    }
} -description 'Publish to PowerShellGallery'