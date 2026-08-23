module softmax_normalizer(
    input  [31:0] exp_value,
    input  [31:0] reciprocal_sum,
    output [31:0] softmax_value
);

    wire [31:0] mul_out;

    fp32_multiplier mul (
        .a      (exp_value),
        .b      (reciprocal_sum),
        .result (mul_out)
    );

    assign softmax_value = mul_out;

endmodule