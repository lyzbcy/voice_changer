# Voice Changer Better - Windows Anaconda环境启动脚本
# 用于在Windows PowerShell环境下启动Voice Changer服务

param(
    [switch]$Help,
    [switch]$CheckEnv,
    [switch]$InstallDeps,
    [switch]$GPU,
    [switch]$CPU
)

# 颜色输出函数
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Step {
    param([string]$Message)
    Write-Host "[STEP] $Message" -ForegroundColor Magenta
}

# 显示帮助信息
function Show-Help {
    Write-Host "Voice Changer Better - Windows Anaconda环境启动脚本"
    Write-Host ""
    Write-Host "用法: .\start_anaconda.ps1 [选项]"
    Write-Host ""
    Write-Host "选项:"
    Write-Host "  -Help              显示此帮助信息"
    Write-Host "  -CheckEnv           仅检查环境，不启动服务"
    Write-Host "  -InstallDeps        安装/更新Python依赖"
    Write-Host "  -GPU                强制使用GPU模式（如果可用）"
    Write-Host "  -CPU                强制使用CPU模式"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\start_anaconda.ps1           # 启动服务"
    Write-Host "  .\start_anaconda.ps1 -CheckEnv # 检查环境"
    Write-Host "  .\start_anaconda.ps1 -InstallDeps # 安装依赖"
}

if ($Help) {
    Show-Help
    exit 0
}

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Voice Changer Better - Anaconda启动" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# 检查是否在项目根目录
if (-Not (Test-Path "server\MMVCServerSIO.py")) {
    Write-Error "未找到server\MMVCServerSIO.py，请确保在项目根目录运行此脚本"
    Write-Info "当前目录: $(Get-Location)"
    exit 1
}

# 检查conda是否可用
Write-Step "检查Anaconda安装..."
$condaPath = $null

# 检查常见的conda路径
$condaPaths = @(
    "$env:USERPROFILE\anaconda3\Scripts\conda.exe",
    "$env:USERPROFILE\miniconda3\Scripts\conda.exe",
    "$env:LOCALAPPDATA\Continuum\anaconda3\Scripts\conda.exe",
    "$env:LOCALAPPDATA\Continuum\miniconda3\Scripts\conda.exe",
    "$env:ProgramData\Anaconda3\Scripts\conda.exe",
    "$env:ProgramData\Miniconda3\Scripts\conda.exe"
)

# 首先检查PATH中是否有conda
try {
    $condaVersion = conda --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $condaPath = "conda"
        Write-Info "检测到conda: $condaVersion"
    }
} catch {
    # conda不在PATH中，继续查找
}

# 如果PATH中没有，尝试查找常见路径
if (-Not $condaPath) {
    foreach ($path in $condaPaths) {
        if (Test-Path $path) {
            $condaPath = $path
            Write-Success "找到conda: $path"
            # 添加到当前会话的PATH
            $env:Path = "$(Split-Path $path -Parent);$env:Path"
            break
        }
    }
}

if (-Not $condaPath) {
    Write-Error "未找到Anaconda安装，请先安装Anaconda或Miniconda"
    Write-Info "下载地址: https://www.anaconda.com/download"
    Write-Info "或运行部署脚本: .\auto_deploy_anaconda.ps1"
    exit 1
}

# 初始化conda（如果使用完整路径）
if ($condaPath -ne "conda") {
    $condaInitScript = Join-Path (Split-Path (Split-Path $condaPath -Parent) -Parent) "shell\condabin\conda-hook.ps1"
    if (Test-Path $condaInitScript) {
        . $condaInitScript
    }
}

# 激活环境
Write-Step "激活voice-changer-py310环境..."

# 检查环境是否存在
$envExists = $false
try {
    $envs = conda env list
    if ($envs -match "voice-changer-py310") {
        $envExists = $true
    }
} catch {
    Write-Warning "无法检查环境列表"
}

if (-Not $envExists) {
    Write-Error "voice-changer-py310环境不存在"
    Write-Info "请先运行部署脚本: .\auto_deploy_anaconda.ps1"
    exit 1
}

# 激活环境
conda activate voice-changer-py310
if ($LASTEXITCODE -ne 0) {
    Write-Error "激活conda环境失败"
    Write-Info "请手动运行: conda activate voice-changer-py310"
    exit 1
}
Write-Success "环境激活成功"

