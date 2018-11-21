#requires -version 5 -module psake
using namespace System.Management.Automation

<#
.SYNOPSIS
Converts a PSAke script to an invoke-build script, using best practices where possible
.NOTES
Some Params are private in case the variables are used in the psake script
#>
[CmdletBinding()]
param(
	#The path to the PSAke file
	[Parameter(Mandatory)][string]$PRIVATE:Source,
	#The default tab width, in number of spaces. TODO: Auto-Discover this
	[int]$ConvertPSAkeTabWidth = 4
)

#region Initialize
$PSCommonParameters = ([System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
$ConvertPSAkeIndent = " " * $ConvertPSAkeTabWidth
#endregion Initalize

#region psakeDiscovery
$psakeModule = import-module psake -PassThru
$psakeStatements = $psakeModule.ExportedCommands.keys.where{$PSItem -notmatch '-'}
#endregion psakeDiscovery

#region StatementConversions
function Convert-PsakeStatement ([Language.StatementAst]$statement) {
	$statementText = $statement.extent.text
	$psakeStatement = ($statementText | Select-String '^\w+\b').matches.value

	if ($psakeStatement -in $psakeStatements) {
		if (-not (Get-Alias "$psakeStatement" -erroraction SilentlyContinue)) {
			if (get-command "Convert-$psakeStatement" -erroraction SilentlyContinue) {
				Set-Alias "$psakeStatement" "Convert-$psakeStatement"
			} else {
				"<# CONVERTWARNING: This script does not support the $psakeStatement statement yet"
				$statementText
				'#>'
				continue
			}
		}
		$result = Invoke-Command -scriptblock ([ScriptBlock]::Create($statementText))
		$result -join [Environment]::Newline
	} else {
        '<# CONVERTWARNING: Did not recognize this as a psake-allowed statement'
        $statementText
		'#>'
		continue
    }
}

function Convert-FormatTaskName([scriptblock]$formatScriptBlock) {
	write-output '<# CONVERT-TODO: Custom task headers, see the repository Tasks/Header for details.'
	write-output $formatScriptBlock
	write-output '#>'
}

function Convert-Properties([scriptblock]$properties) {
	#Parse into statements and separate variables from other statement types
	$parsedStatementResult = $properties.ast.endblock.statements.where({$PSItem.gettype().Name -match 'AssignmentStatementAst'},'Split')
	$psakeParams = $parsedStatementResult[0]
	$otherStatements = $parsedStatementResult[1]
	if ($psakeParams) {
		#TODO: Fix Indent
		'param ('
		$psakeParams.extent.text -join (',' + [Environment]::NewLine)
		')'
	}
	if ($otherStatements) {
		'Enter-Build {'
		$otherStatements.extent.text
		'}'
	}
}

function Convert-Framework([string]$framework) {
	'# CONVERT-TODO: Specify used tool names exactly as they are used in the script.'
	'# MSBuild is an example. It should be used as MSBuild, not MSBuild.exe'
	'# Example with more tools: use 4.0 MSBuild, csc, ngen'
	if ($framework -notmatch '^\d+\.\d+$') {
		"# CONVERT-TODO: The form '$framework' is not supported. See help:"
		'# . Invoke-Build; help -full Use-BuildAlias'
	}
	"use $framework MSBuild"
}

function Convert-Include([string]$fileNamePathToInclude) {
	'# CONVERT-TODO: Decide whether it is dot-sourced (.) or just invoked (&).'
	". '$($fileNamePathToInclude.Replace("'", "''"))'"
}

function Convert-TaskSetup([scriptblock]$setup) {
	"Enter-BuildTask {$setup}"
}

function Convert-TaskTearDown([scriptblock]$teardown) {
	"Exit-BuildTask {$teardown}"
}

function Convert-Task
{
	param(
		[string]$name,
		[scriptblock]$action,
		[scriptblock]$preaction,
		[scriptblock]$postaction,
		[scriptblock]$precondition,
		[scriptblock]$postcondition,
		[switch]$continueOnError,
		[string[]]$depends,
		[string[]]$requiredVariables,
		[string]$description,
		[string]$alias
	)

	if ($name -eq '?') {
		"# CONVERTWARNING: You specified a '?' task. Invoke-Build has its own built-in function for this so it was not copied."
		continue
	}

	if ($description) {
		$description = $description -replace '[\r\n]+', ' '
		"# Synopsis: $description"
	}

	if ($alias) {"# CONVERT-TODO: Alias '$alias' is not supported. Do not use it or define another task: task $alias $name"}
	if ($continueOnError) {"# CONVERT-TODO: ContinueOnError is not supported. Instead, callers use its safe reference as '?$name'"}

	$newTaskHeader = 'task '
	if ($name -eq 'default') {
		'# Default task converted from PSAke. If it is the first then any name can be used instead.'
		$newTaskHeader += '.'
	}
	else {
		$newTaskHeader += $name
	}
	if ($precondition) {
		$newTaskHeader += " -If {$precondition}"
	}

	$newTaskJobs = @()
	if ($depends) {
		$newTaskJobs += $depends
	}
	if ($preaction) {
		$newTaskJobs += "{$preaction}"
	}
	if ($action) {
		if ($requiredVariables) {
			$outAction = New-Object Text.StringBuilder
			$outAction.AppendLine() > $null
			$requiredVariables.foreach{
				$outAction.appendLine("${ConvertPSAkeIndent}property $PSItem") > $null
			}
			$outaction.appendLine($action.tostring()) > $null
			$action = [Scriptblock]::Create($outaction.tostring())
		}
		$newTaskJobs += "{$action}"
	}
	if ($postaction) {
		$newTaskJobs += "{$postaction}"
	}
	if ($postcondition) {
		$newTaskJobs += " { assert `$($postcondition) }"
	}

	#output the formatted header
	$newTaskHeader + " " + ($newTaskJobs -join ', ')
}
#endregion StatementConversions


#region Main
New-Variable parseTokens -force
New-Variable parseErrors -force

$ErrorActionPreference = 'Stop'

$sourceRaw = (Get-Content -Path $Source -Raw)

#Psake Variable Substitution
#TODO: More structured method using AST
#TODO: Variable Collision Detection
$sourceRaw = $sourceRaw -replace [regex]::Escape('$psake.context.currentTaskName'), '$task.name'
$sourceRaw = $sourceRaw -replace [regex]::Escape('$psake.context.Peek().Tasks.Keys'), '$BuildTask'
$sourceRaw = $sourceRaw -replace [regex]::Escape('$psake.version'), '[string](get-command invoke-build | % version)'
$sourceRaw = $sourceRaw -replace [regex]::Escape('$psake.build_script_file'), '$BuildFile'
$sourceRaw = $sourceRaw -replace [regex]::Escape('$psake.build_script_dir'), '(Split-Path $BuildFile -Parent)'


$out = New-Object System.Text.Stringbuilder

$parseResult = [Language.Parser]::ParseInput(
    $sourceRaw, #Source of data
    [ref]$parseTokens, #Tokens found during parsing
    [ref]$parseErrors #Any parse errors found
)

if ($parseErrors) {throw "Parsing Errors Found! Please fix first: $parseErrors"}

#Parse the Powershell source into statement blocks
$statements = $ParseResult.endblock.statements

$statements.foreach{
	$statementItem = $PSItem
	$statementItemText = $statementItem.extent.text

	#TODO: AST-based variable substitution for $psake
	$unsupportedPsakeVarErrors = [ordered]@{
		'context' = '$psake.context is unsupported. Use properties instead'
		'config_default' = '$psake.config_default is unsupported. Use Invoke-Build -Result instead'
		'run_by_psake_build_tester' = '$psake.run_by_psake_build_tester is unsupported. Use Invoke-Build -Result instead'
		'build_success'= '$psake.build_success is unsupported. Use Invoke-Build -Result instead'
		'error_message' = '$psake.error_message is unsupported. Use Invoke-Build -Result instead'
		'' = 'Use of the $psake variable is unsupported. Use Invoke-Build -Result to get build status'
	}
	$psakeVarFound = $false
	foreach ($psakeVarErrorItem in $unsupportedPsakeVarErrors.keys) {
		$unsupportedPsakeVarsRegex = "\`$psake\.?$([regex]::Escape($psakeVarErrorItem))"
		if ($statementItemText -match $unsupportedPsakeVarsRegex) {
			$out.AppendLine("<# CONVERTWARNING: " + $unsupportedPsakeVarErrors[$psakeVarErrorItem]) > $null
			$out.AppendLine($statementItemText) > $null
			$out.AppendLine('#>') > $null
			$psakeVarFound = $true
			break
		}
	}
	if ($psakeVarFound) {return}

	switch ($statementItem.gettype().name) {
        'PipelineAst' {
            switch -regex ($statementItem.extent.text) {
                #Known psake functions
                "^($($psakeStatements -join '|'))\b" {
                    try {
						$convertStatementResult = Convert-PsakeStatement $StatementItem
						if ($convertStatementResult -is [String]) {
							$out.AppendLine($convertStatementResult) > $null
						}
                    }
                    catch {
                        $out.AppendLine("<# CONVERTWARNING: This statement was copied not converted due to the error: $PSItem") > $null
                        $out.AppendLine($statementItemText) > $null
                        $out.AppendLine('#>') > $null
                    }
                }
                default {
                    $out.AppendLine('#CONVERTWARNING: psake to InvokeBuild Conversion did not recognize this codeblock and passed through as-is. Consider moving it to Enter-Build') > $null
                    $out.AppendLine($statementItemText) > $null
                }
            }
		}
		'AssignmentStatementAst' {
			$out.AppendLine($statementItemText) > $null
		}
        default {
            $out.AppendLine('#CONVERT-WARNING: psake to InvokeBuild Conversion did not recognize this codeblock and passed through as-is') > $null
            $out.AppendLine($statementItemText) > $null
        }
	}

	#Add a line break between statements for consistency
	$out.AppendLine() > $null
}

$out.tostring()
#endregion Main
