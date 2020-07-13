@echo off

set SYSTEM_LETTER=C
set BOOT_LETTER=W
set SMB_SHARE_IP=10.99.0.11
set SMB_SHARE_PATH="\\%SMB_SHARE_IP%\media_storage"
call :unquote SMB_SHARE_PATH %SMB_SHARE_PATH%
set SMB_INSTALL_WIM_PATH="%SMB_SHARE_PATH%\install.wim"
call :unquote SMB_INSTALL_WIM_PATH %SMB_INSTALL_WIM_PATH%

echo | set /p="Check %SMB_SHARE_IP% address for alive "

:IPAddressLoopPing
set errorlevel=0
ping -n 1 %SMB_SHARE_IP% | find "TTL=" >nul
if errorlevel 1 (
	echo | set /p="."
	call :Sleep
	goto :IPAddressLoopPing
)
set errorlevel=0
echo .

echo | set /p="Trying mount SMB share "

:MountSMBLoop
net use Z: "%SMB_SHARE_PATH%" /user:Anonymous anonymous
if errorlevel 1 (
	echo | set /p="."
	call :Sleep
	goto :MountSMBLoop
)
set errorlevel=0
echo .

:selectDeviceStep1
echo List of all available disks
call :listDevices

echo Please enter device id number to continue
SET /P DEVICE_ID=""
REM echo Device id is %DEVICE_ID%

set errorlevel=0
call :selectDeviceId %DEVICE_ID%
if %errorlevel% equ 1 (
	echo Please enter valid device id!
	goto :selectDeviceStep1
)

echo Confirm selection
call :inputSelection1 :diskSelectConfirmed1 :selectDeviceStep1
goto :EOF

:diskSelectConfirmed1
echo Selection confirmed: %DEVICE_ID%

call :cleanDisks
call :makeBootDrive
call :makeSystemDrive

echo All preparations is completed! Initialize applying Windows image from external storage...

echo dism /apply-image /imagefile:%SMB_INSTALL_WIM_PATH% /index:1 /applydir:%SYSTEM_LETTER%:\
dism /apply-image /imagefile:%SMB_INSTALL_WIM_PATH% /index:1 /applydir:%SYSTEM_LETTER%:\

goto :OOBE_END

:OOBE_START

echo Now some mess around with Windows registry...

reg load HKLM\sys "%SYSTEM_LETTER%:\Windows\System32\config\SYSTEM"
reg delete HKLM\sys\Setup /v OOBEInProgress /f
reg add HKLM\sys\Setup /v OOBEInProgress /t REG_DWORD /f /d 1
reg delete HKLM\sys\Setup /v CmdLine /f
reg add HKLM\sys\Setup /v CmdLine /t REG_SZ /f /d "%SYSTEM_LETTER%:\Installation\oobe.bat"
reg save HKLM\sys "%SYSTEM_LETTER%:\Windows\System32\config\SYSTEM" /y
reg unload HKLM\sys

reg load HKLM\soft "%SYSTEM_LETTER%:\Windows\System32\config\SOFTWARE"
reg add HKLM\soft\Microsoft\Windows\CurrentVersion\Policies\System /v VerboseStatus /t REG_DWORD /f /d 1
reg save HKLM\soft "%SYSTEM_LETTER%:\Windows\System32\config\SOFTWARE" /y
reg unload HKLM\soft

:OOBE_END

echo "Creating bcdboot..."

call :createBoot

echo "Installation complete! Rebooting..."
goto :END

:listDevices
	powershell -c "Get-PhysicalDisk | Select-Object -Property @{Label=\"DeviceId\";Expression={[int]$_.DeviceId}},FriendlyName,@{Label=\"Size (MiB)\";Expression={($_.Size/1024/1024).toString(\"#.##\")}},MediaType | Sort-Object -Property DeviceId | Format-Table" 
	goto :EOF