# 检查Python版本
Write-Step "检查Python版本..."
try {
    $pythonVersion = python --version 2>&1
    Write-Info "当前Python版本: $pythonVersion"
    if ($pythonVersion -match "3\.10\.") {
        Write-Success "Python版本正确 (3.10.x)"
    } else {
        Write-Warning "当前Python版本不是3.10，可能会出现兼容性问题"
    }
} catch {
    Write-Error "无法检查Python版本"
    exit 1
}

# 检查PyTorch安装
Write-Step "检查PyTorch安装状态..."
try {
    $torchVersion = python -c "import torch; print(torch.__version__)" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Info "检测到PyTorch版本: $torchVersion"
    } else {
        Write-Error "未检测到PyTorch，请先运行: .\auto_deploy_anaconda.ps1"
        exit 1
    }
} catch {
    Write-Error "未检测到PyTorch，请先运行: .\auto_deploy_anaconda.ps1"
    exit 1
}

# 检查GPU支持
$gpuSupport = $false
if (-Not $CPU) {
    Write-Step "检查GPU支持..."
    try {
        $nvidiaSmi = nvidia-smi 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Info "检测到NVIDIA GPU"
            $nvidiaSmi | Select-Object -First 3 | ForEach-Object { Write-Info $_ }
            
            # 检查PyTorch GPU支持
            $cudaAvailable = python -c "import torch; print(torch.cuda.is_available())" 2>&1
            if ($cudaAvailable -eq "True") {
                $cudaVersion = python -c "import torch; print(torch.version.cuda)" 2>&1
                Write-Success "PyTorch GPU支持已启用，CUDA版本: $cudaVersion"
                $gpuSupport = $true
            } else {
                Write-Warning "PyTorch GPU支持未启用，将使用CPU模式"
            }
        } else {
            Write-Info "未检测到NVIDIA GPU，将使用CPU模式"
        }
    } catch {
        Write-Info "未检测到NVIDIA GPU，将使用CPU模式"
    }
} else {
    Write-Info "强制使用CPU模式"
}

# 安装/更新依赖
if ($InstallDeps) {
    Write-Step "安装/更新Python依赖..."
    if (Test-Path "server\requirements.txt") {
        pip install -r server\requirements.txt
        if ($LASTEXITCODE -eq 0) {
            Write-Success "依赖安装完成"
        } else {
            Write-Warning "某些依赖安装失败，请检查错误信息"
        }
    } else {
        Write-Error "未找到server\requirements.txt文件"
        exit 1
    }
}

# 检查项目文件
Write-Step "检查项目文件..."
if (-Not (Test-Path "server\model_dir")) {
    New-Item -ItemType Directory -Path "server\model_dir" -Force | Out-Null
    Write-Info "创建模型目录: server\model_dir"
}

# 显示环境信息
Write-Host ""
Write-Info "=== 环境信息 ==="
Write-Info "Conda环境: voice-changer-py310"
Write-Info "Python版本: $(python --version)"
Write-Info "工作目录: $(Get-Location)"

try {
    $torchVersion = python -c "import torch; print(torch.__version__)" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Info "PyTorch版本: $torchVersion"
    }
} catch {
    # 忽略
}

Write-Host ""

# 如果只是检查环境，则退出
if ($CheckEnv) {
    Write-Success "环境检查完成"
    exit 0
}

# 进入服务器目录
Set-Location server

# 设置环境变量
if (($GPU -or $gpuSupport) -and -Not $CPU) {
    $env:CUDA_VISIBLE_DEVICES = "0"
    Write-Info "启用GPU模式"
} else {
    $env:CUDA_VISIBLE_DEVICES = ""
    Write-Info "使用CPU模式"
}

# 启动服务
Write-Step "启动Voice Changer服务..."
Write-Info "服务将在 http://localhost:18888 启动"
Write-Info "按 Ctrl+C 停止服务"
Write-Host ""

# 捕获中断信号
try {
    python MMVCServerSIO.py
} catch {
    Write-Error "服务启动失败"
    exit 1
} finally {
    Write-Info "服务已停止"
}

