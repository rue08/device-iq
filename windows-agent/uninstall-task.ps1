Unregister-ScheduledTask -TaskName "DeviceIQAgent" -Confirm:$false
Write-Host "Uninstalled. The running tray icon (if any) won't stop until you Exit it or log off."
