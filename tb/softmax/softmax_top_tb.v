`timescale 1ns/1ps

module softmax_top_tb;

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

    wire [31:0] softmax0;
    wire [31:0] softmax1;
    wire [31:0] softmax2;
    wire [31:0] softmax3;

    wire softmax_valid;
    wire done;


    integer pass_count;
    integer fail_count;

    real value;
    real expected;
    real error;


    // ============================================================
    // DUT
    // ============================================================

    softmax_top dut (

        .clk           (clk),
        .rst           (rst),
        .start         (start),

        .x0            (x0),
        .x1            (x1),
        .x2            (x2),
        .x3            (x3),

        .softmax0      (softmax0),
        .softmax1      (softmax1),
        .softmax2      (softmax2),
        .softmax3      (softmax3),

        .softmax_valid (softmax_valid),
        .done          (done)

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

        $dumpfile("softmax_top_tb.vcd");

        $dumpvars(0, softmax_top_tb);

    end


    // ============================================================
    // MONITOR
    // ============================================================

    always @(posedge clk)
    begin

        $display(
            "TIME = %0t | STATE = %0d | READ_ADDR = %0d | VALID = %b | DONE = %b",
            $time,
            dut.state,
            dut.read_addr,
            softmax_valid,
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


        // ========================================================
        // INITIALIZATION
        // ========================================================

        rst   = 1'b1;
        start = 1'b0;

        x0 = 32'h3F800000;     // 1.0
        x1 = 32'h40000000;     // 2.0
        x2 = 32'h40400000;     // 3.0
        x3 = 32'h40800000;     // 4.0


        // ========================================================
        // RESET
        // ========================================================

        #12;

        rst = 1'b0;


        $display("");
        $display("==============================================");
        $display("       FINAL SOFTMAX TOP TEST");
        $display("==============================================");
        $display("");

        $display("INPUTS:");
        $display("x0 = 1.0");
        $display("x1 = 2.0");
        $display("x2 = 3.0");
        $display("x3 = 4.0");

        $display("");


        // ========================================================
        // START
        // ========================================================

        #8;

        start = 1'b1;

        $display(
            "TIME = %0t | START ASSERTED",
            $time
        );


        #10;

        start = 1'b0;

        $display(
            "TIME = %0t | START DEASSERTED",
            $time
        );

        $display("");


        // ========================================================
        // WAIT FOR SOFTMAX VALUES
        // ========================================================

        wait (done == 1'b1);


        #1;


        // ========================================================
        // RESULT
        // ========================================================

        $display("");
        $display("----------------------------------------------");
        $display("          FINAL SOFTMAX RESULTS");
        $display("----------------------------------------------");


        // ========================================================
        // SOFTMAX 0
        // ========================================================

        value    = fp32_to_real(softmax0);
        expected = 0.03205860;

        error = relative_error(value, expected);


        $display(
            "SOFTMAX0 = %12.8f | EXPECTED = %12.8f | ERROR = %8.4f%%",
            value,
            expected,
            error * 100.0
        );


        if (error <= 0.005)
        begin

            $display("PASS : SOFTMAX0");

            pass_count = pass_count + 1;

        end

        else
        begin

            $display("FAIL : SOFTMAX0");

            fail_count = fail_count + 1;

        end


        // ========================================================
        // SOFTMAX 1
        // ========================================================

        value    = fp32_to_real(softmax1);
        expected = 0.08714432;

        error = relative_error(value, expected);


        $display(
            "SOFTMAX1 = %12.8f | EXPECTED = %12.8f | ERROR = %8.4f%%",
            value,
            expected,
            error * 100.0
        );


        if (error <= 0.005)
        begin

            $display("PASS : SOFTMAX1");

            pass_count = pass_count + 1;

        end

        else
        begin

            $display("FAIL : SOFTMAX1");

            fail_count = fail_count + 1;

        end


        // ========================================================
        // SOFTMAX 2
        // ========================================================

        value    = fp32_to_real(softmax2);
        expected = 0.23688282;

        error = relative_error(value, expected);


        $display(
            "SOFTMAX2 = %12.8f | EXPECTED = %12.8f | ERROR = %8.4f%%",
            value,
            expected,
            error * 100.0
        );


        if (error <= 0.005)
        begin

            $display("PASS : SOFTMAX2");

            pass_count = pass_count + 1;

        end

        else
        begin

            $display("FAIL : SOFTMAX2");

            fail_count = fail_count + 1;

        end


        // ========================================================
        // SOFTMAX 3
        // ========================================================

        value    = fp32_to_real(softmax3);
        expected = 0.64391426;

        error = relative_error(value, expected);


        $display(
            "SOFTMAX3 = %12.8f | EXPECTED = %12.8f | ERROR = %8.4f%%",
            value,
            expected,
            error * 100.0
        );


        if (error <= 0.005)
        begin

            $display("PASS : SOFTMAX3");

            pass_count = pass_count + 1;

        end

        else
        begin

            $display("FAIL : SOFTMAX3");

            fail_count = fail_count + 1;

        end


        // ========================================================
        // VALID / DONE
        // ========================================================

        $display("");
        $display("----------------------------------------------");
        $display("             CONTROL RESULT");
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

            $display("PASS : DONE asserted");

            pass_count = pass_count + 1;

        end

        else
        begin

            $display("FAIL : DONE not asserted");

            fail_count = fail_count + 1;

        end


        // ========================================================
        // CHECK SOFTMAX SUM
        // ========================================================

        value =
            fp32_to_real(softmax0) +
            fp32_to_real(softmax1) +
            fp32_to_real(softmax2) +
            fp32_to_real(softmax3);


        $display("");
        $display("----------------------------------------------");
        $display("             PROBABILITY SUM");
        $display("----------------------------------------------");

        $display(
            "SUM OF SOFTMAX = %12.8f",
            value
        );

        $display(
            "EXPECTED       = 1.00000000"
        );


        error = value - 1.0;

        if (error < 0.0)
            error = -error;


        if (error <= 0.005)
        begin

            $display(
                "PASS : Softmax outputs sum to approximately 1"
            );

            pass_count = pass_count + 1;

        end

        else
        begin

            $display(
                "FAIL : Softmax outputs do not sum to 1"
            );

            fail_count = fail_count + 1;

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
        $display("       FINAL SOFTMAX TOP TEST COMPLETE");
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