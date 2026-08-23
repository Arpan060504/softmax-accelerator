module reciprocal_lut (
    input  [3:0]  lut_index,
    output reg [31:0] reciprocal_estimate
);

    always @(*)
    begin
        case (lut_index)

            4'd0:  reciprocal_estimate = 32'h3F783E10; // 0.969697
            4'd1:  reciprocal_estimate = 32'h3F6A0EA1; // 0.914286
            4'd2:  reciprocal_estimate = 32'h3F5D67C9; // 0.864865
            4'd3:  reciprocal_estimate = 32'h3F520D21; // 0.820513

            4'd4:  reciprocal_estimate = 32'h3F47CE0C; // 0.780488
            4'd5:  reciprocal_estimate = 32'h3F3E82FA; // 0.744186
            4'd6:  reciprocal_estimate = 32'h3F360B61; // 0.711111
            4'd7:  reciprocal_estimate = 32'h3F2E4C41; // 0.680851

            4'd8:  reciprocal_estimate = 32'h3F272F05; // 0.653061
            4'd9:  reciprocal_estimate = 32'h3F20A0A1; // 0.627451
            4'd10: reciprocal_estimate = 32'h3F1A90E8; // 0.603774
            4'd11: reciprocal_estimate = 32'h3F14F209; // 0.581818

            4'd12: reciprocal_estimate = 32'h3F0FB824; // 0.561404
            4'd13: reciprocal_estimate = 32'h3F0AD8F3; // 0.542373
            4'd14: reciprocal_estimate = 32'h3F064B8A; // 0.524590
            4'd15: reciprocal_estimate = 32'h3F020821; // 0.507937

            default:
                reciprocal_estimate = 32'h00000000;

        endcase
    end

endmodule