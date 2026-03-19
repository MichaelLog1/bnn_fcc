`timescale 1ns / 100ps

module popcount_tb #(
    parameter int NUM_TESTS = 10000,
    parameter int NUM_INPUTS = 16,
    parameter int OUTPUT_DATA_WIDTH = 1 + $clog2(NUM_INPUTS)
);

    logic clk = 1'b0;
    logic rst, valid_in, valid_out;

    logic [NUM_INPUTS-1:0] data_in;
    logic [OUTPUT_DATA_WIDTH-1:0] data_out;

    popcount #(
        .NUM_INPUTS(NUM_INPUTS)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .in(data_in),
        .valid_out(valid_out),
        .out(data_out)
    );

    
    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    initial begin : apply_tests
        $timeformat(-9, 0, " ns", 0);

        rst <= 1'b1;
        valid_in <= 1'b0;
        data_in <= '0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;
        @(posedge clk);

        for (int i = 0; i < NUM_TESTS; i++) begin
            data_in <= $urandom;
            valid_in <= $urandom;
            @(posedge clk);
        end

        $display("Tests completed.");
        disable generate_clock;
    end


    function automatic logic [OUTPUT_DATA_WIDTH-1:0] model(logic [NUM_INPUTS-1:0] data_in);
        logic [OUTPUT_DATA_WIDTH-1:0] sum = 0;
        for (int i = 0; i < NUM_INPUTS; i++) sum += data_in[i];
        return sum;
    endfunction

    assert property (@(posedge clk) disable iff (rst) valid_out |-> (data_out == model($past(data_in, DUT.LATENCY))));
    assert property (@(posedge clk) disable iff (rst) valid_out |-> valid_out == $past(valid_in, DUT.LATENCY));
    assert property (@(posedge clk) rst |=> data_out == '0);

endmodule