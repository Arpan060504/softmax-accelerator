`timescale 1ns/1ps

module exp_r_lut (
    input  wire [31:0] r,
    output wire [31:0] exp_r
);

    // ============================================================
    // EXP(R) PIECEWISE-LINEAR LUT (8 REGIONS OVER [0, 0.7])
    //
    // Region width h = 0.0875
    // Approximation: exp(r) ~= a*r + b
    // ============================================================

    reg [31:0] a;
    reg [31:0] b;

    // Region boundary FP32 hex constants
    localparam [31:0] BOUND_0 = 32'h3DB33333; // 0.0875
    localparam [31:0] BOUND_1 = 32'h3E333333; // 0.1750
    localparam [31:0] BOUND_2 = 32'h3E866666; // 0.2625
    localparam [31:0] BOUND_3 = 32'h3EB33333; // 0.3500
    localparam [31:0] BOUND_4 = 32'h3EE00000; // 0.4375
    localparam [31:0] BOUND_5 = 32'h3F066666; // 0.5250
    localparam [31:0] BOUND_6 = 32'h3F1CCCCD; // 0.6125

    always @(*) begin
        // Region 0: [0.0000, 0.0875)
        // a = 1.04505328, b = 1.00000000
        if (r < BOUND_0) begin
            a = 32'h3F85C453;
            b = 32'h3F800000;
        end

        // Region 1: [0.0875, 0.1750)
        // a = 1.14061778, b = 0.99163810
        else if (r < BOUND_1) begin
            a = 32'h3F92003F;
            b = 32'h3F7DDD8E;
        end

        // Region 2: [0.1750, 0.2625)
        // a = 1.24491666, b = 0.97338580
        else if (r < BOUND_2) begin
            a = 32'h3F9F5943;
            b = 32'h3F793006;
        end

        // Region 3: [0.2625, 0.3500)
        // a = 1.35875569, b = 0.94350306
        else if (r < BOUND_3) begin
            a = 32'h3FADE614;
            b = 32'h3F718B99;
        end

        // Region 4: [0.3500, 0.4375)
        // a = 1.48300232, b = 0.90001674
        else if (r < BOUND_4) begin
            a = 32'h3FBDD2C4;
            b = 32'h3F6667C2;
        end

        // Region 5: [0.4375, 0.5250)
        // a = 1.61861810, b = 0.84068483
        else if (r < BOUND_5) begin
            a = 32'h3FCF2F24;
            b = 32'h3F5737B5;
        end

        // Region 6: [0.5250, 0.6125)
        // a = 1.76660865, b = 0.76298980
        else if (r < BOUND_6) begin
            a = 32'h3FE2208E;
            b = 32'h3F43534B;
        end

        // Region 7: [0.6125, ~0.7000]
        // a = 1.92817273, b = 0.66403180
        else begin
            a = 32'h3FF6CD4C;
            b = 32'h3F29FEFA;
        end
    end

    // ============================================================
    // PIPELINE COMPUTATION: exp(r) ~= a*r + b
    // ============================================================
    wire [31:0] ar;
    wire [31:0] computed_exp_r;

    fp32_multiplier u_multiplier (
        .a      (a),
        .b      (r),
        .result (ar)
    );

    fp32_adder u_adder (
        .a      (ar),
        .b      (b),
        .result (computed_exp_r)
    );

    // Exact zero corner bypass
    assign exp_r = (r[30:0] == 31'd0) ? 32'h3F800000 : computed_exp_r;

endmodule