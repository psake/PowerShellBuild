$projectRoot    = if ($ENV:BHProjectPath) { $ENV:BHProjectPath } else { $PSScriptRoot }
$moduleName     = $env:BHProjectName
$moduleVersion  = (Import-PowerShellDataFile -Path $env:BHPSModuleManifest).ModuleVersion
$outDir         = Join-Path -Path $projectRoot -ChildPath Output
$moduleOutDir   = "$outDir/$moduleName/$moduleVersion"
@{
    ProjectRoot     = $projectRoot
    ProjectName     = $env:BHProjectName
    SUT             = $env:BHModulePath
    Tests           = Get-ChildItem -Path (Join-Path -Path $projectRoot -ChildPath tests) -Filter '*.tests.ps1'
    OutputDir       = $outDir
    ModuleOutDir    = $moduleOutDir
    ManifestPath    = $env:BHPSModuleManifest
    Manifest        = Import-PowerShellDataFile -Path $env:BHPSModuleManifest
    PSVersion       = $PSVersionTable.PSVersion.ToString()
    PSGalleryApiKey = $env:PSGALLERY_API_KEY
}
