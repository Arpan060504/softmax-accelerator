module softmax_normalizer_tb;

    // ============================================================
    // SIGNALS
    // ============================================================

    reg  [31:0] exp_value;
    reg  [31:0] reciprocal_sum;

    wire [31:0] softmax_value;


    // ============================================================
    // REAL VARIABLES
    // ============================================================

    real exp_real;
    real reciprocal_real;
    real dut_real;
    real expected_real;

    real abs_error;
    real rel_error;

    real max_error;
    real max_error_input;

    integer pass_count;
    integer fail_count;


    // ============================================================
    // DEVICE UNDER TEST
    // ============================================================

    softmax_normalizer dut (
        .exp_value      (exp_value),
        .reciprocal_sum (reciprocal_sum),
        .softmax_value  (softmax_value)
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


            // ----------------------------------------------------
            // ZERO
            // ----------------------------------------------------

            if ((e == 0) && (f == 0))
            begin
                fp32_to_real = 0.0;
            end


            // ----------------------------------------------------
            // NORMAL NUMBER
            // ----------------------------------------------------

            else if (e != 0)
            begin

                // Implicit leading 1
                mantissa = 1.0;

                // First fraction bit = 1/2
                weight = 0.5;


                // Build mantissa
                for (i = 22; i >= 0; i = i - 1)
                begin

                    if (f[i])
                        mantissa = mantissa + weight;

                    weight = weight / 2.0;

                end


                // Remove FP32 bias
                unbiased_exp = e - 127;


                // ------------------------------------------------
                // Multiply by 2^unbiased_exp
                // ------------------------------------------------

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


                // Apply sign
                if (s)
                    mantissa = -mantissa;


                fp32_to_real = mantissa;

            end


            // ----------------------------------------------------
            // SUBNORMAL
            // ----------------------------------------------------

            else
            begin

                mantissa = 0.0;

                weight = 0.5;


                for (i = 22; i >= 0; i = i - 1)
                begin

                    if (f[i])
                        mantissa = mantissa + weight;

                    weight = weight / 2.0;

                end


                // Subnormal exponent = -126
                for (j = 0; j < 126; j = j + 1)
                    mantissa = mantissa / 2.0;


                if (s)
                    mantissa = -mantissa;


                fp32_to_real = mantissa;

            end

        end

    endfunction


    // ============================================================
    // NORMALIZER TEST TASK
    // ============================================================

    task test_normalizer;

        input [31:0] input_exp;
        input [31:0] input_reciprocal;
        input real expected_value;
        input real tolerance;

        begin

            // ----------------------------------------------------
            // Apply inputs
            // ----------------------------------------------------

            exp_value      = input_exp;
            reciprocal_sum = input_reciprocal;

            #10;


            // ----------------------------------------------------
            // Convert values to REAL
            // ----------------------------------------------------

            exp_real       = fp32_to_real(exp_value);

            reciprocal_real = fp32_to_real(reciprocal_sum);

            dut_real       = fp32_to_real(softmax_value);


            // ----------------------------------------------------
            // Expected value
            // ----------------------------------------------------

            // We pass the mathematical expected result
            // directly into the task.


            // ----------------------------------------------------
            // Absolute error
            // ----------------------------------------------------

            abs_error = dut_real - expected_value;

            if (abs_error < 0.0)
                abs_error = -abs_error;


            // ----------------------------------------------------
            // Relative error
            // ----------------------------------------------------

            rel_error = abs_error / expected_value;

            if (rel_error < 0.0)
                rel_error = -rel_error;


            // ----------------------------------------------------
            // Track maximum error
            // ----------------------------------------------------

            if (rel_error > max_error)
            begin
                max_error = rel_error;
                max_error_input = exp_real;
            end


            // ----------------------------------------------------
            // PASS / FAIL
            // ----------------------------------------------------

            if (rel_error <= tolerance)
            begin

                pass_count = pass_count + 1;

                $display(
                    "PASS : exp = %10.6f | reciprocal = %12.8f | expected = %12.8f | DUT = %12.8f | error = %8.4f%%",
                    exp_real,
                    reciprocal_real,
                    expected_value,
                    dut_real,
                    rel_error * 100.0
                );

            end

            else
            begin

                fail_count = fail_count + 1;

                $display(
                    "FAIL : exp = %10.6f | reciprocal = %12.8f | expected = %12.8f | DUT = %12.8f | error = %8.4f%%",
                    exp_real,
                    reciprocal_real,
                    expected_value,
                    dut_real,
                    rel_error * 100.0
                );

            end

        end

    endtask


    // ============================================================
    // MAIN TEST
    // ============================================================

    initial
    begin

        // --------------------------------------------------------
        // Initialize
        // --------------------------------------------------------

        exp_value      = 32'd0;
        reciprocal_sum = 32'd0;

        pass_count = 0;
        fail_count = 0;

        max_error = 0.0;
        max_error_input = 0.0;


        // --------------------------------------------------------
        // VCD
        // --------------------------------------------------------

        $dumpfile("softmax_normalizer_tb.vcd");
        $dumpvars(0, softmax_normalizer_tb);


        // --------------------------------------------------------
        // Header
        // --------------------------------------------------------

        $display("");
        $display("==============================================");
        $display("      SOFTMAX NORMALIZER TESTBENCH");
        $display("==============================================");
        $display("");

        $display("Tolerance = 0.5%%");
        $display("");


        // ========================================================
        // BASIC TESTS
        // ========================================================

        // 1.0 × 0.1 = 0.1
        test_normalizer(
            32'h3F800000,
            32'h3DCCCCCD,
            0.1,
            0.005
        );


        // 2.0 × 0.1 = 0.2
        test_normalizer(
            32'h40000000,
            32'h3DCCCCCD,
            0.2,
            0.005
        );


        // 3.0 × 0.1 = 0.3
        test_normalizer(
            32'h40400000,
            32'h3DCCCCCD,
            0.3,
            0.005
        );


        // 4.0 × 0.1 = 0.4
        test_normalizer(
            32'h40800000,
            32'h3DCCCCCD,
            0.4,
            0.005
        );


        // ========================================================
        // OTHER VALUES
        // ========================================================

        // 5 × 0.1 = 0.5
        test_normalizer(
            32'h40A00000,
            32'h3DCCCCCD,
            0.5,
            0.005
        );


        // 6 × 0.1 = 0.6
        test_normalizer(
            32'h40C00000,
            32'h3DCCCCCD,
            0.6,
            0.005
        );


        // 7 × 0.1 = 0.7
        test_normalizer(
            32'h40E00000,
            32'h3DCCCCCD,
            0.7,
            0.005
        );


        // 8 × 0.1 = 0.8
        test_normalizer(
            32'h41000000,
            32'h3DCCCCCD,
            0.8,
            0.005
        );


        // ========================================================
        // DIFFERENT RECIPROCALS
        // ========================================================

        // 1 × 0.2 = 0.2
        test_normalizer(
            32'h3F800000,
            32'h3E4CCCCD,
            0.2,
            0.005
        );


        // 2 × 0.2 = 0.4
        test_normalizer(
            32'h40000000,
            32'h3E4CCCCD,
            0.4,
            0.005
        );


        // 3 × 0.2 = 0.6
        test_normalizer(
            32'h40400000,
            32'h3E4CCCCD,
            0.6,
            0.005
        );


        // 4 × 0.2 = 0.8
        test_normalizer(
            32'h40800000,
            32'h3E4CCCCD,
            0.8,
            0.005
        );


        // ========================================================
        // ACTUAL SOFTMAX-LIKE EXAMPLE
        // ========================================================

        // exp values = 1,2,3,4
        // sum = 10
        //
        // reciprocal ≈ 0.1
        //
        // individual outputs:
        //
        // 1 × 0.1 = 0.1
        // 2 × 0.1 = 0.2
        // 3 × 0.1 = 0.3
        // 4 × 0.1 = 0.4


        test_normalizer(
            32'h3F800000,
            32'h3DCCCCCD,
            0.1,
            0.005
        );


        test_normalizer(
            32'h40000000,
            32'h3DCCCCCD,
            0.2,
            0.005
        );


        test_normalizer(
            32'h40400000,
            32'h3DCCCCCD,
            0.3,
            0.005
        );


        test_normalizer(
            32'h40800000,
            32'h3DCCCCCD,
            0.4,
            0.005
        );


        // ========================================================
        // SUMMARY
        // ========================================================

        $display("");
        $display("==============================================");
        $display("                TEST SUMMARY");
        $display("==============================================");

        $display(
            "PASS COUNT       = %0d",
            pass_count
        );

        $display(
            "FAIL COUNT       = %0d",
            fail_count
        );

        $display(
            "MAX RELATIVE ERR = %f%%",
            max_error * 100.0
        );

        $display(
            "WORST INPUT      = %f",
            max_error_input
        );

        $display("");


        if (fail_count == 0)
            $display("OVERALL RESULT : PASS");
        else
            $display("OVERALL RESULT : FAIL");


        $display("");

        $display("==============================================");
        $display("    SOFTMAX NORMALIZER TEST COMPLETE");
        $display("==============================================");

        $finish;

    end

endmodule