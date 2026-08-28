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

  Context 'Invoke-PSBuildModuleSigning' {

    It 'Should exist and be exported' {
      Get-Command Invoke-PSBuildModuleSigning -Module PowerShellBuild -ErrorAction SilentlyContinue |
        Should -Not -BeNullOrEmpty
    }

    It 'Has a SYNOPSIS section in the help' {
      (Get-Help Invoke-PSBuildModuleSigning).Synopsis |
        Should -Not -BeNullOrEmpty
    }

    It 'Has at least one EXAMPLE section in the help' {
      (Get-Help Invoke-PSBuildModuleSigning).Examples.Example |
        Should -Not -BeNullOrEmpty
    }

    It 'Requires Path parameter' {
      $command = Get-Command Invoke-PSBuildModuleSigning
      $command.Parameters['Path'].Attributes.Where({ $_.TypeId.Name -eq 'ParameterAttribute' }).Mandatory |
        Should -Contain $true
    }

    It 'Requires Certificate parameter' {
      $command = Get-Command Invoke-PSBuildModuleSigning
      $command.Parameters['Certificate'].Attributes.Where({ $_.TypeId.Name -eq 'ParameterAttribute' }).Mandatory |
        Should -Contain $true
    }

    It 'Validates that Path must be a directory' {
      $testFilePath = Join-Path -Path $TestDrive -ChildPath 'testfile.txt'
      New-Item -Path $testFilePath -ItemType File -Force | Out-Null

      $mockCert = [PSCustomObject]@{ Subject = 'CN=Test' }

      { Invoke-PSBuildModuleSigning -Path $testFilePath -Certificate $mockCert } |
        Should -Throw
    }

    It 'Accepts TimestampServer and HashAlgorithm parameters' {
      # Just verify parameters are accepted without error
      $command = Get-Command Invoke-PSBuildModuleSigning
      $command.Parameters.ContainsKey('TimestampServer') | Should -BeTrue
      $command.Parameters.ContainsKey('HashAlgorithm') | Should -BeTrue
      $command.Parameters['TimestampServer'].ParameterType.Name | Should -Be 'String'
      $command.Parameters['HashAlgorithm'].ParameterType.Name | Should -Be 'String'
    }

    It 'Has correct default values' {
      $command = Get-Command Invoke-PSBuildModuleSigning
      # Check default timestamp server
      $tsParam = $command.Parameters['TimestampServer']
      $tsParam | Should -Not -BeNullOrEmpty
      # Check default hash algorithm
      $hashParam = $command.Parameters['HashAlgorithm']
      $hashParam.Attributes.Where({ $_.TypeId.Name -eq 'ValidateSetAttribute' }).ValidValues |
        Should -Contain 'SHA256'
    }

    It 'ValidateSet accepts valid HashAlgorithm values' {
      $command = Get-Command Invoke-PSBuildModuleSigning
      $parameter = $command.Parameters['HashAlgorithm']
      $validValues = $parameter.Attributes.ValidValues
      $validValues | Should -Contain 'SHA256'
      $validValues | Should -Contain 'SHA384'
      $validValues | Should -Contain 'SHA512'
      $validValues | Should -Contain 'SHA1'
    }

    # Everything above this point reads the command's metadata; none of it runs the function, so
    # its body reported no coverage at all and nothing checked that the Include patterns, the
    # timestamp server, or the hash algorithm reach Set-AuthenticodeSignature rather than being
    # accepted and dropped. See psake/PowerShellBuild#217.
    #
    # Set-AuthenticodeSignature exists only on Windows, so a mock of it cannot even be declared
    # elsewhere, and signing is a Windows-only capability by design. Windows-only here means
    # platform, not edition: $IsWindows does not exist on Windows PowerShell 5.1, where
    # -Skip:(-not $IsWindows) would skip on the engine signing is most common on. See
    # psake/PowerShellBuild#197.
    Context 'Signing files' -Skip:($null -ne $IsWindows -and -not $IsWindows) {

      BeforeAll {
        # A certificate that exists only in memory and is never added to a certificate store. It
        # is here to satisfy the X509Certificate2 parameter type; nothing in this context signs
        # anything, because Set-AuthenticodeSignature is mocked.
        $script:signingKey = [System.Security.Cryptography.RSA]::Create(2048)
        $certificateRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
          'CN=PowerShellBuild Mocked Signing Test Certificate',
          $script:signingKey,
          [System.Security.Cryptography.HashAlgorithmName]::SHA256,
          [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
        $script:mockedCertificate = $certificateRequest.CreateSelfSigned(
          [DateTimeOffset]::UtcNow.AddDays(-1),
          [DateTimeOffset]::UtcNow.AddDays(30)
        )
      }

      AfterAll {
        if ($script:mockedCertificate) {
          $script:mockedCertificate.Dispose()
        }
        if ($script:signingKey) {
          $script:signingKey.Dispose()
        }
      }

      BeforeEach {
        # A fresh tree per test, so no test can be affected by what another one signed. The
        # script under Public is there to prove the search recurses, and the text file to prove
        # the Include patterns filter.
        $script:moduleDirectory = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $publicDirectory = Join-Path -Path $script:moduleDirectory -ChildPath 'Public'
        New-Item -Path $publicDirectory -ItemType Directory -Force | Out-Null
        "@{ ModuleVersion = '1.0.0' }" | Out-File -FilePath (Join-Path -Path $script:moduleDirectory -ChildPath 'TestModule.psd1')
        '. $PSScriptRoot/Public/Get-Widget.ps1' | Out-File -FilePath (Join-Path -Path $script:moduleDirectory -ChildPath 'TestModule.psm1')
        'function Get-Widget { }' | Out-File -FilePath (Join-Path -Path $publicDirectory -ChildPath 'Get-Widget.ps1')
        'This file is documentation, not code.' | Out-File -FilePath (Join-Path -Path $script:moduleDirectory -ChildPath 'readme.txt')

        Mock -ModuleName PowerShellBuild -CommandName Set-AuthenticodeSignature -MockWith {
          [PSCustomObject]@{ Status = 'Valid' }
        }
      }

      It 'Signs every file matching the default Include patterns' {
        $null = Invoke-PSBuildModuleSigning -Path $script:moduleDirectory -Certificate $script:mockedCertificate

        Should -Invoke -ModuleName PowerShellBuild -CommandName Set-AuthenticodeSignature -Times 3 -Exactly
      }

      It 'Signs a file nested below the path' {
        $null = Invoke-PSBuildModuleSigning -Path $script:moduleDirectory -Certificate $script:mockedCertificate

        Should -Invoke -ModuleName PowerShellBuild -CommandName Set-AuthenticodeSignature -Times 1 -Exactly `
          -ParameterFilter { $LiteralPath -like '*Get-Widget.ps1' }
      }

      It 'Does not sign a file that matches no Include pattern' {
        $null = Invoke-PSBuildModuleSigning -Path $script:moduleDirectory -Certificate $script:mockedCertificate

        Should -Invoke -ModuleName PowerShellBuild -CommandName Set-AuthenticodeSignature -Times 0 -Exactly `
          -ParameterFilter { $LiteralPath -like '*readme.txt' }
      }

      It 'Signs only the files matching a custom Include pattern' {
        $null = Invoke-PSBuildModuleSigning -Path $script:moduleDirectory -Certificate $script:mockedCertificate `
          -Include '*.psd1'

        Should -Invoke -ModuleName PowerShellBuild -CommandName Set-AuthenticodeSignature -Times 1 -Exactly `
          -ParameterFilter { $LiteralPath -like '*TestModule.psd1' }
      }

      It 'Passes the certificate, timestamp server, and hash algorithm it was given to the signing cmdlet' {
        $null = Invoke-PSBuildModuleSigning -Path $script:moduleDirectory -Certificate $script:mockedCertificate `
          -TimestampServer 'http://timestamp.example.test' -HashAlgorithm 'SHA512'

        Should -Invoke -ModuleName PowerShellBuild -CommandName Set-AuthenticodeSignature -Times 3 -Exactly `
          -ParameterFilter {
          $Certificate.Thumbprint -eq $script:mockedCertificate.Thumbprint -and
          $TimestampServer -eq 'http://timestamp.example.test' -and
          $HashAlgorithm -eq 'SHA512'
        }
      }

      It 'Passes the default timestamp server and hash algorithm when none are given' {
        $null = Invoke-PSBuildModuleSigning -Path $script:moduleDirectory -Certificate $script:mockedCertificate

        Should -Invoke -ModuleName PowerShellBuild -CommandName Set-AuthenticodeSignature -Times 3 -Exactly `
          -ParameterFilter {
          $TimestampServer -eq 'http://timestamp.digicert.com' -and
          $HashAlgorithm -eq 'SHA256'
        }
      }

      It 'Returns what the signing cmdlet returned for every file' {
        $signature = Invoke-PSBuildModuleSigning -Path $script:moduleDirectory -Certificate $script:mockedCertificate

        @($signature).Count | Should -Be 3
      }
    }

    # The mocked context proves the function forwards what it was handed. Only a run against a
    # certificate that can really sign proves the arguments it forwards are ones
    # Set-AuthenticodeSignature will accept.
    Context 'Signing with a real certificate' -Skip:($null -ne $IsWindows -and -not $IsWindows) {

      BeforeAll {
        $script:certificateStoreLocation = 'Cert:\CurrentUser\My'
        $script:realCertificate = New-SelfSignedCertificate -Type CodeSigningCert `
          -Subject 'CN=PowerShellBuild Integration Test Certificate' `
          -CertStoreLocation $script:certificateStoreLocation `
          -NotAfter (Get-Date).AddDays(1)

        $script:realModuleDirectory = Join-Path -Path $TestDrive -ChildPath 'RealSigning'
        $publicDirectory = Join-Path -Path $script:realModuleDirectory -ChildPath 'Public'
        New-Item -Path $publicDirectory -ItemType Directory -Force | Out-Null
        "@{ ModuleVersion = '1.0.0' }" | Out-File -FilePath (Join-Path -Path $script:realModuleDirectory -ChildPath 'TestModule.psd1')
        '. $PSScriptRoot/Public/Get-Widget.ps1' | Out-File -FilePath (Join-Path -Path $script:realModuleDirectory -ChildPath 'TestModule.psm1')
        'function Get-Widget { }' | Out-File -FilePath (Join-Path -Path $publicDirectory -ChildPath 'Get-Widget.ps1')
        'This file is documentation, not code.' | Out-File -FilePath (Join-Path -Path $script:realModuleDirectory -ChildPath 'readme.txt')

        # An empty timestamp server keeps the test off the network. A timestamp is what keeps a
        # signature valid past the certificate's expiry, and nothing here outlives the test run.
        $script:realSignature = Invoke-PSBuildModuleSigning -Path $script:realModuleDirectory `
          -Certificate $script:realCertificate -TimestampServer ''
      }

      AfterAll {
        # This runs on a real person's machine. Whatever happened above, the certificate this
        # context installed does not outlive it.
        if ($script:realCertificate) {
          Get-ChildItem -Path $script:certificateStoreLocation |
            Where-Object { $_.Thumbprint -eq $script:realCertificate.Thumbprint } |
            Remove-Item -Force
        }
      }

      It 'Signs exactly the files matching the Include patterns, including nested ones' {
        $signedFileName = @($script:realSignature | ForEach-Object { Split-Path -Path $_.Path -Leaf } | Sort-Object)

        $signedFileName | Should -Be @('Get-Widget.ps1', 'TestModule.psd1', 'TestModule.psm1')
      }

      It 'Signs every file with the certificate it was given' {
        $signerThumbprint = @($script:realSignature.SignerCertificate.Thumbprint | Sort-Object -Unique)

        $signerThumbprint | Should -Be @($script:realCertificate.Thumbprint)
      }

      It 'Leaves a signature the platform reads back from the file' {
        $signature = Get-AuthenticodeSignature -FilePath (
          Join-Path -Path $script:realModuleDirectory -ChildPath 'TestModule.psm1'
        )

        $signature.SignerCertificate.Thumbprint | Should -Be $script:realCertificate.Thumbprint
      }
    }
  }

}
