module softmax_exp_accumulator (
    input        clk,
    input        rst,
    input        start,

    input  [31:0] x0,
    input  [31:0] x1,
    input  [31:0] x2,
    input  [31:0] x3,

    input  [1:0]  read_addr,

    output [31:0] sum,
    output        done,
    output [31:0] exp_out
);

    // ============================================================
    // EXP ENGINE
    // ============================================================

    wire [31:0] exp_value;
    wire        exp_done;
    wire        exp_valid;

    softmax_exp_engine exp_engine (
        .clk       (clk),
        .rst       (rst),
        .start     (start),

        .x0        (x0),
        .x1        (x1),
        .x2        (x2),
        .x3        (x3),

        .exp_value (exp_value),
        .done      (exp_done),
        .exp_valid (exp_valid)
    );


    // ============================================================
    // EXP ACCUMULATOR + RAM
    // ============================================================

    wire [31:0] accumulator_sum;
    wire        accumulator_done;
    wire [31:0] accumulator_exp_out;

    exp_accumulator accumulator (
        .clk       (clk),
        .rst       (rst),
        .start     (start),

        .exp_in    (exp_value),
        .exp_valid (exp_valid),

        .read_addr (read_addr),

        .done      (accumulator_done),
        .sum       (accumulator_sum),
        .exp_out   (accumulator_exp_out)
    );


    // ============================================================
    // OUTPUTS
    // ============================================================

    assign sum     = accumulator_sum;
    assign done    = accumulator_done;
    assign exp_out = accumulator_exp_out;

endmodule