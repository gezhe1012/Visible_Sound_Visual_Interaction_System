// User-owned safe clock configuration; original vendor sys_pll stays unchanged.
// Same 1GHz VCO and 100MHz feedback/output0 as the original board example.
// output1: 40MHz, output2: 40MHz/180deg, allowing 12.5ns per SDRAM half-cycle.
`timescale 1ns/100fs
module science_sys_pll(input refclk,reset,output clk0_out,clk1_out,clk2_out);
wire clk0_buf;
EG_LOGIC_BUFG bufg_feedback(.i(clk0_buf),.o(clk0_out));
EG_PHY_PLL #(
    .DPHASE_SOURCE("DISABLE"),.DYNCFG("DISABLE"),.FIN("50.000000"),
    .FEEDBK_MODE("NORMAL"),.FEEDBK_PATH("CLKC0_EXT"),
    .STDBY_ENABLE("DISABLE"),.PLLRST_ENA("ENABLE"),.SYNC_ENABLE("DISABLE"),
    .GMC_GAIN(4),.ICP_CURRENT(29),.KVCO(4),.LPF_CAPACITOR(1),.LPF_RESISTOR(2),
    .REFCLK_DIV(1),.FBCLK_DIV(2),
    .CLKC0_ENABLE("ENABLE"),.CLKC0_DIV(10),.CLKC0_CPHASE(9),.CLKC0_FPHASE(0),
    .CLKC1_ENABLE("ENABLE"),.CLKC1_DIV(25),.CLKC1_CPHASE(24),.CLKC1_FPHASE(0),
    .CLKC2_ENABLE("ENABLE"),.CLKC2_DIV(25),.CLKC2_CPHASE(11),.CLKC2_FPHASE(4)
) pll_inst(
    .refclk(refclk),.reset(reset),.stdby(1'b0),.extlock(),
    .load_reg(1'b0),.psclk(1'b0),.psdown(1'b0),.psstep(1'b0),.psclksel(3'b000),.psdone(),
    .dclk(1'b0),.dcs(1'b0),.dwe(1'b0),.di(8'd0),.daddr(6'd0),.do(),
    .fbclk(clk0_out),.clkc({open,open,clk2_out,clk1_out,clk0_buf})
);
endmodule
