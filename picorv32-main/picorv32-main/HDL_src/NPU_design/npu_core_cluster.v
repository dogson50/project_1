`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 模块名: npu_core_cluster
// 功能  : 多个 4x4 tile 并行组成的 NPU 计算簇（cluster）
//
// 设计说明:
// 1) 每个 tile 独立接收自己的 A/B 边界输入，彼此并行工作；
// 2) clear_acc_i、in_valid_i 采用“每 tile 1bit”控制，便于调度器细粒度控制；
// 3) 输出 c_mat_o 为所有 tile 的结果拼接（tile0 在低位）；
// 4) 当前模块只做并行拼接与分发，不做跨 tile 的归约。
//////////////////////////////////////////////////////////////////////////////////
module npu_core_cluster #(
    parameter integer CORE_NUM    = 2,
    parameter integer DATA_W      = 8,
    parameter integer SIMD_PER_PE = 2,
    parameter integer ACC_W       = 32
) (
    input  wire                                       clk,            // 时钟
    input  wire                                       resetn,         // 低有效复位
    input  wire [CORE_NUM-1:0]                        clear_acc_i,    // 每个 tile 的累加器清零控制
    input  wire [CORE_NUM-1:0]                        in_valid_i,     // 每个 tile 的输入有效
    input  wire [CORE_NUM*4*SIMD_PER_PE*DATA_W-1:0]  a_west_i,       // 每个 tile 的西侧输入（4行）
    input  wire [CORE_NUM*4*SIMD_PER_PE*DATA_W-1:0]  b_north_i,      // 每个 tile 的北侧输入（4列）
    output wire [CORE_NUM-1:0]                        out_valid_o,    // 每个 tile 的 out_valid
    output wire [CORE_NUM*16*ACC_W-1:0]              c_mat_o,        // 每个 tile 的 4x4 输出矩阵
    output wire [CORE_NUM*16-1:0]                     dbg_pe_valid_o  // 每个 tile 内 16 个 PE 的 valid
);

    localparam integer TILE_AW = 4 * SIMD_PER_PE * DATA_W;
    localparam integer TILE_CW = 16 * ACC_W;
    localparam integer TILE_DW = 16;

    genvar t;
    generate
        for (t = 0; t < CORE_NUM; t = t + 1) begin : G_TILE
            npu_core_tile_4x4 #(
                .DATA_W(DATA_W),
                .SIMD_PER_PE(SIMD_PER_PE),
                .ACC_W(ACC_W)
            ) u_tile (
                .clk(clk),
                .resetn(resetn),
                .clear_acc_i(clear_acc_i[t]),
                .in_valid_i(in_valid_i[t]),
                .a_west_i(a_west_i[t*TILE_AW +: TILE_AW]),
                .b_north_i(b_north_i[t*TILE_AW +: TILE_AW]),
                .out_valid_o(out_valid_o[t]),
                .c_mat_o(c_mat_o[t*TILE_CW +: TILE_CW]),
                .dbg_pe_valid_o(dbg_pe_valid_o[t*TILE_DW +: TILE_DW])
            );
        end
    endgenerate

endmodule

