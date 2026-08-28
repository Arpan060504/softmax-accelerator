`timescale 1ns/1ps

module softmax_normalizer (
    input  wire [31:0] exp0,
    input  wire [31:0] exp1,
    input  wire [31:0] exp2,
    input  wire [31:0] exp3,

    input  wire [31:0] reciprocal,

    output wire [31:0] softmax0,
    output wire [31:0] softmax1,
    output wire [31:0] softmax2,
    output wire [31:0] softmax3
);

    // ============================================================
    // SOFTMAX NORMALIZATION
    //
    // softmax_i = exp_i / sum(exp)
    //
    // Since reciprocal = 1 / sum(exp):
    //
    // softmax_i = exp_i * reciprocal
    // ============================================================

    fp32_multiplier u_mult0 (
        .a      (exp0),
        .b      (reciprocal),
        .result (softmax0)
    );

    fp32_multiplier u_mult1 (
        .a      (exp1),
        .b      (reciprocal),
        .result (softmax1)
    );

    fp32_multiplier u_mult2 (
        .a      (exp2),
        .b      (reciprocal),
        .result (softmax2)
    );

    fp32_multiplier u_mult3 (
        .a      (exp3),
        .b      (reciprocal),
        .result (softmax3)
    );

endmodule