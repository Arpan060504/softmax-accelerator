module exp_range_reducer(x0 , x1 ,x2 ,x3 ,y0 ,y1 , y2 , y3);
input [31:0] x0 , x1 ,x2 ,x3;
output [31:0] y0 ,y1 , y2 , y3;

wire [31:0] max , max1 , max2 ;

max_finder max_find0(.a(x0) , .b(x1) , .max(max1));
max_finder max_find1(.a(x2) , .b(x3) , .max(max2));
max_finder max_find2(.a(max2) , .b(max1) , .max(max));

wire [31:0] neg_max;
assign neg_max = {~max[31], max[30:0]};

fp32_adder sub0 (x0 , neg_max , y0);
fp32_adder sub1 (x1 , neg_max , y1);
fp32_adder sub2 (x2 , neg_max , y2);
fp32_adder sub3 (x3 , neg_max , y3);
endmodule 