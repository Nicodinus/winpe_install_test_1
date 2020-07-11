@echo off

echo I am test script loaded from github

echo Boot type is %BOOT_TYPE%

goto :END

:testCall1
	echo test call
	goto :EOF

:END

:EOF