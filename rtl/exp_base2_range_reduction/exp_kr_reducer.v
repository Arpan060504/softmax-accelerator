`timescale 1ns/1ps

module exp_kr_reducer (
    input  wire [31:0] y,

    output reg  signed [7:0] k,
    output wire [31:0] r
);

    // ============================================================
    // CONSTANTS
    // ============================================================

    // 1 / ln(2) = 1.442695040...
    // FP32 approximation
    localparam [31:0] INV_LN2 = 32'h3FB8AA3B;

    // ln(2) = 0.69314718056...
    // FP32 approximation
    localparam [31:0] LN2 = 32'h3F317218;


    // ============================================================
    // STEP 1
    //
    // q = y / ln(2)
    //
    // Implemented as:
    //
    // q = y * (1/ln(2))
    //
    // Since y <= 0 in the Softmax path,
    // q <= 0.
    // ============================================================

    wire [31:0] q_fp;

    fp32_multiplier u_div_ln2 (
        .a      (y),
        .b      (INV_LN2),
        .result (q_fp)
    );


    // ============================================================
    // STEP 2
    //
    // Extract integer magnitude of |q|
    //
    // Example:
    //
    // q = -2.885
    //
    // magnitude = 2
    //
    // q_trunc = -2
    // ============================================================

    reg signed [7:0] q_trunc;

    always @(*)
    begin

        q_trunc = 8'sd0;

        if (q_fp == 32'h00000000)
        begin
            q_trunc = 8'sd0;
        end

        else if (q_fp[31] == 1'b0)
        begin
            // Positive q

            q_trunc = fp32_to_integer(q_fp);
        end

        else
        begin
            // Negative q
            //
            // Remove sign temporarily,
            // convert magnitude to integer,
            // then restore negative sign.

            q_trunc =
                -fp32_to_integer(
                    {1'b0, q_fp[30:0]}
                );
        end

    end


    // ============================================================
    // STEP 3
    //
    // Detect whether q contains a fractional component.
    //
    // Example:
    //
    // q = -2.885
    //
    // q_trunc    = -2
    // q_fraction = 1
    //
    // Therefore:
    //
    // floor(q) = -3
    //
    //
    // q = -3.0
    //
    // q_trunc    = -3
    // q_fraction = 0
    //
    // Therefore:
    //
    // floor(q) = -3
    // ============================================================

    reg q_fraction;

    always @(*)
    begin

        q_fraction = has_fraction(q_fp);

    end


    // ============================================================
    // STEP 4
    //
    // k = floor(q)
    //
    // For negative q:
    //
    // q = -2.885
    //
    // trunc(q) = -2
    // floor(q) = -3
    //
    // For exact integer:
    //
    // q = -3.0
    //
    // floor(q) = -3
    // ============================================================

    always @(*)
    begin

        k = 8'sd0;

        // --------------------------------------------------------
        // q = 0
        // --------------------------------------------------------

        if (q_fp == 32'h00000000)
        begin

            k = 8'sd0;

        end

        // --------------------------------------------------------
        // Negative q
        // --------------------------------------------------------

        else if (q_fp[31] == 1'b1)
        begin

            if (q_fraction)
                k = q_trunc - 8'sd1;
            else
                k = q_trunc;

        end

        // --------------------------------------------------------
        // Positive q
        //
        // Not normally used in Softmax because y <= 0.
        // Still handled correctly.
        // --------------------------------------------------------

        else
        begin

            k = q_trunc;

        end

    end


    // ============================================================
    // STEP 5
    //
    // Convert integer k -> FP32
    //
    // Example:
    //
    // k = -3
    //
    // k_fp = -3.0
    // ============================================================

    reg [31:0] k_fp;

    always @(*)
    begin

        k_fp = integer_to_fp32(k);

    end


    // ============================================================
    // STEP 6
    //
    // Calculate:
    //
    // k * ln(2)
    // ============================================================

    wire [31:0] k_ln2;

    fp32_multiplier u_k_ln2 (
        .a      (k_fp),
        .b      (LN2),
        .result (k_ln2)
    );


    // ============================================================
    // STEP 7
    //
    // r = y - k*ln(2)
    //
    // Since k is negative:
    //
    // k*ln(2) < 0
    //
    // therefore:
    //
    // r = y - negative_number
    //
    // r = y + |k*ln(2)|
    //
    // which should produce:
    //
    //             0 <= r < ln(2)
    //
    // assuming y <= 0.
    // ============================================================

    wire [31:0] neg_k_ln2;

    assign neg_k_ln2 = {
        ~k_ln2[31],
         k_ln2[30:0]
    };


    fp32_adder u_residual (
        .a      (y),
        .b      (neg_k_ln2),
        .result (r)
    );


    // ============================================================
    // FUNCTION
    //
    // FP32 -> INTEGER
    //
    // Returns truncated integer magnitude.
    //
    // Examples:
    //
    // 2.885 -> 2
    // 3.000 -> 3
    // 0.5   -> 0
    //
    // The caller handles the sign.
    // ============================================================

    function signed [7:0] fp32_to_integer;

        input [31:0] value;

        reg        sign;
        reg [7:0]  exponent;
        reg [22:0] fraction;

        reg [23:0] mantissa;

        integer shift;

        reg [31:0] magnitude;

        begin

            sign     = value[31];
            exponent = value[30:23];
            fraction = value[22:0];

            // ----------------------------------------------------
            // Zero / subnormal
            // ----------------------------------------------------

            if (exponent == 0)
            begin

                magnitude = 0;

            end

            else
            begin

                // Restore hidden leading 1

                mantissa = {1'b1, fraction};

                shift = exponent - 127;

                // ------------------------------------------------
                // |value| < 1
                // ------------------------------------------------

                if (shift < 0)
                begin

                    magnitude = 0;

                end

                // ------------------------------------------------
                // Integer part requires shifting mantissa left
                // ------------------------------------------------

                else if (shift >= 23)
                begin

                    magnitude =
                        mantissa << (shift - 23);

                end

                // ------------------------------------------------
                // Normal case
                // ------------------------------------------------

                else
                begin

                    magnitude =
                        mantissa >> (23 - shift);

                end

            end


            // ----------------------------------------------------
            // Restore sign
            // ----------------------------------------------------

            if (sign)
                fp32_to_integer = -magnitude[7:0];
            else
                fp32_to_integer = magnitude[7:0];

        end

    endfunction


    // ============================================================
    // FUNCTION
    //
    // Detect fractional component
    //
    // Returns:
    //
    // 0 -> exact integer
    // 1 -> has fractional part
    //
    // Examples:
    //
    // 2.0     -> 0
    // 2.5     -> 1
    // 2.885   -> 1
    // 3.0     -> 0
    // ============================================================

    function has_fraction;

        input [31:0] value;

        reg [7:0]  exponent;
        reg [22:0] fraction;

        integer shift;

        reg [22:0] fractional_mask;

        begin

            exponent = value[30:23];
            fraction = value[22:0];

            // ----------------------------------------------------
            // Zero
            // ----------------------------------------------------

            if ((exponent == 0) && (fraction == 0))
            begin

                has_fraction = 1'b0;

            end

            // ----------------------------------------------------
            // |value| < 1
            //
            // Any nonzero value here is fractional.
            // ----------------------------------------------------

            else if (exponent < 127)
            begin

                has_fraction = 1'b1;

            end

            // ----------------------------------------------------
            // exponent >= 150
            //
            // Unbiased exponent >= 23.
            //
            // All 23 fraction bits are now part of the integer.
            // Therefore no fractional portion exists.
            // ----------------------------------------------------

            else if (exponent >= 150)
            begin

                has_fraction = 1'b0;

            end

            // ----------------------------------------------------
            // 1 <= |value| < 2^23
            // ----------------------------------------------------

            else
            begin

                shift = exponent - 127;

                fractional_mask =
                    23'h7FFFFF >> shift;

                if ((fraction & fractional_mask) != 0)
                    has_fraction = 1'b1;
                else
                    has_fraction = 1'b0;

            end

        end

    endfunction


    // ============================================================
    // FUNCTION
    //
    // Signed integer -> FP32
    //
    // Supported k range:
    //
    // 0 to -12
    //
    // This is sufficient for approximately:
    //
    // y = 0 to -8
    // ============================================================

    function [31:0] integer_to_fp32;

        input signed [7:0] value;

        begin

            case (value)

                8'sd0:
                    integer_to_fp32 = 32'h00000000;

                -8'sd1:
                    integer_to_fp32 = 32'hBF800000;

                -8'sd2:
                    integer_to_fp32 = 32'hC0000000;

                -8'sd3:
                    integer_to_fp32 = 32'hC0400000;

                -8'sd4:
                    integer_to_fp32 = 32'hC0800000;

                -8'sd5:
                    integer_to_fp32 = 32'hC0A00000;

                -8'sd6:
                    integer_to_fp32 = 32'hC0C00000;

                -8'sd7:
                    integer_to_fp32 = 32'hC0E00000;

                -8'sd8:
                    integer_to_fp32 = 32'hC1000000;

                -8'sd9:
                    integer_to_fp32 = 32'hC1100000;

                -8'sd10:
                    integer_to_fp32 = 32'hC1200000;

                -8'sd11:
                    integer_to_fp32 = 32'hC1300000;

                -8'sd12:
                    integer_to_fp32 = 32'hC1400000;

                default:
                    integer_to_fp32 = 32'h00000000;

            endcase

        end

    endfunction

endmodule