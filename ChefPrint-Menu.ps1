#requires -RunAsAdministrator

# --- 1. 配置下载地址 ---
$JdkUrl      = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/jdk-8u201-windows-x64.zip?sign=wqP_jGY8WUy6l3pQQS_oRQHAwF0AKuA6SWe7Mrgq7yA=:0"
$PrintUrl    = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/shop-print-driver-1.0.zip?sign=8QG1UKoSmYlAX3-vWKp5IKJMJ1rAUJv8LCqsvLJT3N0=:0"
$AlwaysUpUrl = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/AlwaysUp.zip?sign=eBYEdtTm4LnA2YACyMjmOYTEOZHwN5-OhomeROEvI8E=:0"
$SprtUrl     = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/SP-DRV2157Win.exe?sign=-v-uNwgi52bwhSu-qMAJUWnXmEN2_6M1jpc3JX1zcL0=:0"

# --- 2. 基础配置 ---
$TargetDrive = "D:\"
if (!(Test-Path $TargetDrive)) {
    Write-Warning "未检测到 D 盘，将默认安装到 C:\HDL_Print_Service"
    $TargetDrive = "C:\HDL_Print_Service"
    New-Item -ItemType Directory -Path $TargetDrive -Force | Out-Null
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
            Write-Host "正在静默安装 JDK，请稍候..." -ForegroundColor Yellow
            Start-Process $exe.FullName -ArgumentList "/s" -Wait 
        } else {
            Write-Error "在压缩包中未找到 JDK 安装程序。"
            return
        }

        # 环境变量配置
        Write-Host "配置环境变量..." -ForegroundColor Cyan
        $jh = "C:\Program Files\Java\jdk1.8.0_201"
        if (!(Test-Path $jh)) {
            Write-Warning "未检测到 JDK 安装目录 ($jh)，请检查安装是否成功。"
            return
        }

        [Environment]::SetEnvironmentVariable("JAVA_HOME", $jh, "Machine")
        
        # 优化 Path 设置逻辑，避免重复添加
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($currentPath -notlike "*%JAVA_HOME%\bin*") {
            $newPath = if ($currentPath.EndsWith(";")) { $currentPath + "%JAVA_HOME%\bin;%JAVA_HOME%\jre\bin;" } else { $currentPath + ";%JAVA_HOME%\bin;%JAVA_HOME%\jre\bin;" }
            [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
        }
        
        [Environment]::SetEnvironmentVariable("CLASSPATH", ".;%JAVA_HOME%\lib;%JAVA_HOME%\lib\tools.jar", "Machine")
        Write-Host "JDK 安装及配置完成！(注意：可能需要重启终端生效)" -ForegroundColor Green
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
        
        $ip = Read-Host "请输入服务器IP (例如 192.168.1.100)"
        # 根据实际解压路径调整，防止多一层文件夹
        $potentialPath1 = Join-Path $TargetDrive "shop-print-driver-1.0\conf\env\shop.conf"
        
        if (Test-Path $potentialPath1) {
            $confContent = Get-Content $potentialPath1
            # 正则替换：查找 jdbc:mysql:// 和 :3306 中间的内容
            $newContent = $confContent -replace '(?<=jdbc:mysql://).*?(?=:3306)', $ip 
            $newContent | Set-Content $potentialPath1
            Write-Host "配置文件已更新 ($potentialPath1)。" -ForegroundColor Green
        } else {
            Write-Warning "未找到配置文件，请手动检查路径：$TargetDrive"
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
        Write-Host "正在下载..." -ForegroundColor Gray
        Invoke-WebRequest $AlwaysUpUrl -OutFile $zipPath -UseBasicParsing
        
        Write-Host "正在解压..." -ForegroundColor Gray
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        Expand-Archive $zipPath -DestinationPath $extractDir -Force

        $installerExe = Get-ChildItem -Path $extractDir -Recurse -Filter "*.exe" | Select-Object -First 1
        if ($installerExe) {
            Write-Host "检测到安装程序，正在执行静默安装..." -ForegroundColor Yellow
            # 静默安装参数
            Start-Process -FilePath $installerExe.FullName -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait
            Write-Host "AlwaysUp 安装完成。" -ForegroundColor Green
        } else {
            Write-Error "未找到 AlwaysUp 安装程序 (exe)。"
        }
    }
    catch {
        Write-Error "AlwaysUp 安装出错: $_"
    }
    finally {
        # 清理临时文件
        Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    }
}

function Set-DBAuth {
    Write-Host "`n>>> 数据库授权配置" -ForegroundColor Cyan
    $ip = Read-Host "请输入服务器IP"
    $pw = Read-Host "请输入数据库密码(将用于MySQL命令)"
    $sql = "grant select,insert,update,delete on shop_cloud.* to 'hdldev'@'%' identified by '9^3jIe^0*5'; flush privileges;"
    
    Write-Host "注意：即将尝试 SSH 连接。如果未配置免密登录，您需要手动输入 Linux Root 密码。" -ForegroundColor Yellow
    try {
        # 注意：Windows 自带的 OpenSSH 客户端必须已安装
        ssh -o StrictHostKeyChecking=no root@$ip "mysql -u root -p'$pw' -e `"$sql`""
        Write-Host "命令发送完毕。" -ForegroundColor Green
    }
    catch {
        Write-Error "SSH 执行失败，请检查是否安装了 OpenSSH 客户端或网络连通性。"
    }
}

function Set-WinUpdate {
    param([int]$val)
    # 0 = 开启, 1 = 关闭
    $statusText = if ($val -eq 1) { "禁用 (Disabled)" } else { "手动 (Manual)" }
    $svcStart = if ($val -eq 1) { "Disabled" } else { "Manual" }
    
    try {
        Set-Service "wuauserv" -StartupType $svcStart
        
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        if (!(Test-Path $path)) { New-Item $path -Force | Out-Null }
        
        # NoAutoUpdate: 1 = 禁用自动更新
        Set-ItemProperty $path -Name "NoAutoUpdate" -Value $val
        Write-Host "Windows 更新策略已设置为: $statusText" -ForegroundColor Green
    }
    catch {
        Write-Error "设置
