param(
	[Parameter(Mandatory = $true, Position = 0)] [string] $RepositoryRoot,
	[Parameter(Mandatory = $true, Position = 1)] [string] $Environment,
	[Parameter(Mandatory = $false)] [switch] $Headless
)

# These modules are required by this script so we import them here. They will be unloaded and reloaded when calling "Initialize-Shell"
Import-Module "$PSScriptRoot\modules\Environment.psm1"
Import-Module "$PSScriptRoot\modules\Configuration.psm1"
Import-Module "$PSScriptRoot\modules\Isolation.psm1"
Import-Module "$PSScriptRoot\modules\TemplateEngine.psm1"
Import-Module "$PSScriptRoot\modules\PackageManager.psm1"

# Globals
$global:System = @{
	RootDirectory   = $RepositoryRoot
	IsHeadlessShell = $Headless
	Version         = (New-XmlPropertyContainer "$PSScriptRoot\system.props").getProperty("Version")
	Environment     = @{}
	Modules         = $null
}

$global:Environment = $Environment

# Definitions
class ModuleContainer {

	hidden [System.Collections.Generic.HashSet[System.String]] $_Modules
	
	ModuleContainer() {
		$this._Modules = New-Object System.Collections.Generic.HashSet[System.String]
	}

	[bool] load($Name) {
	
		if ([string]::IsNullOrWhiteSpace($Name)) {
			return $false
		}
		
		$fullPath = Join-Path $PSScriptRoot "modules\$Name.psm1"
		Write-Host -NoNewLine "Loading module ""$Name""..."
		
		try {
			$ErrorActionPreference = "Stop"
		
			if (-not (Test-Path -PathType Leaf -Path $fullPath)) {
				throw "The module is not installed."
			}
			
			Import-Module "$fullPath"
		} 
		catch {
			Write-Host -ForegroundColor Red "FAILED: $($_.Exception.Message)"
			return $false
		}
		
		Write-Host -ForegroundColor Green "OK"
		$null = $this._Modules.Add($Name.ToLower())
		
		return $true
	}
	[bool] isLoaded($Name) {
		if ([string]::IsNullOrWhiteSpace($Name)) {
			return $false
		}
	
		return $this._Modules.Contains($Name.ToLower())
	}
}

function Initialize-Shell { 
	Remove-Variable * -ErrorAction SilentlyContinue
	Remove-Module *

	$error.Clear()

	$PreviousErrorActionPreference = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	write-host ""
	
	$classes = Get-ChildItem -filter "*.psm1" -path "$PSScriptRoot\modules"
	$success = $true
	
	$global:System.Modules = New-Object ModuleContainer

	Write-Host -NoNewLine "Loading external dependencies..."
	Push-Location $PSScriptRoot

	$paketExecutable = "$PSScriptRoot\.paket\paket.exe"
	$paketOutput = & $paketExecutable install -s 2>&1
	$paketErrors = @($paketOutput | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | Foreach-Object { $_.Exception.Message })

	Pop-Location

	if ($LASTEXITCODE -ne 0) {
		if ($paketErrors.Length -eq 0) {
			$paketErrors = @("Paket failed with exit code $LASTEXITCODE.")
		}

		$paketErrors = @($paketOutput | Foreach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ } }) 
		$compositePaketError = $paketErrors -join [Environment]::NewLine
		
		Write-Host -ForegroundColor Red "FAILED: $compositePaketError"
		$success = $false
	}

	$ErrorActionPreference = "Stop"
	
	if (-$success){
		Write-Host -ForegroundColor Green "OK"

		foreach($class in $classes) 
		{
			$success = $success -and ($global:System.Modules.load($class.BaseName))
		}
	}
	
	Write-Host ""

	$ErrorActionPreference = $PreviousErrorActionPreference
	$PreviousErrorActionPreference = $null
	
	if ($null -ne (Get-Command "Set-Environment" -ErrorAction SilentlyContinue)) {
		Set-Environment -TargetEnvironment $Environment | Out-Null
	}
} 

# Shell prompt
function prompt {
    $pl = (([IO.DirectoryInfo](Get-Location).Path).FullName).TrimEnd("\")
    $pb = (([IO.DirectoryInfo]$global:System.RootDirectory).FullName).TrimEnd("\")
    
    if ($pl.StartsWith($pb)) {
        $pl = $pl.Substring($pb.Length).TrimStart("\")
    }

    Write-Host ("$pl `$".Trim()) -nonewline -foregroundcolor White
    return " "
}

# Logic when executing initially
if (-not $global:System.IsHeadlessShell) {
	Set-Environment -TargetEnvironment $Environment | Out-Null
	
	$displayTitle = $global:Repository.EffectiveConfiguration.getProperty("Title")
        
	if ([string]::IsNullOrWhiteSpace($displayTitle)) {
		$displayTitle = "$(([IO.DirectoryInfo] $global:System.RootDirectory).Name)"
	}

	write-host -ForegroundColor cyan -NoNewline $displayTitle
	write-host -ForegroundColor white " Developer Shell"
	write-host -ForegroundColor white "Version $($global:System.Version)"
	
	$licenseFiles = @(
		'LICENSE',
		'LICENSE.txt'
	)
	
	foreach($licenseFile in $licenseFiles) {
		$licenseFullPath = Join-Path $PSScriptRoot "..\..\$licenseFile"
		if (Test-Path -PathType Leaf $licenseFullPath) {
			$licenseText = (Get-Content -Raw $licenseFullPath | Expand-Template).Trim(@("`r","`n"))
			write-host -ForegroundColor Gray "`n$licenseText"
		}
	}
}

Set-Alias -Name reboot -Value Initialize-Shell
Initialize-Shell