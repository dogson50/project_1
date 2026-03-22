`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 文件名: tb_npu_core_tile_4x4.v
// 功能  : npu_core_tile_4x4 的基础功能仿真
//
// 测试内容:
// 1) 清零后采用“斜向注入（skewed feed）”驱动 7 拍，检查 4x4 输出矩阵；
// 2) 在不 clear 的情况下重复一次同样驱动，检查累加是否翻倍；
// 3) 支持 +vcd 参数导出波形。
//////////////////////////////////////////////////////////////////////////////////
module tb_npu_core_tile_4x4;

    localparam integer DATA_W      = 8;
    localparam integer SIMD_PER_PE = 2;
    localparam integer ACC_W       = 32;
    localparam integer VEC_W       = DATA_W * SIMD_PER_PE;

    reg                             clk;
    reg                             resetn;
    reg                             clear_acc_i;
    reg                             in_valid_i;
    reg  [4*VEC_W-1:0]              a_west_i;
    reg  [4*VEC_W-1:0]              b_north_i;
    wire                            out_valid_o;
    wire [16*ACC_W-1:0]             c_mat_o;
    wire [15:0]                     dbg_pe_valid_o;

    // 被测模块
    npu_core_tile_4x4 #(
        .DATA_W(DATA_W),
        .SIMD_PER_PE(SIMD_PER_PE),
        .ACC_W(ACC_W)
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .clear_acc_i(clear_acc_i),
        .in_valid_i(in_valid_i),
        .a_west_i(a_west_i),
        .b_north_i(b_north_i),
        .out_valid_o(out_valid_o),
        .c_mat_o(c_mat_o),
        .dbg_pe_valid_o(dbg_pe_valid_o)
    );

    // 10ns 时钟周期
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // 期望矩阵（行优先）
    // A = [ [1,2], [3,4], [5,6], [7,8] ]
    // B = [ [1,0,1,2], [0,1,1,-1] ]   （按列喂给北侧）
    // C = A * B
    reg [16*ACC_W-1:0] exp_base_mat;
    reg [16*ACC_W-1:0] exp_double_mat;

    integer idx;
    initial begin
        exp_base_mat = '0;
        // row0
        exp_base_mat[0*ACC_W +: ACC_W]  = $signed(32'sd1);
        exp_base_mat[1*ACC_W +: ACC_W]  = $signed(32'sd2);
        exp_base_mat[2*ACC_W +: ACC_W]  = $signed(32'sd3);
        exp_base_mat[3*ACC_W +: ACC_W]  = $signed(32'sd0);
        // row1
        exp_base_mat[4*ACC_W +: ACC_W]  = $signed(32'sd3);
        exp_base_mat[5*ACC_W +: ACC_W]  = $signed(32'sd4);
        exp_base_mat[6*ACC_W +: ACC_W]  = $signed(32'sd7);
        exp_base_mat[7*ACC_W +: ACC_W]  = $signed(32'sd2);
        // row2
        exp_base_mat[8*ACC_W +: ACC_W]  = $signed(32'sd5);
        exp_base_mat[9*ACC_W +: ACC_W]  = $signed(32'sd6);
        exp_base_mat[10*ACC_W +: ACC_W] = $signed(32'sd11);
        exp_base_mat[11*ACC_W +: ACC_W] = $signed(32'sd4);
        // row3
        exp_base_mat[12*ACC_W +: ACC_W] = $signed(32'sd7);
        exp_base_mat[13*ACC_W +: ACC_W] = $signed(32'sd8);
        exp_base_mat[14*ACC_W +: ACC_W] = $signed(32'sd15);
        exp_base_mat[15*ACC_W +: ACC_W] = $signed(32'sd6);

        exp_double_mat = '0;
        for (idx = 0; idx < 16; idx = idx + 1)
            exp_double_mat[idx*ACC_W +: ACC_W] =
                $signed(exp_base_mat[idx*ACC_W +: ACC_W]) <<< 1;
    end

    task automatic check_matrix(
        input [16*ACC_W-1:0] mat,
        input [16*ACC_W-1:0] exp_mat,
        input [255:0] phase_name
    );
        integer i;
        reg fail;
        reg signed [ACC_W-1:0] got;
        begin
            fail = 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                got = $signed(mat[i*ACC_W +: ACC_W]);
                if (got !== $signed(exp_mat[i*ACC_W +: ACC_W])) begin
                    fail = 1'b1;
                    $display("[TB][%0s] MISMATCH idx=%0d got=%0d exp=%0d",
                             phase_name, i, got, $signed(exp_mat[i*ACC_W +: ACC_W]));
                end
            end

            if (fail) begin
                $display("[TB] FAIL at phase: %0s", phase_name);
                $finish(1);
            end else begin
                $display("[TB] PASS phase: %0s", phase_name);
            end
        end
    endtask

    // row 向量: [1,2], [3,4], [5,6], [7,8]
    function automatic [VEC_W-1:0] row_vec(input integer r);
        begin
            case (r)
                0: row_vec = {8'sd2, 8'sd1};
                1: row_vec = {8'sd4, 8'sd3};
                2: row_vec = {8'sd6, 8'sd5};
                3: row_vec = {8'sd8, 8'sd7};
                default: row_vec = '0;
            endcase
        end
    endfunction

    // col 向量: [1,0], [0,1], [1,1], [2,-1]
    function automatic [VEC_W-1:0] col_vec(input integer c);
        begin
            case (c)
                0: col_vec = {8'sd0,  8'sd1};
                1: col_vec = {8'sd1,  8'sd0};
                2: col_vec = {8'sd1,  8'sd1};
                3: col_vec = {-8'sd1, 8'sd2};
                default: col_vec = '0;
            endcase
        end
    endfunction

    // 脉动阵列 token 斜向注入:
    // 第 t 拍:
    // - 仅当 t==r 时在第 r 行西侧注入 row_vec(r)
    // - 仅当 t==c 时在第 c 列北侧注入 col_vec(c)
    // 这样 PE(r,c) 会在 t=r+c 拍收到一次非零 pair。
    task automatic drive_skewed_once;
        integer t, r, c;
        reg [4*VEC_W-1:0] a_tmp;
        reg [4*VEC_W-1:0] b_tmp;
        begin
            for (t = 0; t <= 6; t = t + 1) begin
                a_tmp = '0;
                b_tmp = '0;

                for (r = 0; r < 4; r = r + 1) begin
                    if (t == r)
                        a_tmp[r*VEC_W +: VEC_W] = row_vec(r);
                end
                for (c = 0; c < 4; c = c + 1) begin
                    if (t == c)
                        b_tmp[c*VEC_W +: VEC_W] = col_vec(c);
                end

                @(posedge clk);
                in_valid_i <= 1'b1;
                a_west_i   <= a_tmp;
                b_north_i  <= b_tmp;
            end

            @(posedge clk);
            in_valid_i <= 1'b0;
            a_west_i   <= '0;
            b_north_i  <= '0;
        end
    endtask

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_npu_core_tile_4x4.vcd");
            $dumpvars(0, tb_npu_core_tile_4x4);
        end

        resetn      = 1'b0;
        clear_acc_i = 1'b0;
        in_valid_i  = 1'b0;
        a_west_i    = '0;
        b_north_i   = '0;

        repeat (3) @(posedge clk);
        resetn <= 1'b1;

        // 先清零一次累加器
        @(posedge clk);
        clear_acc_i <= 1'b1;
        @(posedge clk);
        clear_acc_i <= 1'b0;

        // 第 1 轮斜向注入
        drive_skewed_once();
        repeat (10) @(posedge clk);
        #1;
        check_matrix(c_mat_o, exp_base_mat, "first_inject");

        // 第 2 轮斜向注入（不 clear，结果应翻倍）
        drive_skewed_once();
        repeat (10) @(posedge clk);
        #1;
        check_matrix(c_mat_o, exp_double_mat, "second_inject_accumulate");

        $display("[TB] ALL PASS.");
        $finish(0);
    end

endmodule
