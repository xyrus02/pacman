@echo off

for /F "tokens=* USEBACKQ" %%F in (`powershell -nologo -noprofile -command "import-module '%~d0%~p0tools\pacman\modules\configuration.psm1';(new-xmlpropertycontainer '%~d0%~p0config.props').getProperty('DefaultEnvironment')"`) DO (
  set ENV=%%F
)

powershell -nologo -noexit -command ".'%~d0%~p0tools\pacman\LaunchShell.ps1' -RepositoryRoot '%~d0%~p0' -Environment '%ENV%'"