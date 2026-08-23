module softmax_read_controller_tb;

    reg clk;
    reg rst;
    reg start;

    wire [1:0] read_addr;
    wire       valid;
    wire       done;

    integer pass_count;
    integer fail_count;


    // ============================================================
    // DUT
    // ============================================================

    softmax_read_controller dut (
        .clk       (clk),
        .rst       (rst),
        .start     (start),

        .read_addr (read_addr),
        .valid     (valid),
        .done      (done)
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
    // TEST
    // ============================================================

    initial
    begin

        pass_count = 0;
        fail_count = 0;

        rst   = 1'b1;
        start = 1'b0;


        $display("");
        $display("==============================================");
        $display("       SOFTMAX READ CONTROLLER - PHASE 5B-1");
        $display("==============================================");
        $display("");


        // --------------------------------------------------------
        // RESET
        // --------------------------------------------------------

        #15;

        rst = 1'b0;

        #10;


        // --------------------------------------------------------
        // START
        // --------------------------------------------------------

        start = 1'b1;

        @(posedge clk);

        #1;

        $display(
            "START : READ_ADDR = %0d | VALID = %b | DONE = %b",
            read_addr,
            valid,
            done
        );

        if ((read_addr == 2'd0) && (valid == 1'b1))
        begin
            pass_count = pass_count + 1;
            $display("PASS : Address 0 generated");
        end
        else
        begin
            fail_count = fail_count + 1;
            $display("FAIL : Address 0");
        end

        start = 1'b0;


        // --------------------------------------------------------
        // ADDRESS 1
        // --------------------------------------------------------

        @(posedge clk);

        #1;

        $display(
            "READ : READ_ADDR = %0d | VALID = %b | DONE = %b",
            read_addr,
            valid,
            done
        );

        if ((read_addr == 2'd1) && (valid == 1'b1))
        begin
            pass_count = pass_count + 1;
            $display("PASS : Address 1 generated");
        end
        else
        begin
            fail_count = fail_count + 1;
            $display("FAIL : Address 1");
        end


        // --------------------------------------------------------
        // ADDRESS 2
        // --------------------------------------------------------

        @(posedge clk);

        #1;

        $display(
            "READ : READ_ADDR = %0d | VALID = %b | DONE = %b",
            read_addr,
            valid,
            done
        );

        if ((read_addr == 2'd2) && (valid == 1'b1))
        begin
            pass_count = pass_count + 1;
            $display("PASS : Address 2 generated");
        end
        else
        begin
            fail_count = fail_count + 1;
            $display("FAIL : Address 2");
        end


        // --------------------------------------------------------
        // ADDRESS 3
        // --------------------------------------------------------

        @(posedge clk);

        #1;

        $display(
            "READ : READ_ADDR = %0d | VALID = %b | DONE = %b",
            read_addr,
            valid,
            done
        );

        if ((read_addr == 2'd3) && (valid == 1'b1))
        begin
            pass_count = pass_count + 1;
            $display("PASS : Address 3 generated");
        end
        else
        begin
            fail_count = fail_count + 1;
            $display("FAIL : Address 3");
        end


        // --------------------------------------------------------
        // DONE
        // --------------------------------------------------------

        @(posedge clk);

        #1;

        $display(
            "DONE  : READ_ADDR = %0d | VALID = %b | DONE = %b",
            read_addr,
            valid,
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

        $display("PASS COUNT = %0d", pass_count);
        $display("FAIL COUNT = %0d", fail_count);

        $display("");

        if (fail_count == 0)
            $display("OVERALL RESULT : PASS");
        else
            $display("OVERALL RESULT : FAIL");

        $display("");

        $display("==============================================");
        $display("       PHASE 5B-1 TEST COMPLETE");
        $display("==============================================");
        $display("");

        $finish;

    end


    // ============================================================
    // WAVEFORM
    // ============================================================

    initial
    begin

        $dumpfile("softmax_read_controller_tb.vcd");

        $dumpvars(
            0,
            softmax_read_controller_tb
        );

    end

endmodule