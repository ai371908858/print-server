#requires -RunAsAdministrator
<#
ChefPrint Menu Script (Interactive)
1) Install JDK 8u201 (interactive installer) + set env
2) Disable Windows Update
3) Restore Windows Update
4) Download print service ZIP to D:\ and extract
5) Download Sprt printer driver EXE to D:\

NOTE:
- ExecutionPolicy might block scripts in your environment. Run with:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\ChefPrint-Menu.ps1
#>

param(
  [string]$JdkZipUrl = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/jdk-8u201-windows-x64.zip?sign=wqP_jGY8WUy6l3pQQS_oRQHAwF0AKuA6SWe7Mrgq7yA=:0",
  [string]$PrintServiceZipUrl = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/shop-print-driver-250610.zip?sign=3tjyW-usu2Zkox8c1t9idfcaSfSpgH-4Z0QbnnVPz7I=:0",
  [string]$SprtDriverExeUrl = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/SP-DRV2157Win.exe?sign=-v-uNwgi52bwhSu-qMAJUWnXmEN2_6M1jpc3JX1zcL0=:0",

  # Expected JDK default location (Oracle JDK 8u201 default)
  [string]$DefaultJavaHome = "C:\Program Files\Java\jdk1.8.0_201",

  [string]$LogPath = "$env:SystemDrive\temp\chefprint_menu.log"
)

# ---------------- Logging / Utils ----------------
function Write-Log {
  param([string]$Msg)
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $line = "[{0}] {1}" -f $ts, $Msg
  Write-Host $line
  New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
  Add-Content -Path $LogPath -Value $line
}

function Ensure-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run PowerShell as Administrator." -ForegroundColor Red
    exit 1
  }
}

function Ensure-DDrive {
  if (-not (Test-Path "D:\")) {
    throw "D:\ drive not found. Please ensure D: exists."
  }
}

function Test-ZipHeaderPK {
  param([string]$Path)
  $fs = [System.IO.File]::OpenRead($Path)
  try {
    $b1 = $fs.ReadByte(); $b2 = $fs.ReadByte()
    return ($b1 -eq 0x50 -and $b2 -eq 0x4B)
  } finally { $fs.Close() }
}

function Download-File {
  param([string]$Url, [string]$OutPath)

  Write-Log ("Downloading: {0}" -f $Url)
  Write-Log ("Saving to:  {0}" -f $OutPath)

  Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing
  if (-not (Test-Path $OutPath)) { throw "Download failed: output file not found." }

  return $OutPath
}

# ---------------- JDK: Detect / Install / Env ----------------
function Get-JavaHomeFromRegistry {
  # Oracle/OpenJDK often set this key after install:
  # HKLM\SOFTWARE\JavaSoft\Java Development Kit\1.8\JavaHome
  $candidates = @(
    "HKLM:\SOFTWARE\JavaSoft\Java Development Kit\1.8",
    "HKLM:\SOFTWARE\WOW6432Node\JavaSoft\Java Development Kit\1.8"
  )
  foreach ($k in $candidates) {
    try {
      $v = (Get-ItemProperty -Path $k -ErrorAction Stop).JavaHome
      if ($v -and (Test-Path $v)) { return $v }
    } catch {}
  }
  return $null
}

function Test-JdkInstalled {
  param([string]$JavaHome)
  if ([string]::IsNullOrWhiteSpace($JavaHome)) { return $false }
  return (Test-Path (Join-Path $JavaHome "bin\java.exe"))
}

function Extract-ZipToTemp {
  param([string]$ZipPath)
  $tmp = Join-Path $env:TEMP ("chefzip_" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  Write-Log ("Extracting ZIP to temp: {0}" -f $tmp)
  Expand-Archive -Path $ZipPath -DestinationPath $tmp -Force
  return $tmp
}

function Find-JdkInstallerExe {
  param([string]$ExtractRoot)
  # Your ZIP contains the EXE installer.
  $exe = Get-ChildItem -Path $ExtractRoot -Recurse -File -Filter "*.exe" -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -ieq "jdk-8u201-windows-x64.exe" } |
         Select-Object -First 1
  if (-not $exe) {
    $exe = Get-ChildItem -Path $ExtractRoot -Recurse -File -Filter "*.exe" -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -match "jdk" -and $_.Name -match "8u201" } |
           Select-Object -First 1
  }
  if (-not $exe) { throw "JDK installer EXE not found in extracted content." }
  return $exe.FullName
}

