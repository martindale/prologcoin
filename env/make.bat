@echo off

REM -- Change settings here -------------------------------------------

REM To set a specific VC: SET CHOOSEVC=VS110 (VS120, VS130, ...)
SET CHOOSEVC=

REM To set debug mode, set DEBUGMODE=1
SET DEBUGMODE=1


SET CCFLAGS=/nologo /c /EHsc
SET LINKFLAGS=/nologo

SET CCFLAGS_DEBUG=/nologo /DDEBUG /c /EHsc /Zi
SET LINKFLAGS_DEBUG=/nologo /debug

REM -------------------------------------------------------------------

REM
REM It's hopeless to use gmake and fix gmake so it works under Windows.
REM Normally, users would use Visual Studio and not the command line.
REM However, this provides a simple way of building without relying
REM on external tools.
REM

REM
REM Check if cl.exe is present on path
REM
WHERE /q cl.exe
IF NOT ERRORLEVEL 1 (
GOTO :MAIN
)

SETLOCAL ENABLEDELAYEDEXPANSION
set VCHOME=
call :SELECTVC "%CHOOSEVC%" VCHOME VCNAME
ECHO !VCHOME! >%TEMP%\vchome.txt
ECHO !VCNAME! >%TEMP%\vcname.txt
ENDLOCAL

FOR /f "delims=" %%A IN (%TEMP%\vchome.txt) DO SET VCHOME=%%A
FOR /f "delims=" %%A IN (%TEMP%\vcname.txt) DO SET VCNAME=%%A
CALL :trim VCHOME %VCHOME%
CALL :trim VCNAME %VCNAME%

CALL "%VCHOME%..\..\vc\bin\vcvars32.bat"

GOTO:MAIN

:trim
SETLOCAL ENABLEDELAYEDEXPANSION
SET params=%*
FOR /f "tokens=1*" %%a IN ("!params!") DO ENDLOCAL & SET %1=%%b
GOTO :EOF

:CHECKVC
SET _VCLIST=%2
SET _VCLIST=%_VCLIST:"=%
IF DEFINED %1 (
   IF NOT "!_VCLIST!"=="" SET _VCLIST=!_VCLIST!,
   SET _VCLIST=!_VCLIST!%1
)
SET %3=!_VCLIST!
GOTO:EOF

:SELECTVC
set CHOOSEVC=%1
set CHOOSEVC=%CHOOSEVC:"=%
set VCLIST=
call :CHECKVC VS150COMNTOOLS "!VCLIST!" VCLIST
call :CHECKVC VS140COMNTOOLS "!VCLIST!" VCLIST
call :CHECKVC VS130COMNTOOLS "!VCLIST!" VCLIST
call :CHECKVC VS120COMNTOOLS "!VCLIST!" VCLIST
call :CHECKVC VS110COMNTOOLS "!VCLIST!" VCLIST

SET VCARG=
FOR %%X IN (%VCLIST%) DO (
   IF "%%X"=="!CHOOSEVC!COMNTOOLS" SET VCARG=%%X
)

IF "!VCARG!"=="" (
  FOR %%X IN (!VCLIST!) DO (
     IF "!VCARG!"=="" SET VCARG=%%X
  )
)
set %2=!%VCARG%!
set %3=!VCARG!

GOTO :EOF

:MAIN

REM ----------------------------------------------------
REM  MAIN
REM ----------------------------------------------------

IF "%1"=="help" (
GOTO :HELP
)

SETLOCAL ENABLEEXTENSIONS
SETLOCAL ENABLEDELAYEDEXPANSION

REM
REM Retrocheck version of Visual Studio from the CL command
REM

SET VCVER=
CALL :GETVCVER VCVER
IF "!VCVER!"=="" (
   ECHO Couldn't determine version of Visual C++ from CL command
   ECHO Where cl.exe is
   WHERE cl.exe
   GOTO :EOF
)

SET BOOST=
CALL :CHECKBOOST !VCVER! BOOST
IF "!BOOST!"=="" (
   GOTO :EOF
)

IF "%DEBUGMODE%"=="1" (
   SET CCFLAGS=!CCFLAGS_DEBUG!
   SET LINKFLAGS=!LINKFLAGS_DEBUG!
)

IF NOT "%DOLIB%"=="" (
   SET LINKFLAGS=!LINKFLAGS:/debug=!
)

SET CCFLAGS=!CCFLAGS! /I"!BOOST!"

set ABSROOT=%~dp0

set ENV=%ROOT%\env
set SRC=%ROOT%\src
set OUT=%ROOT%\out
set BIN=%ROOT%\bin

REM
REM Is this a LIB target? Update goal appropriately.
REM
IF NOT "%DOLIB%"=="" (
   SET GOAL=%BIN%\%DOLIB%.lib
   SET LINKCMD=lib.exe
)

