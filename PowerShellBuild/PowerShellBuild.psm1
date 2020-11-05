# Dot source public functions
$private = @(Get-ChildItem -Path ([IO.Path]::Combine($PSScriptRoot, 'Private/*.ps1')) -Recurse)
$public  = @(Get-ChildItem -Path ([IO.Path]::Combine($PSScriptRoot, 'Public/*.ps1')) -Recurse)
foreach ($import in $public + $private) {
    try {
        . $import.FullName
    } catch {
        throw "Unable to dot source [$($import.FullName)]"
    }
}

Export-ModuleMember -Function $public.Basename

# $psakeTaskAlias = 'PowerShellBuild.psake.tasks'
# Set-Alias -Name $psakeTaskAlias -Value $PSScriptRoot/psakeFile.ps1
# Export-ModuleMember -Alias $psakeTaskAlias

# Invoke-Build task aliases
$ibAlias = 'PowerShellBuild.IB.Tasks'
Set-Alias -Name $ibAlias -Value $PSScriptRoot/IB.tasks.ps1
Export-ModuleMember -Alias $ibAlias
