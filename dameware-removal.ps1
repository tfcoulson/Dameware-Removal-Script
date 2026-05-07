#Set Logfile
$logfile = "$env:systemdrive\Temp\DW-remove.log"

#Set Service List
$ServiceList = "DWMRCS",
"DNTUS26"

#Set Registry Path
$RegPathList = "HKLM:\Software\DameWare Development"

#MSI Code List
$MSICodeList =
"{385FED21-85D3-401E-8B8A-38140333FAC8}", #x64 installer
"{9F660272-3D31-47CE-BEB6-7A065B8901A5}" #x32 installer

#List of Files to search for
$FindFileList =
"DWRCS.EXE", #Dameware remote control service
"DNTUS26.EXE" #Dameware utility service

#Parent folder to delete if it exists.
$FindFolder = "DWRCS" #Known location of Dameware files; also known to reside in the system32 folder but we don't want to delete system32

#Possible registered DLLs
$registeredDLLs =
"$env:windir\DWRCS\DWRCSh.dll",
"$env:windir\DWRCS\DWRCSE.dll",
"$env:windir\DWRCS\DWRCSET.dll",
"$env:windir\DWRCS\DWRCSI.dll",
"$env:windir\DWRCS\DWRCRSS.dll",
"$env:windir\DWRCS\DWRCK.dll",
"$env:windir\DWRCS\DWRCWXL.dll"


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
    ((GetTimeDate) + " " + $LogBuffer) | out-file -FilePath $logfile -Append
    switch -Wildcard ($LogBuffer) {
        "Error*" { write-host ((GetTimeDate) + " " + $LogBuffer) -ForegroundColor Red }
        "Warning*" { write-host ((GetTimeDate) + " " + $LogBuffer) -ForegroundColor Yellow }
        Default { write-host ((GetTimeDate) + " " + $LogBuffer) }
    }

}

Function filedelete ($fileLocation) {
        if (Test-Path $fileLocation) {
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
        } else {
            $LogBuffer = "Warning: " + $fileLocation + " was not found."
            outlog
        }
}

Function FolderDelete ($folder) {
    if ($folder -match $FindFolder) {
        if (remove-item $folder -recurse -force -ErrorAction SilentlyContinue) {
            $LogBuffer = $folder + " was successfully deleted."
            outlog
        } else {
            $LogBuffer = "Error: " + $folder + " was not successfully deleted."
            outlog
        }
    }
}
Function FindFile {
    foreach ($FindFile in $FindFileList) {
        $LogBuffer = "Searching for " + $FindFile + "."
        outlog
        $files = Get-ChildItem -path $env:systemroot -Filter $FindFile -Recurse -ErrorAction SilentlyContinue
        if ($files -eq $null) {
            $LogBuffer = "Warning: "+ $FindFile + " was not found."
            outlog
        } else {
            $folder = $files.DirectoryName
            $fileLocation = $files.FullName
            $LogBuffer = "Found " + $FindFile + " in " + $folder
            outlog
            filedelete($fileLocation)
            folderdelete($folder)
        }
    }
}

Function MSIx {
    foreach ($MSICode in $MSICodeList) {
        $LogBuffer = "Executing MSI Uninstall string: MSIEXEC.EXE /X" + $MSICode + " /QN /NORESTART"
        outlog
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/X$MSICode", "/QN", "/NORESTART" -Wait -PassThru
        $Exit = $process.ExitCode

    switch ($Exit) {
        "1603" {
            $LogBuffer = "MSI Result Code was: " + $Exit + " Error: Fatal error during uninstallation. Application not removed."
            outlog
        }
        "1605" {
            $LogBuffer = "Warning: MSI Result Code was: " + $Exit + " Application is not installed."
            outlog
        }
        "0" {
            $LogBuffer = "Warning: MSI Result code was: " + $Exit + " Application successfully uninstalled."
            outlog
            MSISuccessHandler
        }
        Default {
            $LogBuffer = "Error: MSI Result Code was: " + $Exit
            outlog }
    }
    $LogBuffer = "It looks like PowerShell."
    outlog
    }
}

Function DeleteService {
    foreach ($ServiceName in $Servicelist) {
        if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
            $ServName = Get-Service -Name $ServiceName
            $LogBuffer = "The service '" + $ServName.DisplayName + "' was found."
            outlog
            $LogBuffer = "Stopping service: '" + $ServName.DisplayName + "'"
            outlog
            Set-Service $ServName.Name -Status Stopped
            $ServiceStatus = Get-Service -Name $ServName.Name
            $LogBuffer = "The Service: '" + $ServName.DisplayName + "' is " + $ServiceStatus.Status + "."
            outlog
            $LogBuffer = "Deleting the service '" + $ServName.DisplayName + "'."
            outlog
 
            $null = (Get-WmiObject win32_service | Where-Object {$_.Name -Like $ServName.Name}).delete()
            Start-Sleep -Seconds 10

            if (Get-Service -Name $ServName.Name -ErrorAction SilentlyContinue) {
                $LogBuffer = "Error: The service: '" + $ServName.DisplayName + "' was not deleted."
                outlog
            } else {
                $LogBuffer = "The service: '" + $ServName.DisplayName + "' was successfully deleted."
                outlog
            }
        } else {
            $LogBuffer = "Warning: The service: '" + $ServiceName + "' was not found."
            outlog
        }
    }
}

Function RegClean {
    foreach ($RegPath in $RegPathList) {
        if (Test-Path $RegPath) {
            $LogBuffer = $RegPath + " was found in the registry."
            outlog
            $LogBuffer = "Deleting " + $RegPath + "."
            outlog
            Remove-Item $RegPath -Recurse -Force
            if (Test-Path $RegPath) {
                $LogBuffer = "Error: " + $RegPath + " was not deleted from the registry."
                outlog
            } else {
                $LogBuffer = $RegPath + " was successfully deleted from the registry."
                outlog
            }
        } else {
            $LogBuffer = "Warning: " + $RegPath + " was not found in the registry."
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
        $LogBuffer = "Warning: MSI uninstall was successful. Remainder of script is probably not necessary."
        outlog
    }
}
Function RegSvr {
    foreach ($dll in $registeredDLLs) {
        $registered = reg query HKLM\SOFTWARE\Classes /s /f $dll
        if ($registered -match '(?i)(C:\\Windows\\\S+)') {
            $LogBuffer = "The registered DLL '" + $dll + "' was found."
            outlog
            $LogBuffer = "Unregistering DLL: '" + $dll + "'"
            outlog
            regsvr32 /u /s $dll
            Start-Sleep -Seconds 10
            $registered = reg query HKLM\SOFTWARE\Classes /s /f $dll
            if ($registered -match '(?i)(C:\\Windows\\\S+)') {
                $LogBuffer = "Error: The DLL: '" + $dll + "' was not unregistered."
                outlog
            } else {
                $LogBuffer = "The service: '" + $dll + "' was successfully unregistered."
                outlog
            }
        } else {
            $LogBuffer = "Warning: The DLL: '" + $dll + "' was not found."
            outlog
        }
    }
}


#Do all the things
StartLog
MSIx
DeleteService
RegSvr
FindFile
RegClean
StopLog
