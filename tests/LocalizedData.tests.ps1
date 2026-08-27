# Coverage for how the module resolves its user-facing strings at import
# (psake/PowerShellBuild#185).
#
# PowerShellBuild.psm1 used to carry a second, hand-written copy of every string in an inline
# `data LocalizedData { ConvertFrom-StringData ... }` block, kept for the case where
# Import-LocalizedData resolved nothing. The import runs with -ErrorAction SilentlyContinue, so a
# lookup that misses binds that copy without saying anything -- and the copy went sixteen strings
# stale, still naming the pre-#182 Pester floor of 5.0.0.
#
# The lookup misses more often than it looks. Import-LocalizedData resolves Messages.psd1 through
# the current UI culture and that culture's parent chain, and the module ships en-US only.
# PowerShell 7 has a final en-US fallback, so it always lands on the shipped file; Windows
# PowerShell 5.1 has no such fallback, so on a machine whose display language is French or
# Japanese the lookup binds nothing at all and the stale copy is what consumers got. 5.1 is a
# supported host (`PowerShellVersion = '5.1'`), which is what made the drift reachable rather
# than theoretical.
#
# Two things are pinned here. The first It is the drift guard: one definition of the strings, so
# there is no second copy left to fall out of step. The Context below is the behavioral
# guarantee, and it runs in a child process per supported host -- a UI culture has to be in place
# before the module is imported, and setting it in-process would leak into the rest of the suite.

BeforeDiscovery {
    # Probe the host running the suite, plus Windows PowerShell when it is installed, because the
    # two do not agree about the en-US fallback and only the 5.1 leg catches the regression. The
    # current process is used for the first leg rather than a PATH lookup so this always produces
    # at least one leg, whichever host the suite was started with; identical paths collapse.
    $currentHostPath = [System.Diagnostics.Process]::GetCurrentProcess().Path
    $windowsPowerShellPath = (
        Get-Command -Name 'powershell.exe' -CommandType 'Application' -ErrorAction SilentlyContinue |
            Select-Object -First 1
    ).Source

    # Sort-Object -Unique rather than Select-Object -Unique: when the suite is running under
    # Windows PowerShell the two lookups return the same executable spelled differently
    # (powershell.EXE and powershell.exe), and only Sort-Object collapses that by default.
    $script:localizationHost = @(
        $currentHostPath, $windowsPowerShellPath |
            Where-Object { $_ } |
            Sort-Object -Unique |
            ForEach-Object { @{ HostName = [IO.Path]::GetFileName($_); HostPath = $_ } }
    )
    if ($script:localizationHost.Count -eq 0) {
        # An empty -ForEach collection throws during discovery, which reads as a file that
        # silently disappeared. Say what actually went wrong instead.
        throw 'Could not resolve the path of the host running this suite; no host can be probed.'
    }
}