function Install-JdkInteractiveAndSetEnv {
  Write-Log "== Option 1: Install JDK (interactive) + set env =="

  # If already installed, still (re)apply env
  $regHome = Get-JavaHomeFromRegistry
  $javaHome = if ($regHome) { $regHome } else { $DefaultJavaHome }

  if (-not (Test-JdkInstalled -JavaHome $javaHome)) {
    $zipPath = Join-Path $env:TEMP "jdk-8u201-windows-x64.zip"
    Download-File -Url $JdkZipUrl -OutPath $zipPath | Out-Null

    if (-not (Test-ZipHeaderPK -Path $zipPath)) {
      throw "Downloaded JDK file is not a valid ZIP (PK header missing). URL may be expired or returned an error page."
    }

    $extractRoot = Extract-ZipToTemp -ZipPath $zipPath
    try {
      $installerExe = Find-JdkInstallerExe -ExtractRoot $extractRoot
      Write-Log ("Launching installer (interactive): {0}" -f $installerExe)
      Write-Host ""
      Write-Host ">>> Please click NEXT to install JDK. Keep DEFAULT install directory." -ForegroundColor Yellow
      Write-Host ">>> When finished, close the installer window to continue." -ForegroundColor Yellow
      Write-Host ""
      Start-Process -FilePath $installerExe -Wait
    }
    finally {
      Remove-Item -Path $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Re-detect after install
    $regHome = Get-JavaHomeFromRegistry
    if ($regHome) { $javaHome = $regHome }

    if (-not (Test-JdkInstalled -JavaHome $javaHome)) {
      # last resort: user input
      Write-Host ""
      Write-Host "Could not auto-detect JAVA_HOME after install." -ForegroundColor Yellow
      $inp = Read-Host "Please input JAVA_HOME (e.g. C:\Program Files\Java\jdk1.8.0_201)"
      if (-not [string]::IsNullOrWhiteSpace($inp)) { $javaHome = $inp }
    }

    if (-not (Test-JdkInstalled -JavaHome $javaHome)) {
      throw ("JDK install not detected. java.exe not found under: {0}" -f $javaHome)
    }
  } else {
    Write-Log ("JDK already installed: {0}" -f $javaHome)
  }

  # Set env (Machine)
  Write-Log ("Setting JAVA_HOME (Machine): {0}" -f $javaHome)
  [Environment]::SetEnvironmentVariable("JAVA_HOME", $javaHome, "Machine")

  $append = "%JAVA_HOME%\bin;%JAVA_HOME%\jre\bin;"
  $path = [Environment]::GetEnvironmentVariable("Path", "Machine")
  if ($path -notlike "*%JAVA_HOME%\bin*") {
    $newPath = if ([string]::IsNullOrWhiteSpace($path)) { $append } else { "$path;$append" }
    Write-Log ("Appending Machine PATH: {0}" -f $append)
    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
  } else {
    Write-Log "Machine PATH already contains %JAVA_HOME%\bin. Skip."
  }

  $cp = ".;%JAVA_HOME%\lib;%JAVA_HOME%\lib\tools.jar"
  Write-Log ("Setting CLASSPATH (Machine): {0}" -f $cp)
  [Environment]::SetEnvironmentVariable("CLASSPATH", $cp, "Machine")

  # Verify
  Write-Log "Running: java -version (open a new terminal/reboot if needed)"
  try {
    $out = & cmd /c "java -version" 2>&1
    Write-Log ($out -join "`n")
  } catch {
    Write-Log ("java -version failed: {0}" -f $_.Exception.Message)
  }

  Write-Log "Option 1 done."
}

# ---------------- Windows Update: Disable / Restore ----------------
function Disable-WindowsAutoUpdate {
  Write-Log "== Option 2: Disable Windows Update =="

  # Policy: NoAutoUpdate=1
  $auKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
  New-Item -Path $auKey -Force | Out-Null
  New-ItemProperty -Path $auKey -Name "NoAutoUpdate" -PropertyType DWord -Value 1 -Force | Out-Null
  New-ItemProperty -Path $auKey -Name "AUOptions"    -PropertyType DWord -Value 2 -Force | Out-Null

  # Disable services
  $services = @("wuauserv","bits","dosvc","UsoSvc")
  foreach ($svc in $services) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
      try {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service  -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Log ("Service disabled: {0}" -f $svc)
      } catch {
        Write-Log ("Service disable failed: {0} - {1}" -f $svc, $_.Exception.Message)
      }
    }
  }

  # Best effort: WaaSMedic
  try {
    & sc.exe stop WaaSMedicSvc | Out-Null
    & sc.exe config WaaSMedicSvc start= disabled | Out-Null
    Write-Log "WaaSMedicSvc set to disabled (may be reverted by OS protection)."
  } catch {
    Write-Log ("WaaSMedicSvc change failed (ignored): {0}" -f $_.Exception.Message)
  }

  # Disable common tasks (best effort)
  $taskPaths = @(
    "\Microsoft\Windows\WindowsUpdate\",
    "\Microsoft\Windows\UpdateOrchestrator\",
    "\Microsoft\Windows\WaaSMedic\"
  )
  foreach ($tp in $taskPaths) {
    try {
      $tasks = Get-ScheduledTask -TaskPath $tp -ErrorAction SilentlyContinue
      foreach ($t in $tasks) {
        try {
          Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue | Out-Null
          Write-Log ("Task disabled: {0}{1}" -f $t.TaskPath, $t.TaskName)
        } catch {
          Write-Log ("Task disable failed: {0}{1} - {2}" -f $t.TaskPath, $t.TaskName, $_.Exception.Message)
        }
      }
    } catch {}
  }

  Write-Log "Option 2 done."
}

