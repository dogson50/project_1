`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 模块名: npu_core_tile_4x4
// 功能  : 4x4 脉动阵列计算 tile（16 个 PE）
//
// 设计要点:
// 1) 左侧输入 a_west_i 提供 4 行向量；上侧输入 b_north_i 提供 4 列向量；
// 2) 数据在阵列中脉动传播：A 向右传、B 向下传；
// 3) 每个 PE 内部做 SIMD 点积并累加，得到 16 个输出累加值 c_mat_o；
// 4) out_valid_o 由右下角 PE 的 out_valid 给出，可作为“本轮数据已到达阵列末端”的观测信号；
// 5) clear_acc_i 同步清零全阵列累加器。
//////////////////////////////////////////////////////////////////////////////////
module npu_core_tile_4x4 #(
    parameter integer DATA_W      = 8,
    parameter integer SIMD_PER_PE = 2,
    parameter integer ACC_W       = 32
) (
    input  wire                                 clk,          // 时钟
    input  wire                                 resetn,       // 低有效复位
    input  wire                                 clear_acc_i,  // 同步清零所有 PE 累加器
    input  wire                                 in_valid_i,   // 阵列左上角输入有效
    input  wire [4*SIMD_PER_PE*DATA_W-1:0]     a_west_i,     // 西侧输入: 4 行，每行 1 个 SIMD 向量
    input  wire [4*SIMD_PER_PE*DATA_W-1:0]     b_north_i,    // 北侧输入: 4 列，每列 1 个 SIMD 向量
    output wire                                 out_valid_o,  // 右下角 PE 的有效信号
    output wire [16*ACC_W-1:0]                 c_mat_o,      // 4x4 累加结果矩阵（行优先打包）
    output wire [15:0]                          dbg_pe_valid_o // 调试: 每个 PE 的 valid（行优先）
);

    localparam integer ROWS  = 4;
    localparam integer COLS  = 4;
    localparam integer VEC_W = SIMD_PER_PE * DATA_W;

    // 拆分边界输入：a_west_vec[r] 对应第 r 行，b_north_vec[c] 对应第 c 列
    wire [VEC_W-1:0] a_west_vec [0:ROWS-1];
    wire [VEC_W-1:0] b_north_vec [0:COLS-1];

    genvar rr, cc;
    generate
        for (rr = 0; rr < ROWS; rr = rr + 1) begin : G_WEST_UNPACK
            assign a_west_vec[rr] = a_west_i[rr*VEC_W +: VEC_W];
        end
        for (cc = 0; cc < COLS; cc = cc + 1) begin : G_NORTH_UNPACK
            assign b_north_vec[cc] = b_north_i[cc*VEC_W +: VEC_W];
        end
    endgenerate

    // 阵列内部连线
    wire [VEC_W-1:0]               a_fwd [0:ROWS-1][0:COLS-1]; // A 向右
    wire [VEC_W-1:0]               b_fwd [0:ROWS-1][0:COLS-1]; // B 向下
    wire                           v_fwd [0:ROWS-1][0:COLS-1]; // valid 传播
    wire signed [ACC_W-1:0]        acc   [0:ROWS-1][0:COLS-1]; // 每个 PE 的累加值

    generate
        for (rr = 0; rr < ROWS; rr = rr + 1) begin : G_ROW
            for (cc = 0; cc < COLS; cc = cc + 1) begin : G_COL
                // 通过 generate 分支显式处理边界，避免工具对“未选中分支”做越界求值告警
                wire [VEC_W-1:0] a_in_vec;
                wire [VEC_W-1:0] b_in_vec;
                wire             pe_valid_in;

                if (rr == 0 && cc == 0) begin : G_IN_00
                    assign a_in_vec   = a_west_vec[rr];
                    assign b_in_vec   = b_north_vec[cc];
                    assign pe_valid_in = in_valid_i;
                end else if (rr == 0) begin : G_IN_TOP
                    assign a_in_vec   = a_fwd[rr][cc-1];
                    assign b_in_vec   = b_north_vec[cc];
                    assign pe_valid_in = v_fwd[rr][cc-1];
                end else if (cc == 0) begin : G_IN_LEFT
                    assign a_in_vec   = a_west_vec[rr];
                    assign b_in_vec   = b_fwd[rr-1][cc];
                    assign pe_valid_in = v_fwd[rr-1][cc];
                end else begin : G_IN_MID
                    assign a_in_vec   = a_fwd[rr][cc-1];
                    assign b_in_vec   = b_fwd[rr-1][cc];
                    assign pe_valid_in = v_fwd[rr][cc-1] & v_fwd[rr-1][cc];
                end

                npu_pe #(
                    .DATA_W(DATA_W),
                    .SIMD_PER_PE(SIMD_PER_PE),
                    .ACC_W(ACC_W)
                ) u_pe (
                    .clk(clk),
                    .resetn(resetn),
                    .clear_acc_i(clear_acc_i),
                    .in_valid_i(pe_valid_in),
                    .a_vec_i(a_in_vec),
                    .b_vec_i(b_in_vec),
                    .a_vec_o(a_fwd[rr][cc]),
                    .b_vec_o(b_fwd[rr][cc]),
                    .out_valid_o(v_fwd[rr][cc]),
                    .acc_o(acc[rr][cc])
                );

                // 矩阵输出扁平化（行优先）:
                // index = rr*4 + cc
                assign c_mat_o[(rr*COLS + cc)*ACC_W +: ACC_W] = acc[rr][cc];
                assign dbg_pe_valid_o[rr*COLS + cc]           = v_fwd[rr][cc];
            end
        end
    endgenerate

    assign out_valid_o = v_fwd[ROWS-1][COLS-1];

endmodule
