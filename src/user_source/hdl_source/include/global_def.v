


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

// Science kiosk: 40MHz SDRAM, 25ns. Refresh count must follow the real clock.
`define	  SDR_CLK_PERIOD				1000000000/40000000
// Controller counts 0..INTERVAL inclusive: subtract one for exact 64ms/2048.
`define   SELF_REFRESH_INTERVAL			(64000000/`SDR_CLK_PERIOD/2**(`ROW_WIDTH)-1)

