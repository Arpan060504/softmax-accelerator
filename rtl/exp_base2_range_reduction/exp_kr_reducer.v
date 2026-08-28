`timescale 1ns/1ps

module exp_kr_reducer (
    input  wire [31:0] y,
    output reg  signed [7:0] k,
    output reg  [31:0] r
);

    localparam [31:0] INV_LN2 = 32'h3FB8AA3B; // 1 / ln(2)
    localparam [31:0] LN2     = 32'h3F317218; // ln(2)

    wire [31:0] q_fp;

    fp32_multiplier u_div_ln2 (
        .a      (y),
        .b      (INV_LN2),
        .result (q_fp)
    );

    reg signed [7:0] q_trunc;

    always @(*) begin
        if (q_fp[30:0] == 31'd0)
            q_trunc = 8'sd0;
        else if (q_fp[31] == 1'b0)
            q_trunc = fp32_to_integer(q_fp);
        else
            q_trunc = -fp32_to_integer({1'b0, q_fp[30:0]});
    end

    reg q_fraction;

    always @(*) begin
        q_fraction = has_fraction(q_fp);
    end

    always @(*) begin
        if (y[30:0] == 31'd0 || q_fp[30:0] == 31'd0) begin
            k = 8'sd0;
        end else if (q_fp[31] == 1'b1) begin
            if (q_fraction)
                k = q_trunc - 8'sd1;
            else
                k = q_trunc;
        end else begin
            k = q_trunc;
        end
    end

    reg [31:0] k_fp;

    always @(*) begin
        k_fp = integer_to_fp32(k);
    end

    wire [31:0] k_ln2;

    fp32_multiplier u_k_ln2 (
        .a      (k_fp),
        .b      (LN2),
        .result (k_ln2)
    );

    wire [31:0] neg_k_ln2 = {~k_ln2[31], k_ln2[30:0]};
    wire [31:0] r_computed;

    fp32_adder u_residual (
        .a      (y),
        .b      (neg_k_ln2),
        .result (r_computed)
    );

    always @(*) begin
        if (y[30:0] == 31'd0) begin
            r = 32'h00000000;
        end else begin
            // Guard against negative roundoff epsilon
            r = (r_computed[31] == 1'b1) ? 32'h00000000 : r_computed;
        end
    end

    function signed [7:0] fp32_to_integer;
        input [31:0] value;
        reg [7:0]  exponent;
        reg [22:0] fraction;
        reg [23:0] mantissa;
        integer shift;
        reg [31:0] magnitude;
        begin
            exponent = value[30:23];
            fraction = value[22:0];

            if (exponent < 127) begin
                magnitude = 0;
            end else begin
                mantissa = {1'b1, fraction};
                shift = exponent - 127;
                if (shift >= 23)
                    magnitude = mantissa << (shift - 23);
                else
                    magnitude = mantissa >> (23 - shift);
            end
            fp32_to_integer = magnitude[7:0];
        end
    endfunction

    function has_fraction;
        input [31:0] value;
        reg [7:0]  exponent;
        reg [22:0] fraction;
        integer shift;
        reg [22:0] fractional_mask;
        begin
            exponent = value[30:23];
            fraction = value[22:0];

            if (value[30:0] == 31'd0) begin
                has_fraction = 1'b0;
            end else if (exponent < 127) begin
                has_fraction = 1'b1;
            end else if (exponent >= 150) begin
                has_fraction = 1'b0;
            end else begin
                shift = exponent - 127;
                fractional_mask = 23'h7FFFFF >> shift;
                has_fraction = ((fraction & fractional_mask) != 0);
            end
        end
    endfunction

    function [31:0] integer_to_fp32;
        input signed [7:0] value;
        begin
            case (value)
                8'sd0:   integer_to_fp32 = 32'h00000000;
                -8'sd1:  integer_to_fp32 = 32'hBF800000;
                -8'sd2:  integer_to_fp32 = 32'hC0000000;
                -8'sd3:  integer_to_fp32 = 32'hC0400000;
                -8'sd4:  integer_to_fp32 = 32'hC0800000;
                -8'sd5:  integer_to_fp32 = 32'hC0A00000;
                -8'sd6:  integer_to_fp32 = 32'hC0C00000;
                -8'sd7:  integer_to_fp32 = 32'hC0E00000;
                -8'sd8:  integer_to_fp32 = 32'hC1000000;
                -8'sd9:  integer_to_fp32 = 32'hC1100000;
                -8'sd10: integer_to_fp32 = 32'hC1200000;
                -8'sd11: integer_to_fp32 = 32'hC1300000;
                -8'sd12: integer_to_fp32 = 32'hC1400000;
                default: integer_to_fp32 = 32'h00000000;
            endcase
        end
    endfunction

endmodule