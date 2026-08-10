package ov7670_pkg;

    // Structure to group register address and its configuration value
    typedef struct packed {
        logic [7:0] addr;
        logic [7:0] data;
    } reg_data_t;

    // Total number of registers to configure
    // 1 Reset + 42 Defaults + 8 QVGA + 6 Frame Control + 2 RGB565 + 1 Brightness + 7 Color Matrix
    localparam TOTAL_REGS = 67;
 
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
 
        // 3. QVGA Resolution (Corresponds to RES_QVGA array in OV7670_REG.h)
        '{
            addr: 8'h12,
            data: 8'h11
        },  // COM7 (QVGA select)
        '{addr: 8'h0C, data: 8'h04},  // COM3
        '{addr: 8'h3E, data: 8'h19},  // COM14
        '{addr: 8'h70, data: 8'h3A},  // SCALING_XSC
        '{addr: 8'h71, data: 8'h35},  // SCALING_YSC
        '{addr: 8'h72, data: 8'h11},  // SCALING_DCWCTR
        '{addr: 8'h73, data: 8'hF1},  // SCALING_PCLK_DIV
        '{addr: 8'hA2, data: 8'h02},  // SCALING_PCLK_DELAY
 
        // 4. QVGA Frame Control (OV7670_SetFrameControl(168, 24, 12, 492))
        '{addr: 8'h17, data: 8'h15},  // HSTART
        '{addr: 8'h18, data: 8'h03},  // HSTOP
        '{addr: 8'h32, data: 8'h00},  // HREF
        '{addr: 8'h19, data: 8'h03},  // VSTART
        '{addr: 8'h1A, data: 8'h7B},  // VSTOP
        '{addr: 8'h03, data: 8'h00},  // VREF
 
        // 5. Color Format (RGB565)
        '{
            addr: 8'h12,
            data: 8'h14
        },  // COM7 (QVGA + RGB select)
        '{addr: 8'h40, data: 8'h10},  // COM15 (RGB565 select)
 
        // 6. Brightness Setting (120)
        '{
            addr: 8'h55,
            data: 8'h87
        },  // BRIGHT
 
        // 7. Color Matrix & Saturation Settings (Color Bar & Chroma quality enhancement)
        '{addr: 8'h4F, data: 8'hB3},  // MTX1: Color Matrix Coefficient 1
        '{addr: 8'h50, data: 8'hB3},  // MTX2: Color Matrix Coefficient 2
        '{addr: 8'h51, data: 8'h00},  // MTX3: Color Matrix Coefficient 3
        '{addr: 8'h52, data: 8'h3D},  // MTX4: Color Matrix Coefficient 4
        '{addr: 8'h53, data: 8'hB0},  // MTX5: Color Matrix Coefficient 5
        '{addr: 8'h54, data: 8'hE4},  // MTX6: Color Matrix Coefficient 6
        '{addr: 8'h58, data: 8'h9E}   // MTX_SIGN: Color Matrix Coefficient Sign Matrix
    };

endpackage
