`timescale 1ns/1ps

module exp_range_reduce (

    input  wire [31:0] x,

    output wire signed [31:0] k,

    output wire [31:0] r

);

    // ============================================================
    // CONSTANTS
    // ============================================================

    // log2(e)
    //
    // 1.4426950408889634
    //
    localparam [31:0] LOG2E =
        32'h3FB8AA3B;


    // ln(2)
    //
    // 0.6931471805599453
    //
    localparam [31:0] LN2 =
        32'h3F317218;


    // ============================================================
    // STAGE 1
    //
    // y = x * log2(e)
    //
    // Example:
    //
    // x = 4
    //
    // y = 4 * 1.442695
    //   = 5.77078
    //
    // ============================================================

    wire [31:0] y;

    fp32_multiplier u_log2e_multiplier (

        .a      (x),
        .b      (LOG2E),
        .result (y)

    );


    // ============================================================
    // STAGE 2
    //
    // k = round(y)
    //
    // Example:
    //
    // y = 5.77078
    //
    // k = 6
    //
    // ============================================================

    wire signed [31:0] k_int;

    fp32_round_to_int u_round (

        .x (y),
        .k (k_int)

    );

    assign k = k_int;


    // ============================================================
    // STAGE 3
    //
    // Convert integer k back to FP32.
    //
    // Example:
    //
    // k = 6
    //
    // k_fp32 = 6.0
    //
    // ============================================================

    wire [31:0] k_fp32;

    int_to_fp32 u_int_to_fp32 (

        .in  (k_int),
        .out (k_fp32)

    );


    // ============================================================
    // STAGE 4
    //
    // k_ln2 = k * ln(2)
    //
    // Example:
    //
    // k = 6
    //
    // k_ln2 = 6 * 0.693147
    //       = 4.158883
    //
    // ============================================================

    wire [31:0] k_ln2;

    fp32_multiplier u_ln2_multiplier (

        .a      (k_fp32),
        .b      (LN2),
        .result (k_ln2)

    );


    // ============================================================
    // STAGE 5
    //
    // r = x - k*ln(2)
    //
    // FP32 adder has no subtract input, therefore negate
    // k_ln2 by flipping its sign bit.
    //
    // ============================================================

    wire [31:0] neg_k_ln2;

    assign neg_k_ln2 = {
        ~k_ln2[31],
        k_ln2[30:0]
    };


    fp32_adder u_residual (

        .a      (x),
        .b      (neg_k_ln2),
        .result (r)

    );


endmodule