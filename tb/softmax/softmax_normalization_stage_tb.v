`timescale 1ns/1ps

module softmax_normalization_stage_tb;

    reg  [31:0] exp_value;
    reg  [31:0] reciprocal;

    wire [31:0] softmax_value;

    real exp_real;
    real reciprocal_real;
    real dut_real;
    real expected_real;

    real abs_error;
    real rel_error;

    integer pass_count;
    integer fail_count;

    real tolerance;


    // ============================================================
    // DUT
    // ============================================================

    softmax_normalization_stage dut (
        .exp_value     (exp_value),
        .reciprocal    (reciprocal),
        .softmax_value (softmax_value)
    );


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
    // TEST TASK
    // ============================================================

    task test_normalization;

        input [31:0] exp_input;
        input [31:0] reciprocal_input;

        begin

            exp_value = exp_input;
            reciprocal = reciprocal_input;

            #5;

            exp_real       = fp32_to_real(exp_value);
            reciprocal_real = fp32_to_real(reciprocal);
            dut_real       = fp32_to_real(softmax_value);

            expected_real = exp_real * reciprocal_real;


            // ----------------------------------------------------
            // Absolute error
            // ----------------------------------------------------

            abs_error = dut_real - expected_real;

            if (abs_error < 0.0)
                abs_error = -abs_error;


            // ----------------------------------------------------
            // Relative error
            // ----------------------------------------------------

            if (expected_real != 0.0)
                rel_error = abs_error / expected_real;
            else
                rel_error = abs_error;


            if (rel_error < 0.0)
                rel_error = -rel_error;


            // ----------------------------------------------------
            // Display
            // ----------------------------------------------------

            $display(
                "EXP = %12.8f | RECIP = %12.8f | EXPECTED = %12.8f | DUT = %12.8f | ERROR = %8.4f%%",
                exp_real,
                reciprocal_real,
                expected_real,
                dut_real,
                rel_error * 100.0
            );


            // ----------------------------------------------------
            // PASS / FAIL
            // ----------------------------------------------------

            if (rel_error <= tolerance)
            begin

                $display("PASS");
                pass_count = pass_count + 1;

            end

            else
            begin

                $display("FAIL");
                fail_count = fail_count + 1;

            end

            $display("");

        end

    endtask


    // ============================================================
    // MAIN TEST
    // ============================================================

    initial
    begin

        pass_count = 0;
        fail_count = 0;

        tolerance = 0.005;


        $display("");
        $display("==============================================");
        $display(" SOFTMAX NORMALIZATION STAGE - PHASE 5C-3B-1");
        $display("==============================================");
        $display("");

        $display("Tolerance = 0.5%%");
        $display("");


        // ========================================================
        // EXP VALUES FROM x = [1,2,3,4]
        // reciprocal ≈ 1 / 84.79102488
        // ========================================================

        test_normalization(
            32'h402DF855,       // exp(1) ≈ 2.71828198
            32'h3C413097        // reciprocal ≈ 0.01179137
        );

        test_normalization(
            32'h40EC7328,       // exp(2) ≈ 7.38905716
            32'h3C413097
        );

        test_normalization(
            32'h41A0AF30,       // exp(3) ≈ 20.08554077
            32'h3C413097
        );

        test_normalization(
            32'h425A6484,       // exp(4) ≈ 54.59815979
            32'h3C413097
        );


        // ========================================================
        // SUMMARY
        // ========================================================

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
        $display("       PHASE 5C-3B-1 TEST COMPLETE");
        $display("==============================================");

        $finish;

    end

endmodule