Describe 'Localized string resolution' {

    BeforeAll {
        $script:repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:sourceModulePath = [IO.Path]::Combine(
            $script:repositoryRoot, 'PowerShellBuild', 'PowerShellBuild.psm1'
        )

        # Probe the built module rather than the source tree: it is what a consumer installs, and
        # the versioned directory is the -BaseDirectory Import-LocalizedData needs.
        $sourceManifestPath = [IO.Path]::Combine(
            $script:repositoryRoot, 'PowerShellBuild', 'PowerShellBuild.psd1'
        )
        $moduleVersion = (Import-PowerShellDataFile -Path $sourceManifestPath).ModuleVersion
        $script:builtModulePath = [IO.Path]::Combine(
            $script:repositoryRoot, 'Output', 'PowerShellBuild', $moduleVersion
        )
        # The probe imports the .psm1 directly, not the manifest. The manifest's RequiredModules
        # are resolved against the child process's inherited PSModulePath, which on Windows
        # PowerShell means the PowerShell 7 module directories it was spawned from -- a failure
        # that has nothing to do with which strings got bound. The .psm1 is the file under test.
        $script:builtModuleFilePath = Join-Path -Path $script:builtModulePath -ChildPath 'PowerShellBuild.psm1'

        # The strings as shipped. Read through Import-LocalizedData because Messages.psd1 is a
        # ConvertFrom-StringData document rather than a hashtable literal, so
        # Import-PowerShellDataFile cannot read it.
        $importShippedStringParameters = @{
            BindingVariable = 'shippedString'
            BaseDirectory   = $script:builtModulePath
            FileName        = 'Messages.psd1'
            UICulture       = 'en-US'
            ErrorAction     = 'Stop'
        }
        Import-LocalizedData @importShippedStringParameters
        $script:shippedString = $shippedString

        # The probe reports what the module bound at import, from inside the module's own scope.
        # Written to $TestDrive rather than checked in, following the convention in
        # Test-PSBuildPester.tests.ps1 for generated fixtures.
        $script:probeScriptPath = Join-Path -Path $TestDrive -ChildPath 'Get-ResolvedString.ps1'
        Set-Content -Path $script:probeScriptPath -Value @'
param(
    [Parameter(Mandatory)]
    [string]
    $ModuleFilePath,

    [Parameter(Mandatory)]
    [string]
    $UICulture
)

# Set before the import, because Import-LocalizedData reads the UI culture as the module loads.
# This is the state a machine whose Windows display language is not English starts up in.
[System.Threading.Thread]::CurrentThread.CurrentUICulture =
    [System.Globalization.CultureInfo]::new($UICulture)

Import-Module -Name $ModuleFilePath -Force -WarningAction SilentlyContinue -ErrorAction Stop
$resolvedString = & (Get-Module -Name 'PowerShellBuild') { $LocalizedData }
$resolvedString | ConvertTo-Json -Depth 2 -Compress
'@
    }

    It 'defines its user-facing strings in exactly one place' {
        # en-US/Messages.psd1 is the only place a string may be written. A second copy inside the
        # module file cannot be kept in step by hand, which is the whole of #185.
        $moduleSource = Get-Content -Path $script:sourceModulePath -Raw
        $moduleSource | Should -Not -Match 'ConvertFrom-StringData'
    }

    Context 'Imported by <_.HostName> under a non-English UI culture' -ForEach $script:localizationHost {

        BeforeAll {
            # fr-FR is chosen because the module ships no fr-FR directory and none of its parents
            # is en-US, so nothing but a deliberate fallback can reach the shipped strings.
            $probeArgument = @(
                '-NoProfile'
                '-NonInteractive'
                '-File', $script:probeScriptPath
                '-ModuleFilePath', $script:builtModuleFilePath
                '-UICulture', 'fr-FR'
            )
            $probeOutput = & $_.HostPath @probeArgument 2>&1

            # The probe writes one JSON document and nothing else. Selecting the line rather than
            # taking all output keeps a stray host warning from breaking the parse.
            $probeJson = $probeOutput |
                Where-Object { $_ -is [string] -and $_.TrimStart().StartsWith('{') } |
                Select-Object -Last 1

            $script:probeOutput = $probeOutput
            $script:resolvedString = if ($probeJson) { $probeJson | ConvertFrom-Json }
        }

        It 'reports a string table from the probe' {
            # Guards the two assertions below: a probe that produced nothing would otherwise
            # satisfy a foreach over an empty set and prove nothing.
            $script:resolvedString |
                Should -Not -BeNullOrEmpty -Because "the probe wrote: $($script:probeOutput -join '; ')"
        }

        It 'binds every string the module ships' {
            $resolvedKey = $script:resolvedString.PSObject.Properties.Name | Sort-Object
            $shippedKey = $script:shippedString.Keys | Sort-Object
            $resolvedKey | Should -Be $shippedKey
        }

        It 'binds each string to its shipped text' {
            # Key-for-key rather than a count, because the failure this pins was a copy that had
            # the right shape and the wrong words -- it named a Pester floor of 5.0.0 long after
            # #182 raised the real one to 6.0.0.
            foreach ($key in $script:shippedString.Keys) {
                $script:resolvedString.$key |
                    Should -Be $script:shippedString[$key] -Because "[$key] must match en-US/Messages.psd1"
            }
        }
    }
}
