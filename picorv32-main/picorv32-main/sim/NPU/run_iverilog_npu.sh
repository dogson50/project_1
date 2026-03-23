#!/usr/bin/env bash
set -euo pipefail

wave=0
if [[ "${1:-}" == "--wave" ]]; then
  wave=1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
cd "${repo_root}"

iverilog_bin="${IVERILOG_BIN:-}"
vvp_bin="${VVP_BIN:-}"

if [[ -z "${iverilog_bin}" || -z "${vvp_bin}" ]]; then
  if command -v iverilog >/dev/null 2>&1 && command -v vvp >/dev/null 2>&1; then
    iverilog_bin="$(command -v iverilog)"
    vvp_bin="$(command -v vvp)"
  elif [[ -x "${HOME}/.local/micromamba/envs/fpga-sim/bin/iverilog" && -x "${HOME}/.local/micromamba/envs/fpga-sim/bin/vvp" ]]; then
    iverilog_bin="${HOME}/.local/micromamba/envs/fpga-sim/bin/iverilog"
    vvp_bin="${HOME}/.local/micromamba/envs/fpga-sim/bin/vvp"
  else
    echo "ERROR: cannot find iverilog/vvp. Install them or set IVERILOG_BIN/VVP_BIN." >&2
    exit 1
  fi
fi

mkdir -p .sim

"${iverilog_bin}" -g2012 -f sim/NPU/filelist_npu.f -o .sim/tb_npu_core_tile_4x4.vvp

if [[ "${wave}" -eq 1 ]]; then
  "${vvp_bin}" -N .sim/tb_npu_core_tile_4x4.vvp +vcd
  echo "Wave dumped to ${repo_root}/tb_npu_core_tile_4x4.vcd"
else
  "${vvp_bin}" -N .sim/tb_npu_core_tile_4x4.vvp
fi
