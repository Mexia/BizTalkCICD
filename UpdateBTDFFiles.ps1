# Look for a 0.0.0.0 pattern in the build number. 
# If found use it to update BTDF Deployment.btdfproj file.
#
# For example, if the 'Build number format' build process parameter 
# $(BuildDefinitionName)_$(Year:yyyy).$(Month).$(DayOfMonth)$(Rev:.r)

# Enable -Verbose option
[CmdletBinding()]


# Regular expression pattern to find the version in the build number 
# and then apply it to the assemblies
$VersionRegex = "\d+\.\d+\.\d+\.\d+"
$VersionProductVersionRegex = "<ProductVersion>[\s\S]*?<\/ProductVersion>"
$VersionProductIdRegex = "<ProductId>[\s\S]*?<\/ProductId>"

Write-Verbose "Entering script UpdateBTDFFiles.ps1" -Verbose

# If this script is not running on a build server, remind user to 
# set environment variables so that this script can be debugged
if(-not ($Env:BUILD_SOURCESDIRECTORY -and $Env:BUILD_BUILDNUMBER))
{
    Write-Error "You must set the following environment variables"
    Write-Error "to test this script interactively."
    Write-Host '$Env:BUILD_SOURCESDIRECTORY - For example, enter something like:'
    Write-Host '$Env:BUILD_SOURCESDIRECTORY = "C:\code\FabrikamTFVC\HelloWorld"'
    Write-Host '$Env:BUILD_BUILDNUMBER - For example, enter something like:'
    Write-Host '$Env:BUILD_BUILDNUMBER = "Build HelloWorld_0000.00.00.0"'
    exit 1
}

# Make sure path to source code directory is available
if (-not $Env:BUILD_SOURCESDIRECTORY)
{
    Write-Error ("BUILD_SOURCESDIRECTORY environment variable is missing.")
    exit 1
}
elseif (-not (Test-Path $Env:BUILD_SOURCESDIRECTORY))
{
    Write-Error "BUILD_SOURCESDIRECTORY does not exist: $Env:BUILD_SOURCESDIRECTORY"
    exit 1
}
Write-Verbose "BUILD_SOURCESDIRECTORY: $Env:BUILD_SOURCESDIRECTORY" -Verbose

# Make sure there is a build number
if (-not $Env:BUILD_BUILDNUMBER)
{
    Write-Error ("BUILD_BUILDNUMBER environment variable is missing.")
    exit 1
}
Write-Verbose "BUILD_BUILDNUMBER: $Env:BUILD_BUILDNUMBER" -Verbose

# Get and validate the version data
$VersionData = [regex]::matches($Env:BUILD_BUILDNUMBER,$VersionRegex)
switch($VersionData.Count)
{
   0        
      { 
         Write-Error "Could not find version number data in BUILD_BUILDNUMBER."
         exit 1
      }
   1 {}
   default 
      { 
         Write-Warning "Found more than instance of version data in BUILD_BUILDNUMBER." 
         Write-Warning "Will assume first instance is version."
      }
}
$VersionData0 = $VersionData[0]
$NewProductIdGuid = [guid]::NewGuid()
$NewProductVersion = "<ProductVersion>$VersionData0</ProductVersion>"
$NewProductId = "<ProductId>$NewProductIdGuid</ProductId>"
Write-Verbose "ProductVersion = $NewProductVersion" -Verbose
Write-Verbose "ProductId = $NewProductId" -Verbose

# Apply the ProductVersion to the BTDF Project File
$files = gci $Env:BUILD_SOURCESDIRECTORY -recurse -include "Deployment" | 
    ?{ $_.PSIsContainer } | 
    foreach { gci -Path $_.FullName -Recurse -include *.btdfproj }
if($files)
{
    Write-Verbose "Will apply $NewProductVersion to $($files.count) files."

    foreach ($file in $files) {
        #$filecontent = Get-Content($file)
        attrib $file -r
        #$filecontent -replace $VersionProductVersionRegex, $NewProductVersion | Out-File $file -Encoding utf8
        #$filecontent -replace $VersionProductIdRegex, $NewProductId | Out-File $file 

        (Get-Content $file) | ForEach-Object {$_ -replace $VersionProductVersionRegex, $NewProductVersion} | ForEach-Object {$_ -replace $VersionProductIdRegex, $NewProductId} | Out-File $file -Encoding utf8 

        Write-Verbose "$file - version and Id applied" -Verbose
    }
}
else
{
    Write-Warning "Found no files."
}
