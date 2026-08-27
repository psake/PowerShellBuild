# Dot source public functions
$private = @(Get-ChildItem -Path ([IO.Path]::Combine($PSScriptRoot, 'Private/*.ps1')) -Recurse)
$public = @(Get-ChildItem -Path ([IO.Path]::Combine($PSScriptRoot, 'Public/*.ps1')) -Recurse)
foreach ($import in $public + $private) {
    try {
        . $import.FullName
    } catch {
        throw "Unable to dot source [$($import.FullName)]"
    }
}

# Every user-facing string lives in en-US/Messages.psd1 and nowhere else. Import-LocalizedData
# resolves that file through the current UI culture and the culture's parent chain, so the lookup
# misses whenever the machine's UI culture has no directory of its own -- and this module ships
# en-US only. PowerShell 7 has a final en-US fallback that hides the miss; Windows PowerShell 5.1
# has none and binds nothing at all, which is why a French or Japanese Windows install got no
# strings. Ask for en-US by name when the culture lookup comes up empty, and fail the import if
# even that is not there: silent, missing strings turn every message into an empty warning or a
# bare ScriptHalted (psake/PowerShellBuild#185).
$importLocalizedDataParameters = @{
    BindingVariable = 'LocalizedData'
    FileName        = 'Messages.psd1'
    ErrorAction     = 'SilentlyContinue'
}
Import-LocalizedData @importLocalizedDataParameters
if (-not $LocalizedData) {
    $importLocalizedDataParameters['UICulture'] = 'en-US'
    $importLocalizedDataParameters['ErrorAction'] = 'Stop'
    Import-LocalizedData @importLocalizedDataParameters
}


Export-ModuleMember -Function $public.Basename

# $psakeTaskAlias = 'PowerShellBuild.psake.tasks'
# Set-Alias -Name $psakeTaskAlias -Value $PSScriptRoot/psakeFile.ps1
# Export-ModuleMember -Alias $psakeTaskAlias

# Invoke-Build task aliases
$ibAlias = 'PowerShellBuild.IB.Tasks'
Set-Alias -Name $ibAlias -Value $PSScriptRoot/IB.tasks.ps1
Export-ModuleMember -Alias $ibAlias
