#requires -RunAsAdministrator

# --- 1. 配置下载地址 ---
$JdkUrl      = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/jdk-8u201-windows-x64.zip?sign=wqP_jGY8WUy6l3pQQS_oRQHAwF0AKuA6SWe7Mrgq7yA=:0"
$PrintUrl    = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/shop-print-driver-1.0.zip?sign=8QG1UKoSmYlAX3-vWKp5IKJMJ1rAUJv8LCqsvLJT3N0=:0"
$SprtUrl     = "https://hi.alwy.top/d/HDL%E6%96%B0%E5%BA%97/%E5%8E%A8%E6%89%93%E6%9C%8D%E5%8A%A1/SP-DRV2157Win.exe?sign=-v-uNwgi52bwhSu-qMAJUWnXmEN2_6M1jpc3JX1zcL0=:0"
# NSSM 下载地址
$NssmUrl     = "https://nssm.cc/release/nssm-2.24.zip" 

# --- 2. 基础配置 (自动检测 D 盘) ---
$TargetDrive = "D:"
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
        } else { Write-Error "未找到 JDK 安装程序。" }

        $jh = "C:\Program Files\Java\jdk1.8.0_201"
        if (Test-Path $jh) {
            [Environment]::SetEnvironmentVariable("JAVA_HOME", $jh, "Machine")
            $cp = [Environment]::GetEnvironmentVariable("Path", "Machine")
            if ($cp -notlike "*%JAVA_HOME%\bin*") {
                $newPath = if ($cp.EndsWith(";")) { $cp + "%JAVA_HOME%\bin;" } else { $cp + ";%JAVA_HOME%\bin;" }
                [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
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
        # 确保目标路径以反斜杠结尾，避免解压出错
        $dest = if ($TargetDrive.EndsWith("\")) { $TargetDrive } else { $TargetDrive + "\" }
        Expand-Archive $zip -DestinationPath $dest -Force
        
        $ip = Read-Host "请输入服务器IP"
        $conf = "$dest\shop-print-driver-1.0\conf\env\shop.conf"
        if (Test-Path $conf) {
            (Get-Content $conf) -replace '(?<=jdbc:mysql://).*?(?=:3306)', $ip | Set-Content $conf
            Write-Host "配置文件已更新。" -ForegroundColor Green
        } else { Write-Warning "未找到 shop.conf (尝试路径: $conf)。" }
    } catch { Write-Error "打印服务部署失败: $_" }
}

function Set-NssmService {
    Write-Host "`n>>> 正在配置 Shop-print 服务 (基于 NSSM)..." -ForegroundColor Cyan
    
    # 1. 准备 NSSM
    $nssmExe = "$env:TEMP\nssm.exe"
    if (!(Test-Path $nssmExe)) {
        Write-Host "正在下载 NSSM 工具..." -ForegroundColor Gray
        $zip = "$env:TEMP\nssm.zip"
        try {
            Invoke-WebRequest $NssmUrl -OutFile $zip -UseBasicParsing
            Expand-Archive $zip -DestinationPath "$env:TEMP\nssm_pkg" -Force
            # 提取 64位 版本
            $src = Get-ChildItem "$env:TEMP\nssm_pkg" -Recurse -Filter "nssm.exe" | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
            if ($src) {
                Copy-Item $src.FullName -Destination $nssmExe -Force
            } else {
                Write-Error "解压 NSSM 失败：未找到 win64/nssm.exe"
                return
            }
        } catch {
            Write-Error "NSSM 下载失败: $_"
            return
        }
    }

    # 2. 定位 Bat 文件 (修复路径拼接问题)
    # 确保 TargetDrive 不带尾部斜杠，方便拼接
    $rootPath = $TargetDrive.TrimEnd("\")
    
    # 手动构建路径数组，避免 Join-Path 兼容性问题
    $possiblePaths = @(
        "$rootPath\shop-print-driver-1.0\bin\shop-print-driver.bat",
        "$rootPath\shop-print-driver-1.0\bin\shop-print.bat",
        "$rootPath\shop-print-1.0\bin\shop-print.bat"
    )
