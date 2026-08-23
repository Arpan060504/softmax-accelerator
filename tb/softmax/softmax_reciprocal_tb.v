`timescale 1ns/1ps

module softmax_reciprocal_tb;

    // ============================================================
    // DUT SIGNALS
    // ============================================================

    reg  [31:0] sum;
    wire [31:0] reciprocal_sum;


    // ============================================================
    // DUT
    // ============================================================

    softmax_reciprocal dut (
        .sum            (sum),
        .reciprocal_sum(reciprocal_sum)
    );


    // ============================================================
    // REAL VARIABLES
    // ============================================================

    real sum_real;
    real reciprocal_real;
    real expected_real;

    real error;
    real relative_error;

    real tolerance;

    integer pass_count;
    integer fail_count;


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


    // ============================================================
    // MAIN TEST
    // ============================================================

    initial
    begin

        pass_count = 0;
        fail_count = 0;

        tolerance = 0.005;       // 0.5%


        // ========================================================
        // HEADER
        // ========================================================

        $display("");
        $display("==============================================");
        $display("       SOFTMAX RECIPROCAL - PHASE 5A");
        $display("==============================================");
        $display("");

        $display("Tolerance = 0.5%%");
        $display("");


        // ========================================================
        // ACTUAL ACCUMULATOR SUM
        // ========================================================
        //
        // SUM = e^1 + e^2 + e^3 + e^4
        //
        // SUM ≈ 84.79103851
        //
        // FP32 = 0x42A99503
        //
        // Expected reciprocal ≈ 0.01179355
        //
        // ========================================================

        sum = 32'h42A99503;


        #10;


        // ========================================================
        // CONVERT RESULTS
        // ========================================================

        sum_real       = fp32_to_real(sum);

        reciprocal_real = fp32_to_real(reciprocal_sum);

        expected_real  = 1.0 / sum_real;


        // ========================================================
        // ERROR CALCULATION
        // ========================================================

        error = reciprocal_real - expected_real;

        if (error < 0.0)
            error = -error;


        relative_error = error / expected_real;

        if (relative_error < 0.0)
            relative_error = -relative_error;


        // ========================================================
        // DISPLAY
        // ========================================================

        $display("----------------------------------------------");
        $display("              RECIPROCAL RESULT");
        $display("----------------------------------------------");

        $display(
            "SUM         = %12.8f",
            sum_real
        );

        $display(
            "RECIPROCAL  = %12.8f",
            reciprocal_real
        );

        $display(
            "EXPECTED    = %12.8f",
            expected_real
        );

        $display(
            "ERROR       = %8.4f%%",
            relative_error * 100.0
        );


        // ========================================================
        // CHECK
        // ========================================================

        if (relative_error <= tolerance)
        begin

            pass_count = pass_count + 1;

            $display("");
            $display(
                "PASS : Reciprocal within 0.5%% tolerance"
            );

        end

        else
        begin

            fail_count = fail_count + 1;

            $display("");
            $display(
                "FAIL : Reciprocal outside tolerance"
            );

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
        $display("       PHASE 5A TEST COMPLETE");
        $display("==============================================");
        $display("");


        $finish;

    end


    // ============================================================
    // WAVEFORM
    // ============================================================

    initial
    begin

        $dumpfile("softmax_reciprocal_tb.vcd");

        $dumpvars(
            0,
            softmax_reciprocal_tb
        );

    end

endmodule