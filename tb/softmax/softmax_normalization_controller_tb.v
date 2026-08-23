`timescale 1ns/1ps

module softmax_normalization_controller_tb;

    // ============================================================
    // SIGNALS
    // ============================================================

    reg        clk;
    reg        rst;
    reg        start;

    reg [31:0] exp_value;
    reg [31:0] reciprocal;

    wire [1:0]  read_addr;
    wire [31:0] softmax_value;
    wire        softmax_valid;
    wire        done;

    reg [31:0] exp_ram [0:3];

    integer pass_count;
    integer fail_count;

    real dut_real;
    real expected_real;
    real error;
    real tolerance;


    // ============================================================
    // DUT
    // ============================================================

    softmax_normalization_controller dut (

        .clk           (clk),
        .rst           (rst),
        .start         (start),

        .exp_value     (exp_value),
        .reciprocal    (reciprocal),

        .read_addr     (read_addr),

        .softmax_value (softmax_value),

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

        $dumpfile("softmax_normalization_controller_tb.vcd");

        $dumpvars(0, softmax_normalization_controller_tb);

    end


    // ============================================================
    // RAM MODEL
    // ============================================================

    always @(*)
    begin

        case (read_addr)

            2'd0:
                exp_value = exp_ram[0];

            2'd1:
                exp_value = exp_ram[1];

            2'd2:
                exp_value = exp_ram[2];

            2'd3:
                exp_value = exp_ram[3];

            default:
                exp_value = 32'd0;

        endcase

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
    // MAIN TEST
    // ============================================================

    initial
    begin

        pass_count = 0;
        fail_count = 0;

        tolerance = 0.005;


        // --------------------------------------------------------
        // EXP VALUES
        // --------------------------------------------------------

        exp_ram[0] = 32'h402DF855;
        exp_ram[1] = 32'h40EC7328;
        exp_ram[2] = 32'h41A0AF30;
        exp_ram[3] = 32'h425A6484;


        // Reciprocal produced by your reciprocal unit

        reciprocal = 32'h3C413097;


        // --------------------------------------------------------
        // RESET
        // --------------------------------------------------------

        rst   = 1'b1;
        start = 1'b0;

        #12;

        rst = 1'b0;


        // --------------------------------------------------------
        // HEADER
        // --------------------------------------------------------

        $display("");
        $display("==============================================");
        $display(" SOFTMAX NORMALIZATION CONTROLLER - PHASE 5C-3B-2");
        $display("==============================================");
        $display("");

        $display("Tolerance = 0.5%%");
        $display("");


        // --------------------------------------------------------
        // START
        // --------------------------------------------------------

        @(posedge clk);

        start = 1'b1;

        @(posedge clk);

        #1;

        start = 1'b0;


        // --------------------------------------------------------
        // MONITOR FOUR OUTPUTS
        // --------------------------------------------------------

        wait (done == 1'b1);


        $display("");
        $display("----------------------------------------------");
        $display("              CONTROL RESULT");
        $display("----------------------------------------------");

        $display("DONE = %b", done);


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
        $display("       PHASE 5C-3B-2 TEST COMPLETE");
        $display("==============================================");

        #10;

        $finish;

    end


    // ============================================================
    // CHECK EVERY VALID OUTPUT
    // ============================================================

    always @(posedge clk)
    begin

        if (softmax_valid)
        begin

            #1;

            dut_real = fp32_to_real(softmax_value);


            case (read_addr)

                2'd0:
                    expected_real = 0.03205227;

                2'd1:
                    expected_real = 0.08712711;

                2'd2:
                    expected_real = 0.23683604;

                2'd3:
                    expected_real = 0.64378710;

                default:
                    expected_real = 0.0;

            endcase


            error = dut_real - expected_real;

            if (error < 0.0)
                error = -error;


            if (expected_real != 0.0)
                error = error / expected_real;


            $display(
                "ADDR = %0d | EXP = %12.8f | SOFTMAX = %12.8f | EXPECTED = %12.8f | ERROR = %8.4f%%",
                read_addr,
                fp32_to_real(exp_value),
                dut_real,
                expected_real,
                error * 100.0
            );


            if (error <= tolerance)
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

    end

endmodule