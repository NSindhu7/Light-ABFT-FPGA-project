`timescale 1ns / 1ps
// ============================================================
// tb_top.v - Quick check of the board design (same as before + traditional ABFT)
//   Run 1: no fault -> C correct, sum(C) = L = 852, no errors
//   Run 2: fault    -> column 2 wrong, Light error = 1,
//                      Traditional error = 1, faulty column = 0100 (col 2)
// ============================================================
module tb_top;
    reg  clk = 0, rst = 1, start_btn = 0, fault_sw = 0;
    wire led_done, led_ok, led_error, led_trad_error;
    wire [3:0] led_col;

    top dut (
        .clk(clk), .rst(rst), .start_btn(start_btn), .fault_sw(fault_sw),
        .data_sw(4'd0),
        .led_done(led_done), .led_ok(led_ok), .led_error(led_error),
        .led_trad_error(led_trad_error), .led_col(led_col)
    );

    always #5 clk = ~clk;

    reg [17:0] exp_c [0:3][0:3];
    integer x, y, fails;

    task run_once;
        begin
            @(posedge clk); start_btn = 1;
            repeat (5) @(posedge clk);
            start_btn = 0;
            wait (led_done == 1'b1);
            repeat (2) @(posedge clk);
        end
    endtask

    task print_c;
        begin
            for (x = 0; x < 4; x = x + 1)
                $display("   [%4d %4d %4d %4d]",
                         dut.u_core.c_mat[x][0], dut.u_core.c_mat[x][1],
                         dut.u_core.c_mat[x][2], dut.u_core.c_mat[x][3]);
        end
    endtask

    initial begin
        exp_c[0][0]=17;  exp_c[0][1]=20; exp_c[0][2]=13; exp_c[0][3]=13;
        exp_c[1][0]=45;  exp_c[1][1]=44; exp_c[1][2]=41; exp_c[1][3]=33;
        exp_c[2][0]=73;  exp_c[2][1]=68; exp_c[2][2]=69; exp_c[2][3]=53;
        exp_c[3][0]=101; exp_c[3][1]=92; exp_c[3][2]=97; exp_c[3][3]=73;
        fails = 0;

        repeat (5) @(posedge clk);
        rst = 0;

        // ---------- Run 1 ----------
        fault_sw = 0;
        run_once;
        $display("\n=== RUN 1: NO FAULT ===");
        print_c;
        for (x = 0; x < 4; x = x + 1)
            for (y = 0; y < 4; y = y + 1)
                if (dut.u_core.c_mat[x][y] !== exp_c[x][y]) fails = fails + 1;
        $display("   sum(C) = %0d  L = %0d  Light err = %b  Trad err = %b  Trad col = %b",
                 dut.u_core.u_abft.sum_c, dut.u_core.u_abft.L,
                 led_error, led_trad_error, led_col);
        if (dut.u_core.u_abft.sum_c !== 852 || dut.u_core.u_abft.L !== 852 ||
            led_error !== 1'b0 || led_trad_error !== 1'b0) begin
            $display("   RUN 1 FAILED"); fails = fails + 1;
        end else
            $display("   RUN 1 PASSED");

        // ---------- Run 2 ----------
        fault_sw = 1;
        repeat (4) @(posedge clk);
        run_once;
        $display("\n=== RUN 2: FAULT IN PE(1,2) ===");
        print_c;
        $display("   sum(C) = %0d  L = %0d  Light err = %b  Trad err = %b  Trad col = %b",
                 dut.u_core.u_abft.sum_c, dut.u_core.u_abft.L,
                 led_error, led_trad_error, led_col);
        if (dut.u_core.u_abft.sum_c !== 884 || dut.u_core.u_abft.L !== 852 ||
            led_error !== 1'b1 || led_trad_error !== 1'b1 || led_col !== 4'b0100) begin
            $display("   RUN 2 FAILED"); fails = fails + 1;
        end else
            $display("   RUN 2 PASSED: both checkers detect it, Traditional locates column 2");

        $display("\n=== %s (%0d failures) ===\n",
                 (fails == 0) ? "ALL TESTS PASSED" : "SOME TESTS FAILED", fails);
        $finish;
    end
endmodule
