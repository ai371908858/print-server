#requires -RunAsAdministrator

# 1. 配置下载地址
$JdkUrl      = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/jdk-8u201-windows-x64.zip?sign=wqP_jGY8WUy6l3pQQS_oRQHAwF0AKuA6SWe7Mrgq7yA=:0"
$PrintUrl    = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/shop-print-driver-1.0.zip?sign=8QG1UKoSmYlAX3-vWKp5IKJMJ1rAUJv8LCqsvLJT3N0=:0"
$AlwaysUpUrl = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/AlwaysUp.zip?sign=eBYEdtTm4LnA2YACyMjmOYTEOZHwN5-OhomeROEvI8E=:0"
$SprtUrl     = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/SP-DRV2157Win.exe?sign=-v-uNwgi52bwhSu-qMAJUWnXmEN2_6M1jpc3JX1zcL0=:0"

# --- 功能模块 ---

function Set-JDK {
    Write-Host ">>> 正在下载并安装 JDK..." -ForegroundColor Cyan
    $zip = "$env:TEMP\jdk.zip"
    $dir = "$env:TEMP\jdk_temp"
    Invoke-WebRequest $JdkUrl -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath $dir -Force
    $exe = Get-ChildItem $dir -Recurse -Filter "jdk*.exe" | Select-Object -First 1
    if ($exe) { Start-Process $exe.FullName -ArgumentList "/s" -Wait }
    
    # 环境变量
    $jh = "C:\Program Files\Java\jdk1.8.0_201"
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $jh, "Machine")
    $p = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($p -notlike "*%JAVA_HOME%\bin*") {
        $p = if ($p.EndsWith(";")) { $p + "%JAVA_HOME%\bin;%JAVA_HOME%\jre\bin;" } else { $p + ";%JAVA_HOME%\bin;%JAVA_HOME%\jre\bin;" }
        [Environment]::SetEnvironmentVariable("Path", $p, "Machine")
    }
    [Environment]::SetEnvironmentVariable("CLASSPATH", ".;%JAVA_HOME%\lib;%JAVA_HOME%\lib\tools.jar", "Machine")
    Write-Host "JDK 配置完成。" -ForegroundColor Green
}

function Set-PrintService {
    Write-Host ">>> 正在下载打印服务..." -ForegroundColor Cyan
    $zip = "$env:TEMP\print.zip"
    Invoke-WebRequest $PrintUrl -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath "D:\" -Force
    $ip = Read-Host "请输入服务器IP"
    $conf = "D:\shop-print-driver-1.0\conf\env\shop.conf"
    if (Test-Path $conf) {
        (Get-Content $conf) -replace '(?<=jdbc:mysql://).*?(?=:3306)', $ip | Set-Content $conf
        Write-Host "配置文件已更新。" -ForegroundColor Green
    }
}

function Set-AlwaysUp {
    Write-Host ">>> 正在安装 AlwaysUp..." -ForegroundColor Cyan
    $zip = "$env:TEMP\au.zip"
    Invoke-WebRequest $AlwaysUpUrl -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath "$env:TEMP\au_dir" -Force
    $exe = Get-ChildItem "$env:TEMP\au_dir" -Recurse -Filter "*.exe" | Select-Object -First 1
    if ($exe) { Start-Process $exe.FullName -Wait }
    $au = "C:\Program Files (x86)\AlwaysUp\AlwaysUp.exe"
    if (Test-Path $au) {
        & $au -add "Shop-print" "D:\shop-print-driver-1.0\bin\shop-print.bat" "-Dhttp.port=8041 -Dconfig.resource=env/shop.conf -Dplay.crypto.secret=123"
        Write-Host "服务已添加。" -ForegroundColor Green
    }
}

function Set-DBAuth {
    $ip = Read-Host "请输入服务器IP"
    $pw = Read-Host "请输入数据库密码"
    $sql = "grant select,insert,update,delete on shop_cloud.* to 'hdldev'@'%' identified by '9^3jIe^0*5'; flush privileges;"
    Write-Host "尝试连接 SSH..."
    ssh root@$ip "mysql -u root -p'$pw' -e `"$sql`""
}

function Set-WinUpdate {
    param([int]$val)
    $status = if ($val -eq 1) { "Disabled" } else { "Manual" }
    Set-Service "wuauserv" -StartupType $status
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (!(Test-Path $path)) { New-Item $path -Force | Out-Null }
    Set-ItemProperty $path -Name "NoAutoUpdate" -Value $val
    Write-Host "Windows更新已设置为: $status"
}

function Set-PidTask {
    $act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c del D:\shop-print-driver-1.0\bin\RUNNING_PID"
    $trig = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName "CleanupPID" -Action $act -Trigger $trig -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM") -Force
    Write-Host "启动项清理任务已创建。"
}

# --- 主程序循环 ---
while ($true) {
    Write-Host "`n--- ChefPrint 维护菜单 ---" -ForegroundColor Yellow
    Write-Host "1. 安装JDK  2. 打印服务  3. AlwaysUp  4. 数据库授权"
    Write-Host "5. 关闭更新  6. 开启更新  7. PID清理任务  8. 下载驱动"
    Write-Host "q. 退出"
    $choice = Read-Host "请选择"
    switch ($choice) {
        "1" { Set-JDK }
        "2" { Set-PrintService }
        "3" { Set-AlwaysUp }
        "4" { Set-DBAuth }
        "5" { Set-WinUpdate 1 }
        "6" { Set-WinUpdate 0 }
        "7" { Set-PidTask }
        "8" { Invoke-WebRequest $SprtUrl -OutFile "D:\SP-DRV2157Win.exe" }
        "q" { break }
    }
}
