# TestModule root module loader
#
# Dot-sources the function files at import time, guarded so the same file also works after
# PowerShellBuild compiles the module: compile mode concatenates the function files into this
# .psm1 and copies neither Public/ nor Private/ to the output, so the loader has to do nothing
# when those directories are absent.
#
# There is deliberately no Export-ModuleMember call. PowerShellBuild writes the public function
# names into FunctionsToExport in the built manifest, and a call here would run after the
# concatenated functions in a compiled build, where it would find no files and empty the export
# set the manifest had just been given. See psake/PowerShellBuild#201.
foreach ($sourceDirectoryName in @('Public', 'Private')) {
    $sourceDirectoryPath = [IO.Path]::Combine($PSScriptRoot, $sourceDirectoryName)
    if (-not (Test-Path -Path $sourceDirectoryPath)) {
        continue
    }

    $sourceFile = Get-ChildItem -Path ([IO.Path]::Combine($sourceDirectoryPath, '*.ps1'))
    foreach ($import in $sourceFile) {
        . $import.FullName
    }
}