function Restore-WindowsAutoUpdate {
  Write-Log "== Option 3: Restore Windows Update =="

  # Remove policy keys (best effort)
  $wuKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
  try {
    if (Test-Path $wuKey) {
      Remove-Item -Path $wuKey -Recurse -Force -ErrorAction SilentlyContinue
      Write-Log "Removed WindowsUpdate policy registry."
    } else {
      Write-Log "WindowsUpdate policy registry not present."
    }
  } catch {
    Write-Log ("Policy registry removal failed (ignored): {0}" -f $_.Exception.Message)
  }

  # Restore services to Manual and start
  $services = @("wuauserv","bits","dosvc","UsoSvc")
  foreach ($svc in $services) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
      try {
        Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service -Name $svc -ErrorAction SilentlyContinue
        Write-Log ("Service set to Manual and started (best effort): {0}" -f $svc)
      } catch {
        Write-Log ("Service restore failed: {0} - {1}" -f $svc, $_.Exception.Message)
      }
    }
  }

  # WaaSMedicSvc back to demand (manual) - best effort
  try {
    & sc.exe config WaaSMedicSvc start= demand | Out-Null
    & sc.exe start WaaSMedicSvc | Out-Null
    Write-Log "WaaSMedicSvc set to demand and started (best effort)."
  } catch {
    Write-Log ("WaaSMedicSvc restore failed (ignored): {0}" -f $_.Exception.Message)
  }

  # Enable common tasks (best effort)
  $taskPaths = @(
    "\Microsoft\Windows\WindowsUpdate\",
    "\Microsoft\Windows\UpdateOrchestrator\",
    "\Microsoft\Windows\WaaSMedic\"
  )
  foreach ($tp in $taskPaths) {
    try {
      $tasks = Get-ScheduledTask -TaskPath $tp -ErrorAction SilentlyContinue
      foreach ($t in $tasks) {
        try {
          Enable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue | Out-Null
          Write-Log ("Task enabled: {0}{1}" -f $t.TaskPath, $t.TaskName)
        } catch {
          Write-Log ("Task enable failed: {0}{1} - {2}" -f $t.TaskPath, $t.TaskName, $_.Exception.Message)
        }
      }
    } catch {}
  }

  Write-Log "Option 3 done."
}

