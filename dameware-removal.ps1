#Set Logfile
$logfile = "$env:systemdrive\Temp\DW-remove.log"

#Set Service List
$ServiceList = "DWMRCS",
"DNTUS26"

#Set Registry Path
$RegPathList = @(
    "HKLM:\Software\DameWare Development"
    "HKLM:\Software\WOW6432Node\DameWare Development Common Data"
    "HKLM:\Software\WOW6432Node\SolarWinds"
)
#MSI Code List
$MSICodeList = @()
$MSIPaths = @(
    "HKLM:\software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)


#List of Files to search for
$FindFileList =
"DWRCS.EXE", #Dameware remote control service
"DNTUS26.EXE" #Dameware utility service

#Parent folder to delete if it exists.
$FindFolder = "DWRCS" #Known location of Dameware files; also known to reside in the system32 folder but we don't want to delete system32

#Possible registered DLLs
$registeredDLLs = @(
"$env:windir\DWRCS\DWRCSh.dll",
"$env:windir\DWRCS\DWRCSE.dll",
"$env:windir\DWRCS\DWRCSET.dll",
"$env:windir\DWRCS\DWRCSI.dll",
"$env:windir\DWRCS\DWRCRSS.dll",
"$env:windir\DWRCS\DWRCK.dll",
"$env:windir\DWRCS\DWRCWXL.dll"
)

#Define Functions
Function GetTimeDate {
    $Month = Get-Date -Format MM
    $Day = Get-Date -Format dd
    $Year = Get-Date -Format yyyy
    $Hour = Get-Date -Format hh
    $Minute = Get-Date -Format mm
    $Seconds = Get-Date -Format ss
    $SecondsF = Get-Date -Format fff
    $TimeDate = ($Day + "-" + $Month + "-" + $Year + "_" + $Hour + ":" + $Minute + ":" + $Seconds + "." + $SecondsF)
    Return $TimeDate
}

Function OutLog {
    ((GetTimeDate) + " " + $LogBuffer) | Out-File -FilePath $logfile -Append
    switch -Wildcard ($LogBuffer) {
        "Error*" { Write-Host ((GetTimeDate) + " " + $LogBuffer) -ForegroundColor Red }
        "Warning*" { Write-Host ((GetTimeDate) + " " + $LogBuffer) -ForegroundColor Yellow }
        Default { Write-Host ((GetTimeDate) + " " + $LogBuffer) }
    }

}

Function filedelete ($fileLocation) {
    if (Test-Path $fileLocation) {
        try {
            $LogBuffer = $fileLocation + " was found."
            outlog
            $LogBuffer = "Deleting " + $fileLocation + "."
            outlog
            Remove-Item $fileLocation -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
            if (Test-Path $fileLocation) {
                $LogBuffer = "Error: " + $fileLocation + " was not deleted."
                outlog
             } else {
                $LogBuffer = $fileLocation + " was successfully deleted."
                outlog
             }
         } catch {
            $LogBuffer = "File delete error: $_"
            outlog
         }
     } else {
        $LogBuffer = "Warning: " + $fileLocation + " was not found."
        outlog
     }
}

function FolderDelete ($folder) {
    if ($folder -match $FindFolder) {
        try {
            Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop

            if (-not (Test-Path $folder)) {
                $LogBuffer = "$folder was successfully deleted."
            } else {
                $LogBuffer = "Error: $folder was not successfully deleted."
            }

            outlog
        }
        catch {
            $LogBuffer = "Folder delete error: $_"
            outlog
        }
    }
}

Function FindFile {
    foreach ($fileName in $FindFileList) {
        $LogBuffer = "Searching for $fileName."
        outlog

        $files = Get-ChildItem -Path $env:systemroot -Filter $fileName -Recurse -ErrorAction SilentlyContinue

        if (-not $files) {
            $LogBuffer = "Warning: $fileName was not found."
            outlog
        }
        else {
            foreach ($file in $files) {
                $folder = $file.DirectoryName
                $fileLocation = $file.FullName

                $LogBuffer = "Found $fileName in $folder"
                outlog

                filedelete $fileLocation
                folderdelete $folder
            }
        }
    }
}


Function MSIx {
    foreach ($MSIPath in $MSIPaths) {
        Get-ItemProperty $MSIPath | Where-Object {$_.displayname -like "dameware*"} | ForEach-Object { $MSICodeList += $_.PSChildName }
    }
    foreach ($MSICode in $MSICodeList) {
        try {
            $LogBuffer = "Executing MSI uninstall: msiexec.exe /X $MSICode /QN /NORESTART"
            outlog

            $process = Start-Process -FilePath "msiexec.exe" `
                -ArgumentList "/X $MSICode /QN /NORESTART" `
                -Wait -PassThru

            $Exit = $process.ExitCode

            switch ($Exit) {
                0 {
                    $LogBuffer = "SUCCESS: MSI uninstall completed (Code: $Exit)."
                    outlog
                    MSISuccessHandler
                }
                3010 {
                    $LogBuffer = "SUCCESS: MSI uninstall completed, reboot required (Code: $Exit)."
                    outlog
                }
                1603 {
                    $LogBuffer = "ERROR: Fatal error during uninstall (Code: $Exit)."
                    outlog
                }
                1605 {
                    $LogBuffer = "WARNING: Application not installed (Code: $Exit)."
                    outlog
                }
                1614 {
                    $LogBuffer = "INFO: Product already uninstalled (Code: $Exit)."
                    outlog
                }
                1619 {
                    $LogBuffer = "ERROR: MSI package could not be opened (Code: $Exit)."
                    outlog
                }
                default {
                    $LogBuffer = "ERROR: Unknown MSI result code: $Exit"
                    outlog
                }
            }
        }
        catch {
            $LogBuffer = "MSI uninstall exception: $_"
            outlog
        }
    }
}

Function DeleteService {
    foreach ($ServiceName in $Servicelist) {

        $ServName = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

        if ($ServName) {
            try {
                $LogBuffer = "Service found: '$($ServName.DisplayName)'"
                outlog

                if ($ServName.Status -ne 'Stopped') {
                    $LogBuffer = "Stopping service: '$($ServName.DisplayName)'"
                    outlog

                    Stop-Service -Name $ServName.Name -Force -ErrorAction Stop
                    $ServName.WaitForStatus('Stopped', '00:00:30')
                }

                $LogBuffer = "Service is now stopped."
                outlog

                $LogBuffer = "Deleting service: '$($ServName.DisplayName)'"
                outlog

                $serviceCim = Get-CimInstance Win32_Service -Filter "Name='$($ServName.Name)'"

                if ($serviceCim) {
                    $null = Invoke-CimMethod -InputObject $serviceCim -MethodName Delete
                }

                $deleted = $false
                for ($i = 0; $i -lt 10; $i++) {
                    if (-not (Get-Service -Name $ServName.Name -ErrorAction SilentlyContinue)) {
                        $deleted = $true
                        break
                    }
                    Start-Sleep -Seconds 2
                }

                if ($deleted) {
                    $LogBuffer = "SUCCESS: Service '$($ServName.DisplayName)' deleted."
                } else {
                    $LogBuffer = "ERROR: Service '$($ServName.DisplayName)' still exists after deletion attempt."
                }

                outlog
            }
            catch {
                $LogBuffer = "Delete service error: $_"
                outlog
            }
        }
        else {
            $LogBuffer = "WARNING: Service '$ServiceName' not found."
            outlog
        }
    }
}


Function RegClean {
    foreach ($RegPath in $RegPathList) {

        if (Test-Path -Path $RegPath) {
            try {
                $LogBuffer = "$RegPath was found in the registry."
                outlog

                $LogBuffer = "Deleting $RegPath."
                outlog

                Remove-Item -Path $RegPath -Recurse -Force -ErrorAction Stop

                if (-not (Test-Path -Path $RegPath)) {
                    $LogBuffer = "SUCCESS: $RegPath was removed from the registry."
                } else {
                    $LogBuffer = "ERROR: $RegPath still exists after deletion attempt."
                }

                outlog
            }
            catch {
                $LogBuffer = "Registry clean error: $_"
                outlog
            }
        }
        else {
            $LogBuffer = "WARNING: $RegPath not found in the registry."
            outlog
        }
    }
}


Function StartLog {
    $LogBuffer = "----====Logging started====----"
    outlog
}
Function StopLog {
 
    $LogBuffer = "----====Logging stopped====----"
    outlog
}
Function MSISuccessHandler {
    if ($Exit -eq "0")
    {
        $LogBuffer = "Notice: MSI uninstall was successful."
        outlog
    }
}

Function RegSvr {
    foreach ($dll in $registeredDLLs) {

        if (-not (Test-Path $dll)) {
            $LogBuffer = "WARNING: DLL not found: $dll"
            outlog
            continue
        }

        try {
            $LogBuffer = "Unregistering DLL: $dll"
            outlog

            $process = Start-Process -FilePath "regsvr32.exe" `
                -ArgumentList "/u /s `"$dll`"" `
                -Wait -PassThru

            $exitCode = $process.ExitCode

            if ($exitCode -eq 0) {
                $LogBuffer = "SUCCESS: DLL unregistered: $dll"
            } else {
                $LogBuffer = "ERROR: Failed to unregister DLL ($dll). Exit code: $exitCode"
            }

            outlog
        }
        catch {
            $LogBuffer = "RegSvr unregister error: $_"
            outlog
        }
    }
}


StartLog
MSIx
DeleteService
RegSvr
FindFile
RegClean
StopLog
