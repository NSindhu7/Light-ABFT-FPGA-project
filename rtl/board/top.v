// ============================================================
// top.v - Board wrapper for EDGE Artix-7
//   Top button = start, center button = reset
//   SW0-SW3 = data (added to A and B), SW7 = fault (weight bit 0 of PE(1,2))
//   LED0 = done, LED1 = OK, LED2 = Light ABFT error,
//   LED3 = Traditional ABFT error, LED4-LED7 = faulty column (traditional)
// ============================================================
module top (
    input  wire       clk,
    input  wire       rst,
    input  wire       start_btn,
    input  wire       fault_sw,
    input  wire [3:0] data_sw,
    output wire       led_done,
    output wire       led_ok,
    output wire       led_error,
    output wire       led_trad_error,
    output wire [3:0] led_col
);
    reg [1:0] start_sync, fault_sync;
    reg [3:0] data_s;
    always @(posedge clk) begin
        if (rst) begin
            start_sync <= 2'b00; fault_sync <= 2'b00; data_s <= 4'd0;
        end else begin
            start_sync <= {start_sync[0], start_btn};
            fault_sync <= {fault_sync[0], fault_sw};
            data_s     <= data_sw;
        end
    end

    wire       done, light_err, trad_err;
    wire [3:0] trad_col;

    abft_core u_core (
        .clk(clk), .rst(rst), .start(start_sync[1]), .data_sw(data_s),
        .f_type(fault_sync[1] ? 3'd1 : 3'd0), .f_pe(4'd6), .f_bit(4'd0),
        .done(done), .light_err(light_err), .trad_err(trad_err),
        .trad_col(trad_col), .trad_row()
    );

    assign led_done       = done;
    assign led_ok         = done & ~light_err;
    assign led_error      = done &  light_err;
    assign led_trad_error = done &  trad_err;
    assign led_col        = done ? trad_col : 4'b0000;
endmodule
