// this module counts the number of bits asserted in an arbitrary length value, fully pipelined

module popcount #(
    parameter int NUM_INPUTS = 1,
    parameter int NUM_STAGES = $clog2(NUM_INPUTS),
    parameter int NUM_INPUTS_PADDED = 2 ** NUM_STAGES,
    parameter int OUTPUT_DATA_WIDTH = 1 + NUM_STAGES
) (
    input logic clk,
    input logic rst,
    input logic valid_in,
    input logic [NUM_INPUTS-1:0] in,

    output logic valid_out,
    output logic [OUTPUT_DATA_WIDTH-1:0] out

);
    localparam int LATENCY = NUM_STAGES;

    logic [NUM_STAGES:0][NUM_INPUTS_PADDED-1:0][OUTPUT_DATA_WIDTH-1:0] data;
    logic [LATENCY-1:0] valid_delay_r;

    genvar stage, adder;
    generate
        for( stage = 0; stage <= NUM_STAGES; stage++ ) begin : stages

            localparam STAGE_INPUTS = NUM_INPUTS_PADDED >> stage;
            // each stage will need more bits to prevent overflow
            localparam STAGE_WIDTH = 1 + stage;

            if (stage == '0) begin
                for (adder = 0; adder < STAGE_INPUTS; adder++) begin : generate_inputs
                    always_comb begin
                        if (adder < NUM_INPUTS) begin
                            // this should just copy the individual bits
                            data[stage][adder][STAGE_WIDTH-1:0] <= in[adder];
                            data[stage][adder][OUTPUT_DATA_WIDTH-1:STAGE_WIDTH] <= '0;
                        end else begin
                            data[stage][adder][OUTPUT_DATA_WIDTH-1:0] <= '0;
                        end
                    end
                end
            end else begin
                for (adder = 0; adder < STAGE_INPUTS; adder++) begin : generate_adders
                    always_ff @(posedge clk or posedge rst) begin
                        if (rst) begin
                            data[stage][adder][OUTPUT_DATA_WIDTH-1:0] <= '0;
                        end else begin
                            data[stage][adder][STAGE_WIDTH-1:0] <= data[stage-1][adder*2][(STAGE_WIDTH-1)-1:0] + data[stage-1][adder*2+1][(STAGE_WIDTH-1)-1:0];
                        end
                    end
                end
            end
        end
    endgenerate

    assign out = data[NUM_STAGES][0];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_delay_r <= '{default: '0};
        end else begin
            valid_delay_r[0] <= valid_in;
            for (int i = 1; i < LATENCY; i++) valid_delay_r[i] <= valid_delay_r[i-1];
        end
    end

    assign valid_out = valid_delay_r[LATENCY-1];


endmodule