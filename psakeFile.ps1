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

task Analyze -depends Build {
    $analysis = Invoke-ScriptAnalyzer -Path $settings.ModuleOutDir -Recurse -Verbose:$false
    $errors   = $analysis | Where-Object {$_.Severity -eq 'Error'}
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

task Pester -depends Build {
    Remove-Module $settings.ProjectName -ErrorAction SilentlyContinue -Verbose:$false

    $testResultsXml = Join-Path -Path $settings.OutputDir -ChildPath 'testResults.xml'
    $testResults = Invoke-Pester -Path $settings.Tests -PassThru -OutputFile $testResultsXml -OutputFormat NUnitXml

    # Upload test artifacts to AppVeyor
    if ($env:APPVEYOR_JOB_ID) {
        $wc = New-Object 'System.Net.WebClient'
        $wc.UploadFile("https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)", $testResultsXml)
    }

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

    #Generate Invoke-Build tasks from Psake tasks
    $psakePath = join-path $settings.ModuleOutDir 'psakefile.ps1'
    $ibPath = join-path $settings.ModuleOutDir 'IB.tasks.ps1'
    & .\Build\Convert-PSAke.ps1 $psakePath | Out-File -Encoding UTF8 $ibPath
}

task Publish -depends Test {
    "    Publishing version [$($settings.Manifest.ModuleVersion)] to PSGallery..."
    if ($settings.PSGalleryApiKey) {
        Publish-Module -Path $settings.ModuleOutDir -NuGetApiKey $settings.PSGalleryApiKey -Repository PSGallery
    } else {
        throw 'Did not find PSGallery API key!'
    }
} -description 'Publish to PowerShellGallery'
