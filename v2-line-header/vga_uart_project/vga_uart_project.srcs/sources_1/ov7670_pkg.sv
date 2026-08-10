package ov7670_pkg;

    // Structure to group register address and its configuration value
    typedef struct packed {
        logic [7:0] addr;
        logic [7:0] data;
    } reg_data_t;

    // Total number of registers to configure
    // 1 Reset + 42 Defaults + 3 timing lock + 8 VGA + 6 Frame Control
    // + 1 defect-pixel correction + 2 RGB565 + 1 Brightness + 7 Color Matrix
    localparam TOTAL_REGS = 71;
 
    // Configuration ROM Table
    localparam reg_data_t OV7670_REG_ROM[0:TOTAL_REGS-1] = '{
        // 1. Software Reset
        '{
            addr: 8'h12,
            data: 8'h80
        },  // Reset (COM7 = 0x80)
 
        // 2. Default Settings (Corresponds to defaults array in OV7670_REG.h)
        '{
            addr: 8'h3A,
            data: 8'h04
        },  // TSLB
        '{addr: 8'h12, data: 8'h00},  // COM7 (VGA, YUV)
        '{
            addr: 8'h13,
            data: 8'hE7
        },  // COM8 (Fast AGC/AEC, AGC, AWB, AEC enabled)
        '{addr: 8'h6F, data: 8'h9F},  // AWBCTR0 (White balance)
        '{addr: 8'hB0, data: 8'h84},  // reserved
        '{addr: 8'h70, data: 8'h3A},
        '{addr: 8'h71, data: 8'h35},
        '{addr: 8'h72, data: 8'h11},
        '{addr: 8'h73, data: 8'hF0},
        '{addr: 8'h7A, data: 8'h20},
        '{addr: 8'h7B, data: 8'h10},
        '{addr: 8'h7C, data: 8'h1E},
        '{addr: 8'h7D, data: 8'h35},
        '{addr: 8'h7E, data: 8'h5A},
        '{addr: 8'h7F, data: 8'h69},
        '{addr: 8'h80, data: 8'h76},
        '{addr: 8'h81, data: 8'h80},
        '{addr: 8'h82, data: 8'h88},
        '{addr: 8'h83, data: 8'h8F},
        '{addr: 8'h84, data: 8'h96},
        '{addr: 8'h85, data: 8'hA3},
        '{addr: 8'h86, data: 8'hAF},
        '{addr: 8'h87, data: 8'hC4},
        '{addr: 8'h88, data: 8'hD7},
        '{addr: 8'h89, data: 8'hE8},
        '{addr: 8'h00, data: 8'h00},  // GAIN
        '{addr: 8'h10, data: 8'h00},  // AECH
        '{addr: 8'h0D, data: 8'h40},  // COM4
        '{addr: 8'h14, data: 8'h18},  // COM9
        '{addr: 8'hA5, data: 8'h05},  // BD50MAX
        '{addr: 8'hAB, data: 8'h07},  // BD60MAX
        '{addr: 8'h24, data: 8'h95},  // AEW
        '{addr: 8'h25, data: 8'h33},  // AEB
        '{addr: 8'h26, data: 8'hE3},  // VPT
        '{addr: 8'h9F, data: 8'h78},  // HAECC1
        '{addr: 8'hA0, data: 8'h68},  // HAECC2
        '{addr: 8'hA1, data: 8'h03},  // reserved
        '{addr: 8'hA6, data: 8'hD8},  // HAECC3
        '{addr: 8'hA7, data: 8'hD8},  // HAECC4
        '{addr: 8'hA8, data: 8'hF0},  // HAECC5
        '{addr: 8'hA9, data: 8'h90},  // HAECC6
        '{addr: 8'hAA, data: 8'h94},  // HAECC7
        '{addr: 8'h76, data: 8'hE1},  // REG76: white/black defect-pixel correction
 
    // 3. Native-VGA stable reduced-rate setting.  Keep the 640 x 480 window,
    // RGB565 path, and the established 22.981 MHz XCLK unchanged.
    '{addr: 8'h6B, data: 8'h4A},  // DBLV: PLL x4
    '{addr: 8'h11, data: 8'h02},  // CLKRC: divide by 3 (~20 fps, PCLK ~15.15 MHz)
        '{addr: 8'h3B, data: 8'h00},  // COM11: fixed frame rate

        // 4. Native VGA.  Disable the OV7670 scaler/downsampler and restore
        // the normal pixel clock; the FPGA now receives all 640 x 480 pixels.
        '{
            addr: 8'h12,
            data: 8'h00
        },  // COM7 (VGA, YUV until the RGB write below)
        '{addr: 8'h0C, data: 8'h00},  // COM3: no DCW/scaling
        '{addr: 8'h3E, data: 8'h00},  // COM14: normal PCLK
        '{addr: 8'h70, data: 8'h3A},  // SCALING_XSC
        '{addr: 8'h71, data: 8'h35},  // SCALING_YSC
        '{addr: 8'h72, data: 8'h11},  // SCALING_DCWCTR
        '{addr: 8'h73, data: 8'hF0},  // SCALING_PCLK_DIV: divide by 1
        '{addr: 8'hA2, data: 8'h02},  // SCALING_PCLK_DELAY
 
        // 5. VGA output window (OV7670 VGA reset values)
        '{addr: 8'h17, data: 8'h11},  // HSTART
        '{addr: 8'h18, data: 8'h61},  // HSTOP
        '{addr: 8'h32, data: 8'h80},  // HREF low bits
        '{addr: 8'h19, data: 8'h03},  // VSTART
        '{addr: 8'h1A, data: 8'h7B},  // VSTOP
        '{addr: 8'h03, data: 8'h00},  // VREF
 
        // 6. Color Format (RGB565)
        '{
            addr: 8'h12,
            data: 8'h04
        },  // COM7 (VGA + RGB select)
        '{addr: 8'h40, data: 8'h10},  // COM15 (RGB565 select)
 
        // 7. Brightness Setting (120)
        '{
            addr: 8'h55,
            data: 8'h87
        },  // BRIGHT
 
        // 8. Color Matrix & Saturation Settings (Color Bar & Chroma quality enhancement)
        '{addr: 8'h4F, data: 8'hB3},  // MTX1: Color Matrix Coefficient 1
        '{addr: 8'h50, data: 8'hB3},  // MTX2: Color Matrix Coefficient 2
        '{addr: 8'h51, data: 8'h00},  // MTX3: Color Matrix Coefficient 3
        '{addr: 8'h52, data: 8'h3D},  // MTX4: Color Matrix Coefficient 4
        '{addr: 8'h53, data: 8'hB0},  // MTX5: Color Matrix Coefficient 5
        '{addr: 8'h54, data: 8'hE4},  // MTX6: Color Matrix Coefficient 6
        '{addr: 8'h58, data: 8'h9E}   // MTX_SIGN: Color Matrix Coefficient Sign Matrix
    };

endpackage
