#requires -RunAsAdministrator

# --- 1. 配置下载地址 ---
$JdkUrl      = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/jdk-8u201-windows-x64.zip?sign=wqP_jGY8WUy6l3pQQS_oRQHAwF0AKuA6SWe7Mrgq7yA=:0"
$PrintUrl    = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/shop-print-driver-1.0.zip?sign=8QG1UKoSmYlAX3-vWKp5IKJMJ1rAUJv8LCqsvLJT3N0=:0"
$AlwaysUpUrl = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/AlwaysUp.zip?sign=eBYEdtTm4LnA2YACyMjmOYTEOZHwN5-OhomeROEvI8E=:0"
$SprtUrl     = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/SP-DRV2157Win.exe?sign=-v-uNwgi52bwhSu-qMAJUWnXmEN2_6M1jpc3JX1zcL0=:0"

# --- 2. 基础配置 (自动检测 D 盘) ---
$TargetDrive = "D:\"
if (!(Test-Path $TargetDrive)) {
    Write-Warning "未检测到 D 盘，将默认安装到 C:\HDL_Print_Service"
    $TargetDrive = "C:\HDL_Print_Service"
    if (!(Test-Path $TargetDrive)) { New-Item -ItemType Directory -Path $TargetDrive -Force | Out-Null }
}

# --- 3. 功能模块 ---

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
        } else {
            Write-Error "错误：在压缩包中未找到 JDK 安装程序。"
            return
        }

        # 环境变量配置
        $jh = "C:\Program Files\Java\jdk1.8.0_201"
        if (!(Test-Path $jh)) {
            Write-Warning "未检测到 JDK 目录 ($jh)，安装可能未完成。"
            return
        }
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $jh, "Machine")
        
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($currentPath -notlike "*%JAVA_HOME%\bin*") {
            $newPath = if ($currentPath.EndsWith(";")) { $currentPath + "%JAVA_HOME%\bin;%JAVA_HOME%\jre\bin;" } else { $currentPath + ";%JAVA_HOME%\bin;%JAVA_HOME%\jre\bin;" }
            [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
        }
        [Environment]::SetEnvironmentVariable("CLASSPATH", ".;%JAVA_HOME%\lib;%JAVA_HOME%\lib\tools.jar", "Machine")
        Write-Host "JDK 安装及配置完成。" -ForegroundColor Green
    }
    catch {
        Write-Error "JDK 安装失败: $_"
    }
}

function Set-PrintService {
    Write-Host "`n>>> 正在下载打印服务..." -ForegroundColor Cyan
    $zip = "$env:TEMP\print.zip"
    
    try {
        Invoke-WebRequest $PrintUrl -OutFile $zip -UseBasicParsing
        Write-Host "正在解压到 $TargetDrive ..." -ForegroundColor Yellow
        Expand-Archive $zip -DestinationPath $TargetDrive -Force
        
        $ip = Read-Host "请输入服务器IP"
        $potentialPath1 = Join-Path $TargetDrive "shop-print-driver-1.0\conf\env\shop.conf"
        
        if (Test-Path $potentialPath1) {
            $confContent = Get-Content $potentialPath1
            $newContent = $confContent -replace '(?<=jdbc:mysql://).*?(?=:3306)', $ip 
            $newContent | Set-Content $potentialPath1
            Write-Host "配置文件已更新。" -ForegroundColor Green
        } else {
            Write-Warning "未找到配置文件 shop.conf，请手动检查路径。"
        }
    }
    catch {
        Write-Error "打印服务部署失败: $_"
    }
}

