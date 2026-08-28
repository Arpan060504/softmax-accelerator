`timescale 1ns/1ps

module exp_power_of_two (
    input  wire [31:0] exp_r,
    input  wire signed [7:0] k,
    output reg  [31:0] exp_out
);

    // ============================================================
    // FP32 representation
    //
    //       31        30      23        22             0
    //      +-----------+--------+-----------------------+
    //      |   sign    | exponent |      fraction       |
    //      +-----------+--------+-----------------------+
    //
    // For our exp(r):
    //
    //       exp_r > 0
    //       exp_r is normalized
    //       sign = 0
    //
    // Therefore:
    //
    //       exp_r = (1.fraction) * 2^E
    //
    // and
    //
    //       2^k * exp_r
    //       = (1.fraction) * 2^(E+k)
    //
    // So we only need to modify the exponent.
    // ============================================================


    reg        sign;
    reg [7:0]  exponent;
    reg [22:0] fraction;

    reg signed [9:0] new_exponent;


    // ============================================================
    // Main logic
    // ============================================================

    always @(*)
    begin

        // --------------------------------------------------------
        // Unpack FP32
        // --------------------------------------------------------

        sign     = exp_r[31];
        exponent = exp_r[30:23];
        fraction = exp_r[22:0];


        // --------------------------------------------------------
        // Default
        // --------------------------------------------------------

        exp_out = 32'h00000000;
        new_exponent = 10'sd0;


        // ========================================================
        // ZERO
        // ========================================================

        if (exp_r == 32'h00000000)
        begin
            exp_out = 32'h00000000;
        end


        // ========================================================
        // NaN / Infinity
        //
        // exponent = 255
        //
        // Not expected in our Softmax path, but handled safely.
        // ========================================================

        else if (exponent == 8'hFF)
        begin
            exp_out = exp_r;
        end


        // ========================================================
        // SUBNORMAL
        //
        // Not expected because exp(r) >= 1.
        //
        // For now, pass it through rather than incorrectly
        // treating it as a normalized FP32 number.
        // ========================================================

        else if (exponent == 8'h00)
        begin

            exp_out = exp_r;

        end


        // ========================================================
        // NORMALIZED FP32
        // ========================================================

        else
        begin

            // ----------------------------------------------------
            // Add k to exponent
            //
            // FP32 exponent is biased:
            //
            //       E_biased = E_actual + 127
            //
            // Multiplication by 2^k:
            //
            //       E_new = E_old + k
            //
            // The bias does NOT need to be modified separately.
            // ----------------------------------------------------

            new_exponent = $signed({1'b0, exponent}) + k;


            // ====================================================
            // UNDERFLOW
            //
            // If new exponent becomes <= 0, the result is below
            // the normalized FP32 range.
            //
            // For the current Softmax range this should generally
            // not happen because:
            //
            //       y >= approximately -6
            //
            // and therefore exp(y) >= exp(-6).
            //
            // We output zero for now.
            // ====================================================

            if (new_exponent <= 0)
            begin

                exp_out = 32'h00000000;

            end


            // ====================================================
            // OVERFLOW
            //
            // FP32 maximum finite exponent field = 254.
            //
            // exponent = 255 is reserved for Inf/NaN.
            // ====================================================

            else if (new_exponent >= 255)
            begin

                // Positive infinity

                exp_out = {
                    1'b0,
                    8'hFF,
                    23'h000000
                };

            end


            // ====================================================
            // NORMAL RESULT
            // ====================================================

            else
            begin

                exp_out = {
                    sign,
                    new_exponent[7:0],
                    fraction
                };

            end

        end

    end

endmodule