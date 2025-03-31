Import-Module ../../Output/PowerShellBuild -Force
. PowerShellBuild.IB.Tasks

$PSBPreference.Build.CompileModule = $true

Task Build $PSBPreference.TaskDependencies.Build

Task . Build
