# Get local directory paths
#$tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment
#$scriptDir = $tsenv.Value('EngrIT_ScriptsGoHere')
$scriptDir = "C:\engrit\scripts"
$logDir = "c:\engrit\logs"
#$logDir = $tsenv.Value('EngrIT_LogsGoHere')

# Logging
$log = "$logDir\download-scripts-from-pshell-repo.log"
function log($msg) {
	$timestamp = Get-Date -UFormat "%Y-%m-%d %H:%M:%S"
	"[$timestamp] $msg" | Out-File $log -Append
}
log "Downloading scripts from repo..."

# Define target folder
$targetFolder = "pshell"
$targetFolderPath = "$scriptDir\$targetFolder"

# Check if pshell folder exists
if (Test-Path -Path $targetFolderPath) {
    Write-Host "Removing existing '$targetFolder' folder..."
    Remove-Item -Path $targetFolderPath -Recurse -Force
}

# Full master branch zip file
# $repo = $tsenv.Value('EngrIT_TSRepo')
$repo = "https://github.com/gpenecios/pshell"
# https://github.com/gpenecios/pshell/archive/refs/heads/main.zip
$zipURL = "$repo/archive/refs/heads/main.zip"
log "Zip URL: $zipURL"
$zipFilename = $zipURL.Substring($zipURL.LastIndexOf("/") + 1)
$zipDirname = $zipFilename -Replace ".zip",""

#$zipDirname = "pshell"
$zipDir = "$scriptDir\pshell-$zipDirname"
log "Zip filename: $zipFilename"


# Download zip and save to x:\engrit\scripts
$zipPath = "$scriptDir\$zipFilename"
log "Zip destination: $zipPath"

log "Downloading..."
Invoke-WebRequest -Uri $zipURL -OutFile $zipPath | Out-File $log -append
log "    Done."

# Extract zip
log "Extracting..."
Expand-Archive -Path $zipPath -DestinationPath $scriptDir | Out-File $log -append
log "    Done."

# Move scripts out of archive subdirectory into root x:\engrit\scripts directory
log "Moving scripts up a directory, out of the archive-named directory..."
Rename-Item -Path "$zipDir" -NewName "$scriptDir\pshell" 
#Move-Item -Path "$zipDir\*" -Destination $scriptDir\pshell\.
Remove-Item -Path $zipPath
log "    Done."

log "EOF"
