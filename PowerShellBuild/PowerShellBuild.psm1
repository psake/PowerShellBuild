# Dot source public functions
$public  = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public/*.ps1')  -Recurse -ErrorAction Stop)
foreach ($import in $public) {
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
