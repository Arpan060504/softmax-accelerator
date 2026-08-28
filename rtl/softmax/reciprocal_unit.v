module reciprocal_unit (
    input  [31:0] x,
    output [31:0] reciprocal
);

    // ============================================================
    // 1. FP32 UNPACKING
    // ============================================================

    wire        sign;
    wire [7:0]  exponent;
    wire [22:0] fraction;

    assign sign     = x[31];
    assign exponent = x[30:23];
    assign fraction = x[22:0];


    // ============================================================
    // 2. ORIGINAL UNBIASED EXPONENT
    //
    // x = M * 2^e
    //
    // e = biased_exponent - 127
    // ============================================================

    wire signed [9:0] unbiased_exp;

    assign unbiased_exp =
        $signed({2'b00, exponent}) - 10'sd127;


    // ============================================================
    // 3. LUT INDEX
    // ============================================================

    wire [3:0] lut_index;

    assign lut_index = fraction[22:19];


    // ============================================================
    // 4. LUT
    //
    // y0 ≈ 1/M
    // ============================================================

    wire [31:0] reciprocal_estimate;

    reciprocal_lut lut (
        .lut_index            (lut_index),
        .reciprocal_estimate  (reciprocal_estimate)
    );


    // ============================================================
    // 5. CONVERT MANTISSA TO FP32
    //
    // M = 1.fraction
    //
    // FP32:
    //
    // sign     = 0
    // exponent = 127
    // fraction = original fraction
    // ============================================================

    wire [31:0] mantissa_fp32;

    assign mantissa_fp32 = {
        1'b0,
        8'd127,
        fraction
    };


    // ============================================================
    // 6. NEWTON-RAPHSON
    //
    // y1 = y0 * (2 - M*y0)
    // ============================================================

    // ------------------------------------------------------------
    // First multiplication:
    //
    // mul1_out = M * y0
    // ------------------------------------------------------------

    wire [31:0] mul1_out;

    fp32_multiplier mul1 (
        .a      (mantissa_fp32),
        .b      (reciprocal_estimate),
        .result (mul1_out)
    );


    // ------------------------------------------------------------
    // Negate M*y0
    //
    // FP32 negation = flip sign bit
    // ------------------------------------------------------------

    wire [31:0] negative_mul1_out;

    assign negative_mul1_out = {
        ~mul1_out[31],
        mul1_out[30:0]
    };


    // ------------------------------------------------------------
    // correction = 2 - M*y0
    //
    // 2.0 = 0x40000000
    // ------------------------------------------------------------

    wire [31:0] correction;

    fp32_adder adder (
        .a      (32'h40000000),
        .b      (negative_mul1_out),
        .result (correction)
    );


    // ------------------------------------------------------------
    // Second multiplication:
    //
    // y1 = y0 * correction
    // ------------------------------------------------------------

    wire [31:0] y1;

    fp32_multiplier mul2 (
        .a      (reciprocal_estimate),
        .b      (correction),
        .result (y1)
    );


    // ============================================================
    // 7. FIND UNBIASED EXPONENT OF y1
    //
    // y1 = My1 * 2^ey1
    //
    // ey1 = biased_y1 - 127
    // ============================================================

    wire signed [9:0] y1_unbiased_exp;

    assign y1_unbiased_exp =
        $signed({2'b00, y1[30:23]}) - 10'sd127;


    // ============================================================
    // 8. FINAL UNBIASED EXPONENT
    //
    // x  = M * 2^e
    // y1 ≈ 1/M
    //
    // Therefore:
    //
    // 1/x = (1/M) * 2^(-e)
    //
    // final exponent:
    //
    // efinal = ey1 - e
    // ============================================================

    wire signed [9:0] final_unbiased_exp;

    assign final_unbiased_exp =
        y1_unbiased_exp - unbiased_exp;


    // ============================================================
    // 9. RE-BIAS FINAL EXPONENT
    //
    // FP32 stores:
    //
    // biased exponent = unbiased exponent + 127
    // ============================================================

    wire signed [9:0] final_biased_exp;

    assign final_biased_exp =
        final_unbiased_exp + 10'sd127;


    // ============================================================
    // 10. FINAL FP32 RECONSTRUCTION
    // ============================================================

    reg [31:0] reciprocal_reg;

    always @(*)
    begin

        // --------------------------------------------------------
        // Zero input
        // --------------------------------------------------------

        if (x[30:0] == 31'd0)
        begin
            // 1/0 = infinity
            reciprocal_reg = {
                sign,
                8'hFF,
                23'd0
            };
        end

        // --------------------------------------------------------
        // Exponent overflow
        // --------------------------------------------------------

        else if (final_biased_exp >= 10'sd255)
        begin
            reciprocal_reg = {
                sign,
                8'hFF,
                23'd0
            };
        end

        // --------------------------------------------------------
        // Exponent underflow
        // --------------------------------------------------------

        else if (final_biased_exp <= 10'sd0)
        begin
            reciprocal_reg = {
                sign,
                8'd0,
                23'd0
            };
        end

        // --------------------------------------------------------
        // Normal result
        // --------------------------------------------------------

        else
        begin
            reciprocal_reg = {
                sign,
                final_biased_exp[7:0],
                y1[22:0]
            };
        end

    end


    // ============================================================
    // 11. OUTPUT
    // ============================================================

    assign reciprocal = reciprocal_reg;

endmodule