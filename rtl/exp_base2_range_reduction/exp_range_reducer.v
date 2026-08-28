`timescale 1ns/1ps

module exp_range_reducer(
    input  wire [31:0] x0, x1, x2, x3,
    output wire [31:0] y0, y1, y2, y3
);

    wire [31:0] max1, max2, max;

    max_finder max_find0(.a(x0),   .b(x1),   .max(max1));
    max_finder max_find1(.a(x2),   .b(x3),   .max(max2));
    max_finder max_find2(.a(max2), .b(max1), .max(max));

    wire [31:0] neg_max = {~max[31], max[30:0]};

    fp32_adder sub0 (.a(x0), .b(neg_max), .result(y0));
    fp32_adder sub1 (.a(x1), .b(neg_max), .result(y1));
    fp32_adder sub2 (.a(x2), .b(neg_max), .result(y2));
    fp32_adder sub3 (.a(x3), .b(neg_max), .result(y3));

endmodule