:selectDeviceId
	set F1=0
	for /f "delims=" %%a in ('powershell -c "Get-PhysicalDisk | Select-Object -Property @{Label='DeviceId';Expression={[int]$_.DeviceId}},FriendlyName,@{Label='Size (MiB)';Expression={($_.Size/1024/1024).toString('#.##')}},MediaType | where {$_.DeviceId -eq ([int]'%1')} | Format-Table"') do (
		set F1=1
		set out=%%a
		for /f "delims=" %%b in ('echo "%%a" ^| findstr "Exception"') do (
			set errorlevel=1
			goto :EOF
		)
	)
	if %F1% equ 0 set errorlevel=1
	if %F1% equ 1 echo %out%
	goto :EOF

:inputSelection1
	@SET /P EA=(Y or N):
	@if %EA%.==y. set EA=Y
	@if %EA%.==n. set EA=N
	@if %EA%.==q. set EA=Q
	@if %EA%.==Q. goto :END
	@if %EA%.==N. goto %2
	@if %EA%.==Y. goto %1
	goto :EOF

:cleanDisks
	echo Warning! Clean disks is pending. You have 10 seconds for abort installation!
	ping 127.0.0.1 -n 11>nul
	echo sel disk %DEVICE_ID% > "%Temp%\clean_disks.txt"
	echo clean >> "%Temp%\clean_disks.txt"
	if not defined BOOT_TYPE (
		REM undefined
	) else (
		if "%BOOT_TYPE%" equ "UEFI" (
			echo convert gpt >> "%Temp%\clean_disks.txt"
		) else (
			REM undefined
		)
	)
	echo Clean disks initialized...
	diskpart /s "%Temp%\clean_disks.txt"
	echo Clean disks completed!
	goto :EOF

:makeSystemDrive
	echo sel disk %DEVICE_ID% > "%Temp%\create_system_drive.txt"
	echo create part primary >> "%Temp%\create_system_drive.txt"
	echo format quick >> "%Temp%\create_system_drive.txt"
	echo assign letter %SYSTEM_LETTER% >> "%Temp%\create_system_drive.txt"
	diskpart /s "%Temp%\create_system_drive.txt"
	goto :EOF

:makeBootDrive
	echo sel disk %DEVICE_ID% > "%Temp%\create_boot_drive.txt"
	if not defined BOOT_TYPE (
		REM TODO: make legacy booter
		echo create part primary size=100 >> "%Temp%\create_boot_drive.txt"
		echo format fs=fat32 quick >> "%Temp%\create_boot_drive.txt"
		echo assign letter %BOOT_LETTER% >> "%Temp%\create_boot_drive.txt"
		echo active >> "%Temp%\create_boot_drive.txt"
		echo set id=27 >> "%Temp%\create_boot_drive.txt"
	) else (
		if "%BOOT_TYPE%" equ "UEFI" (
			echo create part efi size=500 >> "%Temp%\create_boot_drive.txt"
			echo format fs=fat32 quick >> "%Temp%\create_boot_drive.txt"
			echo assign letter %BOOT_LETTER% >> "%Temp%\create_boot_drive.txt"
		) else (
			echo create part primary size=100 >> "%Temp%\create_boot_drive.txt"
			echo format fs=fat32 quick >> "%Temp%\create_boot_drive.txt"
			echo assign letter %BOOT_LETTER% >> "%Temp%\create_boot_drive.txt"
			echo active >> "%Temp%\create_boot_drive.txt"
			echo set id=27 >> "%Temp%\create_boot_drive.txt"
		)
	)
	diskpart /s "%Temp%\create_boot_drive.txt"
	goto :EOF

:createBoot
	if not defined BOOT_TYPE (
		bcdboot %SYSTEM_LETTER%:\Windows /s %BOOT_LETTER%: /f BIOS
	) else (
		if "%BOOT_TYPE%" equ "UEFI" (
			bcdboot %SYSTEM_LETTER%:\Windows /s %BOOT_LETTER%: /f UEFI
		) else (
			bcdboot %SYSTEM_LETTER%:\Windows /s %BOOT_LETTER%: /f BIOS
		)
	)
	goto :EOF

:Sleep
	if [%~1] equ [] (
		ping 127.0.0.1 -n 2 >nul
	) else (
		ping 127.0.0.1 -n %~1 >nul
	)
	goto :EOF

:unquote
	set %1=%~2
	goto :EOF

:END

:EOF