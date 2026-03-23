param(
    [switch]$Wave
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Resolve-Path (Join-Path $scriptDir "..\..")
Set-Location $repoRoot

New-Item -ItemType Directory -Force ".sim" | Out-Null

iverilog -g2012 -f sim/NPU/filelist_npu_csr.f -o .sim/tb_npu_csr_if.vvp
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Wave) {
    vvp -N .sim/tb_npu_csr_if.vvp +vcd
} else {
    vvp -N .sim/tb_npu_csr_if.vvp
}
exit $LASTEXITCODE
