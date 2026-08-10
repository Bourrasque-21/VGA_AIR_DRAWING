`timescale 1ns / 1ps
module clock_gen (
    input        clk,
    input        rst,
    output logic o_tick_25,
    output logic o_xclk_24
);
  logic [1:0] r_count;
  logic xclk_raw, xclk_fb_raw, xclk_fb, xclk_locked;

  // 25 MHz one-cycle tick at a 100 MHz system clock.
  assign o_tick_25 = (r_count == 2'd3);

  // Basys3 VGA timing is 800 x 521 at a 25 MHz pixel clock:
  //   VGA = 25 MHz / (800 * 521) = 59.980806142 Hz.
  // Camera XCLK = 100 MHz * 29.875 / 4 / 32.5 = 22.980769 MHz.
  // With the native-VGA OV7670 table and CLKRC = 0x02, the measured PCLK is
  // about 15.15 MHz and the camera delivers about 20 fps without DVP speckle.
  // Faster CLKRC settings were not stable on the current PMOD wiring.
  MMCME2_BASE #(
      .BANDWIDTH        ("OPTIMIZED"),
      .CLKFBOUT_MULT_F  (29.875),
      .CLKIN1_PERIOD    (10.0),
      .CLKOUT0_DIVIDE_F (32.500),
      .DIVCLK_DIVIDE    (4),
      .STARTUP_WAIT     ("FALSE")
  ) U_CAMERA_PLL (
      .CLKIN1    (clk),
      .RST       (rst),
      .PWRDWN    (1'b0),
      .CLKFBIN   (xclk_fb),
      .CLKFBOUT  (xclk_fb_raw),
      .CLKFBOUTB (),
      .CLKOUT0   (xclk_raw),
      .CLKOUT0B  (),
      .CLKOUT1   (),
      .CLKOUT1B  (),
      .CLKOUT2   (),
      .CLKOUT2B  (),
      .CLKOUT3   (),
      .CLKOUT3B  (),
      .CLKOUT4   (),
      .CLKOUT5   (),
      .CLKOUT6   (),
      .LOCKED    (xclk_locked)
  );

  BUFG U_CAMERA_PLL_FB (
      .I (xclk_fb_raw),
      .O (xclk_fb)
  );
  BUFG U_CAMERA_XCLK_BUF (
      .I (xclk_raw),
      .O (o_xclk_24)
  );

  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      //o_pclk  <= 0;
      r_count <= 0;
    end else begin
      if (r_count == 4 - 1) begin
        //o_pclk  <= 1;
        r_count <= 0;
      end else begin
        //o_pclk  <= 0;
        r_count <= r_count + 1;
      end
    end
  end
endmodule
