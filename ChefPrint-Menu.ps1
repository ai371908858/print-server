#requires -RunAsAdministrator
$ErrorActionPreference = "SilentlyContinue"

function Log($m){Write-Host "`n[$(Get-Date -Format HH:mm:ss)] $m" -ForegroundColor Cyan}
function Download($u,$o){Log "Downloading...";Invoke-WebRequest $u -OutFile $o}

# ================= JDK =================
function Install-JDK {
    Log "安装 JDK..."
    $url="https://hi.alwy.top/d/HDL新店/厨打服务/jdk-8u201-windows-x64.zip?sign=wqP_jGY8WUy6l3pQQS_oRQHAwF0AKuA6SWe7Mrgq7yA=:0"
    $zip="$env:TEMP\jdk.zip"
    $dest="C:\Program Files\Java"
    $jdk="$dest\jdk1.8.0_201"

    Download $url $zip
    Expand-Archive $zip $dest -Force

    [Environment]::SetEnvironmentVariable("JAVA_HOME",$jdk,"Machine")
    $path=[Environment]::GetEnvironmentVariable("Path","Machine")
    if($path -notlike "*JAVA_HOME*"){
        [Environment]::SetEnvironmentVariable("Path","$path;%JAVA_HOME%\bin;%JAVA_HOME%\jre\bin","Machine")
    }
    [Environment]::SetEnvironmentVariable("CLASSPATH",".;%JAVA_HOME%\lib;%JAVA_HOME%\lib\tools.jar","Machine")
    Log "JDK 安装完成"
}

# ================= 打印服务 =================
function Install-PrintService {
    $ip=Read-Host "数据库服务器IP"
    $url="https://hi.alwy.top/d/HDL新店/厨打服务/shop-print-driver-1.0.zip?sign=8QG1UKoSmYlAX3-vWKp5IKJMJ1rAUJv8LCqsvLJT3N0=:0"
    $zip="D:\shop.zip"
    $dest="D:\shop-print-driver-1.0"

    Download $url $zip
    Expand-Archive $zip "D:\" -Force

    $conf="$dest\conf\env\shop.conf"
    (Get-Content $conf) -replace 'jdbc:mysql://.*:3306','jdbc:mysql://'+$ip+':3306' | Set-Content $conf
    Log "打印服务部署完成"
}

# ================= AlwaysUp =================
function Install-AlwaysUp {
    Log "安装 AlwaysUp..."
    $url="https://hi.alwy.top/d/HDL新店/厨打服务/alwaysup.rar?sign=b_Y__u8-G5dwfmxfBu03u3JwmX8ZP40W0e2UKg-D1Ac=:0"
    $rar="$env:TEMP\a.rar"; Download $url $rar
    Invoke-WebRequest https://www.7-zip.org/a/7zr.exe -OutFile "$env:TEMP\7zr.exe"
    & "$env:TEMP\7zr.exe" x $rar "-o$env:TEMP\a" -y | Out-Null
    $setup=Get-ChildItem "$env:TEMP\a" -Filter *.exe | Select-Object -First 1
    Start-Process $setup.FullName -ArgumentList "/VERYSILENT /NORESTART" -Wait

    $cmd="C:\Program Files (x86)\AlwaysUp\AlwaysUpCmd.exe"
    if(!(Test-Path $cmd)){$cmd="C:\Program Files\AlwaysUp\AlwaysUpCmd.exe"}

    & $cmd add "Shop-print" "D:\shop-print-driver-1.0\bin\shop-print.bat"
    & $cmd set "Shop-print" arguments "-Dhttp.port=8041 -Dconfig.resource=env/shop.conf -Dplay.crypto.secret=123"
    & $cmd set "Shop-print" startmode automatic
    & $cmd start "Shop-print"

    Log "守护服务完成"
}

# ================= 数据库授权 =================
function DB-Grant {
    $ip=Read-Host "服务器IP"
    ssh root@$ip "mysql -u root -p -e `"grant select,insert,update,delete on shop_cloud.* to 'hdldev'@'%' identified by '9^3jIe^0*5';flush privileges;`""
}

# ================= Windows 更新控制 =================
function Disable-WindowsUpdate {
    Log "关闭系统更新..."
    Stop-Service wuauserv -Force
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv" Start 4
    Stop-Service usosvc -Force
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\UsoSvc" Start 4
    Stop-Service WaaSMedicSvc -Force
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" Start 4
    Log "更新已关闭"
}

function Enable-WindowsUpdate {
    Log "恢复系统更新..."
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv" Start 3
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\UsoSvc" Start 3
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" Start 3
    Start-Service wuauserv
    Log "更新已恢复"
}

# ================= PID 清理 =================
function Create-PIDTask {
    "Remove-Item D:\shop-print-driver-1.0\bin\RUNNING_PID -ErrorAction SilentlyContinue" | Out-File C:\cleanup.ps1
    schtasks /create /sc onstart /tn CleanupPID /tr "powershell -ExecutionPolicy Bypass -File C:\cleanup.ps1" /ru SYSTEM
    Log "PID 自动清理任务已创建"
}

# ================= 驱动 =================
function Download-PrinterDriver {
    Download "https://hi.alwy.top/d/HDL新店/厨打服务/SP-DRV2157Win.exe?sign=-v-uNwgi52bwhSu-qMAJUWnXmEN2_6M1jpc3JX1zcL0=:0" "D:\SP-DRV2157Win.exe"
}

# ================= 健康检查 =================
function Health-Check {
    Write-Host "`n===== 健康检查 =====" -ForegroundColor Yellow
    if(Get-Command java){Write-Host "JDK 正常" -ForegroundColor Green}else{Write-Host "未检测到 JDK" -ForegroundColor Red}
    if(Get-Service Shop-print -ErrorAction SilentlyContinue){Write-Host "守护服务存在" -ForegroundColor Green}else{Write-Host "无守护服务" -ForegroundColor Red}
    if(netstat -ano|findstr 8041){Write-Host "端口8041正常" -ForegroundColor Green}else{Write-Host "端口未监听" -ForegroundColor Red}
    $conf="D:\shop-print-driver-1.0\conf\env\shop.conf"
    if(Test-Path $conf -and (Select-String "jdbc:mysql://" $conf)){Write-Host "数据库配置存在" -ForegroundColor Green}
    if(Test-Path "D:\shop-print-driver-1.0\bin\RUNNING_PID"){Write-Host "存在残留PID" -ForegroundColor Yellow}
    Write-Host "===== 检查完成 =====`n"
}

# ================= 菜单 =================
while($true){
Write-Host "1. 安装 JDK 环境"
Write-Host "2. 部署打印服务"
Write-Host "3. 安装守护服务"
Write-Host "4. 数据库授权"
Write-Host "5. 关闭 Windows 更新"
Write-Host "6. 开启 Windows 更新"
Write-Host "7. 创建 PID 清理任务"
Write-Host "8. 下载打印机驱动"
Write-Host "9. 一键健康检查"
Write-Host "q. 退出"
$c=Read-Host "选择"
switch($c){
"1"{Install-JDK}
"2"{Install-PrintService}
"3"{Install-AlwaysUp}
"4"{DB-Grant}
"5"{Disable-WindowsUpdate}
"6"{Enable-WindowsUpdate}
"7"{Create-PIDTask}
"8"{Download-PrinterDriver}
"9"{Health-Check}
"q"{break}
}} 
