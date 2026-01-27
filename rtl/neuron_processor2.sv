module neuron_processor2 #(
    parameter int PARALLEL_INPUTS  = 1
) (
    input logic clk,
    input logic rst,

    input logic [PARALLEL_INPUTS-1:0] x,
    input logic [PARALLEL_INPUTS-1:0] w,
    input logic [               31:0] threshold,

    input logic          valid_in,
    input logic          eof,

    output logic         valid_out,
    output logic         out,
    output logic         popcount
);

    logic [PARALLEL_INPUTS-1:0] xnor_r;
    logic [               31:0] popcount_r;
    // logic [               31:0] current_count;

    logic [1:0] valid_r;

    logic out_r;



    always_ff @(posedge(clk) or posedge(rst)) begin
        if (rst) begin
            popcount_r <= '0;
            xnor_r <= '0;
            out_r <= '0;
        end
        else begin
            if (valid_in) begin
                xnor_r <= (x ~^ w);
            end
            popcount_r <= popcount_r + $countones(xnor_r);

            if (valid_r[1]) begin
                out_r <= 1'b0;
                if (popcount_r >= threshold) begin
                    out_r <= 1'b1;
                end
            end 
        end
    end

    assign popcount = popcount_r;
    assign out = out_r;

    // valid bit tracking
    always_ff @(posedge(clk) or posedge(rst)) begin
        if (rst) begin
            valid_r <= '0;
        end
        else begin
            if (eof) begin
                valid_r[0] <= eof;
            end
            valid_r[1] <= valid_r[0];
        end
    end

    assign valid_out = valid_r[1]; 


endmodule