IF "%1"=="clean" (
GOTO :CLEAN
)

IF "%1"=="testclean" (
GOTO :TESTCLEAN
)

IF "%1"=="vcxproj" (
GOTO :VCXPROJ
)

IF "%1"=="vssln" (
GOTO :VSSLN
)

IF "%DEBUGMODE%"=="1" (
   echo [DEBUG MODE]
)

REM
REM Get all .cpp files
REM
set CPP_FILES=
FOR %%S IN (%SRC%\%SUBDIR%\*.cpp) DO (
    set CPP_FILES=!CPP_FILES! %%S
)

REM
REM Ensure that out directory is present
REM
IF NOT EXIST %OUT% (
mkdir %OUT%
)
IF NOT EXIST %OUT%\%SUBDIR% (
mkdir %OUT%\%SUBDIR%
)

REM
REM Compile all .cpp files into .obj
REM
set OBJ_FILES=
for %%i in (!CPP_FILES!) DO (
    set CPPFILE=%%i
    set OBJFILE=!CPPFILE:.cpp=.obj!
    set OBJFILE=!OBJFILE:%SRC%=%OUT%!

    IF NOT EXIST !OBJFILE! (
        set PDBFILE=
        IF "!DEBUGMODE!"=="1" set PDBFILE=/Fd:!OBJFILE:.obj=.pdb!
        cl.exe !CCFLAGS! /Fo:!OBJFILE! !PDBFILE! !CPPFILE!
REM        echo cl.exe !CCFLAGS! /Fo:!OBJFILE! !PDBFILE! !CPPFILE!
        IF ERRORLEVEL 1 GOTO :EOF
    )
    set OBJ_FILES=!OBJ_FILES! "!OBJFILE!"
)

REM
REM Ensure that bin directory is present
REM
IF NOT EXIST %BIN% (
mkdir %BIN%
)

REM
REM Dispatch to test if requested
REM
IF "%1"=="test" (
GOTO :TEST
)

IF EXIST !GOAL! (
echo !GOAL! already exists. Run make clean to first to recompile.
GOTO :EOF
)

REM
REM Link final goal
REM
ECHO %GOAL%

set PDBFILE=
IF "!DEBUGMODE!"=="1" IF "!DOLIB!"=="" set PDBFILE=/pdb:"!GOAL:.exe=.pdb!"
%LINKCMD% %LINKFLAGS% /out:"!GOAL!" !PDBFILE! !OBJ_FILES!

GOTO :EOF

REM ----------------------------------------------------
REM  TEST
REM ----------------------------------------------------

:TEST

REM
REM Ensure that out\test and bin\test directories are present
REM
IF NOT EXIST %OUT%\%SUBDIR%\test (
mkdir %OUT%\%SUBDIR%\test
)
IF NOT EXIST %BIN%\test (
mkdir %BIN%\test
)

REM
REM Compile and run tests
REM
set OBJ_FILES0=
for %%i in (!OBJ_FILES!) DO (
    IF NOT "%%~ni"=="main" (
        set OBJ_FILES0=!OBJ_FILES0! %%i
    )
)
for %%S in (%SRC%\%SUBDIR%\test\*.cpp) DO (
    set CPPFILE=%%S
    set OBJFILE=!CPPFILE:.cpp=.obj!
    set OBJFILE=!OBJFILE:%SRC%=%OUT%!
    set BINOKFILE=!OBJFILE:%OUT%=%BIN%!
    set BINEXEFILE=!OBJFILE:%OUT%=%BIN%!
    for %%i in (!CPPFILE!) do set BINOKFILE=%BIN%\test\%%~ni.ok
    for %%i in (!CPPFILE!) do set BINEXEFILE=%BIN%\test\%%~ni.exe
    for %%i in (!CPPFILE!) do set BINLOGFILE=%BIN%\test\%%~ni.log
    IF NOT EXIST !BINOKFILE! (
	set PDBFILE=
        IF "!DEBUGMODE!"=="1" set PDBFILE=/Fd:!OBJFILE:.obj=.pdb!
        cl.exe !CCFLAGS! /I%SRC% /Fo:!OBJFILE! !PDBFILE! !CPPFILE!
        IF ERRORLEVEL 1 GOTO :EOF

	set PDBFILE=
	IF "!DEBUGMODE!"=="1" set PDBFILE=/debug /pdb:"!BINEXEFILE:.exe=.pdb!"
	link !LINKFLAGS! /out:!BINEXEFILE! !PDBFILE! !OBJ_FILES0! !OBJFILE!
        IF ERRORLEVEL 1 GOTO :EOF
	ECHO Running !BINEXEFILE!
	ECHO   [output to !BINLOGFILE!]
	!BINEXEFILE! 1>!BINLOGFILE! 2>&1
        IF ERRORLEVEL 1 GOTO :EOF
	for %%i in (!BINLOGFILE!) do if %%~zi==0 (
	    echo Error while running !BINEXEFILE!
	    GOTO :EOF
	)
	copy /Y NUL !BINOKFILE! >NUL
    )
)

