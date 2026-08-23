module softmax_normalization_stage (
    input  [31:0] exp_value,
    input  [31:0] reciprocal,
    output [31:0] softmax_value
);

    softmax_normalizer normalizer (
        .exp_value      (exp_value),
        .reciprocal_sum (reciprocal),
        .softmax_value  (softmax_value)
    );

endmodule