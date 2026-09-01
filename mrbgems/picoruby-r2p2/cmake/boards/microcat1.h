/*
 * mechatrax MicroCat.1 (RP2350B + SIMCom SIM7672JP LTE Cat 1)
 *
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The stock Raspberry Pi Pico 2 board header (pico2.h) hard-codes
 * PICO_RP2350A = 1, which caps NUM_BANK0_GPIOS at 30. MicroCat.1 carries
 * the 80-pin RP2350B and wires the cellular modem to GPIO30-39, so it needs
 * its own header selecting the B variant.
 *
 *   GPIO30  modem power control (PWRKEY), active high, >50ms pulse = ON
 *   GPIO31  modem reset,                  active high, >=500ms pulse
 *   GPIO32  modem power status,           active high (input)
 *   GPIO34  LED2
 *   GPIO36  UART1 TX  -> modem RXD
 *   GPIO37  UART1 RX  <- modem TXD
 *   GPIO38  UART1 CTS
 *   GPIO39  UART1 RTS
 *   GPIO43  VSYS sense (ADC3)
 *   GPIO47  PSRAM chip select
 *
 * Ref: https://github.com/mechatrax/microcat1/wiki
 */

// -----------------------------------------------------
// NOTE: THIS HEADER IS ALSO INCLUDED BY ASSEMBLER SO
//       SHOULD ONLY CONSIST OF PREPROCESSOR DIRECTIVES
// -----------------------------------------------------

#ifndef _BOARDS_MICROCAT1_H
#define _BOARDS_MICROCAT1_H

pico_board_cmake_set(PICO_PLATFORM, rp2350)

// For board detection
#define MECHATRAX_MICROCAT1

// --- RP2350 VARIANT ---
// 0 selects the RP2350B (80-pin, 48 GPIOs); pico2.h uses 1 (RP2350A).
#define PICO_RP2350A 0

// --- UART ---
// Console defaults to UART0 on GP0/GP1 (matches MicroPython's MTX_MICROCAT1).
// The modem lives on UART1 (GP36-39) and is opened explicitly by the driver.
#ifndef PICO_DEFAULT_UART
#define PICO_DEFAULT_UART 0
#endif
#ifndef PICO_DEFAULT_UART_TX_PIN
#define PICO_DEFAULT_UART_TX_PIN 0
#endif
#ifndef PICO_DEFAULT_UART_RX_PIN
#define PICO_DEFAULT_UART_RX_PIN 1
#endif

// --- LED ---
#ifndef PICO_DEFAULT_LED_PIN
#define PICO_DEFAULT_LED_PIN 29
#endif

// --- I2C ---
#ifndef PICO_DEFAULT_I2C
#define PICO_DEFAULT_I2C 0
#endif
#ifndef PICO_DEFAULT_I2C_SDA_PIN
#define PICO_DEFAULT_I2C_SDA_PIN 4
#endif
#ifndef PICO_DEFAULT_I2C_SCL_PIN
#define PICO_DEFAULT_I2C_SCL_PIN 5
#endif

// --- SPI ---
#ifndef PICO_DEFAULT_SPI
#define PICO_DEFAULT_SPI 0
#endif
#ifndef PICO_DEFAULT_SPI_SCK_PIN
#define PICO_DEFAULT_SPI_SCK_PIN 18
#endif
#ifndef PICO_DEFAULT_SPI_TX_PIN
#define PICO_DEFAULT_SPI_TX_PIN 19
#endif
#ifndef PICO_DEFAULT_SPI_RX_PIN
#define PICO_DEFAULT_SPI_RX_PIN 16
#endif
#ifndef PICO_DEFAULT_SPI_CSN_PIN
#define PICO_DEFAULT_SPI_CSN_PIN 17
#endif

// --- FLASH ---
#define PICO_BOOT_STAGE2_CHOOSE_W25Q080 1

#ifndef PICO_FLASH_SPI_CLKDIV
#define PICO_FLASH_SPI_CLKDIV 2
#endif

// Conservative default. If the fitted flash is larger this only limits the
// littlefs/FAT region size, not correctness. Override with -D PICO_FLASH_SIZE_BYTES.
pico_board_cmake_set_default(PICO_FLASH_SIZE_BYTES, (4 * 1024 * 1024))
#ifndef PICO_FLASH_SIZE_BYTES
#define PICO_FLASH_SIZE_BYTES (4 * 1024 * 1024)
#endif

// --- PSRAM ---
#ifndef PICO_PSRAM_CS_PIN
#define PICO_PSRAM_CS_PIN 47
#endif

// --- Power sensing ---
#ifndef PICO_VBUS_PIN
#define PICO_VBUS_PIN 24
#endif
// MicroCat.1 divides VSYS onto ADC3 / GPIO43.
#ifndef PICO_VSYS_PIN
#define PICO_VSYS_PIN 43
#endif

pico_board_cmake_set_default(PICO_RP2350_A2_SUPPORTED, 1)
#ifndef PICO_RP2350_A2_SUPPORTED
#define PICO_RP2350_A2_SUPPORTED 1
#endif

#endif
