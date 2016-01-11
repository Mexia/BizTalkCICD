$ErrorActionPreference = "Stop"

function Wrap-Arguments($Arguments)
{
	return $Arguments | % { 
		
		[string]$val = $_
		
		#calling msiexec fails when arguments are quoted
		if (($val.StartsWith("/") -and $val.IndexOf(" ") -eq -1) -or ($val.IndexOf("=") -ne -1) -or ($val.IndexOf('"') -ne -1)) {
			return $val
		}
	
		return '"{0}"' -f $val
	}
}

function Start-Process2($FilePath, $ArgumentList, [switch]$showCall)
{
	$ArgumentListString = (Wrap-Arguments $ArgumentList) -Join " "

	$pinfo = New-Object System.Diagnostics.ProcessStartInfo
	$pinfo.FileName = $FilePath
	$pinfo.UseShellExecute = $false
	$pinfo.CreateNoWindow = $true
	$pinfo.RedirectStandardOutput = $true
	$pinfo.RedirectStandardError = $true
	$pinfo.Arguments = $ArgumentListString;
	$pinfo.WorkingDirectory = $pwd

	$exitCode = 0
	
    if ($showCall) {
	  	$x = Write-Output "$FilePath $ArgumentListString"
	}
	
	$p = New-Object System.Diagnostics.Process
	$p.StartInfo = $pinfo
	$started = $p.Start()
	$p.WaitForExit()

	$stdout = $p.StandardOutput.ReadToEnd()
	$stderr = $p.StandardError.ReadToEnd()
	$x = Write-Output $stdout
	$x = Write-Output $stderr
		
	$exitCode = $p.ExitCode
	
	return $exitCode
}

& {
    Write-Output "Installing MSI"
    
    Write-Host " Current Directory: $(get-location)" -f Gray
    Write-Host " Full Script Path: $PSScriptRoot" -f Gray

    $files = get-childitem "$PSScriptRoot\*.msi"
    Write-Host " files: $files" -f Gray
    foreach ($file in $files)
    {
        $MsiFilePath = $file.FullName
    }
    Write-Host " MsiFilePath: $MsiFilePath" -f Gray
    
	Write-Host " Action: $Action" -f Gray
	Write-Host

	if ((Get-Command msiexec) -Eq $Null) {
		throw "Command msiexec could not be found"
	}
	
	if (!(Test-Path $MsiFilePath)) {
		throw "Could not find the file $MsiFilePath"
	}

    $actionOption = "/i"
	$actionOptionFile = Resolve-Path $MsiFilePath
	
	$logOption = "/L*"
    $logOptionFile = "$MsiFilePath.log"
	
	$quiteOption = "/qn"
	$noRestartOption = "/norestart"

	$options = @($actionOption, $actionOptionFile, $logOption, $logOptionFile, $quiteOption, $noRestartOption) 

	$exePath = "msiexec.exe"

	$exitCode = Start-Process2 -FilePath $exePath -ArgumentList $options -ShowCall
	
	Write-Output "Exit Code was! $exitCode"
	
	if (Test-Path $logOptionFile) {
		Write-Output "Reading installer log"
	    $logfile = Get-Content $logOptionFile
        Write-Output $logfile
        foreach($line in $logfile) {
            if ($line.StartsWith("Property(S): INSTALLDIR")) {
                $INSTALLDIR = $line.Split("=")[1].Trim()
            }
            if ($line.StartsWith("Property(S): MSBUILDPATH")) {
                $MSBUILDPATH = $line.Split("=")[1].Trim()
            }
        }
	} else {
		Write-Output "No logs were generated"
	}

	if ($exitCode -Ne 0) {
	
		$errorCodeString = $exitCode.ToString()
		$errorMessage = $errorCodeString

		throw "Error code $exitCode was returned: $errorMessage" 
	}

    $DeployToDatabase = "True"
    $InstallDirectory = $INSTALLDIR
    $SkipUndeploy= "False"
    $LogFileName = "$InstallDirectory\" + "logfile01"
    $MSBuildPath = $MSBUILDPATH
    $PackagePath = $PSScriptRoot
    $BTDFSettingsFile = "$PackagePath\" + "Exported_RMSettings.xml"

    $hashConfig = $null
    $hashConfig = @{}

    [xml]$configFile = Get-Content "$BTDFSettingsFile"

    $errorActionPreference = 'Stop'

    foreach( $property in $configFile.settings.property) 
    {
        write-host "property.InnerText : " + "$property.InnerText"
        $Inner = $property.InnerText
		#write-host "Inner : $Inner"
        $Inner = $Inner -replace "#{", ""
		#write-host "Inner : $Inner"
        $Inner = $Inner -replace "}", ""
		#write-host "Inner : $Inner"
		#found issue with . in names
		$Inner = $Inner -replace "\.", "_"
        write-host "Inner : $Inner"

        try
        {
            $hashConfig.Add($property.InnerText, (get-item env:$Inner).Value)
        }
        catch
        {
            Write-host "$Inner not found"
            throw
        }
    }

    $hashConfig 

    Rename-Item "$BTDFSettingsFile" "$BTDFSettingsFile.old"

    Get-Content -Path "$BTDFSettingsFile.old" | ForEach-Object { 
        $line = $_

        $hashConfig.GetEnumerator() | ForEach-Object {
            if ($line -match $_.Key)
            {
                $line = $line -replace $_.Key, $_.Value
            }
        }
       $line
    } | Set-Content -Path $BTDFSettingsFile

    Write-Host "DeployToDatabase = $DeployToDatabase" 
    Write-Host "InstallDirectory = $InstallDirectory" 
    Write-Host "SkipUndeploy = $SkipUndeploy" 
    Write-Host "LogFileName = $LogFileName" 
    Write-Host "MSBuildPath = $MSBuildPath" 
    Write-Host "PackagePath = $PackagePath" 
    Write-Host "BTDFSettingsFile = $BTDFSettingsFile" 

    &$MSBuildPath "/p:DeployBizTalkMgmtDB=$DeployToDatabase;Configuration=Server;SkipUndeploy=$SkipUndeploy" /target:Deploy "/l:FileLogger,Microsoft.Build.Engine;logfile=$LogFileName" "$InstallDirectory\Deployment\Deployment.btdfproj" "/p:ENV_SETTINGS=$BTDFSettingsFile"

} 
