// ============================================================================
// AXI_Decoder
// ----------------------------------------------------------------------------
// 基于 BASE/MASK 的地址译码器：
//   命中条件 = (addr & MASK) == BASE
//
// 适用场景：
// 1) 地址块按高位分段，例如 0x0000_xxxx、0x2000_xxxx
// 2) 做最小 SoC 的片选（Program RAM / Data RAM）
// ============================================================================
module AXI_Decoder #(
    parameter [31:0] PORT0_BASE = 32'h0000_0000,
    parameter [31:0] PORT0_MASK = 32'hffff_0000,
    parameter [31:0] PORT1_BASE = 32'h2000_0000,
    parameter [31:0] PORT1_MASK = 32'hffff_0000
) (
    input  wire [31:0] addr,
    output wire        p0_sel,
    output wire        p1_sel
);

// 端口 0 命中（一般映射 Program RAM）
assign p0_sel = ((addr & PORT0_MASK) == PORT0_BASE);
// 端口 1 命中（一般映射 Data RAM）
assign p1_sel = ((addr & PORT1_MASK) == PORT1_BASE);

endmodule
