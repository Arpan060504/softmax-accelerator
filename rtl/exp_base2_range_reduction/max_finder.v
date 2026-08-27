module max_finder (
    input  [31:0] a,
    input  [31:0] b,
    output reg [31:0] max
);

    // ------------------------------------------------------------
    // Unpack FP32
    // ------------------------------------------------------------

    wire       sign_a;
    wire       sign_b;

    wire [7:0] exponent_a;
    wire [7:0] exponent_b;

    wire [22:0] fraction_a;
    wire [22:0] fraction_b;


    assign sign_a = a[31];
    assign sign_b = b[31];

    assign exponent_a = a[30:23];
    assign exponent_b = b[30:23];

    assign fraction_a = a[22:0];
    assign fraction_b = b[22:0];


    // ------------------------------------------------------------
    // Compare
    // ------------------------------------------------------------

    always @(*)
    begin

        // ========================================================
        // Different signs
        // ========================================================

        if (sign_a != sign_b)
        begin

            // Positive number is greater
            if (sign_a == 1'b0)
                max = a;
            else
                max = b;

        end


        // ========================================================
        // Both POSITIVE
        // ========================================================

        else if (sign_a == 1'b0)
        begin

            if (exponent_a > exponent_b)
                max = a;

            else if (exponent_a < exponent_b)
                max = b;

            else
            begin
                if (fraction_a >= fraction_b)
                    max = a;
                else
                    max = b;
            end

        end


        // ========================================================
        // Both NEGATIVE
        // ========================================================

        else
        begin

            // Reverse comparison because these are negative

            if (exponent_a < exponent_b)
                max = a;

            else if (exponent_a > exponent_b)
                max = b;

            else
            begin
                if (fraction_a <= fraction_b)
                    max = a;
                else
                    max = b;
            end

        end

    end

endmodule