# Voice Changer Better - Windows Anaconda自动化部署脚本
# 用于在Windows PowerShell环境下自动部署Anaconda环境

param(
    [switch]$Help,
    [switch]$CheckOnly
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
    Write-Host "Voice Changer Better - Windows Anaconda自动化部署脚本"
    Write-Host ""
    Write-Host "用法: .\auto_deploy_anaconda.ps1 [选项]"
    Write-Host ""
    Write-Host "选项:"
    Write-Host "  -Help              显示此帮助信息"
    Write-Host "  -CheckOnly         仅检查环境，不执行部署"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\auto_deploy_anaconda.ps1           # 执行完整部署"
    Write-Host "  .\auto_deploy_anaconda.ps1 -CheckOnly # 仅检查环境"
}

if ($Help) {
    Show-Help
    exit 0
}

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Voice Changer Better - Anaconda部署" -ForegroundColor Cyan
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
        Write-Success "检测到conda: $condaVersion"
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
    Write-Info "或使用Miniconda: https://docs.conda.io/en/latest/miniconda.html"
    exit 1
}

if ($CheckOnly) {
    Write-Info "环境检查完成"
    exit 0
}

# 检查环境是否已存在
Write-Step "检查conda环境..."
$envExists = $false
try {
    $envs = conda env list
    if ($envs -match "voice-changer-py310") {
        $envExists = $true
        Write-Info "检测到已存在的voice-changer-py310环境"
        $response = Read-Host "是否重新创建环境？(y/N)"
        if ($response -eq "y" -or $response -eq "Y") {
            Write-Info "删除现有环境..."
            conda env remove -n voice-changer-py310 -y
            $envExists = $false
        } else {
            Write-Info "使用现有环境"
        }
    }
} catch {
    Write-Warning "无法检查环境列表"
}

# 创建环境（如果不存在）
if (-Not $envExists) {
    Write-Step "创建Python 3.10环境..."
    conda create -n voice-changer-py310 python=3.10 -y
    if ($LASTEXITCODE -ne 0) {
        Write-Error "创建conda环境失败"
        exit 1
    }
    Write-Success "环境创建成功"
}

# 激活环境并安装依赖
Write-Step "激活环境并安装依赖..."

# 初始化conda（如果使用完整路径）
if ($condaPath -ne "conda") {
    $condaInitScript = Join-Path (Split-Path (Split-Path $condaPath -Parent) -Parent) "shell\condabin\conda-hook.ps1"
    if (Test-Path $condaInitScript) {
        . $condaInitScript
    }
}

# 激活环境
conda activate voice-changer-py310
if ($LASTEXITCODE -ne 0) {
    Write-Error "激活conda环境失败"
    Write-Info "请手动运行: conda activate voice-changer-py310"
    exit 1
}

# 检查PyTorch是否已安装
Write-Step "检查PyTorch安装状态..."
$pytorchInstalled = $false
try {
    $torchCheck = python -c "import torch; print(torch.__version__)" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $pytorchInstalled = $true
        Write-Info "检测到PyTorch版本: $torchCheck"
    }
} catch {
    # PyTorch未安装
}

# 检测GPU支持
$hasGPU = $false
try {
    $nvidiaSmi = nvidia-smi 2>&1
    if ($LASTEXITCODE -eq 0) {
        $hasGPU = $true
        Write-Info "检测到NVIDIA GPU"
        Write-Info $nvidiaSmi | Select-Object -First 5
    }
} catch {
    Write-Info "未检测到NVIDIA GPU，将使用CPU版本"
}

# 安装PyTorch（如果未安装或需要更新）
if (-Not $pytorchInstalled) {
    Write-Step "安装PyTorch..."
    if ($hasGPU) {
        Write-Info "安装PyTorch GPU版本..."
        # 使用conda安装PyTorch GPU版本
        conda install pytorch torchvision torchaudio pytorch-cuda=11.8 -c pytorch -c nvidia -y
    } else {
        Write-Info "安装PyTorch CPU版本..."
        conda install pytorch torchvision torchaudio cpuonly -c pytorch -y
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "conda安装PyTorch失败，尝试使用pip..."
        if ($hasGPU) {
            pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
        } else {
            pip install torch torchvision torchaudio
        }
    }
}

# 安装项目依赖
Write-Step "安装项目依赖..."
if (Test-Path "server\requirements.txt") {
    Write-Info "从requirements.txt安装依赖..."
    pip install -r server\requirements.txt
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "某些依赖安装失败，请检查错误信息"
    } else {
        Write-Success "依赖安装完成"
    }
} else {
    Write-Error "未找到server\requirements.txt文件"
    exit 1
}

# 创建必要的目录
Write-Step "创建必要的目录..."
$directories = @(
    "server\model_dir",
    "server\pretrain",
    "server\tmp_dir"
)

foreach ($dir in $directories) {
    if (-Not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Info "创建目录: $dir"
    }
}

# 显示环境信息
Write-Host ""
Write-Info "=== 部署完成 ==="
Write-Info "Conda环境: voice-changer-py310"
Write-Info "Python版本: $(python --version)"

try {
    $torchVersion = python -c "import torch; print(torch.__version__)" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Info "PyTorch版本: $torchVersion"
        
        if ($hasGPU) {
            $cudaAvailable = python -c "import torch; print(torch.cuda.is_available())" 2>&1
            if ($cudaAvailable -eq "True") {
                Write-Success "GPU支持已启用"
            } else {
                Write-Warning "GPU支持未启用，请检查CUDA安装"
            }
        }
    }
} catch {
    Write-Warning "无法检查PyTorch版本"
}

Write-Host ""
Write-Success "部署完成！"
Write-Info "使用以下命令启动服务:"
Write-Info "  .\start_anaconda.ps1"
Write-Info "或手动启动:"
Write-Info "  conda activate voice-changer-py310"
Write-Info "  cd server"
Write-Info "  python MMVCServerSIO.py"

