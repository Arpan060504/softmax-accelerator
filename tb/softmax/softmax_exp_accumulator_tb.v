`timescale 1ns/1ps

module softmax_exp_accumulator_tb;

    // ============================================================
    // CLOCK / CONTROL
    // ============================================================

    reg clk;
    reg rst;
    reg start;


    // ============================================================
    // INPUTS
    // ============================================================

    reg [31:0] x0;
    reg [31:0] x1;
    reg [31:0] x2;
    reg [31:0] x3;


    // ============================================================
    // RAM READ INTERFACE
    // ============================================================

    reg [1:0] read_addr;

    wire [31:0] exp_out;


    // ============================================================
    // OUTPUTS
    // ============================================================

    wire [31:0] sum;
    wire        done;


    // ============================================================
    // DUT
    // ============================================================

    softmax_exp_accumulator dut (

        .clk       (clk),
        .rst       (rst),
        .start     (start),

        .x0        (x0),
        .x1        (x1),
        .x2        (x2),
        .x3        (x3),

        .read_addr (read_addr),

        .sum       (sum),
        .done      (done),
        .exp_out   (exp_out)

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
    // FP32 -> REAL
    // ============================================================

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
            // NORMAL
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


    // ============================================================
    // REAL VARIABLES
    // ============================================================

    real sum_real;
    real expected_sum;
    real sum_error;
    real sum_relative_error;

    real exp_real;
    real expected_exp;
    real exp_error;
    real exp_relative_error;

    real tolerance;

    integer pass_count;
    integer fail_count;

    integer i;


    // ============================================================
    // TEST
    // ============================================================

    initial
    begin

        // --------------------------------------------------------
        // INITIALIZATION
        // --------------------------------------------------------

        rst       = 1'b1;
        start     = 1'b0;

        x0        = 32'h3F800000;   // 1.0
        x1        = 32'h40000000;   // 2.0
        x2        = 32'h40400000;   // 3.0
        x3        = 32'h40800000;   // 4.0

        read_addr = 2'd0;

        pass_count = 0;
        fail_count = 0;

        tolerance = 0.005;          // 0.5%


        // --------------------------------------------------------
        // HEADER
        // --------------------------------------------------------

        $display("");
        $display("==============================================");
        $display(" SOFTMAX EXP + ACCUMULATOR - RAM INTERFACE");
        $display("==============================================");
        $display("");

        $display("Tolerance = 0.5%%");
        $display("");


        // --------------------------------------------------------
        // RESET
        // --------------------------------------------------------

        #20;

        rst = 1'b0;

        #10;


        // --------------------------------------------------------
        // START
        // --------------------------------------------------------

        start = 1'b1;

        $display("TIME = %0t | START asserted", $time);

        #10;

        start = 1'b0;


        // --------------------------------------------------------
        // WAIT FOR ACCUMULATION
        // --------------------------------------------------------

        wait(done == 1'b1);

        #10;


        // ========================================================
        // SUM TEST
        // ========================================================

        $display("");
        $display("----------------------------------------------");
        $display("              ACCUMULATOR RESULT");
        $display("----------------------------------------------");


        sum_real = fp32_to_real(sum);

        expected_sum =
              2.718281828459045
            + 7.389056098930650
            + 20.085536923187668
            + 54.598150033144236;


        sum_error = sum_real - expected_sum;

        if (sum_error < 0.0)
            sum_error = -sum_error;


        sum_relative_error = sum_error / expected_sum;


        $display(
            "SUM      = %12.8f",
            sum_real
        );

        $display(
            "EXPECTED = %12.8f",
            expected_sum
        );

        $display(
            "ERROR    = %8.4f%%",
            sum_relative_error * 100.0
        );

        $display(
            "DONE     = %b",
            done
        );


        if (sum_relative_error <= tolerance)
        begin
            pass_count = pass_count + 1;
            $display("PASS : SUM within 0.5%% tolerance");
        end
        else
        begin
            fail_count = fail_count + 1;
            $display("FAIL : SUM outside tolerance");
        end


        if (done)
        begin
            pass_count = pass_count + 1;
            $display("PASS : DONE asserted");
        end
        else
        begin
            fail_count = fail_count + 1;
            $display("FAIL : DONE not asserted");
        end


        // ========================================================
        // RAM READBACK
        // ========================================================

        $display("");
        $display("==============================================");
        $display("              RAM READBACK TEST");
        $display("==============================================");


        // --------------------------------------------------------
        // RAM[0]
        // --------------------------------------------------------

        read_addr = 2'd0;

        #5;

        exp_real     = fp32_to_real(exp_out);
        expected_exp = 2.718281828459045;

        exp_error = exp_real - expected_exp;

        if (exp_error < 0.0)
            exp_error = -exp_error;

        exp_relative_error = exp_error / expected_exp;

        $display("");
        $display(
            "READ_ADDR = 0 | EXP_OUT = %h | VALUE = %12.8f | EXPECTED = %12.8f | ERROR = %8.4f%%",
            exp_out,
            exp_real,
            expected_exp,
            exp_relative_error * 100.0
        );

        if (exp_relative_error <= tolerance)
        begin
            pass_count = pass_count + 1;
            $display("PASS : RAM[0] read correctly");
        end
        else
        begin
            fail_count = fail_count + 1;
            $display("FAIL : RAM[0] read incorrect");
        end


        // --------------------------------------------------------
        // RAM[1]
        // --------------------------------------------------------

        read_addr = 2'd1;

        #5;

        exp_real     = fp32_to_real(exp_out);
        expected_exp = 7.389056098930650;

        exp_error = exp_real - expected_exp;

        if (exp_error < 0.0)
            exp_error = -exp_error;

        exp_relative_error = exp_error / expected_exp;

        $display(
            "READ_ADDR = 1 | EXP_OUT = %h | VALUE = %12.8f | EXPECTED = %12.8f | ERROR = %8.4f%%",
            exp_out,
            exp_real,
            expected_exp,
            exp_relative_error * 100.0
        );

        if (exp_relative_error <= tolerance)
        begin
            pass_count = pass_count + 1;
            $display("PASS : RAM[1] read correctly");
        end
        else
        begin
            fail_count = fail_count + 1;
            $display("FAIL : RAM[1] read incorrect");
        end


        // --------------------------------------------------------
        // RAM[2]
        // --------------------------------------------------------

        read_addr = 2'd2;

        #5;

        exp_real     = fp32_to_real(exp_out);
        expected_exp = 20.085536923187668;

        exp_error = exp_real - expected_exp;

        if (exp_error < 0.0)
            exp_error = -exp_error;

        exp_relative_error = exp_error / expected_exp;

        $display(
            "READ_ADDR = 2 | EXP_OUT = %h | VALUE = %12.8f | EXPECTED = %12.8f | ERROR = %8.4f%%",
            exp_out,
            exp_real,
            expected_exp,
            exp_relative_error * 100.0
        );

        if (exp_relative_error <= tolerance)
        begin
            pass_count = pass_count + 1;
            $display("PASS : RAM[2] read correctly");
        end
        else
        begin
            fail_count = fail_count + 1;
            $display("FAIL : RAM[2] read incorrect");
        end


        // --------------------------------------------------------
        // RAM[3]
        // --------------------------------------------------------

        read_addr = 2'd3;

        #5;

        exp_real     = fp32_to_real(exp_out);
        expected_exp = 54.598150033144236;

        exp_error = exp_real - expected_exp;

        if (exp_error < 0.0)
            exp_error = -exp_error;

        exp_relative_error = exp_error / expected_exp;

        $display(
            "READ_ADDR = 3 | EXP_OUT = %h | VALUE = %12.8f | EXPECTED = %12.8f | ERROR = %8.4f%%",
            exp_out,
            exp_real,
            expected_exp,
            exp_relative_error * 100.0
        );

        if (exp_relative_error <= tolerance)
        begin
            pass_count = pass_count + 1;
            $display("PASS : RAM[3] read correctly");
        end
        else
        begin
            fail_count = fail_count + 1;
            $display("FAIL : RAM[3] read incorrect");
        end


        // ========================================================
        // SUMMARY
        // ========================================================

        $display("");
        $display("==============================================");
        $display("                TEST SUMMARY");
        $display("==============================================");

        $display(
            "PASS COUNT = %0d",
            pass_count
        );

        $display(
            "FAIL COUNT = %0d",
            fail_count
        );

        $display("");


        if (fail_count == 0)
            $display("OVERALL RESULT : PASS");
        else
            $display("OVERALL RESULT : FAIL");


        $display("");
        $display("==============================================");
        $display("       PHASE 5A INTERFACE TEST COMPLETE");
        $display("==============================================");
        $display("");


        $finish;

    end


    // ============================================================
    // VCD
    // ============================================================

    initial
    begin

        $dumpfile("softmax_exp_accumulator_tb.vcd");

        $dumpvars(
            0,
            softmax_exp_accumulator_tb
        );

    end

endmodule