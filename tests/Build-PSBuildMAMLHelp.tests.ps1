Describe 'Build-PSBuildMAMLHelp' {
  BeforeAll {
    $script:moduleName = 'PowerShellBuild'
    $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module ([IO.Path]::Combine($script:moduleRoot, 'Output', $script:moduleName)) -Force
  }

  It 'Generates help for each locale directory under Path' {
    Mock Get-ChildItem {
      @(
        [PSCustomObject]@{ Name = 'en-US' }
        [PSCustomObject]@{ Name = 'fr-FR' }
      )
    } -ParameterFilter { $Path -eq 'docs/help' -and $Directory }

    Mock New-ExternalHelp {}

    Build-PSBuildMAMLHelp -Path 'docs/help' -DestinationPath 'out/module' -Verbose:$false

    Assert-MockCalled New-ExternalHelp -Times 2 -Exactly
    Assert-MockCalled New-ExternalHelp -Times 1 -Exactly -ParameterFilter {
      $Path -eq [IO.Path]::Combine('docs/help', 'en-US') -and
      $OutputPath -eq [IO.Path]::Combine('out/module', 'en-US') -and
      $Force -eq $true -and
      $ErrorAction -eq 'SilentlyContinue'
    }
    Assert-MockCalled New-ExternalHelp -Times 1 -Exactly -ParameterFilter {
      $Path -eq [IO.Path]::Combine('docs/help', 'fr-FR') -and
      $OutputPath -eq [IO.Path]::Combine('out/module', 'fr-FR') -and
      $Force -eq $true -and
      $ErrorAction -eq 'SilentlyContinue'
    }
  }

  It 'Surfaces errors from New-ExternalHelp (platyPS dependency)' {
    Mock Get-ChildItem {
      @([PSCustomObject]@{ Name = 'en-US' })
    } -ParameterFilter { $Path -eq 'docs/help' -and $Directory }

    Mock New-ExternalHelp {
      throw 'The term New-ExternalHelp is not recognized as the name of a cmdlet.'
    }

    {
      Build-PSBuildMAMLHelp -Path 'docs/help' -DestinationPath 'out/module' -Verbose:$false
    } | Should -Throw '*New-ExternalHelp*'
  }
}
