
:: Inputs, with defaults

:: mozharness builds use two repositories: gecko (source)
:: and build-tools (miscellaneous) for each, specify *_REPOSITORY.  If the
:: revision is not in the standard repo for the codebase, specify *_BASE_REPO as
:: the canonical repo to clone and *_HEAD_REPO as the repo containing the
:: desired revision.  For Mercurial clones, only *_HEAD_REV is required; for Git
:: clones, specify the branch name to fetch as *_HEAD_REF and the desired sha1
:: as *_HEAD_REV.

if not defined GECKO_REPOSITORY      set GECKO_REPOSITORY=https://hg.mozilla.org/mozilla-central
if not defined GECKO_BASE_REPOSITORY set GECKO_BASE_REPOSITORY=%GECKO_REPOSITORY%
if not defined GECKO_HEAD_REPOSITORY set GECKO_HEAD_REPOSITORY=%GECKO_REPOSITORY%
if not defined GECKO_HEAD_REV        set GECKO_HEAD_REV=default
if not defined GECKO_HEAD_REF        set GECKO_HEAD_REF=%GECKO_HEAD_REV%

if not defined TOOLS_REPOSITORY      set TOOLS_REPOSITORY=https://hg.mozilla.org/build/tools
if not defined TOOLS_BASE_REPOSITORY set TOOLS_BASE_REPOSITORY=%TOOLS_REPOSITORY%
if not defined TOOLS_HEAD_REPOSITORY set TOOLS_HEAD_REPOSITORY=%TOOLS_REPOSITORY%
if not defined TOOLS_HEAD_REV        set TOOLS_HEAD_REV=default
if not defined TOOLS_HEAD_REF        set TOOLS_HEAD_REF=%TOOLS_HEAD_REV%
if not defined TOOLS_DISABLE         set TOOLS_DISABLE=false

if not defined WORKSPACE             set WORKSPACE=%SystemDrive%\home\worker\workspace

if not "%TOOLS_DISABLE%" == "true" (
  if exist %WORKSPACE%\build\tools rmdir %WORKSPACE%\build\tools /s /q || echo ERROR && exit /b
  mkdir %WORKSPACE%\build\tools || echo ERROR && exit /b
  hg clone -U %TOOLS_BASE_REPOSITORY% %WORKSPACE%\build\tools || echo ERROR && exit /b
  hg pull -u -R %WORKSPACE%\build\tools --rev %TOOLS_HEAD_REV% %TOOLS_HEAD_REPOSITORY% || echo ERROR && exit /b
  hg update -R %WORKSPACE%\build\tools --rev %TOOLS_HEAD_REV% || echo ERROR && exit /b
)

for %%r in (%EXTRA_CHECKOUT_REPOSITORIES%) do (
  if exist "!%%r_DEST_DIR!" rmdir "!%%r_DEST_DIR!" /s /q || echo ERROR && exit /b
  mkdir "!%%r_DEST_DIR!" || echo ERROR && exit /b
  hg clone -U "!%%r_BASE_REPOSITORY!" "!%%r_DEST_DIR!" || echo ERROR && exit /b
  hg pull -u -R "!%%r_DEST_DIR!" --rev "!%%r_HEAD_REV!" "!%%r_HEAD_REPOSITORY!" || echo ERROR && exit /b
  hg update -R "!%%r_DEST_DIR!" --rev "!%%r_HEAD_REV!" || echo ERROR && exit /b
)

set GECKO_DIR=%WORKSPACE%\build\src
if exist %GECKO_DIR% rmdir %GECKO_DIR% /s /q || echo ERROR && exit /b
mkdir %GECKO_DIR% || echo ERROR && exit /b
hg clone -U %GECKO_BASE_REPOSITORY% %GECKO_DIR% || echo ERROR && exit /b
hg pull -u -R %GECKO_DIR% --rev %GECKO_HEAD_REV% %GECKO_HEAD_REPOSITORY% || echo ERROR && exit /b
hg update -R %GECKO_DIR% --rev %GECKO_HEAD_REV% || echo ERROR && exit /b
