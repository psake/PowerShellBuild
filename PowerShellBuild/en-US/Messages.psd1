ConvertFrom-StringData @'
NoCommandsExported=No commands have been exported. Skipping markdown generation.
FailedToGenerateMarkdownHelp=Failed to generate markdown help. : {0}
AddingFileToPsm1=Adding [{0}] to PSM1
MakeCabNotAvailable=MakeCab.exe is not available. Cannot create help cab.
DirectoryAlreadyExists=Directory already exists [{0}].
PathLongerThan3Chars=Path [{0}] must be longer than 3 characters.
BuildSystemDetails=Build System Details:
BuildModule=Build Module:       {0}:{1}
PowerShellVersion=PowerShell Version: {0}
EnvironmentVariables={0}Environment variables:
PublishingVersionToRepository=Publishing version [{0}] to repository [{1}]...
FolderDoesNotExist=Folder does not exist: {0}
PathArgumentMustBeAFolder=The Path argument must be a folder. File paths are not allowed.
UnableToFindModuleManifest=Unable to find module manifest [{0}]. Can't import module
PesterTestsFailed=One or more Pester tests failed
CodeCoverage=Code Coverage
Type=Type
CodeCoverageLessThanThreshold=Code coverage: [{0}] is [{1:p}], which is less than the threshold of [{2:p}]
CodeCoverageCodeCoverageFileNotFound=Code coverage file [{0}] not found.
SeverityThresholdSetTo=SeverityThreshold set to: {0}
PSScriptAnalyzerResults=PSScriptAnalyzer results:
ScriptAnalyzerErrors=One or more ScriptAnalyzer errors were found!
ScriptAnalyzerWarnings=One or more ScriptAnalyzer warnings were found!
ScriptAnalyzerIssues=One or more ScriptAnalyzer issues were found!
NoCertificateFound=No valid code signing certificate was found. Verify the configured CertificateSource and that a certificate with a private key is available.
CertificateResolvedFromStore=Resolved code signing certificate from store [{0}]: Subject=[{1}]
CertificateResolvedFromThumbprint=Resolved code signing certificate by thumbprint [{0}]: Subject=[{1}]
CertificateResolvedFromEnvVar=Resolved code signing certificate from environment variable [{0}]
CertificateResolvedFromPfxFile=Resolved code signing certificate from PFX file [{0}]
SigningModuleFiles=Signing [{0}] file(s) matching [{1}] in [{2}]...
CreatingFileCatalog=Creating file catalog [{0}] (version {1})...
FileCatalogCreated=File catalog created: [{0}]
CertificateSourceAutoResolved=CertificateSource is 'Auto'. Resolved to '{0}'.
CertificateMissingPrivateKey=The resolved certificate does not have an accessible private key. Code signing requires a certificate with a private key. Subject=[{0}]
CertificateExpired=The resolved certificate has expired (NotAfter: {0}). Code signing requires a valid, unexpired certificate. Subject=[{1}]
CertificateMissingCodeSigningEku=The resolved certificate does not have the Code Signing Enhanced Key Usage (EKU: 1.3.6.1.5.5.7.3.3). Subject=[{0}]
'@
