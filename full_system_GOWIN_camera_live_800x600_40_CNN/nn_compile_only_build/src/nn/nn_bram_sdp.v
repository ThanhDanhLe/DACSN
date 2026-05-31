`timescale 1ns/1ps
// Simple single-clock simple-dual-port RAM:
//   - one write port
//   - one synchronous read port with registered rd_data
//   - same-address read/write in one cycle is explicitly NO_CHANGE
// DATA_WIDTH=32 is used for two packed int16 activations per word.
module nn_bram_sdp #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 32,
    parameter INIT_FILE  = ""
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   wr_en,
    input  wire [ADDR_WIDTH-1:0]  wr_addr,
    input  wire [DATA_WIDTH-1:0]  wr_data,
    input  wire                   rd_en,
    input  wire [ADDR_WIDTH-1:0]  rd_addr,
    output wire [DATA_WIDTH-1:0]  rd_data
);

`ifdef SIMULATION
    reg [DATA_WIDTH-1:0] rd_data_r;
    assign rd_data = rd_data_r;

    (* ramstyle = "M10K, no_rw_check" *) reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
    wire same_addr_rw = wr_en && rd_en && (wr_addr == rd_addr);
    integer i;
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end else begin
            for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1)
                mem[i] = {DATA_WIDTH{1'b0}};
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data_r <= {DATA_WIDTH{1'b0}};
        end else begin
            // NO_CHANGE on same-address read/write keeps the existing rd_data.
            // nn_compute_mlp16 schedules image/hidden writes and activation
            // reads in separate phases, so this path is only a deterministic
            // safety definition for simulation and debug use.
            if (rd_en && !same_addr_rw)
                rd_data_r <= mem[rd_addr];
            if (wr_en)
                mem[wr_addr] <= wr_data;
        end
    end
`else
    generate
        if ((ADDR_WIDTH == 9) && (DATA_WIDTH == 32)) begin : g_gowin_sdpb_512x32
            wire [13:0] wr_addr_bram = {wr_addr, 5'b00000};
            wire [13:0] rd_addr_bram = {rd_addr, 5'b00000};

            SDPB u_sdpb (
                .DO(rd_data),
                .DI(wr_data),
                .BLKSELA(3'b000),
                .BLKSELB(3'b000),
                .ADA(wr_addr_bram),
                .ADB(rd_addr_bram),
                .CLKA(clk),
                .CLKB(clk),
                .CEA(wr_en),
                .CEB(rd_en),
                .OCE(1'b1),
                .RESETA(~rst_n),
                .RESETB(~rst_n)
            );
            defparam u_sdpb.READ_MODE = 1'b0;
            defparam u_sdpb.BIT_WIDTH_0 = 32;
            defparam u_sdpb.BIT_WIDTH_1 = 32;
            defparam u_sdpb.BLK_SEL_0 = 3'b000;
            defparam u_sdpb.BLK_SEL_1 = 3'b000;
            defparam u_sdpb.RESET_MODE = "SYNC";
        end else begin : g_inferred_fallback
            reg [DATA_WIDTH-1:0] rd_data_r;
            assign rd_data = rd_data_r;

            reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1]
                /* synthesis syn_ramstyle = "block_ram" */;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    rd_data_r <= {DATA_WIDTH{1'b0}};
                end else if (rd_en) begin
                    rd_data_r <= mem[rd_addr];
                end
            end

            always @(posedge clk) begin
                if (wr_en) begin
                    mem[wr_addr] <= wr_data;
                end
            end
        end
    endgenerate
`endif
endmodule
