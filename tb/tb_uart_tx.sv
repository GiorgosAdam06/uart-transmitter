`timescale 1ns / 1ps
`default_nettype none

module tb_uart_tx ();

    localparam int unsigned CLK_FREQ = 50_000_000;
    localparam int unsigned BAUD_RATE = 115_200;
    localparam int unsigned CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam int unsigned FRAME_CLKS = 10 * CLKS_PER_BIT;

    localparam time CLK_PERIOD = 20ns;
    localparam time CHECK_DELAY = 1ns;

    //input logic
    logic clk;
    logic rst_n;
    logic start;
    logic [7:0] data_in;

    //output logic
    logic tx;
    logic busy;

    int unsigned frames_checked;

    // clockgen
    always begin
        clk = 1'b0;
        #(CLK_PERIOD / 2);
        clk = 1'b1;
        #(CLK_PERIOD / 2);
    end

    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) DUT (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .data_in(data_in),
        .tx(tx),
        .busy(busy)
    );

    initial begin
        $dumpfile("uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end

    //Check after the rising-edge register and combinational updates settle.
    task automatic check_outputs(
        input logic expected_tx,
        input logic expected_busy,
        input string test_name
    );
    begin
        if ((tx !== expected_tx) || (busy !== expected_busy)) begin
            $fatal(1, "%0t %s: expected tx=%b busy=%b, got tx=%b busy=%b",
                   $time, test_name, expected_tx, expected_busy, tx, busy);
        end
    end
    endtask

    task automatic check_idle(input int unsigned cycles);
    begin
        repeat (cycles) begin
            @(posedge clk);
            #CHECK_DELAY;
            check_outputs(1'b1, 1'b0, "IDLE");
        end
    end
    endtask

    task automatic reset_dut;
    begin
        //Assert between clock edges to test the asynchronous active-low reset.
        @(negedge clk);
        #(2 * CHECK_DELAY);
        rst_n = 1'b0;
        start = 1'b0;
        data_in = '0;
        #CHECK_DELAY;
        check_outputs(1'b1, 1'b0, "Asynchronous reset");

        repeat (2) begin
            @(posedge clk);
            #CHECK_DELAY;
            check_outputs(1'b1, 1'b0, "Reset held low");
        end

        @(negedge clk);
        rst_n = 1'b1;
        check_idle(2);
    end
    endtask

    task automatic start_tx(input logic [7:0] data);
    begin
        @(negedge clk);
        data_in = data;
        start = 1'b1;
        #CHECK_DELAY;
        check_outputs(1'b1, 1'b0, "Request before acceptance edge");

        @(posedge clk);
        #CHECK_DELAY;
        check_outputs(1'b0, 1'b1, "Request accepted / first START cycle");
        //Return in the FIRST start-bit cycle; check_frame must check it now.
    end
    endtask

    task automatic check_frame(
        input logic [7:0] data,
        input logic pulse_while_busy,
        input logic hold_request
    );
        logic expected_tx;
    begin
        //Called just after the acceptance edge, without skipping a clock.
        //8-N-1: one start bit, eight data bits LSB first, one stop bit.
        for (int bit_index = 0; bit_index < 10; bit_index++) begin
            if (bit_index == 0) begin
                expected_tx = 1'b0;
            end
            else if (bit_index == 9) begin
                expected_tx = 1'b1;
            end
            else begin
                expected_tx = data[bit_index - 1];
            end

            for (int cycle = 0; cycle < CLKS_PER_BIT; cycle++) begin
                check_outputs(expected_tx, 1'b1,
                              $sformatf("Byte 0x%02h bit %0d cycle %0d",
                                        data, bit_index, cycle));

                //Change inputs away from the active edge. The saved byte
                //must survive changes to data_in and requests while busy.
                @(negedge clk);
                data_in = ~data;
                start = hold_request ||
                        (pulse_while_busy && (cycle == CLKS_PER_BIT / 2));
                #CHECK_DELAY;
                check_outputs(expected_tx, 1'b1, "Active frame / input change");

                @(posedge clk);
                #CHECK_DELAY;
            end
        end

        //Exactly 10 * CLKS_PER_BIT clocks after acceptance, STOP ends.
        //busy must remain high through STOP and fall on this exact edge.
        check_outputs(1'b1, 1'b0, "First IDLE cycle after STOP");
        frames_checked++;
        $display("PASS: byte 0x%02h, %0d clocks per bit, %0d clocks per frame",
                 data, CLKS_PER_BIT, FRAME_CLKS);
    end
    endtask

    task automatic test_byte(input logic [7:0] data);
    begin
        start_tx(data);
        check_frame(data, 1'b1, 1'b0);
        //No queued frame may appear after the requests made while busy.
        check_idle(3);
    end
    endtask

    task automatic test_reset_during_frame(
        input int unsigned cycles_before_reset,
        input string phase_name
    );
    begin
        $display("Testing reset during %s", phase_name);
        start_tx(8'h00);
        @(negedge clk);
        start = 1'b0;
        repeat (cycles_before_reset) begin
            @(posedge clk);
            #CHECK_DELAY;
        end

        //With 0x00, START and all data bits are low; STOP is high.
        check_outputs(cycles_before_reset >= 9 * CLKS_PER_BIT, 1'b1,
                      "Frame active before reset");
        reset_dut();
        check_idle(3);
        test_byte(8'h81);
    end
    endtask

    //Test sequence
    initial begin
        rst_n = 1'b1;
        start = 1'b0;
        data_in = '0;
        frames_checked = 0;

        $timeformat(-9, 0, " ns", 12);
        reset_dut();
        check_idle(5);

        test_byte(8'hA5);
        test_byte(8'h00);
        test_byte(8'hFF);
        test_byte(8'h41);
        test_byte(8'h55);
        test_byte(8'hAA);
        test_byte(8'h01);
        test_byte(8'h80);

        //A request held through STOP is not accepted on the STOP-to-IDLE
        //edge. It is accepted on the NEXT rising edge, while in IDLE.
        $display("Testing held start and earliest next-frame acceptance");
        start_tx(8'hA5);
        check_frame(8'hA5, 1'b0, 1'b1);
        @(posedge clk);
        #CHECK_DELAY;
        //check_frame left data_in at ~8'hA5 = 8'h5A and start high.
        check_frame(8'h5A, 1'b0, 1'b0);
        check_idle(3);

        test_reset_during_frame(CLKS_PER_BIT / 2, "START");
        test_reset_during_frame(4 * CLKS_PER_BIT + CLKS_PER_BIT / 2, "DATA");
        test_reset_during_frame(9 * CLKS_PER_BIT + CLKS_PER_BIT / 2, "STOP");

        $display("PASS: all UART transmitter tests passed (%0d complete frames)",
                 frames_checked);
        $finish;
    end

    //Fail a stalled simulation instead of reporting success or hanging.
    initial begin
        #(100 * FRAME_CLKS * CLK_PERIOD);
        $fatal(1, "Timeout: UART transmitter tests did not complete");
    end

endmodule

`default_nettype wire
