module softmax_exp_engine (
    input        clk,
    input        rst,
    input        start,

    input  [31:0] x0,
    input  [31:0] x1,
    input  [31:0] x2,
    input  [31:0] x3,

    output reg [31:0] exp_value,
    output reg        done,
    output reg        exp_valid
);

    // ============================================================
    // CURRENT INPUT INDEX
    // ============================================================

    reg [1:0] x_index;

    wire [31:0] x_selected;

    // ============================================================
    // INPUT SELECTOR
    // ============================================================

    input_selector selector (
        .x0         (x0),
        .x1         (x1),
        .x2         (x2),
        .x3         (x3),
        .x_index    (x_index),
        .x_selected (x_selected)
    );

    // ============================================================
    // EXP UNIT
    // ============================================================

    wire [31:0] exp_calculated;

    exp_unit exp (
        .x       (x_selected),
        .exp_out (exp_calculated)
    );

    // ============================================================
    // CONTROL + OUTPUT REGISTER
    // ============================================================

    always @(posedge clk)
    begin

        // --------------------------------------------------------
        // DEFAULT
        // --------------------------------------------------------

        exp_valid <= 1'b0;

        // --------------------------------------------------------
        // RESET
        // --------------------------------------------------------

        if (rst)
        begin
            x_index   <= 2'd0;
            exp_value <= 32'd0;
            exp_valid <= 1'b0;
            done      <= 1'b0;
        end

        // --------------------------------------------------------
        // START
        // --------------------------------------------------------

        else if (start)
        begin
            x_index   <= 2'd0;
            exp_value <= 32'd0;
            exp_valid <= 1'b0;
            done      <= 1'b0;
        end

        // --------------------------------------------------------
        // PROCESS
        // --------------------------------------------------------

        else if (!done)
        begin

            // ----------------------------------------------------
            // Capture EXP of CURRENT input
            // ----------------------------------------------------

            exp_value <= exp_calculated;
            exp_valid <= 1'b1;

            // ----------------------------------------------------
            // Check whether this is the last input
            // ----------------------------------------------------

            if (x_index == 2'd3)
            begin
                done <= 1'b1;
            end

            else
            begin
                x_index <= x_index + 1'b1;
            end

        end

    end

endmodule