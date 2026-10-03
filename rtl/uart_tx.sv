`default_nettype none

module uart_tx #(
    parameter int unsigned CLK_FREQ = 50_000_000,
    parameter int unsigned BAUD_RATE = 115_200
) (
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic [7:0] data_in,
    output logic tx,
    output logic busy
);

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        START = 2'b01,
        DATA = 2'b10,
        STOP = 2'b11
    } state_t;

    //Local parameters
    localparam int unsigned CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam int unsigned BAUD_CNT_WIDTH = $clog2(CLKS_PER_BIT);

    state_t state;
    state_t next_state; 

    logic [BAUD_CNT_WIDTH-1:0] baud_count;
    logic [BAUD_CNT_WIDTH-1:0] next_baud_count;
    logic clear_baud;

    logic [2:0] bit_count;
    logic [2:0] next_bit_count;
    logic clear_bit;
    logic inc_bit;

    logic [7:0] data_reg;
    logic load_data;


    //Data Register
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            data_reg <= '0;
        end
        else if (load_data) begin
            data_reg <= data_in;
        end
    end


    //Baud Counter
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            baud_count <= '0;
        end
        else if (clear_baud) begin
            baud_count <= '0;
        end
        else begin
            baud_count <= next_baud_count;
        end
    end

    always_comb begin
        next_baud_count = baud_count + 1'b1;
    end


    //Bit Counter
    always_ff @ (posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            bit_count <= '0;
        end
        else if (clear_bit) begin
            bit_count <= '0;
        end
        else begin
            bit_count <= next_bit_count;
        end
    end

    always_comb begin
        next_bit_count = bit_count;
        if (inc_bit) begin
            next_bit_count = bit_count + 1'b1;
        end
    end



    //FSM
    always_ff@ (posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end
        else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;
        
        clear_baud = 1'b0;
        clear_bit = 1'b0;
        inc_bit = 1'b0;
        load_data = 1'b0;

        case (state)
            IDLE: begin
                clear_baud = 1'b1;
                clear_bit = 1'b1;

                if (start) begin
                    next_state = START;
                    load_data = 1'b1;
                end
            end

            START: begin
                if (baud_count == CLKS_PER_BIT - 1) begin
                    clear_baud = 1'b1;
                    next_state = DATA;
                end
            end

            DATA: begin
                if (baud_count == CLKS_PER_BIT - 1) begin
                    clear_baud = 1'b1;
                    if (bit_count == 3'd7) begin
                        next_state = STOP;
                    end
                    else begin
                        inc_bit = 1'b1;
                    end
                end
            end

            STOP: begin
                if (baud_count == CLKS_PER_BIT - 1) begin
                    clear_baud = 1'b1;
                    next_state = IDLE;
                end
            end

            default: begin
                next_state = IDLE;
                clear_baud = 1'b1;
                clear_bit = 1'b1;
            end

        endcase
    end


    //TX
    always_comb begin
        case (state)
            IDLE: begin
                tx = 1'b1;
                busy = 1'b0;
            end

            START: begin
                tx = 1'b0;
                busy = 1'b1;
            end

            DATA: begin
                tx = data_reg[bit_count];
                busy = 1'b1;
            end

            STOP: begin
                tx = 1'b1;
                busy = 1'b1;
            end

            default: begin
                tx = 1'b1;
                busy = 1'b0;
            end

        endcase
    end


endmodule

`default_nettype wire