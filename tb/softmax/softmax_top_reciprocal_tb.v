`timescale 1ns/1ps

module softmax_top_reciprocal_tb;

    // ============================================================
    // SIGNALS
    // ============================================================

    reg clk;
    reg rst;
    reg start;

    reg [31:0] x0;
    reg [31:0] x1;
    reg [31:0] x2;
    reg [31:0] x3;

    wire [31:0] reciprocal;
    wire        done;

    integer pass_count;
    integer fail_count;

    real reciprocal_real;
    real expected_real;
    real error;


    // ============================================================
    // DUT
    // ============================================================

    softmax_top dut (
        .clk        (clk),
        .rst        (rst),
        .start      (start),

        .x0         (x0),
        .x1         (x1),
        .x2         (x2),
        .x3         (x3),

        .reciprocal (reciprocal),
        .done       (done)
    );


    // ============================================================
    // CLOCK
    // ============================================================

    initial
    begin

        clk = 1'b0;

        forever
            #5 clk = ~clk;

    end


    // ============================================================
    // VCD
    // ============================================================

    initial
    begin

        $dumpfile("softmax_top_reciprocal_tb.vcd");

        $dumpvars(0, softmax_top_reciprocal_tb);

    end


    // ============================================================
    // MONITOR
    // ============================================================

    always @(posedge clk)
    begin

        $display(
            "TIME = %0t | STATE = %0d | START = %b | EXP_DONE = %b | RECIP = %h | DONE = %b",
            $time,
            dut.state,
            start,
            dut.exp_done,
            reciprocal,
            done
        );

    end


    // ============================================================
    // MAIN TEST
    // ============================================================

    initial
    begin

        pass_count = 0;
        fail_count = 0;


        // --------------------------------------------------------
        // INPUTS
        // --------------------------------------------------------

        x0 = 32'h3F800000;     // 1.0
        x1 = 32'h40000000;     // 2.0
        x2 = 32'h40400000;     // 3.0
        x3 = 32'h40800000;     // 4.0


        rst   = 1'b1;
        start = 1'b0;


        // --------------------------------------------------------
        // HEADER
        // --------------------------------------------------------

        $display("");
        $display("==============================================");
        $display(" SOFTMAX TOP - PHASE 5C-3A");
        $display("==============================================");

        $display("");
        $display("INPUTS:");
        $display("x0 = 1.0");
        $display("x1 = 2.0");
        $display("x2 = 3.0");
        $display("x3 = 4.0");


        // --------------------------------------------------------
        // RESET
        // --------------------------------------------------------

        #12;

        rst = 1'b0;


        // --------------------------------------------------------
        // START
        // --------------------------------------------------------

        #8;

        start = 1'b1;

        $display("");
        $display("START asserted");

        #10;

        start = 1'b0;

        $display("START deasserted");


        // --------------------------------------------------------
        // WAIT FOR EXP SUM
        // --------------------------------------------------------

        wait(dut.exp_done == 1'b1);


        $display("");
        $display("----------------------------------------------");
        $display("       EXP + ACCUMULATOR COMPLETE");
        $display("----------------------------------------------");

        $display(
            "EXP SUM HEX = %h",
            dut.exp_sum
        );

        $display(
            "EXP SUM REAL = %f",
            fp32_to_real(dut.exp_sum)
        );

        $display(
            "EXP DONE = %b",
            dut.exp_done
        );


        // --------------------------------------------------------
        // CHECK EXP SUM
        // --------------------------------------------------------

        if (
            relative_error(
                fp32_to_real(dut.exp_sum),
                84.79102488
            ) <= 0.005
        )
        begin

            $display("PASS : EXP SUM within 0.5%%");

            pass_count = pass_count + 1;

        end

        else
        begin

            $display("FAIL : EXP SUM outside tolerance");

            fail_count = fail_count + 1;

        end


        // --------------------------------------------------------
        // WAIT FOR TOP DONE
        // --------------------------------------------------------

        wait(done == 1'b1);


        // --------------------------------------------------------
        // RECIPROCAL RESULT
        // --------------------------------------------------------

        reciprocal_real = fp32_to_real(reciprocal);

        expected_real = 0.01179370;

        error = reciprocal_real - expected_real;

        if (error < 0.0)
            error = -error;

        error = error / expected_real;


        $display("");
        $display("----------------------------------------------");
        $display("             RECIPROCAL RESULT");
        $display("----------------------------------------------");

        $display(
            "RECIPROCAL HEX = %h",
            reciprocal
        );

        $display(
            "RECIPROCAL     = %12.8f",
            reciprocal_real
        );

        $display(
            "EXPECTED       = %12.8f",
            expected_real
        );

        $display(
            "ERROR          = %8.4f%%",
            error * 100.0
        );


        // --------------------------------------------------------
        // CHECK RECIPROCAL
        // --------------------------------------------------------

        if (error <= 0.005)
        begin

            $display("PASS : Reciprocal within 0.5%%");

            pass_count = pass_count + 1;

        end

        else
        begin

            $display("FAIL : Reciprocal outside tolerance");

            fail_count = fail_count + 1;

        end


        // --------------------------------------------------------
        // CHECK DONE
        // --------------------------------------------------------

        if (done == 1'b1)
        begin

            $display("PASS : DONE asserted");

            pass_count = pass_count + 1;

        end

        else
        begin

            $display("FAIL : DONE not asserted");

            fail_count = fail_count + 1;

        end


        // --------------------------------------------------------
        // SUMMARY
        // --------------------------------------------------------

        $display("");
        $display("==============================================");
        $display("                TEST SUMMARY");
        $display("==============================================");

        $display("PASS COUNT = %0d", pass_count);
        $display("FAIL COUNT = %0d", fail_count);

        $display("");

        if (fail_count == 0)
            $display("OVERALL RESULT : PASS");
        else
            $display("OVERALL RESULT : FAIL");

        $display("");

        $display("==============================================");
        $display("       PHASE 5C-3A TEST COMPLETE");
        $display("==============================================");

        #20;

        $finish;

    end


    // ============================================================
    // FP32 -> REAL
    // ============================================================

    function real fp32_to_real;

        input [31:0] value;

        reg        s;
        reg [7:0]  e;
        reg [22:0] f;

        real mantissa;
        real weight;

        integer unbiased_exp;
        integer i;
        integer j;

        begin

            s = value[31];
            e = value[30:23];
            f = value[22:0];


            if ((e == 0) && (f == 0))
            begin

                fp32_to_real = 0.0;

            end

            else if (e != 0)
            begin

                mantissa = 1.0;
                weight   = 0.5;


                for (i = 22; i >= 0; i = i - 1)
                begin

                    if (f[i])
                        mantissa = mantissa + weight;

                    weight = weight / 2.0;

                end


                unbiased_exp = e - 127;


                if (unbiased_exp > 0)
                begin

                    for (j = 0; j < unbiased_exp; j = j + 1)
                        mantissa = mantissa * 2.0;

                end

                else if (unbiased_exp < 0)
                begin

                    for (j = 0; j > unbiased_exp; j = j - 1)
                        mantissa = mantissa / 2.0;

                end


                if (s)
                    mantissa = -mantissa;


                fp32_to_real = mantissa;

            end

            else
            begin

                fp32_to_real = 0.0;

            end

        end

    endfunction


    // ============================================================
    // RELATIVE ERROR
    // ============================================================

    function real relative_error;

        input real actual;
        input real expected;

        real error;

        begin

            error = actual - expected;

            if (error < 0.0)
                error = -error;


            if (expected < 0.0)
                expected = -expected;


            if (expected == 0.0)
                relative_error = error;

            else
                relative_error = error / expected;

        end

    endfunction

endmodule