GOTO :EOF

REM ----------------------------------------------------
REM  CLEAN
REM ----------------------------------------------------

:CLEAN
del /S /F /Q %OUT%
del /S /F /Q %BIN%
rmdir /S /Q %OUT%
rmdir /S /Q %BIN%

GOTO :EOF

REM ----------------------------------------------------
REM  TESTCLEAN
REM ----------------------------------------------------

:TESTCLEAN
del /S /F /Q %OUT%\!SUBDIR!\test
del /S /F /Q %BIN%\test
rmdir /S /Q %OUT%\!SUBDIR!\test
rmdir /S /Q %BIN%\test

GOTO :EOF

REM ----------------------------------------------------
REM  GETVCVER
REM ----------------------------------------------------

:GETVCVER
SET VCVER=
WHERE cl.exe >%TEMP%\cl.txt
SET /P CLTXT=<%TEMP%\cl.txt

IF "!VCVER!"=="" IF NOT "!CLTXT:Microsoft Visual Studio 14.0=!"=="!CLTXT!" (
   SET VCVER=14
)
IF "!VCVER!"=="" IF NOT "!CLTXT:Microsoft Visual Studio 13.0=!"=="!CLTXT!" (
   SET VCVER=13
)
IF "!VCVER!"=="" IF NOT "!CLTXT:Microsoft Visual Studio 12.0=!"=="!CLTXT!" (
   SET VCVER=12
)
IF "!VCVER!"=="" IF NOT "!CLTXT:Microsoft Visual Studio 11.0=!"=="!CLTXT!" (
   SET VCVER=11
)
SET %1=!VCVER!

GOTO :EOF

REM ----------------------------------------------------
REM  BOOST
REM ----------------------------------------------------

:CHECKBOOST

REM
REM Determine version of BOOST from version of Visual C++
REM

SET VCVER=%1

SET BOOSTVER=boost_1_55_0

IF "!VCVER!"=="14" (
   SET BOOSTVER=boost_1_59_0
)

SET BOOST=

IF EXIST "%PROGRAMFILES%\boost\!BOOSTVER!" (
    SET BOOST=%PROGRAMFILES%\boost\!BOOSTVER!
)

IF "!BOOST!"=="" (
   ECHO This package requires BOOST !BOOSTVER! and couldn't find it.
   ECHO Tried the following locations:
   ECHO     %PROGRAMFILES%\boost\!BOOSTVER!
   GOTO :EOF
)

SET %2=!BOOST!

GOTO :EOF

REM ----------------------------------------------------
REM  VCXPROJ
REM ----------------------------------------------------

:VCXPROJ

REM
REM Check if csc.exe is present on path
REM
WHERE /q csc.exe
IF ERRORLEVEL 1 (
echo Cannot find csc.exe
GOTO :EOF
)

REM
REM Ensure that bin directory is present
REM
IF NOT EXIST %BIN% (
mkdir %BIN%
)

echo Compiling make_vcxproj.cs
csc.exe /nologo /reference:Microsoft.Build.dll /reference:Microsoft.Build.Framework.dll /out:%BIN%\make_vcxproj.exe %ENV%\make_vcxproj.cs
IF ERRORLEVEL 1 GOTO :EOF
%BIN%\make_vcxproj.exe env=%VCNAME% src=%SRC% out=%OUT% bin=%BIN% boost="!BOOST!"

GOTO :EOF

REM ----------------------------------------------------
REM  VSSLN
REM ----------------------------------------------------

:VSSLN

REM
REM Check if csc.exe is present on path
REM
WHERE /q csc.exe
IF ERRORLEVEL 1 (
echo Cannot find csc.exe
GOTO :EOF
)

REM
REM Ensure that bin directory is present
REM
IF NOT EXIST %BIN% (
mkdir %BIN%
)

echo Compiling make_vssln.cs
csc.exe /nologo /reference:Microsoft.Build.dll /reference:Microsoft.Build.Framework.dll /out:%BIN%\make_vssln.exe %ENV%\make_vssln.cs
IF ERRORLEVEL 1 GOTO :EOF
%BIN%\make_vssln.exe bin=%BIN%

GOTO :EOF

:HELP
echo --------------------------------------------------------
echo  make help
echo --------------------------------------------------------
echo  make          To build the application
echo  make clean    To clean everything
echo  make test     To build and run tests
echo  make vcxproj  To build vcxproj file for Visual Studio
echo  make vssln    To build sln file for Visual Studio
echo --------------------------------------------------------

GOTO :EOF