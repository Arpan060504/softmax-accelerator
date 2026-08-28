`timescale 1ns/1ps

module softmax_reciprocal (
    input  wire [31:0] sum,
    output wire [31:0] reciprocal
);

    // ============================================================
    // SOFTMAX RECIPROCAL
    //
    // Computes:
    //
    //              1
    // reciprocal = ---
    //              sum
    //
    // The actual reciprocal calculation is performed by the
    // previously developed Newton-Raphson reciprocal_unit.
    //
    // Softmax requires:
    //
    //     sum = exp(x0) + exp(x1) + ... + exp(xN)
    //
    // and then:
    //
    //     reciprocal = 1 / sum
    //
    // ============================================================


    // ============================================================
    // RECIPROCAL UNIT
    // ============================================================

    reciprocal_unit u_reciprocal (
        .x         (sum),
        .reciprocal(reciprocal)
    );


endmodule