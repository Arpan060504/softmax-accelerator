module fp32_multiplier(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] result
);

// ============================================================
// UNPACK
// ============================================================

wire sign_a, sign_b;

wire [7:0] exp_a, exp_b;

wire [22:0] fraction_a, fraction_b;

wire [23:0] mantissa_a, mantissa_b;

assign sign_a = a[31];
assign sign_b = b[31];

assign exp_a = a[30:23];
assign exp_b = b[30:23];

assign fraction_a = a[22:0];
assign fraction_b = b[22:0];

assign mantissa_a = {1'b1, fraction_a};
assign mantissa_b = {1'b1, fraction_b};


// ============================================================
// SIGN
// ============================================================

wire result_sign;

assign result_sign = sign_a ^ sign_b;


// ============================================================
// MANTISSA MULTIPLICATION
// ============================================================

reg [47:0] mantissa_product;

always @(*) begin
    mantissa_product = mantissa_a * mantissa_b;
end


// ============================================================
// EXPONENT
// ============================================================

reg [8:0] exponent_sum;

always @(*) begin
    exponent_sum = exp_a + exp_b - 8'd127;
end


// ============================================================
// NORMALIZATION
// ============================================================

reg [7:0] result_exp;
reg [23:0] normalized_mantissa;

always @(*) begin

    result_exp = exponent_sum[7:0];

    if (mantissa_product[47] == 1'b1) begin

        normalized_mantissa = mantissa_product[47:24];

        result_exp = exponent_sum + 1;

    end
    else begin

        normalized_mantissa = mantissa_product[46:23];

    end

end


// ============================================================
// PACK
// ============================================================

wire [22:0] result_fraction;

assign result_fraction = normalized_mantissa[22:0];

assign result = {result_sign,result_exp,result_fraction};

endmodule