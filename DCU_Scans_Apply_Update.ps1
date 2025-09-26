$dcuPath = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
if (!(Test-Path $dcuPath)) {
    $dcuPath = "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe"
}
if (Test-Path $dcuPath) {
    & $dcuPath /scan -updateType="driver,application" -outputlog=C:\DCU_LOGS\ScanUpdates.log -silent
    & $dcuPath /applyUpdates -outputlog=C:\DCU_LOGS\ApplyUpdates.log -reboot=disable -silent
} else {
    Write-Output "dcu-cli.exe not found"
}