# ---------------- Downloads to D:\ ----------------
function Download-And-Extract-Zip-ToD {
  param([string]$Url, [string]$ZipName, [string]$ExtractFolderName)

  Ensure-DDrive

  $zipPath = Join-Path "D:\" $ZipName
  $extractPath = Join-Path "D:\" $ExtractFolderName

  Download-File -Url $Url -OutPath $zipPath | Out-Null

  if (-not (Test-ZipHeaderPK -Path $zipPath)) {
    throw "Downloaded file is not a valid ZIP (PK header missing). URL may be expired or returned an error page."
  }

  if (Test-Path $extractPath) {
    $bk = $extractPath + "_bak_" + (Get-Date -Format "yyyyMMddHHmmss")
    Write-Log ("Extract target exists. Backup: {0} -> {1}" -f $extractPath, $bk)
    Move-Item -Path $extractPath -Destination $bk -Force
  }

  New-Item -ItemType Directory -Force -Path $extractPath | Out-Null
  Write-Log ("Extracting ZIP to: {0}" -f $extractPath)
  Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

  Write-Log "Done."
}

function Download-Exe-ToD {
  param([string]$Url, [string]$ExeName)

  Ensure-DDrive

  $exePath = Join-Path "D:\" $ExeName
  Download-File -Url $Url -OutPath $exePath | Out-Null

  if (-not (Test-Path $exePath)) { throw "EXE download failed." }
  Write-Log ("Saved EXE: {0}" -f $exePath)
}

function Download-PrintService {
  Write-Log "== Option 4: Download print service ZIP to D:\ and extract =="
  Download-And-Extract-Zip-ToD -Url $PrintServiceZipUrl -ZipName "shop-print-driver-250610.zip" -ExtractFolderName "shop-print-driver-250610"
  Write-Log "Option 4 done."
}

function Download-SprtDriver {
  Write-Log "== Option 5: Download Sprt driver EXE to D:\ =="
  Download-Exe-ToD -Url $SprtDriverExeUrl -ExeName "SP-DRV2157Win.exe"
  Write-Log "Option 5 done."
}

# ---------------- Menu ----------------
function Show-Menu {
  Write-Host ""
  Write-Host "================ ChefPrint Setup Menu ================" -ForegroundColor Cyan
  Write-Host "1) Install JDK (interactive) + set env"
  Write-Host "2) Disable Windows Update"
  Write-Host "3) Restore Windows Update"
  Write-Host "4) Download print service ZIP to D:\ and extract"
  Write-Host "5) Download Sprt driver EXE to D:\"
  Write-Host "q) Quit"
  Write-Host "======================================================"
  Write-Host ""
}

# ---------------- Main ----------------
Ensure-Admin
Write-Log "==== ChefPrint Menu Start ===="
Write-Log ("LogPath = {0}" -f $LogPath)

while ($true) {
  Show-Menu
  $choice = Read-Host "Select (1-5 or q)"
  try {
    switch ($choice.ToLower()) {
      "1" { Install-JdkInteractiveAndSetEnv }
      "2" { Disable-WindowsAutoUpdate }
      "3" { Restore-WindowsAutoUpdate }
      "4" { Download-PrintService }
      "5" { Download-SprtDriver }
      "q" { Write-Log "Quit."; break }
      default { Write-Host "Invalid choice." -ForegroundColor Yellow }
    }
  } catch {
    Write-Log ("ERROR: {0}" -f $_.Exception.Message)
    Write-Host ("Failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
  }
}
