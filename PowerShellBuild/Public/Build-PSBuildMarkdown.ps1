function Build-PSBuildMarkdown {
    <#
    .SYNOPSIS
        Creates PlatyPS markdown documents based on comment-based help of module.
    .DESCRIPTION
        Creates PlatyPS markdown documents based on comment-based help of module.
    .PARAMETER ModulePath
        The path to the module
    .PARAMETER ModuleName
        The name of the module.
    .PARAMETER DocsPath
        The path where PlatyPS markdown docs will be saved.
    .PARAMETER Locale
        The locale to save the markdown docs.
    .PARAMETER Overwrite
        Overwrite existing markdown files and use comment based help as the source of truth.
    .EXAMPLE
        PS> Build-PSBuildMarkdown -ModulePath ./output/MyModule/0.1.0 -ModuleName MyModule -DocsPath ./docs -Locale en-US

        Analysis the comment-based help of the MyModule module and create markdown documents under ./docs/en-US.
    #>
    [cmdletbinding()]
    param(
        [parameter(Mandatory)]
        [string]$ModulePath,

        [parameter(Mandatory)]
        [string]$ModuleName,

        [parameter(Mandatory)]
        [string]$DocsPath,

        [parameter(Mandatory)]
        [string]$Locale,

        [parameter(Mandatory)]
        [bool]$Overwrite
    )

    $moduleInfo = Import-Module "$ModulePath/$ModuleName.psd1" -Global -Force -PassThru

    try {
        if ($moduleInfo.ExportedCommands.Count -eq 0) {
            Write-Warning 'No commands have been exported. Skipping markdown generation.'
            return
        }

        if (-not (Test-Path -LiteralPath $DocsPath)) {
            New-Item -Path $DocsPath -ItemType Directory > $null
        }

        if (Get-ChildItem -LiteralPath $DocsPath -Filter *.md -Recurse) {
            Get-ChildItem -LiteralPath $DocsPath -Directory | ForEach-Object {
                Update-MarkdownHelp -Path $_.FullName -Verbose:$VerbosePreference > $null
            }
        }

        # ErrorAction set to SilentlyContinue so this command will not overwrite an existing MD file.
        $newMDParams = @{
            Module = $ModuleName
            Locale = $Locale
            OutputFolder = [IO.Path]::Combine($DocsPath, $Locale)
            ErrorAction = 'SilentlyContinue'
            Verbose = $VerbosePreference
            Force = $Overwrite
        }
        if ($Overwrite) {
            $newMDParams.Add('Force', $true)
            $newMDParams.Remove('ErrorAction')
        }
        New-MarkdownHelp @newMDParams > $null
    } catch {
        Write-Error "Failed to generate markdown help. : $_"
    } finally {
        Remove-Module $moduleName
    }
}
