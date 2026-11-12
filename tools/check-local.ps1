param([switch]$Synthesis, [switch]$Map, [switch]$Formal)
$ErrorActionPreference = 'Stop'
$projectDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workspaceDir = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$edaDir = Join-Path $workspaceDir 'work/tools/eda/ucrt64/bin'
$pythonExe = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
if (!(Test-Path -LiteralPath $pythonExe) -or !(Test-Path -LiteralPath $edaDir)) {
    throw 'Workspace portable tools unavailable. Use Python and Icarus on PATH with tools/check.py instead.'
}
$savedPath = $env:PATH
$savedPythonPath = $env:PYTHONPATH
$savedCache = $env:YOWASP_CACHE_DIR
$savedMount = $env:YOWASP_MOUNT
try {
    $env:PATH = $edaDir + ';' + $env:PATH
    $env:PYTHONPATH = Join-Path $workspaceDir 'work/tools/python'
    $env:YOWASP_CACHE_DIR = Join-Path $workspaceDir 'work/tools/yowasp-cache'
    $env:YOWASP_MOUNT = '/=.'
    $common = @('--iverilog', (Join-Path $edaDir 'iverilog.exe'), '--vvp', (Join-Path $edaDir 'vvp.exe'))
    $checkArgs = $common
    if ($Synthesis) { $checkArgs += '--yosys-wasm' }
    & $pythonExe (Join-Path $projectDir 'tools/check.py') @checkArgs
    if ($LASTEXITCODE -ne 0) { throw 'Regression failed; see project work/ logs.' }
    if ($Map) {
        & $pythonExe (Join-Path $projectDir 'tools/map_cmos5l.py') @common --pdk-root (Join-Path $workspaceDir 'work/ihp-pdk')
        if ($LASTEXITCODE -ne 0) { throw 'CMOS5L mapping check failed; see project work/ logs.' }
    }
    if ($Formal) {
        & $pythonExe (Join-Path $projectDir 'tools/formal_check.py')
        if ($LASTEXITCODE -ne 0) { throw 'Bounded formal checks failed; see project work/ logs.' }
    }
} finally {
    $env:PATH = $savedPath
    $env:PYTHONPATH = $savedPythonPath
    $env:YOWASP_CACHE_DIR = $savedCache
    $env:YOWASP_MOUNT = $savedMount
}
