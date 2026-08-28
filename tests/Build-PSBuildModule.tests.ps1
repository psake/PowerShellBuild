# spell-checker:ignore excludeme psm1 psd1

# Dedicated coverage for Build-PSBuildModule (psake/PowerShellBuild#98).
#
# build.tests.ps1 reaches this same function through a real psake build of tests/TestModule, but
# every assertion there reads the text of the file that was written. This file calls
# Build-PSBuildModule directly, so each parameter can be varied on its own, and it imports what
# the build produced so the assertions are about the module a consumer would install rather than
# about the bytes on disk.
#
# Two source root modules are used, and the difference between them is the whole of
# psake/PowerShellBuild#201:
#
#   * The guarded loader does nothing when Public/ and Private/ are absent, and never calls
#     Export-ModuleMember. It survives compilation, so a module built from it exports its public
#     functions in either mode.
#   * The naive scaffold loader -- the shape Plaster and most module templates generate -- calls
#     Export-ModuleMember with the names it discovered. Compile mode appends the source .psm1
#     after the concatenated functions and copies no Public/ directory to the output, so that
#     call becomes Export-ModuleMember -Function @() and the built module exports nothing even
#     though the manifest names every public function. The build still succeeds; the warning
#     added for #201 is the only thing that says so.

Describe 'Build-PSBuildModule' {

    BeforeAll {
        $script:repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name ([IO.Path]::Combine($script:repositoryRoot, 'Output', 'PowerShellBuild')) -Force
        Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'fixtures', 'FixtureHelpers.psm1')) -Force

        # Distinctive markers so an assertion can locate them in the compiled root module without
        # colliding with anything the fixture functions contain.
        $script:compileHeader = '# ===== module header ====='
        $script:compileFooter = '# ===== module footer ====='
        $script:compileScriptHeader = '# ----- begin script -----'
        $script:compileScriptFooter = '# ----- end script -----'
        $script:loaderMarker = '# PSBuildTestFixture root module loader'

        # Single-quoted here-strings: the loader text has to reach the fixture with $PSScriptRoot
        # intact rather than expanded against this test file.
        $script:guardedLoader = @'
# PSBuildTestFixture root module loader
#
# Guarded for compiled builds: compile mode concatenates the function files into this .psm1 and
# copies neither Public/ nor Private/ to the output, so the loader must do nothing when those
# directories are absent. There is deliberately no Export-ModuleMember call -- the built
# manifest's FunctionsToExport is what governs the export set.
foreach ($sourceDirectoryName in @('Public', 'Private')) {
    $sourceDirectoryPath = Join-Path -Path $PSScriptRoot -ChildPath $sourceDirectoryName
    if (-not (Test-Path -Path $sourceDirectoryPath)) {
        continue
    }

    $sourceFile = Get-ChildItem -Path (Join-Path -Path $sourceDirectoryPath -ChildPath '*.ps1')
    foreach ($import in $sourceFile) {
        . $import.FullName
    }
}
'@

        $script:naiveLoader = @'