function Set-AlwaysUp {
    Write-Host "`n== 开始安装 AlwaysUp ==" -ForegroundColor Cyan
    $zipPath = "$env:TEMP\AlwaysUp.zip"
    $extractDir = "$env:TEMP\AlwaysUp_Install"
    
    try {
        Write-Host "正在下载..." 
        Invoke-WebRequest $AlwaysUpUrl -OutFile $zipPath -UseBasicParsing
        
        Write-Host "正在解压..."
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        Expand-Archive $zipPath -DestinationPath $extractDir -Force

        $installerExe = Get-ChildItem -Path $extractDir -Recurse -Filter "*.exe" | Select-Object -First 1
        if ($installerExe) {
            Write-Host "正在静默安装..." -ForegroundColor Yellow
            Start-Process -FilePath $installerExe.FullName -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait
            Write-Host "AlwaysUp 安装完成。" -ForegroundColor Green
        } else {
            Write-Error "未找到 AlwaysUp 安装程序。"
        }
    }
    catch {
        Write-Error "AlwaysUp 安装出错: $_"
    }
    finally {
        Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Set-DBAuth {
    Write-Host "`n>>> 数据库授权" -ForegroundColor Cyan
    $ip = Read-Host "请输入服务器IP"
    $pw = Read-Host "请输入数据库密码"
    $sql = "grant select,insert,update,delete on shop_cloud.* to 'hdldev'@'%' identified by '9^3jIe^0*5'; flush privileges;"
    
    Write-Host "正在尝试 SSH 连接 (需要 OpenSSH 客户端)..." -ForegroundColor Yellow
    try {
        ssh -o StrictHostKeyChecking=no root@$ip "mysql -u root -p'$pw' -e `"$sql`""
        Write-Host "授权命令执行完毕。" -ForegroundColor Green
    }
    catch {
        Write-Error "SSH 执行失败: $_"
    }
}

function Set-WinUpdate {
    param([int]$val)
    # 0 = 开启, 1 = 关闭
    $statusText = if ($val -eq 1) { "Disabled" } else { "Manual" }
    $svcStart = if ($val -eq 1) { "Disabled" } else { "Manual" }
    
    try {
        Set-Service "wuauserv" -StartupType $svcStart
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        if (!(Test-Path $path)) { New-Item $path -Force | Out-Null }
        
        Set-ItemProperty $path -Name "NoAutoUpdate" -Value $val
        Write-Host "Windows 更新已设置为: $statusText" -ForegroundColor Green
    }
    catch {
        # 确保此处报错信息在一行内，避免语法错误
        Write-Error "设置 Windows 更新失败，请确保以管理员身份运行。"
    }
}

function Set-PidTask {
    Write-Host "`n>>> 创建 PID 清理任务" -ForegroundColor Cyan
    $pidFile = Join-Path $TargetDrive "shop-print-driver-1.0\bin\RUNNING_PID"
    $cmdArg = "/c if exist ""$pidFile"" del ""$pidFile"""
    
    try {
        $act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument $cmdArg
        $trig = New-ScheduledTaskTrigger -AtStartup
        Register-ScheduledTask -TaskName "CleanupPID" -Action $act -Trigger $trig -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM") -Force
        Write-Host "清理任务已创建。" -ForegroundColor Green
    }
    catch {
        Write-Error "任务创建失败: $_"
    }
}

function Get-Driver {
    Write-Host "`n>>> 下载驱动程序" -ForegroundColor Cyan
    $outFile = Join-Path $TargetDrive "SP-DRV2157Win.exe"
    try {
        Invoke-WebRequest $SprtUrl -OutFile $outFile
        Write-Host "驱动已下载至: $outFile" -ForegroundColor Green
    }
    catch {
        Write-Error "下载失败: $_"
    }
}

# --- 4. 主程序循环 ---
while ($true) {
    Write-Host "`n==============================" -ForegroundColor Gray
    Write-Host "    ChefPrint 运维工具箱      " -ForegroundColor Yellow
    Write-Host "==============================" -ForegroundColor Gray
    Write-Host "1. 安装 JDK 环境"
    Write-Host "2. 部署打印服务"
    Write-Host "3. 安装 AlwaysUp"
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
        "3" { Set-AlwaysUp }
        "4" { Set-DBAuth }
        "5" { Set-WinUpdate 1 }
        "6" { Set-WinUpdate 0 }
        "7" { Set-PidTask }
        "8" { Get-Driver }
        "q" { break }
        default { Write-Warning "无效输入" }
    }
}
