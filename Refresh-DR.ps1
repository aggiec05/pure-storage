Import-Module PureStoragePowerShellSDK

$TargetVM = 'MyVirtualMachineName'

$TargetVMSession = New-PSSession -ComputerName $TargetVM

Import-Module SQLPS -PSSession $TargetVMSession -DisableNameChecking

# Offline the database
Write-Host "Offlining the DR database..." -ForegroundColor Red
Invoke-Command -Session $TargetVMSession -ScriptBlock { Invoke-Sqlcmd -ServerInstance . -Database master -Query "ALTER DATABASE My_DR_Database SET OFFLINE WITH ROLLBACK IMMEDIATE" }

# Offline the volume
Write-Host "Offlining the DR volume..." -ForegroundColor Red
Invoke-Command -Session $TargetVMSession -ScriptBlock { Get-Disk | ? { $_.SerialNumber -eq '423F93C2ECF544580001103B' } | Set-Disk -IsOffline $True }

# Connect to the FlashArray's REST API, get a session going
# THIS IS A SAMPLE SCRIPT WE USE FOR DEMOS! _PLEASE_ do not save your password in cleartext here. 
# Use NTFS secured, encrypted files or whatever else -- never cleartext!
Write-Host "Establishing a session against the Pure Storage FlashArray..." -ForegroundColor Red
$FlashArray = New-PfaArray �EndPoint 10.128.0.2 -UserName MyUsername -Password (ConvertTo-SecureString -AsPlainText "MyPassword" -Force) -IgnoreCertificateError

Write-Host "Obtaining the most recent snapshot for the protection group..." -ForegroundColor Red
$MostRecentSnapshot = Get-PfaProtectionGroupSnapshots -Array $FlashArray -Name 'pure-production-array:ProtectionGroup1' | Sort-Object created -Descending | Select -Property name -First 1

# Perform the DR volume overwrite
Write-Host "Overwriting the DR database volume with a copy of the most recent snapshot..." -ForegroundColor Red
New-PfaVolume -Array $FlashArray -VolumeName MyVirtualMachineName-data-volume -Source ($MostRecentSnapshot.name + '.MyProduction-data-volume') -Overwrite

# Online the volume
Write-Host "Onlining the volume..." -ForegroundColor Red
Invoke-Command -Session $TargetVMSession -ScriptBlock { Get-Disk | ? { $_.SerialNumber -eq '423F93C2ECF544580001103B' } | Set-Disk -IsOffline $False }

# Online the database
Write-Host "Onlining the database..." -ForegroundColor Red
Invoke-Command -Session $TargetVMSession -ScriptBlock { Invoke-Sqlcmd -ServerInstance . -Database master -Query "ALTER DATABASE My_DR_Database SET ONLINE WITH ROLLBACK IMMEDIATE" }

Write-Host "DR failover ended." -ForegroundColor Red

# Clean up
Remove-PSSession $TargetVMSession
Write-Host "All done." -ForegroundColor Red