# properties {
#     # Disable "compiling" module into monolithinc PSM1.
#     $PSBPreference.Build.CompileModule = $true

#     # Headers/footers for entire PSM1 and for each inserted function
#     $PSBPreference.Build.CompileHeader       = "# Module Header"
#     $PSBPreference.Build.CompileFooter       = '# Module Footer'
#     $PSBPreference.Build.CompileScriptHeader = '# Function header'
#     $PSBPreference.Build.CompileScriptFooter = '# Function footer'

#     # Override the default output directory
#     $PSBPreference.Build.OutDir = 'Output'
# }

task default -depends Test

task Build -FromModule PowerShellBuild -Version '0.4.0'
