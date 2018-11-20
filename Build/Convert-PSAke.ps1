#requires -version 5 -module psake
using namespace System.Management.Automation

#Params are private in case the variables are used in the psake script
param(
	[Parameter(Mandatory)][string]$PRIVATE:Source
)

#region Setup
Set-Variable -Option Constant -Name PSCommonParameters -Value ([System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters)

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
	'# CONVERT-TODO: Move some properties to script param() in order to use as parameters.'
	$properties
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

	if ($description -or ${*Synopsis}) {
		$description = $description -replace '[\r\n]+', ' '
		"# Synopsis: $description"
	}

	if ($alias) {"# CONVERT-TODO: Alias '$alias' is not supported. Do not use it or define another task: task $alias $name"}
	if ($continueOnError) {"# CONVERT-TODO: ContinueOnError is not supported. Instead, callers use its safe reference as '?$name'"}
	if ($requiredVariables) {'# CONVERT-TODO: RequiredVariables is not supported. Instead, in the action use: $VarName = property VarName'}


	### task Name

	$$ = 'task '
	if ($name -eq 'default') {
		'# CONVERT-TODO: Default task. If it is the first then any name can be used instead.'
		$$ += '.'
	}
	else {
		$$ += $name
	}

	### If
	if ($precondition) {
		$$ += " -If {$precondition}"
	}

	$comma = $false

	### Referenced tasks
	if ($depends) {
		$$ += ' ' + ($depends -join ',')
		$comma = $true
	}

	### Preaction
	if ($preaction) {
		if ($comma) {$$ += ','} else {$comma = $true}
		$$ += " {$preaction}"
	}

	### Action
	if ($action) {
		if ($comma) {$$ += ','} else {$comma = $true}
		$$ += " {$action}"
	}

	### Postaction
	if ($postaction) {
		if ($comma) {$$ += ','} else {$comma = $true}
		$$ += " {$postaction}"
	}

	### Postcondition
	if ($postcondition) {
		if ($comma) {$$ += ','}
		$$ += " { assert `$($postcondition) }"
	}

	$$
}
#endregion StatementConversions


#region Main
New-Variable parseTokens -force
New-Variable parseErrors -force

$ErrorActionPreference = 'Stop'

$sourceRaw = (Get-Content -Path $Source -Raw)

#Psake Variable Substitution
#TODO: More structured method using AST

$sourceRaw = $sourceRaw -replace [regex]::Escape('$psake.context.currentTaskName'), '$task.name'

$out = New-Object System.Text.Stringbuilder

$parseResult = [Language.Parser]::ParseInput(
    $sourceRaw, #Source of data
    [ref]$parseTokens, #Tokens found during parsing
    [ref]$parseErrors #Any parse errors found
)

if ($parseErrors) {throw "Parsing Errors Found! Please fix first: $parseErrors"}


#Variable Replacement

#Parse the Powershell source into statement blocks
$statements = $ParseResult.endblock.statements

foreach ($statementItem in $statements) {
	$statementItemText = $statementItem.extent.text
	#TODO: AST-based variable substitution for $psake
	if ($statementItemText -match [regex]::Escape('$psake.context')) {
		$out.AppendLine('<# CONVERTWARNING: Your script references $psake.context and this is not being converted yet.') > $null
		$out.AppendLine($statementItemText) > $null
		$out.AppendLine('#>') > $null
	}

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
                    $out.AppendLine('#CONVERTWARNING: psake to InvokeBuild Conversion did not recognize this codeblock and passed through as-is') > $null
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
