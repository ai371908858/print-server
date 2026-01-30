# --- 0. [核心功能] 自动获取管理员权限 ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $host.UI.RawUI.WindowTitle = "正在尝试提权..."
    try {
        $process = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs -PassThru
        exit
    }
    catch {
        Write-Error "提权失败，请手动右键选择【以管理员身份运行】。"
        pause
        exit
    }
}

# --- 1. 网络配置 (TLS 1.2) ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- 2. 资源地址 ---
$JdkUrl      = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/jdk-8u201-windows-x64.zip?sign=wqP_jGY8WUy6l3pQQS_oRQHAwF0AKuA6SWe7Mrgq7yA=:0"
$PrintUrl    = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/shop-print-driver-1.0.zip?sign=8QG1UKoSmYlAX3-vWKp5IKJMJ1rAUJv8LCqsvLJT3N0=:0"
$SprtUrl     = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/SP-DRV2157Win.exe?sign=-v-uNwgi52bwhSu-qMAJUWnXmEN2_6M1jpc3JX1zcL0=:0"
$NssmUrl     = "https://nssm.cc/ci/nssm-2.24-101-g897c7ad.zip" 

# --- 3. 基础配置 ---
$TargetDrive = "D:"
if (!(Test-Path $TargetDrive)) {
    Write-Warning "未检测到 D 盘，将默认安装到 C:\HDL_Print_Service"
    $TargetDrive = "C:\HDL_Print_Service"
    if (!(Test-Path $TargetDrive)) { New-Item -ItemType Directory -Path $TargetDrive -Force | Out-Null }
}

# --- 4. 功能模块 ---

