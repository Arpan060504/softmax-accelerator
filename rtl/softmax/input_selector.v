module input_selector (
    input  [31:0] x0,
    input  [31:0] x1,
    input  [31:0] x2,
    input  [31:0] x3,

    input  [1:0]  x_index,

    output reg [31:0] x_selected
);

    always @(*)
    begin
        case (x_index)

            2'd0: x_selected = x0;
            2'd1: x_selected = x1;
            2'd2: x_selected = x2;
            2'd3: x_selected = x3;

            default: x_selected = 32'h00000000;

        endcase
    end

endmodule