# PSBuildTestFixture root module loader
#
# The standard scaffold loader, reproduced from psake/PowerShellBuild#201. It discovers the
# function files at import time and exports whatever it found.
$public = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public/*.ps1') -ErrorAction SilentlyContinue)
$private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private/*.ps1') -ErrorAction SilentlyContinue)
foreach ($import in $public + $private) {
    . $import.FullName
}

Export-ModuleMember -Function $public.BaseName
'@

        # Names Export-ModuleMember only inside a block comment. A line-anchored regex fires
        # on it -- the anchor lands on a line it cannot tell is not code -- where parsing the
        # file does not. This fixture is what separates the two approaches.
        $script:documentedLoader = @'
# PSBuildTestFixture root module loader
<#
    This module deliberately does not call the command named on the next line, which is
    what the standard scaffold would have done here:
    Export-ModuleMember -Function $public.BaseName

    The built manifest FunctionsToExport governs the export set instead.
#>
foreach ($sourceDirectoryName in @('Public', 'Private')) {
    $sourceDirectoryPath = Join-Path -Path $PSScriptRoot -ChildPath $sourceDirectoryName
    if (-not (Test-Path -Path $sourceDirectoryPath)) {
        continue
    }

    foreach ($import in (Get-ChildItem -Path (Join-Path -Path $sourceDirectoryPath -ChildPath '*.ps1'))) {
        . $import.FullName
    }
}
'@

        function New-PSBuildModuleScenario {
            <#
            .SYNOPSIS
                Create an isolated source module and the output path to build it into.
            .DESCRIPTION
                Copies the shared PSBuildTestFixture module into its own directory, replaces its
                root module with the requested loader shape, and returns the paths the tests
                assert against. The fixture is copied rather than used in place so that no test
                run mutates the checked-in fixture.
            .PARAMETER Path
                Directory to create the scenario under, typically $TestDrive. Passed in rather
                than read from the caller so the helper does not depend on a Pester construct.
            .PARAMETER Name
                Name of the scenario directory. Give each scenario its own name so scenarios in
                the same run cannot observe each other's output.
            .PARAMETER Loader
                Which root module loader to stamp onto the copy. 'Guarded' survives compilation;
                'Naive' is the scaffold loader that psake/PowerShellBuild#201 is about.
            .EXAMPLE
                PS> $scenario = New-PSBuildModuleScenario -Path $TestDrive -Name 'compiled'

                Creates $TestDrive/compiled/PSBuildTestFixture with the guarded loader.
            .OUTPUTS
                System.Management.Automation.PSCustomObject
            #>
            [CmdletBinding()]
            [OutputType([PSCustomObject])]
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]
                $Path,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]
                $Name,

                [ValidateSet('Guarded', 'Naive', 'Documented')]
                [string]
                $Loader = 'Guarded'
            )

            $scenarioRoot = Join-Path -Path $Path -ChildPath $Name
            $sourcePath = Copy-PSBuildTestFixture -Destination $scenarioRoot

            $loaderText = switch ($Loader) {
                'Naive' { $script:naiveLoader }
                'Documented' { $script:documentedLoader }
                default { $script:guardedLoader }
            }
            Set-Content -Path (Join-Path -Path $sourcePath -ChildPath 'PSBuildTestFixture.psm1') -Value $loaderText

            # A directory the source tree carries that is not a compile directory, so
            # CopyDirectories has something to copy.
            $resourcePath = Join-Path -Path $sourcePath -ChildPath 'resources'
            New-Item -Path $resourcePath -ItemType Directory -Force > $null
            Set-Content -Path (Join-Path -Path $resourcePath -ChildPath 'widget-template.json') -Value '{}'

            $destinationPath = Join-Path -Path $scenarioRoot -ChildPath 'Output'

            [PSCustomObject]@{
                ModuleName      = 'PSBuildTestFixture'
                SourcePath      = $sourcePath
                DestinationPath = $destinationPath
                ManifestPath    = Join-Path -Path $destinationPath -ChildPath 'PSBuildTestFixture.psd1'
                RootModulePath  = Join-Path -Path $destinationPath -ChildPath 'PSBuildTestFixture.psm1'
            }
        }

        function Get-BuiltModuleExportedFunctionName {
            <#
            .SYNOPSIS
                Report the function names a built module actually exports.
            .DESCRIPTION
                Imports the built module through its manifest and returns the exported function
                names, then removes it again. Reading the export set from the loaded module is
                the point: the manifest's FunctionsToExport and the root module's
                Export-ModuleMember are intersected, so only an import shows which commands a
                consumer would get.

                The import and removal are paired inside one call so the suite never carries a
                built fixture module in session state, and so each scenario reports its own
                exports even though every scenario builds a module of the same name.
            .PARAMETER ManifestPath
                Path to the built module's manifest.
            .EXAMPLE
                PS> Get-BuiltModuleExportedFunctionName -ManifestPath $scenario.ManifestPath

                Returns the sorted names of the functions the built module exports.
            .OUTPUTS
                System.String[]
            #>
            [CmdletBinding()]
            [OutputType([string[]])]
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]
                $ManifestPath
            )

            $module = Import-Module -Name $ManifestPath -Force -PassThru
            $exportedFunctionName = @($module.ExportedFunctions.Keys | Sort-Object)
            Remove-Module -ModuleInfo $module -Force -ErrorAction SilentlyContinue

            # Comma-wrapped so a module that exports nothing comes back as an empty array rather
            # than as no output at all, which is the distinction these tests are about.
            , $exportedFunctionName
        }
    }

    AfterAll {
        Remove-Module -Name 'FixtureHelpers' -Force -ErrorAction SilentlyContinue
    }

    Context 'Building without compilation' {

        BeforeAll {
            $script:scenario = New-PSBuildModuleScenario -Path $TestDrive -Name 'dot-sourced'
            $buildParameter = @{
                Path            = $script:scenario.SourcePath
                DestinationPath = $script:scenario.DestinationPath
                ModuleName      = $script:scenario.ModuleName
                Exclude         = @('excludeme')
            }
            $script:buildWarning = @()
            Build-PSBuildModule @buildParameter -WarningVariable 'buildWarning' -WarningAction 'SilentlyContinue'
            $script:buildWarning = @($buildWarning)
        }

        It 'Creates the destination directory' {
            $script:scenario.DestinationPath | Should -Exist
        }

        It 'Copies the manifest and the root module' {
            $script:scenario.ManifestPath | Should -Exist
            $script:scenario.RootModulePath | Should -Exist
        }

        It 'Preserves the <_> directory' -ForEach @('Public', 'Private', 'resources') {
            Join-Path -Path $script:scenario.DestinationPath -ChildPath $_ | Should -Exist
        }

        It 'Removes files matching an Exclude pattern' {
            Join-Path -Path $script:scenario.DestinationPath -ChildPath 'excludeme.txt' | Should -Not -Exist
        }

        It 'Writes the public function names into FunctionsToExport' {
            $manifest = Import-PowerShellDataFile -Path $script:scenario.ManifestPath

            @($manifest.FunctionsToExport | Sort-Object) | Should -Be @('Get-Widget', 'Set-Widget')
        }

        It 'Builds a module that exports its public functions' {
            $exportedFunctionName = Get-BuiltModuleExportedFunctionName -ManifestPath $script:scenario.ManifestPath

            $exportedFunctionName | Should -Be @('Get-Widget', 'Set-Widget')
        }

        It 'Does not export the private helper' {
            $exportedFunctionName = Get-BuiltModuleExportedFunctionName -ManifestPath $script:scenario.ManifestPath

            $exportedFunctionName | Should -Not -Contain 'Test-WidgetName'
        }

        It 'Emits no warning' {
            $script:buildWarning | Should -BeNullOrEmpty
        }
    }

    Context 'Building with compilation' {

        BeforeAll {
            $script:scenario = New-PSBuildModuleScenario -Path $TestDrive -Name 'compiled'

            # A script file the Exclude pattern has to keep out of the concatenated root module.
            # Added here rather than in the fixture because compile mode is the only place a
            # .ps1 exclusion is applied to the compile directories.
            $excludedScriptPath = Join-Path -Path $script:scenario.SourcePath -ChildPath 'Private/excludeme.ps1'
            Set-Content -Path $excludedScriptPath -Value 'function Get-ExcludedWidget { }'

            $buildParameter = @{
                Path                = $script:scenario.SourcePath
                DestinationPath     = $script:scenario.DestinationPath
                ModuleName          = $script:scenario.ModuleName
                Compile             = $true
                CompileDirectories  = @('Public', 'Private')
                CopyDirectories     = @('resources')
                CompileHeader       = $script:compileHeader
                CompileFooter       = $script:compileFooter
                CompileScriptHeader = $script:compileScriptHeader
                CompileScriptFooter = $script:compileScriptFooter
                Exclude             = @('excludeme')
            }
            $script:buildWarning = @()
            Build-PSBuildModule @buildParameter -WarningVariable 'buildWarning' -WarningAction 'SilentlyContinue'
            $script:buildWarning = @($buildWarning)

            $script:rootModuleContent = Get-Content -Path $script:scenario.RootModulePath -Raw
        }

        It 'Produces only the manifest and a monolithic root module' {
            @(Get-ChildItem -Path $script:scenario.DestinationPath -File).Count | Should -Be 2
            $script:scenario.ManifestPath | Should -Exist
            $script:scenario.RootModulePath | Should -Exist
        }

        It 'Does not copy the <_> compile directory to the output' -ForEach @('Public', 'Private') {
            Join-Path -Path $script:scenario.DestinationPath -ChildPath $_ | Should -Not -Exist
        }

        It 'Copies a CopyDirectories directory as-is' {
            [IO.Path]::Combine(
                $script:scenario.DestinationPath, 'resources', 'widget-template.json'
            ) | Should -Exist
        }

        It 'Concatenates <_> into the root module' -ForEach @('Get-Widget', 'Set-Widget', 'Test-WidgetName') {
            $script:rootModuleContent | Should -BeLike "*function $_*"
        }

        It 'Leaves out a script matching an Exclude pattern' {
            $script:rootModuleContent | Should -Not -BeLike '*Get-ExcludedWidget*'
        }

        It 'Places the compile header above the concatenated functions' {
            $headerIndex = $script:rootModuleContent.IndexOf($script:compileHeader)
            $firstFunctionIndex = $script:rootModuleContent.IndexOf('function ')

            $headerIndex | Should -BeGreaterOrEqual 0
            $headerIndex | Should -BeLessThan $firstFunctionIndex
        }

        It 'Places the compile footer at the end' {
            $footerIndex = $script:rootModuleContent.IndexOf($script:compileFooter)
            $loaderIndex = $script:rootModuleContent.IndexOf($script:loaderMarker)

            $footerIndex | Should -BeGreaterOrEqual 0
            $footerIndex | Should -BeGreaterThan $loaderIndex
        }

        It 'Wraps every compiled script in the script header and footer' {
            # Three scripts survive the Exclude pattern: two public and one private.
            $headerMatch = [regex]::Matches($script:rootModuleContent, [regex]::Escape($script:compileScriptHeader))
            $footerMatch = [regex]::Matches($script:rootModuleContent, [regex]::Escape($script:compileScriptFooter))

            $headerMatch.Count | Should -Be 3
            $footerMatch.Count | Should -Be 3
        }

        It 'Appends the source root module after the concatenated functions' {
            # Compared against the last script footer rather than the last 'function ' keyword:
            # the loader's own comments talk about function files, so a keyword search would find
            # text inside the appended loader itself.
            $loaderIndex = $script:rootModuleContent.IndexOf($script:loaderMarker)
            $lastScriptFooterIndex = $script:rootModuleContent.LastIndexOf($script:compileScriptFooter)

            $loaderIndex | Should -BeGreaterThan $lastScriptFooterIndex
        }

        It 'Writes the public function names into FunctionsToExport' {
            $manifest = Import-PowerShellDataFile -Path $script:scenario.ManifestPath

            @($manifest.FunctionsToExport | Sort-Object) | Should -Be @('Get-Widget', 'Set-Widget')
        }

        It 'Builds a module that exports its public functions' {
            # The assertion the suite was missing. Every other compile-mode assertion reads file
            # text, and file text cannot tell the difference between a module that exports its
            # commands and one that exports nothing (psake/PowerShellBuild#201).
            $exportedFunctionName = Get-BuiltModuleExportedFunctionName -ManifestPath $script:scenario.ManifestPath

            $exportedFunctionName | Should -Be @('Get-Widget', 'Set-Widget')
        }

        It 'Does not export the private helper' {
            $exportedFunctionName = Get-BuiltModuleExportedFunctionName -ManifestPath $script:scenario.ManifestPath

            $exportedFunctionName | Should -Not -Contain 'Test-WidgetName'
        }

        It 'Emits no warning for a root module that does not call Export-ModuleMember' {
            # The guarded loader's comments name Export-ModuleMember while explaining why it
            # deliberately does not call it, so this also pins that a mention in a comment is
            # not reported as a call.
            $script:buildWarning | Should -BeNullOrEmpty
        }
    }

    Context 'Selecting which directories are compiled' {

        BeforeAll {
            $script:scenario = New-PSBuildModuleScenario -Path $TestDrive -Name 'public-only'
            $buildParameter = @{
                Path               = $script:scenario.SourcePath
                DestinationPath    = $script:scenario.DestinationPath
                ModuleName         = $script:scenario.ModuleName
                Compile            = $true
                CompileDirectories = @('Public')
            }
            Build-PSBuildModule @buildParameter

            $script:rootModuleContent = Get-Content -Path $script:scenario.RootModulePath -Raw
        }

        It 'Compiles the named directory' {
            $script:rootModuleContent | Should -BeLike '*function Get-Widget*'
        }

        It 'Leaves out a directory that was not named' {
            $script:rootModuleContent | Should -Not -BeLike '*function Test-WidgetName*'
        }
    }

    Context 'Compiling from a current location that cannot express the source path' {

        # The compile loop used to read each function file through a path resolved relative to
        # the current location. A current location cannot always express another path
        # relatively: on Windows PowerShell 5.1 a source on another drive resolves to .\C:\...,
        # and a source outside the current PSDrive's root to a ..\ path that cannot climb past
        # that root. Both read back as nothing, and the compiled module came out with its
        # headers and footers and none of its functions while the build reported success.
        #
        # The PSDrive here reproduces that on Windows PowerShell 5.1, where it is a real defect;
        # PowerShell 7 returns the absolute path in the same situation, so there the test simply
        # confirms the behavior. CI's Windows PowerShell 5.1 job hits the drive-letter form of
        # this for real, with the repository on D: and the test drive on C:.
        BeforeAll {
            $script:scenario = New-PSBuildModuleScenario -Path $TestDrive -Name 'relative-path'

            $isolatedRootPath = Join-Path -Path $TestDrive -ChildPath 'relative-path-location'
            New-Item -Path $isolatedRootPath -ItemType Directory -Force > $null
            New-PSDrive -Name 'PSBuildTestLocation' -PSProvider 'FileSystem' -Root $isolatedRootPath > $null

            $buildParameter = @{
                Path               = $script:scenario.SourcePath
                DestinationPath    = $script:scenario.DestinationPath
                ModuleName         = $script:scenario.ModuleName
                Compile            = $true
                CompileDirectories = @('Public', 'Private')
            }

            Push-Location -Path 'PSBuildTestLocation:\'
            try {
                Build-PSBuildModule @buildParameter
            } finally {
                Pop-Location
                Remove-PSDrive -Name 'PSBuildTestLocation' -Force
            }

            $script:rootModuleContent = Get-Content -Path $script:scenario.RootModulePath -Raw
        }

        It 'Compiles <_> into the root module' -ForEach @('Get-Widget', 'Set-Widget', 'Test-WidgetName') {
            $script:rootModuleContent | Should -BeLike "*function $_*"
        }
    }

    Context 'Filtering the compiled scripts' {

        # Reaches the private Remove-ExcludedItem directly. The compile path pipes items into it
        # one at a time, which hides what a collection exposes: the exclusion used a labeled
        # break aimed at the loop over the whole input, so every item after the first excluded
        # one was dropped. On Windows PowerShell 5.1 that break escaped the function outright
        # and aborted the caller's loop.
        It 'Keeps the items that follow an excluded one' {
            InModuleScope -ModuleName 'PowerShellBuild' -ScriptBlock {
                # The files do not have to exist: the exclusion is a regular expression match
                # against the path, and only the names are read back.
                $item = @(
                    [IO.FileInfo]::new('source/Public/Get-Widget.ps1')
                    [IO.FileInfo]::new('source/Private/excludeme.ps1')
                    [IO.FileInfo]::new('source/Private/Test-WidgetName.ps1')
                )

                $keptItem = Remove-ExcludedItem -InputObject $item -Exclude @('excludeme')

                @($keptItem.Name) | Should -Be @('Get-Widget.ps1', 'Test-WidgetName.ps1')
            }
        }
    }

    Context 'Building with compilation from a scaffold loader' {

        # psake/PowerShellBuild#201. The naive loader is the shape almost every module template
        # generates, and compiling it produces a module that exports nothing while the build
        # reports success. The fix for #201 is the warning asserted below, not a change to what
        # gets built, so the "exports nothing" assertion here pins current, known behavior
        # rather than desired behavior.
        BeforeAll {
            $script:scenario = New-PSBuildModuleScenario -Path $TestDrive -Name 'compiled-scaffold' -Loader 'Naive'
            $buildParameter = @{
                Path               = $script:scenario.SourcePath
                DestinationPath    = $script:scenario.DestinationPath
                ModuleName         = $script:scenario.ModuleName
                Compile            = $true
                CompileDirectories = @('Public', 'Private')
            }
            $script:buildWarning = @()
            Build-PSBuildModule @buildParameter -WarningVariable 'buildWarning' -WarningAction 'SilentlyContinue'
            $script:buildWarning = @($buildWarning)
        }

        It 'Warns that the source root module calls Export-ModuleMember' {
            $script:buildWarning -join [Environment]::NewLine | Should -BeLike '*Export-ModuleMember*'
        }

        It 'Names the source root module in the warning' {
            $sourceRootModulePath = Join-Path -Path $script:scenario.SourcePath -ChildPath 'PSBuildTestFixture.psm1'

            $script:buildWarning -join [Environment]::NewLine | Should -BeLike "*$sourceRootModulePath*"
        }

        It 'Still writes the public function names into FunctionsToExport' {
            # The manifest is correct. The effective export set is the intersection of
            # FunctionsToExport and Export-ModuleMember, and the appended loader is what empties
            # it, which is why a file-text assertion cannot see the failure.
            $manifest = Import-PowerShellDataFile -Path $script:scenario.ManifestPath

            @($manifest.FunctionsToExport | Sort-Object) | Should -Be @('Get-Widget', 'Set-Widget')
        }

        It 'Builds a module that exports nothing' {
            # Current documented behavior, not desired behavior. The appended loader runs
            # Export-ModuleMember -Function @() because compile mode copied no Public/ directory
            # to the output. If a later change makes compiled scaffold modules export their
            # functions, this test is the one to update.
            $exportedFunctionName = Get-BuiltModuleExportedFunctionName -ManifestPath $script:scenario.ManifestPath

            $exportedFunctionName | Should -BeNullOrEmpty
        }
    }

    Context 'Building without compilation from a scaffold loader' {

        # The counterpart to the context above: the same source module, built without -Compile,
        # keeps its Public/ directory, so the loader finds the files and the module exports its
        # functions. Nothing is wrong with the loader; compilation is what breaks it, and the
        # warning belongs to compile mode alone.
        BeforeAll {
            $script:scenario = New-PSBuildModuleScenario -Path $TestDrive -Name 'dot-sourced-scaffold' -Loader 'Naive'
            $buildParameter = @{
                Path            = $script:scenario.SourcePath
                DestinationPath = $script:scenario.DestinationPath
                ModuleName      = $script:scenario.ModuleName
            }
            $script:buildWarning = @()
            Build-PSBuildModule @buildParameter -WarningVariable 'buildWarning' -WarningAction 'SilentlyContinue'
            $script:buildWarning = @($buildWarning)
        }

        It 'Builds a module that exports its public functions' {
            $exportedFunctionName = Get-BuiltModuleExportedFunctionName -ManifestPath $script:scenario.ManifestPath

            $exportedFunctionName | Should -Be @('Get-Widget', 'Set-Widget')
        }

        It 'Emits no warning' {
            $script:buildWarning | Should -BeNullOrEmpty
        }
    }

    Context 'Compiling a root module that only mentions Export-ModuleMember' {

        # The warning states a fact -- "calls Export-ModuleMember" -- and tells the consumer to
        # guard or remove the call. Reported against a comment, it sends them looking for a
        # call that does not exist. Detection therefore parses the root module instead of
        # matching its text.
        BeforeAll {
            $script:scenario = New-PSBuildModuleScenario -Path $TestDrive -Name 'documented' -Loader 'Documented'
            $buildParameter = @{
                Path            = $script:scenario.SourcePath
                DestinationPath = $script:scenario.DestinationPath
                ModuleName      = $script:scenario.ModuleName
                Compile         = $true
                CompileDirectories = @('Public', 'Private')
            }
            $script:buildWarning = @()
            Build-PSBuildModule @buildParameter -WarningVariable 'buildWarning' -WarningAction 'SilentlyContinue'
            $script:buildWarning = @($buildWarning)
        }

        It 'Emits no warning for a mention inside a block comment' {
            $script:buildWarning | Should -BeNullOrEmpty
        }

        It 'Builds a module that exports its public functions' {
            $exportedFunctionName = Get-BuiltModuleExportedFunctionName -ManifestPath $script:scenario.ManifestPath

            $exportedFunctionName | Should -Be @('Get-Widget', 'Set-Widget')
        }
    }

    Context 'Compiling a source file whose name contains wildcard characters' {

        # FullName is a literal path, and -Path reads [ ] * ? as wildcards, so a file named
        # Get-Widget[legacy].ps1 resolves to nothing and is dropped from the compiled module
        # while the build still succeeds -- the same silent-drop outcome as the drive-relative
        # path this loop already guards against, reached a different way.
        #
        # A bracketed directory would exercise it too, but not testably: New-ModuleManifest
        # has no -LiteralPath, so the fixture cannot be created in one.
        BeforeAll {
            $script:scenario = New-PSBuildModuleScenario -Path $TestDrive -Name 'wildcard-name'
            $bracketedFilePath = Join-Path -Path $script:scenario.SourcePath -ChildPath 'Public/Get-Widget[legacy].ps1'
            Set-Content -LiteralPath $bracketedFilePath -Value 'function Get-WidgetLegacy { 1 }'

            $buildParameter = @{
                Path            = $script:scenario.SourcePath
                DestinationPath = $script:scenario.DestinationPath
                ModuleName      = $script:scenario.ModuleName
                Compile         = $true
                CompileDirectories = @('Public', 'Private')
            }
            Build-PSBuildModule @buildParameter
        }

        It 'Writes the function body into the compiled root module' {
            $rootModuleContent = Get-Content -LiteralPath $script:scenario.RootModulePath -Raw

            $rootModuleContent | Should -Match 'function Get-WidgetLegacy'
        }
    }

    Context 'Converting the readme into about help' {

        BeforeAll {
            $script:scenario = New-PSBuildModuleScenario -Path $TestDrive -Name 'about-help'
            $script:readMePath = Join-Path -Path $script:scenario.SourcePath -ChildPath 'README.md'
            $script:readMeContent = '# PSBuildTestFixture readme content'
            Set-Content -Path $script:readMePath -Value $script:readMeContent

            $buildParameter = @{
                Path            = $script:scenario.SourcePath
                DestinationPath = $script:scenario.DestinationPath
                ModuleName      = $script:scenario.ModuleName
                Compile         = $true
                ReadMePath      = $script:readMePath
                Culture         = 'en-US'
            }
            Build-PSBuildModule @buildParameter

            $script:aboutHelpPath = [IO.Path]::Combine(
                $script:scenario.DestinationPath, 'en-US', 'about_PSBuildTestFixture.help.txt'
            )
        }

        It 'Writes the readme as the about help file in the culture directory' {
            $script:aboutHelpPath | Should -Exist
        }

        It 'Writes the readme content unchanged' {
            (Get-Content -Path $script:aboutHelpPath -Raw).Trim() | Should -Be $script:readMeContent
        }
    }

    Context 'Choosing the about help culture' {

        BeforeAll {
            $script:scenario = New-PSBuildModuleScenario -Path $TestDrive -Name 'about-help-culture'
            $readMePath = Join-Path -Path $script:scenario.SourcePath -ChildPath 'README.md'
            Set-Content -Path $readMePath -Value '# PSBuildTestFixture readme content'

            $buildParameter = @{
                Path            = $script:scenario.SourcePath
                DestinationPath = $script:scenario.DestinationPath
                ModuleName      = $script:scenario.ModuleName
                Compile         = $true
                ReadMePath      = $readMePath
                Culture         = 'fr-FR'
            }
            Build-PSBuildModule @buildParameter
        }

        It 'Writes the about help file into the requested culture directory' {
            [IO.Path]::Combine(
                $script:scenario.DestinationPath, 'fr-FR', 'about_PSBuildTestFixture.help.txt'
            ) | Should -Exist
        }
    }

    Context 'Converting the readme when the culture directory already exists' {

        # Pins current behavior, which looks wrong: the Copy-Item that writes the about help file
        # sits inside the `if (-not (Test-Path $culturePath))` branch that creates the culture
        # directory, so a build whose output already has that directory silently writes no about
        # help file at all. It is reachable in compile mode whenever CopyDirectories names the
        # culture directory. Left as-is here because it is a behavior change outside the scope of
        # psake/PowerShellBuild#98 and #201; reported separately.
        BeforeAll {
            $script:scenario = New-PSBuildModuleScenario -Path $TestDrive -Name 'about-help-existing'
            $readMePath = Join-Path -Path $script:scenario.SourcePath -ChildPath 'README.md'
            Set-Content -Path $readMePath -Value '# PSBuildTestFixture readme content'

            $culturePath = Join-Path -Path $script:scenario.DestinationPath -ChildPath 'en-US'
            New-Item -Path $culturePath -ItemType Directory -Force > $null

            $buildParameter = @{
                Path            = $script:scenario.SourcePath
                DestinationPath = $script:scenario.DestinationPath
                ModuleName      = $script:scenario.ModuleName
                Compile         = $true
                ReadMePath      = $readMePath
                Culture         = 'en-US'
            }
            Build-PSBuildModule @buildParameter
        }

        It 'Writes no about help file' {
            [IO.Path]::Combine(
                $script:scenario.DestinationPath, 'en-US', 'about_PSBuildTestFixture.help.txt'
            ) | Should -Not -Exist
        }
    }

    Context 'Building a source module with no public functions' {

        BeforeAll {
            $script:scenario = New-PSBuildModuleScenario -Path $TestDrive -Name 'no-public'
            Remove-Item -Path (Join-Path -Path $script:scenario.SourcePath -ChildPath 'Public') -Recurse -Force

            $buildParameter = @{
                Path            = $script:scenario.SourcePath
                DestinationPath = $script:scenario.DestinationPath
                ModuleName      = $script:scenario.ModuleName
            }
            Build-PSBuildModule @buildParameter
        }

        It 'Leaves FunctionsToExport in the manifest alone' {
            # Nothing was discovered to write, so the manifest keeps whatever the source declared
            # rather than being emptied.
            $manifest = Import-PowerShellDataFile -Path $script:scenario.ManifestPath

            @($manifest.FunctionsToExport | Sort-Object) | Should -Be @('Get-Widget', 'Set-Widget')
        }
    }
}
