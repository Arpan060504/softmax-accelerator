`timescale 1ns/1ps

module fp32_multiplier(
    input  [31:0] a,
    input  [31:0] b,
    output reg [31:0] result
);

wire sign_a = a[31];
wire sign_b = b[31];
wire [7:0] exp_a = a[30:23];
wire [7:0] exp_b = b[30:23];
wire [22:0] fraction_a = a[22:0];
wire [22:0] fraction_b = b[22:0];

wire [23:0] mantissa_a = {1'b1, fraction_a};
wire [23:0] mantissa_b = {1'b1, fraction_b};
wire result_sign = sign_a ^ sign_b;

reg [47:0] mantissa_product;
reg signed [9:0] exp_calc;
reg [7:0] result_exp;
reg [22:0] result_fraction;

always @(*) begin
    if (a[30:0] == 31'd0 || b[30:0] == 31'd0 || exp_a == 8'd0 || exp_b == 8'd0) begin
        result = 32'h00000000;
    end else begin
        mantissa_product = mantissa_a * mantissa_b;
        exp_calc = $signed({2'b00, exp_a}) + $signed({2'b00, exp_b}) - 10'sd127;

        if (mantissa_product[47]) begin
            result_fraction = mantissa_product[46:24];
            exp_calc = exp_calc + 10'sd1;
        end else begin
            result_fraction = mantissa_product[45:23];
        end

        if (exp_calc <= 0) begin
            result = 32'h00000000;
        end else if (exp_calc >= 255) begin
            result = {result_sign, 8'hFF, 23'd0};
        end else begin
            result_exp = exp_calc[7:0];
            result = {result_sign, result_exp, result_fraction};
        end
    end
end

endmodule