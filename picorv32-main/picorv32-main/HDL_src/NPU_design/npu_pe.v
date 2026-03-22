`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 模块名: npu_pe
// 功能  : NPU 脉动阵列中的单个 Processing Element (PE)
// 说明  :
// 1) 一个 PE 内部包含 SIMD_PER_PE 条 MAC lane；
// 2) 每拍对输入向量 a_vec_i / b_vec_i 做点积 dot_sum；
// 3) dot_sum 在 in_valid_i 有效时累加到 acc_o；
// 4) 同时将输入向量寄存后向东/向南转发（a_vec_o / b_vec_o），用于构成脉动阵列；
// 5) clear_acc_i 为同步清零累加寄存器接口（高优先级）。
//////////////////////////////////////////////////////////////////////////////////
module npu_pe #(
    parameter integer DATA_W      = 8,
    parameter integer SIMD_PER_PE = 2,
    parameter integer ACC_W       = 32
) (
    input  wire                                 clk,         // 时钟
    input  wire                                 resetn,      // 低有效复位
    input  wire                                 clear_acc_i, // 清零累加器
    input  wire                                 in_valid_i,  // 本 PE 输入数据有效
    input  wire [SIMD_PER_PE*DATA_W-1:0]       a_vec_i,     // 输入向量 A（SIMD 打包）
    input  wire [SIMD_PER_PE*DATA_W-1:0]       b_vec_i,     // 输入向量 B（SIMD 打包）
    output reg  [SIMD_PER_PE*DATA_W-1:0]       a_vec_o,     // 向东转发的 A 向量
    output reg  [SIMD_PER_PE*DATA_W-1:0]       b_vec_o,     // 向南转发的 B 向量
    output reg                                  out_valid_o, // 转发数据有效
    output wire signed [ACC_W-1:0]             acc_o        // 当前累加结果
);

    localparam integer PROD_W = 2 * DATA_W;
    localparam integer SUM_W  = PROD_W + ((SIMD_PER_PE <= 1) ? 1 : $clog2(SIMD_PER_PE));

    // 每条 lane 的乘积
    wire signed [PROD_W-1:0] lane_prod [0:SIMD_PER_PE-1];

    genvar lane;
    generate
        for (lane = 0; lane < SIMD_PER_PE; lane = lane + 1) begin : G_LANE
            wire signed [DATA_W-1:0] lane_a = a_vec_i[lane*DATA_W +: DATA_W];
            wire signed [DATA_W-1:0] lane_b = b_vec_i[lane*DATA_W +: DATA_W];
            npu_mac_lane #(
                .DATA_W(DATA_W)
            ) u_mac_lane (
                .a_i(lane_a),
                .b_i(lane_b),
                .p_o(lane_prod[lane])
            );
        end
    endgenerate

    // SIMD 各 lane 乘积求和（点积）
    integer i;
    reg signed [SUM_W-1:0] dot_sum;
    always @* begin
        dot_sum = '0;
        for (i = 0; i < SIMD_PER_PE; i = i + 1)
            dot_sum = dot_sum + $signed(lane_prod[i]);
    end

    // 点积符号扩展到累加位宽
    wire signed [ACC_W-1:0] dot_sum_ext =
        {{(ACC_W-SUM_W){dot_sum[SUM_W-1]}}, dot_sum};

    // 累加寄存器
    reg signed [ACC_W-1:0] acc_r;
    assign acc_o = acc_r;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            acc_r       <= '0;
            a_vec_o     <= '0;
            b_vec_o     <= '0;
            out_valid_o <= 1'b0;
        end else begin
            // 脉动阵列数据转发寄存器
            a_vec_o     <= a_vec_i;
            b_vec_o     <= b_vec_i;
            out_valid_o <= in_valid_i;

            // 累加控制：clear 优先级高于 in_valid
            if (clear_acc_i)
                acc_r <= '0;
            else if (in_valid_i)
                acc_r <= acc_r + dot_sum_ext;
        end
    end

endmodule

