module softmax_normalization_engine_tb;

    reg clk;
    reg rst;
    reg start;

    reg [31:0] exp_out;
    reg [31:0] reciprocal_sum;

    reg [1:0] read_addr;
    reg       valid;

    wire [31:0] softmax_value;
    wire        softmax_valid;
    wire        done;

    integer pass_count;
    integer fail_count;

    real dut_real;
    real expected_real;
    real error;
    real tolerance;


    // ============================================================
    // DUT
    // ============================================================

    softmax_normalization_engine dut (

        .clk            (clk),
        .rst            (rst),
        .start          (start),

        .exp_out        (exp_out),
        .reciprocal_sum (reciprocal_sum),

        .read_addr      (read_addr),
        .valid          (valid),

        .softmax_value  (softmax_value),
        .softmax_valid  (softmax_valid),
        .done           (done)
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

                mantissa = 0.0;
                weight   = 0.5;

                for (i = 22; i >= 0; i = i - 1)
                begin
                    if (f[i])
                        mantissa = mantissa + weight;

                    weight = weight / 2.0;
                end

                for (j = 0; j < 126; j = j + 1)
                    mantissa = mantissa / 2.0;

                if (s)
                    mantissa = -mantissa;

                fp32_to_real = mantissa;

            end

        end

    endfunction


    // ============================================================
    // TEST ONE SOFTMAX VALUE
    // ============================================================

    task test_value;

        input [1:0]  addr;
        input [31:0] exp_input;
        input real   expected;

        begin

            read_addr = addr;
            exp_out   = exp_input;
            valid     = 1'b1;

            @(posedge clk);
            #1;

            dut_real = fp32_to_real(softmax_value);

            error = dut_real - expected;

            if (error < 0.0)
                error = -error;

            if (expected != 0.0)
                error = error / expected;

            $display(
                "ADDR = %0d | EXP = %12.8f | SOFTMAX = %12.8f | EXPECTED = %12.8f | ERROR = %8.4f%%",
                addr,
                fp32_to_real(exp_input),
                dut_real,
                expected,
                error * 100.0
            );


            if (error <= tolerance)
            begin
                pass_count = pass_count + 1;
                $display("PASS");
            end

            else
            begin
                fail_count = fail_count + 1;
                $display("FAIL");
            end

            $display("");

            valid = 1'b0;

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

        rst   = 1'b1;
        start = 1'b0;

        exp_out        = 32'd0;
        reciprocal_sum = 32'd0;
        read_addr      = 2'd0;
        valid          = 1'b0;


        $display("");
        $display("==============================================");
        $display(" SOFTMAX NORMALIZATION ENGINE - PHASE 5B-2");
        $display("==============================================");
        $display("");
        $display("Tolerance = 0.5%%");
        $display("");


        // ========================================================
        // RESET
        // ========================================================

        #15;

        rst = 1'b0;

        #10;


        // ========================================================
        // RECIPROCAL OF SUM
        //
        // sum = 84.79102488
        // reciprocal ≈ 0.01179370
        //
        // FP32 representation
        // ========================================================

        reciprocal_sum = 32'h3C411B5B;


        // ========================================================
        // START
        // ========================================================

        start = 1'b1;

        @(posedge clk);

        #1;

        start = 1'b0;


        // ========================================================
        // SOFTMAX VALUES
        // ========================================================

        // exp(1) = 2.71828183
        // softmax ≈ 0.03206

        test_value(
            2'd0,
            32'h402DF855,
            0.03205860
        );


        // exp(2) = 7.38905610
        // softmax ≈ 0.08714

        test_value(
            2'd1,
            32'h40EC7328,
            0.08714432
        );


        // exp(3) = 20.08553692
        // softmax ≈ 0.23688282

        test_value(
            2'd2,
            32'h41A0AF30,
            0.23688282
        );


        // exp(4) = 54.59815003
        // softmax ≈ 0.64391426

        test_value(
            2'd3,
            32'h425A6484,
            0.64391426
        );


        // ========================================================
        // CHECK DONE
        // ========================================================

        #10;

        $display("----------------------------------------------");
        $display("CONTROL STATUS");
        $display("----------------------------------------------");

        $display(
            "SOFTMAX_VALID = %b",
            softmax_valid
        );

        $display(
            "DONE          = %b",
            done
        );

        if (done == 1'b1)
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
        $display("       PHASE 5B-2 TEST COMPLETE");
        $display("==============================================");

        $finish;

    end


    // ============================================================
    // VCD
    // ============================================================

    initial
    begin

        $dumpfile("softmax_normalization_engine_tb.vcd");

        $dumpvars(
            0,
            softmax_normalization_engine_tb
        );

    end

endmodule