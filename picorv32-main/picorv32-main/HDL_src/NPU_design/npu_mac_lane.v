`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 模块名: npu_mac_lane
// 功能  : NPU 的最小乘法通道（MAC lane 中的乘法部分）
// 说明  :
// 1) 该模块只做有符号乘法，不做加法和累加；
// 2) 上层 PE 会把多个 lane 的乘积求和，再写入累加寄存器；
// 3) 采用纯组合逻辑，时序由上层寄存器边界控制。
//////////////////////////////////////////////////////////////////////////////////
module npu_mac_lane #(
    parameter integer DATA_W = 8
) (
    input  wire signed [DATA_W-1:0] a_i, // 输入操作数 A（有符号）
    input  wire signed [DATA_W-1:0] b_i, // 输入操作数 B（有符号）
    output wire signed [2*DATA_W-1:0] p_o // 乘法结果（有符号）
);

    assign p_o = a_i * b_i;

endmodule

