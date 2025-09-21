module spi_peripheral (
    input  wire       clk,      
    input  wire       rst_n,   
    input  wire       nCS_in,   
    input  wire       COPI_in,  
    input  wire       SCLK_in,  

    output reg  [7:0] en_reg_out_7_0,
    output reg  [7:0] en_reg_out_15_8,
    output reg  [7:0] en_reg_pwm_7_0,
    output reg  [7:0] en_reg_pwm_15_8,
    output reg  [7:0] pwm_duty_cycle
);

// input to multi stage synchronizers

    reg nCS_sync1,  nCS_sync2;
    reg SCLK_sync1, SCLK_sync2;
    reg COPI_sync1, COPI_sync2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nCS_sync1  <= 1'b1;
            nCS_sync2  <= 1'b1;
            SCLK_sync1 <= 1'b0;
            SCLK_sync2 <= 1'b0;
            COPI_sync1 <= 1'b0;
            COPI_sync2 <= 1'b0;
        end else begin
            nCS_sync1  <= nCS_in;
            nCS_sync2  <= nCS_sync1;

            SCLK_sync1 <= SCLK_in;
            SCLK_sync2 <= SCLK_sync1;

            COPI_sync1 <= COPI_in;
            COPI_sync2 <= COPI_sync1;
        end
    end

    // edge detection for sclk (and ncs for transaction finalization)

    reg SCLK_prev;
    wire SCLK_rising = (SCLK_sync2 == 1'b1) && (SCLK_prev == 1'b0);
    // wire SCLK_falling = (SCLK_sync2 == 1'b0) && (SCLK_prev == 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) SCLK_prev <= 1'b0;
        else        SCLK_prev <= SCLK_sync2;
    end

    reg nCS_prev;
    wire nCS_posedge = (nCS_sync2 == 1'b1) && (nCS_prev == 1'b0);
    wire nCS_negedge = (nCS_sync2 == 1'b0) && (nCS_prev == 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) nCS_prev <= 1'b1;  
        else        nCS_prev <= nCS_sync2;
    end



    localparam MAX_ADDRESS = 7'd4;

    reg        in_transaction;       
    reg [4:0]  bit_count;            
    reg        rw_bit;               
    reg [6:0]  addr_sr;              
    reg [7:0]  data_sr;             

    reg        frame_valid;          
    reg        transaction_ready;    
    reg        transaction_processed;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_transaction        <= 1'b0;
            bit_count             <= 5'd0;
            rw_bit                <= 1'b0;
            addr_sr               <= 7'd0;
            data_sr               <= 8'd0;
            frame_valid           <= 1'b0;
            transaction_ready     <= 1'b0;
            transaction_processed <= 1'b0;
        end else begin
            
            if (nCS_negedge) begin
                in_transaction    <= 1'b1;
                bit_count         <= 5'd0;
                frame_valid       <= 1'b0;
            end

            // shift in data bits and increment bit counter
            if (in_transaction && (nCS_sync2 == 1'b0) && SCLK_rising) begin
                case (bit_count)
                    5'd0:  rw_bit  <= COPI_sync2;                             
                    5'd1,
                    5'd2,
                    5'd3,
                    5'd4,
                    5'd5,
                    5'd6,
                    5'd7:  addr_sr <= {addr_sr[5:0], COPI_sync2};               
                    default: if (bit_count >= 5'd8 && bit_count <= 5'd15)
                                data_sr <= {data_sr[6:0], COPI_sync2};          
                endcase
                bit_count <= bit_count + 5'd1;
            end

            // check transaction validity
            if (nCS_posedge) begin
                in_transaction <= 1'b0;
                if (bit_count == 5'd16) begin
                    frame_valid       <= 1'b1;
                    transaction_ready <= 1'b1;
                end else begin
                    frame_valid       <= 1'b0; 
                end
                bit_count <= 5'd0; 
            end

            
            if (transaction_processed) begin
                transaction_ready     <= 1'b0;
                transaction_processed <= 1'b0;
            end
        end
    end



    // commit to regs after successful transfer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_reg_out_7_0   <= 8'h00;
            en_reg_out_15_8  <= 8'h00;
            en_reg_pwm_7_0   <= 8'h00;
            en_reg_pwm_15_8  <= 8'h00;
            pwm_duty_cycle   <= 8'h00;
            transaction_processed <= 1'b0;
        end else begin
            if (transaction_ready && !transaction_processed) begin
                
                if (frame_valid && rw_bit == 1'b1) begin
                    if (addr_sr <= MAX_ADDRESS) begin
                        case (addr_sr)
                            7'd0: en_reg_out_7_0  <= data_sr;
                            7'd1: en_reg_out_15_8 <= data_sr;
                            7'd2: en_reg_pwm_7_0  <= data_sr;
                            7'd3: en_reg_pwm_15_8 <= data_sr;
                            7'd4: pwm_duty_cycle  <= data_sr;
                            default: ; 
                        endcase
                    end
                end
                
                transaction_processed <= 1'b1;
            end else if (transaction_processed) begin
                transaction_ready <= 1'b0;
                transaction_processed <= 1'b0;
            end
        end
    end
endmodule