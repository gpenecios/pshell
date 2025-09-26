param(
	[string]$message='No message given',
	[string]$channel,
	[string]$name='No name given',
	[string]$icon='No icon given',
	[Parameter(Mandatory=$true)][string]$webhook
)

Write-Output "-----------------"
Write-Output "PSVersionTable:"
Write-Output $PSVersionTable
Write-Output "channel: $channel"
Write-Output "message: $message"
Write-Output "name: $name"
Write-Output "icon: $icon"
Write-Output "webhook: $webhook"

# Build payload
$payload = @{}
$payload['channel'] = $channel
$payload['text'] = $message

if($name -ne "No name given") {
	$payload['username'] = $name
}

if($icon -ne "No icon given") {
	if($icon.startswith("http")) {
		$payload['icon_url'] = $icon
	}
	else {
		$payload['icon_emoji'] = $icon
	}
}

Write-Output "payload:"
Write-Output "$payload"

$body = ConvertTo-Json -Compress -InputObject $payload
Write-Output "body:"
Write-Output "$body"

# Send REST call
# https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest?view=powershell-5.1
Invoke-WebRequest -Body $body -UseBasicParsing -Method Post -Uri $webhook

Write-Output "-----------------"