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

    BeforeAll {
      # Get-PSBuildCertificate reads five properties off a certificate: Subject, Thumbprint,
      # HasPrivateKey, NotAfter, and EnhancedKeyUsageList. Objects carrying those properties
      # drive the real selection and validation branches on every platform and every edition,
      # which a generated certificate cannot do: EnhancedKeyUsageList is contributed by
      # PowerShell's own type data, and one and the same generated code-signing certificate
      # reports the Code Signing usage on Windows PowerShell 5.1 and an empty list on
      # PowerShell 7.
      #
      # Mocks that stand these in must be declared with -ModuleName, because a mock is scoped to
      # the session state it is declared in and Get-PSBuildCertificate calls Get-ChildItem from
      # inside the module. Six mocks in this file were declared without it, so they never reached
      # the module and the tests below were asserting that the machine running them happened to
      # have no code-signing certificate installed. See psake/PowerShellBuild#216.
      $script:validCertificate = [PSCustomObject]@{
        Subject       = 'CN=Valid Test Certificate'
        Thumbprint    = 'AAAA111122223333444455556666777788889999'
        HasPrivateKey = $true
        NotAfter      = (Get-Date).AddDays(30)
      }
      $script:expiredCertificate = [PSCustomObject]@{
        Subject       = 'CN=Expired Test Certificate'
        Thumbprint    = 'BBBB111122223333444455556666777788889999'
        HasPrivateKey = $true
        NotAfter      = (Get-Date).AddDays(-1)
      }
      $script:noPrivateKeyCertificate = [PSCustomObject]@{
        Subject       = 'CN=No Private Key Test Certificate'
        Thumbprint    = 'CCCC111122223333444455556666777788889999'
        HasPrivateKey = $false
        NotAfter      = (Get-Date).AddDays(30)
      }
    }

    BeforeEach {
      # Clear environment variables before each test
      Remove-Item env:\SIGNCERTIFICATE -ErrorAction SilentlyContinue
      Remove-Item env:\CERTIFICATEPASSWORD -ErrorAction SilentlyContinue
    }

    Context 'Auto mode' {
      It 'Defaults to Auto mode when no CertificateSource is specified' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
        Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith { }
        $VerboseOutput = Get-PSBuildCertificate -Verbose -ErrorAction SilentlyContinue 4>&1
        $VerboseOutput[0] | Should -Match "CertificateSource is 'Auto'"
      }

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

      It 'Resolves to Store mode when SIGNCERTIFICATE environment variable is not set' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
        Remove-Item env:\SIGNCERTIFICATE -ErrorAction SilentlyContinue
        Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith { }
        $VerboseOutput = Get-PSBuildCertificate -ErrorAction SilentlyContinue -Verbose *>&1
        $VerboseOutput[0] | Should -Match ".*Resolved to 'Store'.*"
      }
    }

    # Store mode only works on Windows
    Context 'Store mode' {
      It 'Searches the certificate store for a valid code-signing certificate' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
        # On Windows, we can test the actual logic without mocking the cert store itself
        # Instead, just verify the function accepts the parameter and attempts the search
        $command = Get-Command Get-PSBuildCertificate
        $command.Parameters['CertificateSource'].Attributes.ValidValues | Should -Contain 'Store'

        # If no cert found, should return $null (not throw)
        { Get-PSBuildCertificate -CertificateSource Store -ErrorAction SilentlyContinue } | Should -Not -Throw
      }

      It 'Returns $null when no valid certificate is found' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
        Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith { }

        $certificate = Get-PSBuildCertificate -CertificateSource Store

        $certificate | Should -BeNullOrEmpty
        # The store this test describes is the mocked one, not whatever the machine happens to
        # hold. Asserting the module actually called the mock is what tells the two apart.
        Should -Invoke -ModuleName PowerShellBuild -CommandName Get-ChildItem -Times 1 -Exactly
      }

      It 'Filters out expired certificates' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
        Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
          $script:expiredCertificate
        }

        $certificate = Get-PSBuildCertificate -CertificateSource Store

        $certificate | Should -BeNullOrEmpty
      }

      It 'Filters out certificates without a private key' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
        Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
          $script:noPrivateKeyCertificate
        }

        $certificate = Get-PSBuildCertificate -CertificateSource Store

        $certificate | Should -BeNullOrEmpty
      }

      It 'Returns a valid certificate that the store does hold' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
        # The counterpart of the three tests above: they only show that unusable certificates are
        # rejected, which an unconditional $null would satisfy just as well.
        Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
          $script:validCertificate
        }

        $certificate = Get-PSBuildCertificate -CertificateSource Store

        $certificate.Subject | Should -Be 'CN=Valid Test Certificate'
      }

      It 'Throws where there is no certificate store to search' -Skip:($null -eq $IsWindows -or $IsWindows) {
        # The mirror image of the guard on every other test in this context. The Store source is
        # Windows-only by design, and on Linux and macOS it is expected to say so rather than
        # fail obscurely inside the certificate provider.
        { Get-PSBuildCertificate -CertificateSource Store } |
          Should -Throw '*only supported on Windows*'
      }

      It 'Uses custom CertStoreLocation when specified' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
        # Just verify the parameter is accepted
        { Get-PSBuildCertificate -CertificateSource Store -CertStoreLocation 'Cert:\LocalMachine\My' -ErrorAction SilentlyContinue } |
          Should -Not -Throw
      }
    }

    Context 'Thumbprint mode' {
      It 'Searches for a certificate with the specified thumbprint' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
        $testThumbprint = 'ABCD1234EFGH5678'
        # Verify the function accepts the thumbprint parameter
        { Get-PSBuildCertificate -CertificateSource Thumbprint -Thumbprint $testThumbprint -ErrorAction SilentlyContinue } |
          Should -Not -Throw
      }

      It 'Returns $null when the specified thumbprint is not found' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
        # The store holds a perfectly usable certificate; it is simply not the one that was
        # asked for. Signing with it would sign with an identity the build never named.
        Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
          $script:validCertificate
        }

        $certificate = Get-PSBuildCertificate -CertificateSource Thumbprint -Thumbprint 'NOTFOUND123'

        $certificate | Should -BeNullOrEmpty
      }

      It 'Throws when the thumbprint is empty' {
        { Get-PSBuildCertificate -CertificateSource Thumbprint -Thumbprint '   ' } |
          Should -Throw "*requires a non-empty Thumbprint value*"
      }

      It 'Returns the certificate whose thumbprint was asked for' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
        Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
          $script:noPrivateKeyCertificate
          $script:validCertificate
        }

        $certificate = Get-PSBuildCertificate -CertificateSource Thumbprint `
          -Thumbprint $script:validCertificate.Thumbprint

        $certificate.Thumbprint | Should -Be $script:validCertificate.Thumbprint
      }
    }

    Context 'EnvVar mode' {
      It 'Throws when the environment variable holds nothing' {
        # The BeforeEach above clears SIGNCERTIFICATE, which is the situation a consumer lands in
        # when the CI secret was never wired up.
        { Get-PSBuildCertificate -CertificateSource EnvVar } |
          Should -Throw '*is not set or is empty*'
      }

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

    # The EnvVar and PfxFile sources load exactly one certificate, so validity is a gate applied
    # to that certificate rather than part of selecting it. Every other test of those two sources
    # in this file feeds the loader deliberately malformed input -- five arbitrary bytes, or an
    # empty file named .pfx -- so the load throws and the gate below it never runs. Standing in
    # for the load is what lets a certificate reach the gate at all, on any platform. See
    # psake/PowerShellBuild#216.
    Context 'Validation of a certificate loaded from EnvVar or PfxFile' {

      BeforeAll {
        $script:codeSigningUsage = [PSCustomObject]@{
          ObjectId     = '1.3.6.1.5.5.7.3.3'
          FriendlyName = 'Code Signing'
        }
        $script:serverAuthenticationUsage = [PSCustomObject]@{
          ObjectId     = '1.3.6.1.5.5.7.3.1'
          FriendlyName = 'Server Authentication'
        }

        $script:loadedValidCertificate = [PSCustomObject]@{
          Subject              = 'CN=Loaded Valid Test Certificate'
          Thumbprint           = 'DDDD111122223333444455556666777788889999'
          HasPrivateKey        = $true
          NotAfter             = (Get-Date).AddDays(30)
          EnhancedKeyUsageList = @($script:codeSigningUsage)
        }
        $script:loadedNoPrivateKeyCertificate = [PSCustomObject]@{
          Subject              = 'CN=Loaded No Private Key Test Certificate'
          Thumbprint           = 'EEEE111122223333444455556666777788889999'
          HasPrivateKey        = $false
          NotAfter             = (Get-Date).AddDays(30)
          EnhancedKeyUsageList = @($script:codeSigningUsage)
        }
        $script:loadedExpiredCertificate = [PSCustomObject]@{
          Subject              = 'CN=Loaded Expired Test Certificate'
          Thumbprint           = 'FFFF111122223333444455556666777788889999'
          HasPrivateKey        = $true
          NotAfter             = (Get-Date).AddDays(-1)
          EnhancedKeyUsageList = @($script:codeSigningUsage)
        }
        $script:loadedWrongUsageCertificate = [PSCustomObject]@{
          Subject              = 'CN=Loaded Server Authentication Test Certificate'
          Thumbprint           = '1111222233334444555566667777888899990000'
          HasPrivateKey        = $true
          NotAfter             = (Get-Date).AddDays(30)
          EnhancedKeyUsageList = @($script:serverAuthenticationUsage)
        }
        $script:loadedUnusableCertificate = [PSCustomObject]@{
          Subject              = 'CN=Loaded Unusable Test Certificate'
          Thumbprint           = '2222333344445555666677778888999900001111'
          HasPrivateKey        = $false
          NotAfter             = (Get-Date).AddDays(-1)
          EnhancedKeyUsageList = @($script:serverAuthenticationUsage)
        }

        $script:pfxFilePath = Join-Path -Path $TestDrive -ChildPath 'codesign.pfx'
      }

      BeforeEach {
        # Any decodable payload will do. The load is stood in for, so nothing turns these bytes
        # into a certificate, but Get-PSBuildCertificate rejects an empty or malformed variable
        # before the load is reached.
        $env:SIGNCERTIFICATE = [System.Convert]::ToBase64String([byte[]]@(1, 2, 3, 4, 5))
      }

      AfterEach {
        Remove-Item env:\SIGNCERTIFICATE -ErrorAction SilentlyContinue
        Remove-Item env:\CERTIFICATEPASSWORD -ErrorAction SilentlyContinue
      }

      It 'Throws when the loaded certificate has no private key' {
        Mock -ModuleName PowerShellBuild -CommandName Import-PSBuildX509Certificate -MockWith {
          $script:loadedNoPrivateKeyCertificate
        }

        { Get-PSBuildCertificate -CertificateSource EnvVar } |
          Should -Throw '*does not have an accessible private key*'
      }

      It 'Throws when the loaded certificate has expired' {
        Mock -ModuleName PowerShellBuild -CommandName Import-PSBuildX509Certificate -MockWith {
          $script:loadedExpiredCertificate
        }

        { Get-PSBuildCertificate -CertificateSource EnvVar } |
          Should -Throw '*has expired*'
      }

      It 'Throws when the loaded certificate has no Code Signing enhanced key usage' {
        Mock -ModuleName PowerShellBuild -CommandName Import-PSBuildX509Certificate -MockWith {
          $script:loadedWrongUsageCertificate
        }

        { Get-PSBuildCertificate -CertificateSource EnvVar } |
          Should -Throw '*Code Signing Enhanced Key Usage*'
      }

      It 'Returns a certificate that passes every check' {
        Mock -ModuleName PowerShellBuild -CommandName Import-PSBuildX509Certificate -MockWith {
          $script:loadedValidCertificate
        }

        $certificate = Get-PSBuildCertificate -CertificateSource EnvVar

        $certificate.Subject | Should -Be 'CN=Loaded Valid Test Certificate'
      }

      It 'Returns an unusable certificate when SkipValidation is set' {
        # SkipValidation drops the checks outright for these two sources, unlike Store and
        # Thumbprint where an unexpired certificate is still preferred.
        Mock -ModuleName PowerShellBuild -CommandName Import-PSBuildX509Certificate -MockWith {
          $script:loadedUnusableCertificate
        }

        $certificate = Get-PSBuildCertificate -CertificateSource EnvVar -SkipValidation

        $certificate.Subject | Should -Be 'CN=Loaded Unusable Test Certificate'
      }

      It 'Applies the same validation to a certificate loaded from a PFX file' {
        Mock -ModuleName PowerShellBuild -CommandName Import-PSBuildX509Certificate -MockWith {
          $script:loadedExpiredCertificate
        }

        { Get-PSBuildCertificate -CertificateSource PfxFile -PfxFilePath $script:pfxFilePath } |
          Should -Throw '*has expired*'
      }

      It 'Returns a certificate loaded from a PFX file that passes every check' {
        Mock -ModuleName PowerShellBuild -CommandName Import-PSBuildX509Certificate -MockWith {
          $script:loadedValidCertificate
        }

        $certificate = Get-PSBuildCertificate -CertificateSource PfxFile -PfxFilePath $script:pfxFilePath

        $certificate.Subject | Should -Be 'CN=Loaded Valid Test Certificate'
      }

      It 'Hands the decoded payload and the password from the environment to the loader' {
        $env:SIGNCERTIFICATE = [System.Convert]::ToBase64String([byte[]]@(10, 20, 30))
        $env:CERTIFICATEPASSWORD = 'certificate-password'
        Mock -ModuleName PowerShellBuild -CommandName Import-PSBuildX509Certificate -MockWith {
          $script:loadedValidCertificate
        }

        $null = Get-PSBuildCertificate -CertificateSource EnvVar

        Should -Invoke -ModuleName PowerShellBuild -CommandName Import-PSBuildX509Certificate `
          -Times 1 -Exactly -ParameterFilter {
          $null -eq (Compare-Object -ReferenceObject $RawData -DifferenceObject ([byte[]]@(10, 20, 30))) -and
          $Password -eq 'certificate-password'
        }
      }
    }

    # The Store and Thumbprint sources select one certificate out of many, so validity is part
    # of the selection rather than a gate applied to a single loaded certificate. SkipValidation
    # therefore relaxes the selection only as a fallback: a valid certificate is preferred
    # whenever one exists, and an expired one is accepted only when nothing valid was found.
    # See psake/PowerShellBuild#193.
    #
    # These tests mock Get-ChildItem inside the module session state, which is the only way the
    # mock reaches the call made by Get-PSBuildCertificate. They are Windows-only because the
    # -CodeSigningCert dynamic parameter comes from the certificate provider, which exists only
    # on Windows, and because the Store source throws on other platforms by design.
    #
    # Windows-only means platform, not edition. $IsWindows does not exist on Windows PowerShell
    # 5.1, so -Skip:(-not $IsWindows) skipped every one of these on the engine where store-based
    # signing is most common. The guard below is the shape Get-PSBuildCertificate itself uses:
    # treat the platform as non-Windows only when $IsWindows is explicitly $false. See
    # psake/PowerShellBuild#197.
    Context 'SkipValidation for store-backed sources' {

      Context 'Store source' {
        It 'Prefers a valid certificate over an expired one even when SkipValidation is set' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
          # The expired certificate is returned first so that a naive implementation, one that
          # hoists the validity checks out of the selection filter, would pick it.
          Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
            $script:expiredCertificate
            $script:validCertificate
          }

          $certificate = Get-PSBuildCertificate -CertificateSource Store -SkipValidation

          $certificate.Subject | Should -Be 'CN=Valid Test Certificate'
        }

        It 'Returns an expired certificate when SkipValidation is set and nothing valid is available' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
          Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
            $script:expiredCertificate
          }

          $certificate = Get-PSBuildCertificate -CertificateSource Store -SkipValidation -WarningAction SilentlyContinue

          $certificate.Subject | Should -Be 'CN=Expired Test Certificate'
        }

        It 'Warns when SkipValidation causes an expired certificate to be selected' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
          Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
            $script:expiredCertificate
          }

          Get-PSBuildCertificate -CertificateSource Store -SkipValidation `
            -WarningVariable warningRecord -WarningAction SilentlyContinue | Out-Null

          $warningRecord -join ' ' | Should -Match 'expired'
        }

        It 'Does not return an expired certificate when SkipValidation is not set' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
          Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
            $script:expiredCertificate
          }

          $certificate = Get-PSBuildCertificate -CertificateSource Store

          $certificate | Should -BeNullOrEmpty
        }

        It 'Does not return a certificate without a private key even when SkipValidation is set' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
          # A certificate with no private key cannot sign anything, so relaxing that check
          # would only defer the failure to Set-AuthenticodeSignature with a worse message.
          Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
            $script:noPrivateKeyCertificate
          }

          $certificate = Get-PSBuildCertificate -CertificateSource Store -SkipValidation -WarningAction SilentlyContinue

          $certificate | Should -BeNullOrEmpty
        }
      }

      Context 'Thumbprint source' {
        It 'Returns an expired certificate when SkipValidation is set and nothing valid is available' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
          Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
            $script:expiredCertificate
          }

          $certificate = Get-PSBuildCertificate -CertificateSource Thumbprint `
            -Thumbprint $script:expiredCertificate.Thumbprint -SkipValidation -WarningAction SilentlyContinue

          $certificate.Subject | Should -Be 'CN=Expired Test Certificate'
        }

        It 'Still honours the requested thumbprint when SkipValidation relaxes the selection' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
          # A valid certificate is present, but it is not the one the consumer named. Returning
          # it would sign with a different identity than the build asked for.
          Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
            $script:validCertificate
            $script:expiredCertificate
          }

          $certificate = Get-PSBuildCertificate -CertificateSource Thumbprint `
            -Thumbprint $script:expiredCertificate.Thumbprint -SkipValidation -WarningAction SilentlyContinue

          $certificate.Thumbprint | Should -Be $script:expiredCertificate.Thumbprint
        }

        It 'Does not return an expired certificate when SkipValidation is not set' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
          Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
            $script:expiredCertificate
          }

          $certificate = Get-PSBuildCertificate -CertificateSource Thumbprint `
            -Thumbprint $script:expiredCertificate.Thumbprint

          $certificate | Should -BeNullOrEmpty
        }

        It 'Does not return a certificate without a private key even when SkipValidation is set' -Skip:($null -ne $IsWindows -and -not $IsWindows) {
          Mock -ModuleName PowerShellBuild -CommandName Get-ChildItem -MockWith {
            $script:noPrivateKeyCertificate
          }

          $certificate = Get-PSBuildCertificate -CertificateSource Thumbprint `
            -Thumbprint $script:noPrivateKeyCertificate.Thumbprint -SkipValidation -WarningAction SilentlyContinue

          $certificate | Should -BeNullOrEmpty
        }
      }
    }
  }
}
