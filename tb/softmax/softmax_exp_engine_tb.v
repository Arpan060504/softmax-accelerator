`timescale 1ns/1ps

module softmax_exp_engine_tb;

    reg clk;
    reg rst;
    reg start;

    reg [31:0] x0;
    reg [31:0] x1;
    reg [31:0] x2;
    reg [31:0] x3;

    wire [31:0] exp_value;
    wire        done;
    wire        exp_valid;

    integer pass_count;
    integer fail_count;

    real actual;
    real expected;
    real error;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------

    softmax_exp_engine dut (
        .clk       (clk),
        .rst       (rst),
        .start     (start),

        .x0        (x0),
        .x1        (x1),
        .x2        (x2),
        .x3        (x3),

        .exp_value (exp_value),
        .done      (done),
        .exp_valid (exp_valid)
    );

    // ------------------------------------------------------------
    // CLOCK
    // ------------------------------------------------------------

    initial
    begin
        clk = 1'b0;

        forever
            #5 clk = ~clk;
    end

    // ------------------------------------------------------------
    // FP32 -> REAL
    // ------------------------------------------------------------

    function real fp32_to_real;

        input [31:0] value;

        reg        sign;
        reg [7:0]  exponent;
        reg [22:0] fraction;

        real mantissa;
        real weight;

        integer unbiased_exp;
        integer i;
        integer j;

        begin

            sign     = value[31];
            exponent = value[30:23];
            fraction = value[22:0];

            // ----------------------------------------------------
            // ZERO
            // ----------------------------------------------------

            if ((exponent == 0) && (fraction == 0))
            begin
                fp32_to_real = 0.0;
            end

            // ----------------------------------------------------
            // NORMAL NUMBER
            // ----------------------------------------------------

            else if (exponent != 0)
            begin

                mantissa = 1.0;
                weight   = 0.5;

                for (i = 22; i >= 0; i = i - 1)
                begin
                    if (fraction[i])
                        mantissa = mantissa + weight;

                    weight = weight / 2.0;
                end

                unbiased_exp = exponent - 127;

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

                if (sign)
                    mantissa = -mantissa;

                fp32_to_real = mantissa;

            end

            // ----------------------------------------------------
            // SUBNORMAL
            // ----------------------------------------------------

            else
            begin

                mantissa = 0.0;
                weight   = 0.5;

                for (i = 22; i >= 0; i = i - 1)
                begin
                    if (fraction[i])
                        mantissa = mantissa + weight;

                    weight = weight / 2.0;
                end

                for (j = 0; j < 126; j = j + 1)
                    mantissa = mantissa / 2.0;

                if (sign)
                    mantissa = -mantissa;

                fp32_to_real = mantissa;

            end

        end

    endfunction

    // ------------------------------------------------------------
    // CHECK RESULT
    // ------------------------------------------------------------

    task check_result;

        input integer index;
        input real expected_value;

        begin

            actual = fp32_to_real(exp_value);

            error = actual - expected_value;

            if (error < 0.0)
                error = -error;

            error = error / expected_value;

            if (error <= 0.005)
            begin

                pass_count = pass_count + 1;

                $display(
                    "PASS : INDEX = %0d | EXP = %12.8f | EXPECTED = %12.8f | ERROR = %8.4f%%",
                    index,
                    actual,
                    expected_value,
                    error * 100.0
                );

            end

            else
            begin

                fail_count = fail_count + 1;

                $display(
                    "FAIL : INDEX = %0d | EXP = %12.8f | EXPECTED = %12.8f | ERROR = %8.4f%%",
                    index,
                    actual,
                    expected_value,
                    error * 100.0
                );

            end

        end

    endtask

    // ------------------------------------------------------------
    // MAIN TEST
    // ------------------------------------------------------------

    initial
    begin

        pass_count = 0;
        fail_count = 0;

        // --------------------------------------------------------
        // INPUTS
        // --------------------------------------------------------

        x0 = 32'h3F800000;   // 1.0
        x1 = 32'h40000000;   // 2.0
        x2 = 32'h40400000;   // 3.0
        x3 = 32'h40800000;   // 4.0

        rst   = 1'b1;
        start = 1'b0;

        $display("");
        $display("==============================================");
        $display("       SOFTMAX EXP ENGINE - PHASE 3B");
        $display("==============================================");
        $display("");

        // --------------------------------------------------------
        // RESET
        // --------------------------------------------------------

        #12;

        rst = 1'b0;

        // --------------------------------------------------------
        // START
        // --------------------------------------------------------

        #3;

        start = 1'b1;

        @(posedge clk);
        #1;

        start = 1'b0;

        // --------------------------------------------------------
        // WAIT FOR EXP(x0)
        // --------------------------------------------------------

        @(posedge clk);
        #1;

        if (exp_valid)
        begin
            $display(
                "INDEX = 0 | X = %f | EXP_VALID = 1",
                fp32_to_real(x0)
            );

            check_result(0, 2.71828183);
        end
        else
        begin
            $display("FAIL : exp_valid missing for x0");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------
        // EXP(x1)
        // --------------------------------------------------------

        @(posedge clk);
        #1;

        if (exp_valid)
        begin
            $display(
                "INDEX = 1 | X = %f | EXP_VALID = 1",
                fp32_to_real(x1)
            );

            check_result(1, 7.38905610);
        end
        else
        begin
            $display("FAIL : exp_valid missing for x1");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------
        // EXP(x2)
        // --------------------------------------------------------

        @(posedge clk);
        #1;

        if (exp_valid)
        begin
            $display(
                "INDEX = 2 | X = %f | EXP_VALID = 1",
                fp32_to_real(x2)
            );

            check_result(2, 20.08553692);
        end
        else
        begin
            $display("FAIL : exp_valid missing for x2");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------
        // EXP(x3)
        // --------------------------------------------------------

        @(posedge clk);
        #1;

        if (exp_valid)
        begin
            $display(
                "INDEX = 3 | X = %f | EXP_VALID = 1",
                fp32_to_real(x3)
            );

            check_result(3, 54.59815003);
        end
        else
        begin
            $display("FAIL : exp_valid missing for x3");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------
        // DONE
        // --------------------------------------------------------

        @(posedge clk);
        #1;

        $display("");
        $display("DONE = %b", done);

        if (done)
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
        $display("       PHASE 3B TEST COMPLETE");
        $display("==============================================");

        $finish;

    end

endmodule