function Set-JDK {
    Write-Host "`n>>> 正在下载并安装 JDK..." -ForegroundColor Cyan
    $zip = "$env:TEMP\jdk.zip"
    $dir = "$env:TEMP\jdk_temp"
    try {
        Invoke-WebRequest $JdkUrl -OutFile $zip -UseBasicParsing
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        Expand-Archive $zip -DestinationPath $dir -Force
        
        $exe = Get-ChildItem $dir -Recurse -Filter "jdk*.exe" | Select-Object -First 1
        if ($exe) { 
            Write-Host "正在静默安装 JDK..." -ForegroundColor Yellow
            Start-Process $exe.FullName -ArgumentList "/s" -Wait 
        } else { Write-Error "未找到 JDK 安装程序。" }

        $jh = "C:\Program Files\Java\jdk1.8.0_201"
        if (Test-Path $jh) {
            [Environment]::SetEnvironmentVariable("JAVA_HOME", $jh, "Machine")
            $cp = [Environment]::GetEnvironmentVariable("Path", "Machine")
            if ($cp -notlike "*%JAVA_HOME%\bin*") {
                $newPath = if ($cp.EndsWith(";")) { $cp + "%JAVA_HOME%\bin;" } else { $cp + ";%JAVA_HOME%\bin;" }
                [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
                $env:Path = $newPath
            }
            Write-Host "JDK 安装及配置完成。" -ForegroundColor Green
        }
    } catch { Write-Error "JDK 安装失败: $_" }
}

function Set-PrintService {
    Write-Host "`n>>> 正在下载打印服务..." -ForegroundColor Cyan
    $zip = "$env:TEMP\print.zip"
    try {
        Invoke-WebRequest $PrintUrl -OutFile $zip -UseBasicParsing
        Write-Host "正在解压到 $TargetDrive ..." -ForegroundColor Yellow
        $dest = if ($TargetDrive.EndsWith("\")) { $TargetDrive } else { $TargetDrive + "\" }
        Expand-Archive $zip -DestinationPath $dest -Force
        
        $ip = Read-Host "请输入服务器IP"
        $conf = "${dest}shop-print-driver-1.0\conf\env\shop.conf"
        if (Test-Path $conf) {
            (Get-Content $conf) -replace '(?<=jdbc:mysql://).*?(?=:3306)', $ip | Set-Content $conf
            Write-Host "配置文件已更新。" -ForegroundColor Green
        } else { Write-Warning "未找到 shop.conf (尝试路径: $conf)。" }
    } catch { Write-Error "打印服务部署失败: $_" }
}

function Install-Nssm-Env {
    $nssmInstallDir = "$TargetDrive\nssm"
    $nssmExePath = "$nssmInstallDir\nssm.exe"

    if (!(Test-Path $nssmExePath)) {
        Write-Host "正在安装 NSSM 到 $nssmInstallDir ..." -ForegroundColor Cyan
        if (!(Test-Path $nssmInstallDir)) { New-Item -ItemType Directory -Path $nssmInstallDir -Force | Out-Null }
        
        $zip = "$env:TEMP\nssm.zip"
        try {
            Invoke-WebRequest $NssmUrl -OutFile $zip -UseBasicParsing
            Expand-Archive $zip -DestinationPath "$env:TEMP\nssm_pkg" -Force
            $src = Get-ChildItem "$env:TEMP\nssm_pkg" -Recurse -Filter "nssm.exe" | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
            if ($src) {
                Copy-Item $src.FullName -Destination $nssmExePath -Force
                Write-Host "NSSM 文件已就绪。" -ForegroundColor Green
            } else { throw "解压失败：未找到 win64\nssm.exe" }
        } catch {
            Write-Error "NSSM 安装失败: $_"
            return $null
        }
    } else { Write-Host "检测到 NSSM 已安装。" -ForegroundColor Gray }

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($currentPath -notlike "*$nssmInstallDir*") {
        Write-Host "正在将 NSSM 加入系统 Path..." -ForegroundColor Yellow
        try {
            $newPath = if ($currentPath.EndsWith(";")) { "$currentPath$nssmInstallDir" } else { "$currentPath;$nssmInstallDir" }
            [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
            $env:Path = $newPath 
            Write-Host "环境变量配置成功！" -ForegroundColor Green
        } catch { Write-Error "环境变量配置失败: $_" }
    }
    return $nssmExePath
}

function Set-NssmService {
    Write-Host "`n>>> 正在配置 Shop-print 服务..." -ForegroundColor Cyan
    
    $nssmExe = Install-Nssm-Env
    if (!$nssmExe) { return }

    $rootPath = $TargetDrive.TrimEnd("\")
    $possiblePaths = @(
        "$rootPath\shop-print-driver-1.0\bin\shop-print-driver.bat",
        "$rootPath\shop-print-driver-1.0\bin\shop-print.bat",
        "$rootPath\shop-print-1.0\bin\shop-print.bat"
    )
    $batPath = $null
    foreach ($p in $possiblePaths) { if (Test-Path $p) { $batPath = $p; break } }

    if (!$batPath) { Write-Error "❌ 未找到启动脚本！请先执行[步骤2]。"; return }
    
    $workDir = Split-Path -Parent $batPath
    $svcName = "Shop-print"
    $svcArgs = "-Dhttp.port=8041 -Dconfig.resource=env/shop.conf -Dplay.crypto.secret=123"

    try {
        Write-Host "正在重置服务..." -ForegroundColor Gray
        & $nssmExe stop $svcName 2>&1 | Out-Null
        & $nssmExe remove $svcName confirm 2>&1 | Out-Null
        Start-Sleep -Seconds 1

        & $nssmExe install $svcName "$batPath" $svcArgs
        & $nssmExe set $svcName AppDirectory "$workDir"
        
        $logPath = "$workDir\service-nssm.log"
        & $nssmExe set $svcName AppStdout "$logPath"
        & $nssmExe set $svcName AppStderr "$logPath"
        & $nssmExe set $svcName AppExit Default Restart
        & $nssmExe set $svcName AppRestartDelay 5000 

        Write-Host "正在启动服务..." -ForegroundColor Yellow
        & $nssmExe start $svcName
        
        Start-Sleep -Seconds 3
        $status = Get-Service $svcName -ErrorAction SilentlyContinue
        if ($status.Status -eq 'Running') {
            Write-Host "=== 服务部署成功！状态：Running ===" -ForegroundColor Green
        } else {
            Write-Warning "服务未启动 (Status: $($status.Status))。请检查日志: $logPath"
        }
    } catch { Write-Error "服务配置异常: $_" }
}

function Set-DBAuth {
    Write-Host "`n>>> 数据库授权" -ForegroundColor Cyan
    $ip = Read-Host "请输入服务器IP"
    $pw = Read-Host "请输入数据库密码"
    $sql = "grant select,insert,update,delete on shop_cloud.* to 'hdldev'@'%' identified by '9^3jIe^0*5'; flush privileges;"
    try {
        ssh -o StrictHostKeyChecking=no root@$ip "mysql -u root -p'$pw' -e `"$sql`""
        Write-Host "授权成功。" -ForegroundColor Green
    } catch { Write-Error "SSH 执行失败: $_" }
}

# --- [重点修复] 注册表强力修改法 ---
function Set-WinUpdate {
    param([int]$val)
    # val=1: 关闭 (Disable), val=0: 开启 (Manual)
    
    $statusText = if ($val -eq 1) { "已禁用 (Disabled)" } else { "已开启 (Manual)" }
    # 注册表 Start 值: 4=Disabled, 3=Manual, 2=Auto
    $startType = if ($val -eq 1) { 4 } else { 3 } 

    try {
        Write-Host "正在通过注册表配置 Windows Update..." -ForegroundColor Gray
        
        # 1. 修改系统服务启动类型 (核心底层配置)
        $svcPath = "HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv"
        if (Test-Path $svcPath) {
            Set-ItemProperty -Path $svcPath -Name "Start" -Value $startType -ErrorAction Stop
        } else {
            Write-Warning "未找到 wuauserv 服务注册表项，系统可能经过精简。"
        }

        # 2. 修改组策略策略 (NoAutoUpdate)
        $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        if (!(Test-Path $policyPath)) { New-Item $policyPath -Force | Out-Null }
        Set-ItemProperty -Path $policyPath -Name "NoAutoUpdate" -Value $val -ErrorAction Stop

        # 3. 尝试停止服务 (仅当禁用时，不强求成功)
        if ($val -eq 1) {
            Stop-Service "wuauserv" -ErrorAction SilentlyContinue
        }

        Write-Host "Windows 更新策略配置完成: $statusText" -ForegroundColor Green
        Write-Host "(注意: 直接修改注册表生效可能需要重启电脑)" -ForegroundColor DarkGray
    }
    catch {
        Write-Error "配置失败: $_"
        Write-Host "如果依然报错，请检查是否有 360/火绒 等安全软件锁定了注册表。" -ForegroundColor Yellow
    }
}

function Set-PidTask {
    Write-Host "`n>>> 创建 PID 清理任务" -ForegroundColor Cyan
    $pidFile = "${TargetDrive}shop-print-driver-1.0\bin\RUNNING_PID"
    $cmdArg = "/c if exist ""$pidFile"" del ""$pidFile"""
    try {
        $act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument $cmdArg
        $trig = New-ScheduledTaskTrigger -AtStartup
        Register-ScheduledTask -TaskName "CleanupPID" -Action $act -Trigger $trig -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM") -Force
        Write-Host "清理任务已创建。" -ForegroundColor Green
    } catch { Write-Error "任务创建失败: $_" }
}

function Get-Driver {
    Write-Host "`n>>> 下载驱动程序" -ForegroundColor Cyan
    $outFile = "${TargetDrive}SP-DRV2157Win.exe"
    try {
        Invoke-WebRequest $SprtUrl -OutFile $outFile
        Write-Host "驱动下载完成。" -ForegroundColor Green
    } catch { Write-Error "下载失败: $_" }
}

# --- 5. 主菜单 ---
while ($true) {
    Write-Host "`n==============================" -ForegroundColor Gray
    Write-Host " 打印服务器一键部署脚本  by:潇潇     " -ForegroundColor Yellow
    Write-Host "==============================" -ForegroundColor Gray
    Write-Host "1. 安装 JDK 环境"
    Write-Host "2. 部署打印服务"
    Write-Host "3. 安装 NSSM 守护服务"
    Write-Host "4. 数据库授权"
    Write-Host "5. 关闭 Windows 自动更新"
    Write-Host "6. 开启 Windows 自动更新"
    Write-Host "7. 创建 PID 清理任务"
    Write-Host "8. 下载驱动"
    Write-Host "q. 退出"
    Write-Host "------------------------------"
    
    $choice = Read-Host "请输入选项"
    
    switch ($choice) {
        "1" { Set-JDK }
        "2" { Set-PrintService }
        "3" { Set-NssmService } 
        "4" { Set-DBAuth }
        "5" { Set-WinUpdate 1 }
        "6" { Set-WinUpdate 0 }
        "7" { Set-PidTask }
        "8" { Get-Driver }
        "q" { break }
        default { Write-Warning "无效输入" }
    }
}
