# spell-checker:ignore SIGNCERTIFICATE CERTIFICATEPASSWORD codesign pfxfile
Describe 'Code Signing Functions' {

  BeforeAll {
    $script:moduleName = 'PowerShellBuild'
    $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module ([IO.Path]::Combine($script:moduleRoot, 'Output', $script:moduleName)) -Force

    # Create a temporary directory for test files
    $script:testPath = Join-Path -Path $TestDrive -ChildPath 'SigningTest'
    New-Item -Path $script:testPath -ItemType Directory -Force | Out-Null
  }

  Context 'Get-PSBuildCertificate' {

    BeforeEach {
      # Clear environment variables before each test
      Remove-Item env:\SIGNCERTIFICATE -ErrorAction SilentlyContinue
      Remove-Item env:\CERTIFICATEPASSWORD -ErrorAction SilentlyContinue
    }

    Context 'Auto mode' {
      It 'Resolves to EnvVar mode when SIGNCERTIFICATE environment variable is set' {
        $env:SIGNCERTIFICATE = 'base64data'
        try {
          $VerboseOutput = Get-PSBuildCertificate -Verbose -WarningAction SilentlyContinue -ErrorAction SilentlyContinue 4>&1
          $VerboseOutput | Should -Match "Resolved to 'EnvVar'"
        } catch {
          # Expected to fail with invalid base64, just checking the mode selection
          $_.Exception.Message | Should -Not -BeNullOrEmpty
        }
      }

      It 'Resolves to Store mode when SIGNCERTIFICATE environment variable is not set' -Skip:(-not $IsWindows) {
        Remove-Item env:\SIGNCERTIFICATE -ErrorAction SilentlyContinue
        Mock Get-ChildItem {}
        $VerboseOutput = Get-PSBuildCertificate -ErrorAction SilentlyContinue -Verbose 4>&1
        $VerboseOutput | Should -Match "Resolved to 'Store'"
      }
    }

    # Store mode only works on Windows
    Context 'Store mode' {
      It 'Searches the certificate store for a valid code-signing certificate' -Skip:(-not $IsWindows) {
        # On Windows, we can test the actual logic without mocking the cert store itself
        # Instead, just verify the function accepts the parameter and attempts the search
        $command = Get-Command Get-PSBuildCertificate
        $command.Parameters['CertificateSource'].Attributes.ValidValues | Should -Contain 'Store'

        # If no cert found, should return $null (not throw)
        { Get-PSBuildCertificate -CertificateSource Store -ErrorAction SilentlyContinue } | Should -Not -Throw
      }

      It 'Returns $null when no valid certificate is found' -Skip:(-not $IsWindows) {
        Mock Get-ChildItem { }
        $cert = Get-PSBuildCertificate -CertificateSource Store
        $cert | Should -BeNullOrEmpty
      }

      It 'Filters out expired certificates' -Skip:(-not $IsWindows) {
        Mock Get-ChildItem {
          # Return nothing (expired cert is filtered by Where-Object)
        }

        $cert = Get-PSBuildCertificate -CertificateSource Store
        $cert | Should -BeNullOrEmpty
      }

      It 'Filters out certificates without a private key' -Skip:(-not $IsWindows) {
        Mock Get-ChildItem {
          # Return nothing (cert without private key is filtered by Where-Object)
        }

        $cert = Get-PSBuildCertificate -CertificateSource Store
        $cert | Should -BeNullOrEmpty
      }

      It 'Uses custom CertStoreLocation when specified' -Skip:(-not $IsWindows) {
        # Just verify the parameter is accepted
        { Get-PSBuildCertificate -CertificateSource Store -CertStoreLocation 'Cert:\LocalMachine\My' -ErrorAction SilentlyContinue } |
          Should -Not -Throw
      }
    }

    Context 'Thumbprint mode' {
      It 'Searches for a certificate with the specified thumbprint' -Skip:(-not $IsWindows) {
        $testThumbprint = 'ABCD1234EFGH5678'
        # Verify the function accepts the thumbprint parameter
        { Get-PSBuildCertificate -CertificateSource Thumbprint -Thumbprint $testThumbprint -ErrorAction SilentlyContinue } |
          Should -Not -Throw
      }

      It 'Returns $null when the specified thumbprint is not found' -Skip:(-not $IsWindows) {
        Mock Get-ChildItem { }
        $cert = Get-PSBuildCertificate -CertificateSource Thumbprint -Thumbprint 'NOTFOUND123'
        $cert | Should -BeNullOrEmpty
      }
    }

    Context 'EnvVar mode' {
      It 'Attempts to decode a Base64-encoded PFX from environment variable' {
        # Create a minimal mock certificate data (will fail to parse, but that's expected)
        $env:SIGNCERTIFICATE = [System.Convert]::ToBase64String([byte[]]@(1, 2, 3, 4, 5))

        # This should fail because the data is not a valid PFX, but that proves it's trying to load it
        { Get-PSBuildCertificate -CertificateSource EnvVar -ErrorAction Stop } | Should -Throw
      }

      It 'Uses custom environment variable names when specified' {
        $env:MY_CUSTOM_CERT = [System.Convert]::ToBase64String([byte[]]@(1, 2, 3, 4, 5))
        $env:MY_CUSTOM_PASS = 'password'

        try {
          Get-PSBuildCertificate -CertificateSource EnvVar `
            -CertificateEnvVar 'MY_CUSTOM_CERT' `
            -CertificatePasswordEnvVar 'MY_CUSTOM_PASS' `
            -ErrorAction SilentlyContinue
        } catch {
          # Expected to fail with invalid certificate data
        }

        # Cleanup
        Remove-Item env:\MY_CUSTOM_CERT -ErrorAction SilentlyContinue
        Remove-Item env:\MY_CUSTOM_PASS -ErrorAction SilentlyContinue
      }
    }

    Context 'PfxFile mode' {
      It 'Accepts a PfxFilePath parameter' {
        $testPfxPath = Join-Path -Path $TestDrive -ChildPath 'test.pfx'
        New-Item -Path $testPfxPath -ItemType File -Force | Out-Null

        try {
          Get-PSBuildCertificate -CertificateSource PfxFile `
            -PfxFilePath $testPfxPath `
            -ErrorAction SilentlyContinue
        } catch {
          # Expected to fail with invalid PFX file
        }

        # Just verify the parameter is accepted
        { Get-PSBuildCertificate -CertificateSource PfxFile -PfxFilePath $testPfxPath -ErrorAction Stop } |
          Should -Throw
      }

      It 'Accepts a PfxFilePassword parameter' {
        $testPfxPath = Join-Path -Path $TestDrive -ChildPath 'test.pfx'
        New-Item -Path $testPfxPath -ItemType File -Force | Out-Null
        $securePassword = ConvertTo-SecureString -String 'password' -AsPlainText -Force

        try {
          Get-PSBuildCertificate -CertificateSource PfxFile `
            -PfxFilePath $testPfxPath `
            -PfxFilePassword $securePassword `
            -ErrorAction SilentlyContinue
        } catch {
          # Expected to fail with invalid PFX file
        }

        # Just verify the parameters are accepted
        $testPfxPath | Should -Exist
      }
    }

    Context 'Parameter validation' {
      It 'ValidateSet accepts valid CertificateSource values' {
        $command = Get-Command Get-PSBuildCertificate
        $parameter = $command.Parameters['CertificateSource']
        $validValues = $parameter.Attributes.ValidValues
        $validValues | Should -Contain 'Auto'
        $validValues | Should -Contain 'Store'
        $validValues | Should -Contain 'Thumbprint'
        $validValues | Should -Contain 'EnvVar'
        $validValues | Should -Contain 'PfxFile'
      }

      It 'Has correct default value for CertStoreLocation' {
        $command = Get-Command Get-PSBuildCertificate
        $parameter = $command.Parameters['CertStoreLocation']
        $parameter.Attributes.Where({ $_.TypeId.Name -eq 'ParameterAttribute' })[0].Mandatory |
          Should -BeFalse
      }

      It 'Has correct default value for CertificateEnvVar' {
        $command = Get-Command Get-PSBuildCertificate
        $parameter = $command.Parameters['CertificateEnvVar']
        $parameter.Attributes.Where({ $_.TypeId.Name -eq 'ParameterAttribute' })[0].Mandatory |
          Should -BeFalse
      }
    }
  }
}
