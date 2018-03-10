$projectRoot = if ($ENV:BHProjectPath) { $ENV:BHProjectPath } else { $PSScriptRoot }

@{
    ProjectRoot     = $projectRoot
    ProjectName     = $env:BHProjectName
    SUT             = $env:BHModulePath
    Tests           = Join-Path -Path $projectRoot -ChildPath Tests
    ManifestPath    = $env:BHPSModuleManifest
    Manifest        = Import-PowerShellDataFile -Path $env:BHPSModuleManifest
    PSVersion       = $PSVersionTable.PSVersion.ToString()
    PSGalleryApiKey = $env:PSGalleryApiKey
}
