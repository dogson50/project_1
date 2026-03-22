`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 文件名: tb_npu_core_cluster.v
// 功能  : npu_core_cluster（多 tile 并行）基础自检
//
// 测试策略:
// 1) CORE_NUM=2，两个 tile 同时做不同矩阵计算；
// 2) 采用脉动阵列需要的 skewed feed（7拍注入）；
// 3) 第一次注入后检查两个 tile 的 4x4 结果；
// 4) 第二次注入且不 clear，检查两个 tile 结果均翻倍。
//////////////////////////////////////////////////////////////////////////////////
module tb_npu_core_cluster;

    localparam integer CORE_NUM    = 2;
    localparam integer DATA_W      = 8;
    localparam integer SIMD_PER_PE = 2;
    localparam integer ACC_W       = 32;
    localparam integer VEC_W       = DATA_W * SIMD_PER_PE;
    localparam integer TILE_AW     = 4 * VEC_W;
    localparam integer TILE_CW     = 16 * ACC_W;

    reg                               clk;
    reg                               resetn;
    reg  [CORE_NUM-1:0]               clear_acc_i;
    reg  [CORE_NUM-1:0]               in_valid_i;
    reg  [CORE_NUM*TILE_AW-1:0]       a_west_i;
    reg  [CORE_NUM*TILE_AW-1:0]       b_north_i;
    wire [CORE_NUM-1:0]               out_valid_o;
    wire [CORE_NUM*TILE_CW-1:0]       c_mat_o;
    wire [CORE_NUM*16-1:0]            dbg_pe_valid_o;

    npu_core_cluster #(
        .CORE_NUM(CORE_NUM),
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

    // 时钟
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------ 期望值 ------------------
    // tile0:
    // A0 = [ [1,2], [3,4], [5,6], [7,8] ]
    // B0 = [ [1,0,1,2], [0,1,1,-1] ]
    // C0 =
    // [ [1,2,3,0],
    //   [3,4,7,2],
    //   [5,6,11,4],
    //   [7,8,15,6] ]
    //
    // tile1:
    // A1 = [ [1,1], [1,0], [0,1], [2,1] ]
    // B1 = [ [1,1,2,0], [1,-1,0,2] ]
    // C1 =
    // [ [2,0,2,2],
    //   [1,1,2,0],
    //   [1,-1,0,2],
    //   [3,1,4,2] ]
    reg [TILE_CW-1:0] exp_tile0_base;
    reg [TILE_CW-1:0] exp_tile1_base;
    reg [TILE_CW-1:0] exp_tile0_double;
    reg [TILE_CW-1:0] exp_tile1_double;
    integer i;

    initial begin
        exp_tile0_base = '0;
        exp_tile1_base = '0;

        // tile0 base
        exp_tile0_base[0*ACC_W +: ACC_W]  = $signed(32'sd1);
        exp_tile0_base[1*ACC_W +: ACC_W]  = $signed(32'sd2);
        exp_tile0_base[2*ACC_W +: ACC_W]  = $signed(32'sd3);
        exp_tile0_base[3*ACC_W +: ACC_W]  = $signed(32'sd0);
        exp_tile0_base[4*ACC_W +: ACC_W]  = $signed(32'sd3);
        exp_tile0_base[5*ACC_W +: ACC_W]  = $signed(32'sd4);
        exp_tile0_base[6*ACC_W +: ACC_W]  = $signed(32'sd7);
        exp_tile0_base[7*ACC_W +: ACC_W]  = $signed(32'sd2);
        exp_tile0_base[8*ACC_W +: ACC_W]  = $signed(32'sd5);
        exp_tile0_base[9*ACC_W +: ACC_W]  = $signed(32'sd6);
        exp_tile0_base[10*ACC_W +: ACC_W] = $signed(32'sd11);
        exp_tile0_base[11*ACC_W +: ACC_W] = $signed(32'sd4);
        exp_tile0_base[12*ACC_W +: ACC_W] = $signed(32'sd7);
        exp_tile0_base[13*ACC_W +: ACC_W] = $signed(32'sd8);
        exp_tile0_base[14*ACC_W +: ACC_W] = $signed(32'sd15);
        exp_tile0_base[15*ACC_W +: ACC_W] = $signed(32'sd6);

        // tile1 base
        exp_tile1_base[0*ACC_W +: ACC_W]  = $signed(32'sd2);
        exp_tile1_base[1*ACC_W +: ACC_W]  = $signed(32'sd0);
        exp_tile1_base[2*ACC_W +: ACC_W]  = $signed(32'sd2);
        exp_tile1_base[3*ACC_W +: ACC_W]  = $signed(32'sd2);
        exp_tile1_base[4*ACC_W +: ACC_W]  = $signed(32'sd1);
        exp_tile1_base[5*ACC_W +: ACC_W]  = $signed(32'sd1);
        exp_tile1_base[6*ACC_W +: ACC_W]  = $signed(32'sd2);
        exp_tile1_base[7*ACC_W +: ACC_W]  = $signed(32'sd0);
        exp_tile1_base[8*ACC_W +: ACC_W]  = $signed(32'sd1);
        exp_tile1_base[9*ACC_W +: ACC_W]  = $signed(-32'sd1);
        exp_tile1_base[10*ACC_W +: ACC_W] = $signed(32'sd0);
        exp_tile1_base[11*ACC_W +: ACC_W] = $signed(32'sd2);
        exp_tile1_base[12*ACC_W +: ACC_W] = $signed(32'sd3);
        exp_tile1_base[13*ACC_W +: ACC_W] = $signed(32'sd1);
        exp_tile1_base[14*ACC_W +: ACC_W] = $signed(32'sd4);
        exp_tile1_base[15*ACC_W +: ACC_W] = $signed(32'sd2);

        exp_tile0_double = '0;
        exp_tile1_double = '0;
        for (i = 0; i < 16; i = i + 1) begin
            exp_tile0_double[i*ACC_W +: ACC_W] = $signed(exp_tile0_base[i*ACC_W +: ACC_W]) <<< 1;
            exp_tile1_double[i*ACC_W +: ACC_W] = $signed(exp_tile1_base[i*ACC_W +: ACC_W]) <<< 1;
        end
    end

    function automatic [VEC_W-1:0] row_vec(
        input integer tile_id,
        input integer r
    );
        begin
            if (tile_id == 0) begin
                case (r)
                    0: row_vec = {8'sd2, 8'sd1};
                    1: row_vec = {8'sd4, 8'sd3};
                    2: row_vec = {8'sd6, 8'sd5};
                    3: row_vec = {8'sd8, 8'sd7};
                    default: row_vec = '0;
                endcase
            end else begin
                case (r)
                    0: row_vec = {8'sd1, 8'sd1};
                    1: row_vec = {8'sd0, 8'sd1};
                    2: row_vec = {8'sd1, 8'sd0};
                    3: row_vec = {8'sd1, 8'sd2};
                    default: row_vec = '0;
                endcase
            end
        end
    endfunction

    function automatic [VEC_W-1:0] col_vec(
        input integer tile_id,
        input integer c
    );
        begin
            if (tile_id == 0) begin
                case (c)
                    0: col_vec = {8'sd0,  8'sd1};
                    1: col_vec = {8'sd1,  8'sd0};
                    2: col_vec = {8'sd1,  8'sd1};
                    3: col_vec = {-8'sd1, 8'sd2};
                    default: col_vec = '0;
                endcase
            end else begin
                case (c)
                    0: col_vec = {8'sd1,  8'sd1};
                    1: col_vec = {-8'sd1, 8'sd1};
                    2: col_vec = {8'sd0,  8'sd2};
                    3: col_vec = {8'sd2,  8'sd0};
                    default: col_vec = '0;
                endcase
            end
        end
    endfunction

    task automatic check_one_tile(
        input [TILE_CW-1:0] got_mat,
        input [TILE_CW-1:0] exp_mat,
        input [127:0]       phase_name,
        input integer       tile_id
    );
        integer k;
        reg fail;
        reg signed [ACC_W-1:0] got_v;
        reg signed [ACC_W-1:0] exp_v;
        begin
            fail = 1'b0;
            for (k = 0; k < 16; k = k + 1) begin
                got_v = $signed(got_mat[k*ACC_W +: ACC_W]);
                exp_v = $signed(exp_mat[k*ACC_W +: ACC_W]);
                if (got_v !== exp_v) begin
                    fail = 1'b1;
                    $display("[TB][%0s][tile%0d] MISMATCH idx=%0d got=%0d exp=%0d",
                             phase_name, tile_id, k, got_v, exp_v);
                end
            end

            if (fail) begin
                $display("[TB] FAIL phase=%0s tile=%0d", phase_name, tile_id);
                $finish(1);
            end else begin
                $display("[TB] PASS phase=%0s tile=%0d", phase_name, tile_id);
            end
        end
    endtask

    task automatic drive_skewed_once_cluster;
        integer t, tile, r, c;
        reg [CORE_NUM*TILE_AW-1:0] a_tmp;
        reg [CORE_NUM*TILE_AW-1:0] b_tmp;
        reg [CORE_NUM-1:0]         v_tmp;
        begin
            for (t = 0; t <= 6; t = t + 1) begin
                a_tmp = '0;
                b_tmp = '0;
                v_tmp = '0;

                for (tile = 0; tile < CORE_NUM; tile = tile + 1) begin
                    v_tmp[tile] = 1'b1;
                    for (r = 0; r < 4; r = r + 1) begin
                        if (t == r)
                            a_tmp[tile*TILE_AW + r*VEC_W +: VEC_W] = row_vec(tile, r);
                    end
                    for (c = 0; c < 4; c = c + 1) begin
                        if (t == c)
                            b_tmp[tile*TILE_AW + c*VEC_W +: VEC_W] = col_vec(tile, c);
                    end
                end

                @(posedge clk);
                in_valid_i <= v_tmp;
                a_west_i   <= a_tmp;
                b_north_i  <= b_tmp;
            end

            @(posedge clk);
            in_valid_i <= '0;
            a_west_i   <= '0;
            b_north_i  <= '0;
        end
    endtask

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_npu_core_cluster.vcd");
            $dumpvars(0, tb_npu_core_cluster);
        end

        resetn      = 1'b0;
        clear_acc_i = '0;
        in_valid_i  = '0;
        a_west_i    = '0;
        b_north_i   = '0;

        repeat (3) @(posedge clk);
        resetn <= 1'b1;

        @(posedge clk);
        clear_acc_i <= {CORE_NUM{1'b1}};
        @(posedge clk);
        clear_acc_i <= '0;

        // 第 1 次注入
        drive_skewed_once_cluster();
        repeat (10) @(posedge clk);
        #1;
        check_one_tile(c_mat_o[0*TILE_CW +: TILE_CW], exp_tile0_base, "first", 0);
        check_one_tile(c_mat_o[1*TILE_CW +: TILE_CW], exp_tile1_base, "first", 1);

        // 第 2 次注入（不 clear，结果翻倍）
        drive_skewed_once_cluster();
        repeat (10) @(posedge clk);
        #1;
        check_one_tile(c_mat_o[0*TILE_CW +: TILE_CW], exp_tile0_double, "second_acc", 0);
        check_one_tile(c_mat_o[1*TILE_CW +: TILE_CW], exp_tile1_double, "second_acc", 1);

        $display("[TB] ALL PASS.");
        $finish(0);
    end

endmodule

