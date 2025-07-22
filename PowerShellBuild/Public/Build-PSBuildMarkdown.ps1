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
    .PARAMETER AlphabeticParamsOrder
        Order parameters alphabetically by name in PARAMETERS section. There are 5 exceptions: -Confirm, -WhatIf, -IncludeTotalCount, -Skip, and -First parameters will be the last.
    .PARAMETER ExcludeDontShow
        Exclude the parameters marked with `DontShow` in the parameter attribute from the help content.
    .PARAMETER UseFullTypeName
        Indicates that the target document will use a full type name instead of a short name for parameters.
    .EXAMPLE
        PS> Build-PSBuildMarkdown -ModulePath ./output/MyModule/0.1.0 -ModuleName MyModule -DocsPath ./docs -Locale en-US

        Analysis the comment-based help of the MyModule module and create markdown documents under ./docs/en-US.
    #>
    [CmdletBinding()]
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
        [bool]$Overwrite,

        [parameter(Mandatory)]
        [bool]$AlphabeticParamsOrder,

        [parameter(Mandatory)]
        [bool]$ExcludeDontShow,

        [parameter(Mandatory)]
        [bool]$UseFullTypeName
    )

    $moduleInfo = Import-Module "$ModulePath/$ModuleName.psd1" -Global -Force -PassThru

    try {
        if ($moduleInfo.ExportedCommands.Count -eq 0) {
            Write-Warning $LocalizedData.NoCommandsExported
            return
        }

        if (-not (Test-Path -LiteralPath $DocsPath)) {
            New-Item -Path $DocsPath -ItemType Directory > $null
        }

        if (Get-ChildItem -LiteralPath $DocsPath -Filter *.md -Recurse) {
            $updateMDParams = @{
                AlphabeticParamsOrder = $AlphabeticParamsOrder
                ExcludeDontShow       = $ExcludeDontShow
                UseFullTypeName       = $UseFullTypeName
                Verbose               = $VerbosePreference
            }
            Get-ChildItem -LiteralPath $DocsPath -Directory | ForEach-Object {
                Update-MarkdownHelp -Path $_.FullName @updateMDParams > $null
            }
        }

        # ErrorAction set to SilentlyContinue so this command will not overwrite an existing MD file.
        $newMDParams = @{
            Module                = $ModuleName
            Locale                = $Locale
            OutputFolder          = [IO.Path]::Combine($DocsPath, $Locale)
            AlphabeticParamsOrder = $AlphabeticParamsOrder
            ExcludeDontShow       = $ExcludeDontShow
            UseFullTypeName       = $UseFullTypeName
            ErrorAction           = 'SilentlyContinue'
            Verbose               = $VerbosePreference
        }
        if ($Overwrite) {
            $newMDParams.Add('Force', $true)
            $newMDParams.Remove('ErrorAction')
        }
        New-MarkdownHelp @newMDParams > $null
    } catch {
        Write-Error ($LocalizedData.FailedToGenerateMarkdownHelp -f $_)
    } finally {
        Remove-Module $moduleName
    }
}
