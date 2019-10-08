Import-Module ../../Output/PowerShellBuild -Force
. PowerShellBuild.IB.Tasks

$PSBPreference.Build.CompileModule = $true

task Build $PSBPreference.build.dependencies

task . Build
